# CLAUDE.md

Gantry is a native macOS workspace for **Claude Code** (SwiftUI + Liquid Glass). It runs the `claude` CLI per session over its bidirectional `stream-json` protocol, renders conversations, tool activity, and permission prompts natively, and manages AI provider profiles and code-host plugins. It is an unofficial client, not affiliated with Anthropic.

## Build and test

Requires macOS 26+, an Xcode 26/27 toolchain (Swift 6.2+), and an authenticated `claude` CLI for manual runs.

```sh
swift build
swift test                        # default suite; must pass before declaring work done

swift run Gantry                  # quick launch from the terminal
./Scripts/build-app.sh            # release .app bundle: icon + MCP helper + ad-hoc signature
open build/Gantry.app

swift test --filter parsesPermissionRequest   # single test

# Gated integration tests (real CLI / login Keychain). Never run in CI.
Gantry_RUN_CLI_INTEGRATION=1 swift test --filter realClaudeCodeSmokeTest
Gantry_RUN_KEYCHAIN_TESTS=1 swift test --filter keychainRoundTrip
Gantry_RUN_KEYCHAIN_TESTS=1 swift test --filter pluginKeychainRoundTrip
```

- Swift tools 6.2; every target pins `.swiftLanguageMode(.v5)`. Keep it unless asked to migrate.
- No third-party dependencies. Ask before adding one.
- Tests use **Swift Testing** (`import Testing`, `@Test`, `#expect`), not XCTest.

## Targets and layout

| Target | Responsibility |
| --- | --- |
| `GantryCore` | Models, Claude runtime/protocol, providers, Keychain, code-host clients, MCP bridge, persistence. All testable logic lives here. |
| `Gantry` | SwiftUI app: `AppModel` observable state, orchestration, design system, views. |
| `GantryPluginMCP` | Bundled stdio MCP helper (`Gantry-plugins`) that forwards tool calls to the app over a Unix socket. |
| `GantryCoreTests` | Unit tests for `GantryCore` with fake CLI and HTTP fixtures. |

- Keep `GantryCore` free of UI; keep SwiftUI views thin and put behavior in testable types.
- Read the README's **Project map** before adding files and update it when the structure changes.
- State: `~/Library/Application Support/Gantry/state.json` (mode `0600`); CLI stderr logs: `~/Library/Logs/Gantry/`.
- Debug overrides: `Gantry_STATE_DIR` redirects app state; `Gantry_CLAUDE_PATH` selects a specific CLI executable. Use these for isolated manual runs.

## Architecture invariants

- **One `ClaudeRuntime` process per session**, reused within a chat; after relaunch it resumes with `--resume <session-id>`. Do not introduce a shared global process.
- **Streaming is coalesced at ~30 fps** (`StreamPreview` in `AppModel`). Do not add per-token UI work or observation.
- **Permission flow is sacred**: `can_use_tool` requests surface as permission cards and get a `control_response` with allow/deny. Never add an auto-approval path or bypass Claude Code's authority.
- **Provider switching** injects env vars and credentials into that child process only, between turns; it must not persist secrets. Keys are read from the Keychain at launch.
- **Plugin MCP bridge**: per-session Unix socket + random bridge token. Code-host tokens never leave the app and are never passed to the helper.
- **Secrets**: API keys and code-host tokens go through `ProviderKeychain`/`PluginKeychain` only. Never log, print, put them in argv, `state.json`, or fixtures (`token-123`-style fakes are fine).
- **Persistence compatibility**: new fields in persisted models need decode-safe defaults (for example `ChatSession.modelUsage` is optional); `state.json` decoding and the 0.1.0 migration tests must keep passing.
- **Cost estimates are model-derived**: `ModelCostEstimator` prices cumulative `modelUsage` deltas with `ModelPricingTable`; update published rates there and keep Claude Code's reported cost only as the fallback for unknown models.
- **Version bumps touch three files**: `AppModel.appVersion`, `Resources/Info.plist` (`CFBundleShortVersionString`/`CFBundleVersion`), and `Sources/GantryPluginMCP/main.swift`.

## UI conventions

- Target macOS 26 Liquid Glass APIs; it is a single-window app.
- Reuse `Design/Theme.swift` and `Design/Components.swift`; follow existing surfaces and spacing.
- Verify UI changes in **both light and dark** appearance and keep accessibility labels meaningful.
- Markdown is parsed by the dependency-free `MarkdownParser` (`GantryCore`) and rendered by `Utilities/MarkdownRendering.swift`; syntax highlighting is custom.

## Tests

- Add or update tests in `Tests/GantryCoreTests` for behavior changes.
- Prefer the existing fake CLI (`ProtocolAndRuntimeTests`) and transport fixtures over real services.
- `swift test` must be green. If a change can't be tested automatically, describe exactly what you ran and observed.

## Git and repo

- **Conventional Commits**: `feat(scope): ...`, `fix: ...`, `docs: ...`, `refactor: ...`, `test: ...`, `chore: ...`.
- Branch off `main` for non-trivial work (`feat/...`, `fix/...`, `docs/...`). `main` is protected: pull requests, linear history, signed commits, no direct pushes.
- Never use `--no-verify`, `--no-gpg-sign`, or otherwise bypass signing.
- Never commit secrets, `.env*` files, or build output (`.build/`, `build/` are ignored).
- Update `README.md` when user-facing behavior or the project map changes; avoid duplicating documentation across files. Comments explain *why*, not *what*.

## Reference

- `README.md` — feature overview, protocol flow, storage/privacy details, project map.
- `CONTRIBUTING.md` — contribution rules, setup, test expectations.
