# AGENTS.md

Operating guide for coding agents working on Gantry. `CLAUDE.md` imports this
file, so this is the single source of truth for Claude Code and other agents.
Deep reference lives in the linked documents; do not fork these rules into
per-agent copies.

## What Gantry is

Gantry is a native macOS workspace for **Claude Code** — SwiftUI and Liquid
Glass — that runs the `claude` CLI as a child process for each chat over its
bidirectional `stream-json` protocol. It renders messages, tool activity, and
permission prompts natively, and manages AI provider profiles, code-host
plugins (GitHub, GitLab, Gitea), and Claude Code extensions and mods.

It is an unofficial client and is not affiliated with Anthropic.

## Read before you change something

| Document | Owns |
| --- | --- |
| `README.md` | Product behavior, feature overview, storage summary, full project map |
| `ARCHITECTURE.md` | Targets, process and protocol flow, persistence, provider/plugin/bridge design |
| `DESIGN.md` | Palette, type scale, surfaces, Liquid Glass rules, motion, accessibility |
| `SECURITY.md` | Trust boundaries, secret handling, permission model, vulnerability reporting |
| `CONTRIBUTING.md` | Contribution process, contribution licensing |

Read the relevant document before editing. Update the document that owns the
fact instead of restating it elsewhere.

## Build and test

Requires macOS 26+, an Xcode 26/27 toolchain (Swift 6.2+), and an authenticated
`claude` CLI for manual runs.

```sh
swift build
swift test                        # default suite; must pass before declaring work done

swift run Gantry                  # quick launch from the terminal
./Scripts/build-app.sh            # release .app bundle: icon + MCP helper + ad-hoc signature
open build/Gantry.app

swift test --filter parsesPermissionRequest   # single test
```

Gated tests touch real external systems. Run them only when the user asks, and
never in CI:

```sh
# Spends a small amount of API credit against the installed CLI.
Gantry_RUN_CLI_INTEGRATION=1 swift test --filter realClaudeCodeSmokeTest
Gantry_RUN_CLI_INTEGRATION=1 swift test --filter realClaudeCodeReportsSlashCommands

# Writes and removes disposable items in the login Keychain.
Gantry_RUN_KEYCHAIN_TESTS=1 swift test --filter keychainRoundTrip
Gantry_RUN_KEYCHAIN_TESTS=1 swift test --filter pluginKeychainRoundTrip
```

- Swift tools 6.2; every target pins `.swiftLanguageMode(.v5)`. Keep it unless
  asked to migrate.
- No third-party dependencies. Ask before adding one.
- Tests use **Swift Testing** (`import Testing`, `@Test`, `#expect`), not XCTest.

## Targets and layout

| Target | Responsibility |
| --- | --- |
| `GantryCore` | Models, Claude runtime/protocol, providers, Keychain, code-host clients, MCP bridge, extension manager, persistence. All testable logic lives here. |
| `Gantry` | SwiftUI app: `AppModel` observable state, orchestration, design system, views. |
| `GantryPluginMCP` | Bundled stdio MCP helper (`Gantry-plugins`) that forwards tool calls to the app over a Unix socket. |
| `GantryCoreTests` | Unit tests for `GantryCore` with a fake CLI and HTTP fixtures. |

- Keep `GantryCore` free of UI; keep SwiftUI views thin and put behavior in
  testable types.
- Read the README's **Project map** before adding a file, and update it when the
  structure changes.
- App state: `~/Library/Application Support/Gantry/state.json` (mode `0600`).
- CLI stderr logs: `~/Library/Logs/Gantry/`.
- Debug overrides: `Gantry_STATE_DIR` redirects app state; `Gantry_CLAUDE_PATH`
  selects a specific CLI executable. Use them for isolated manual runs.

## Architecture invariants

These are non-negotiable unless the user explicitly asks to change the design.
`ARCHITECTURE.md` explains the reasoning.

- **One `ClaudeRuntime` process per session**, reused within a chat. After
  relaunch it resumes with `--resume <session-id>`. Do not introduce a shared
  global process.
- **Streaming is coalesced at ~30 fps** (`StreamPreview` in `AppModel`, 32 ms
  flush). Do not add per-token UI work or observation.
- **Permission flow is sacred**: `can_use_tool` requests surface as permission
  cards (or question cards for `AskUserQuestion`) and get a `control_response`
  with allow or deny. Never add an auto-approval path, synthesize an answer, or
  bypass Claude Code's authority.
- **Provider switching** injects env vars and credentials into that child
  process only, between turns. It must not persist secrets. Keys are read from
  the Keychain at launch.
- **Plugin MCP bridge**: per-session Unix socket plus a random bridge token.
  The app reads code-host tokens from the Keychain and sends them only to the
  configured code host; Claude Code and the helper never receive one.
- **Secrets**: API keys and code-host tokens go through `ProviderKeychain` and
  `PluginKeychain` only. Never log, print, put them in argv, `state.json`, or
  fixtures (`token-123`-style fakes are fine).
- **Persistence compatibility**: new fields in persisted models need
  decode-safe defaults (for example `ChatSession.modelUsage` is optional).
  `state.json` decoding and the legacy 0.1.0 decode tests must keep passing.
- **Cost estimates are model-derived**: `ModelCostEstimator` prices cumulative
  `modelUsage` deltas with `ModelPricingTable`. Update published rates there and
  keep Claude Code's reported cost only as the fallback for unknown models.
- **Version bumps touch three files**: `AppModel.appVersion`,
  `Resources/Info.plist` (`CFBundleShortVersionString` and `CFBundleVersion`),
  and `Sources/GantryPluginMCP/main.swift`.

## UI work

Read `DESIGN.md` before changing a surface. The short version:

- Target macOS 26 Liquid Glass APIs; it is a single-window app.
- Use Apple's real Liquid Glass (`glassEffect`, `GlassEffectContainer`,
  `.buttonStyle(.glass)`, `.glassProminent`) for the sidebar and the floating
  layer: composer, permission cards, palette, menus, and notices. Never paint a
  custom fill, gradient, highlight, or shadow on top of glass; the composer's
  accent focus ring is the only accepted stroke. Content cards use
  `surfaceCard` (flat neutral fill plus a hairline).
- Keep surfaces neutral. The terracotta accent marks the selection rail, live
  work, the primary action, links, and focus only; it does not tint surfaces.
- Reuse `Sources/Gantry/Design/Theme.swift` and `Design/Components.swift`;
  follow existing surfaces and spacing.
- Verify UI changes in **both light and dark** appearance and keep
  accessibility labels meaningful.
- Markdown is parsed by the dependency-free `MarkdownParser` (`GantryCore`) and
  rendered by `Utilities/MarkdownRendering.swift`; syntax highlighting is
  custom.

## Security rules

Read `SECURITY.md` before touching credentials, permissions, networking, or the
MCP bridge. The short version:

- Never read, print, log, or echo the user's Keychain items, tokens, `.env`
  files, or private keys. This includes debugging output and screenshots.
- Do not add `-y`, auto-accept, or any path that answers a permission request
  without the user.
- Never synthesize, preselect, or submit an `AskUserQuestion` answer the user
  did not provide.
- Do not pass a code-host token to `GantryPluginMCP`; Gantry gives the helper
  only the socket path and bridge token.
- Keep state, logs, MCP configs, and sockets at user-only permissions.
- Do not send credentials in URLs, argv, or error messages. Redact CLI output
  before showing or persisting it.

## Tests

- Add or update tests in `Tests/GantryCoreTests` for behavior changes.
- Prefer the existing fake CLI (`ProtocolAndRuntimeTests`) and transport
  fixtures over real services.
- `swift test` must be green before a change is ready. If a change cannot be
  tested automatically, describe exactly what you ran and observed.
- Do not make gated tests part of the default suite.

## Git and pull requests

- **Conventional Commits**: `feat(scope): ...`, `fix: ...`, `docs: ...`,
  `refactor: ...`, `test: ...`, `chore: ...`.
- Branch off `main` for non-trivial work (`feat/...`, `fix/...`, `docs/...`).
  `main` is protected: pull requests, linear history, signed commits, no direct
  pushes.
- Never use `--no-verify`, `--no-gpg-sign`, or otherwise bypass signing.
- Never commit secrets, `.env*` files, or build output (`.build/` and `build/`
  are ignored).
- Do not push, force-push, amend, merge, publish, or open a PR unless the user
  explicitly asks.
- Keep commits logical and leave unrelated working-tree changes alone.
- Update `README.md` when user-facing behavior or the project map changes.
  Comments explain *why*, not *what*.

## Definition of done

A change is done when:

1. The behavior lives in `GantryCore` where it can be tested, and views stay
   thin.
2. Tests cover the change, and `swift build` plus `swift test` pass.
3. UI changes were checked in light and dark appearance with meaningful
   accessibility labels.
4. The owning document (`README.md`, `ARCHITECTURE.md`, `DESIGN.md`,
   `SECURITY.md`) was updated if the change affects it.
5. No secrets, tokens, real Keychain values, or build artifacts are staged.
6. Commits follow Conventional Commits and are signed normally.

## Common change map

| Change | Where it starts | Also update |
| --- | --- | --- |
| New persisted field | `Sources/GantryCore/Models.swift` | Decode-safe default; persistence tests; `ARCHITECTURE.md` if schema meaning changes |
| New provider environment variable | `AIProvider.environment(apiKey:)` | Provider tests; `ARCHITECTURE.md` provider env list |
| New code host | `CodeHostBackend` implementation and `PluginKind` | Fixtures, plugin tests, token scopes, `SECURITY.md` |
| New MCP tool | `PluginToolCatalog` and `PluginToolExecutor` | Tool tests, system prompt, `ARCHITECTURE.md` catalog table |
| New UI surface or control | `Sources/Gantry/Views/` | `Theme.swift`/`Components.swift`, light/dark check, accessibility, `DESIGN.md` |
| New mod template | `ModScaffolder` and the Create Mod wizard | Scaffolder tests, `README.md` |
| New setting | `AppSettings` | Optional default, Settings UI, state compatibility test |
| Release | Version constant, `Info.plist`, MCP helper version | `README.md` "What's new" |

## Local agent environment

- Do not edit shell startup files (`~/.zshrc`, `.zprofile`, and similar); ask
  the user instead.
- Prefer `trash` over `rm` for deletions so they stay recoverable. Ask before
  destructive filesystem operations.
- Never run `sudo`.
- `.claude/` is local, ignored state. Do not commit it or rely on its contents.
- Never point a test or fixture at the user's real Keychain, real code-host
  accounts, or real API keys.
