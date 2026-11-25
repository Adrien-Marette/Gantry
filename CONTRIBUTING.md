# Contributing to Gantry

Thanks for taking the time to contribute. Gantry is a native macOS workspace
for Claude Code, built with SwiftUI and Liquid Glass. It is an independent,
unofficial client and is not affiliated with Anthropic.

This guide covers development setup, what makes a good change, commit and pull
request conventions, and how contributions are licensed.

## Code of conduct

Be respectful and constructive. Harassment, discrimination, personal attacks,
and bad-faith behavior are not welcome. Maintainers may edit, close, or remove
issues, comments, and pull requests that violate these expectations.

## Before you start

- Search existing issues and pull requests before opening a new one.
- For large changes, new features, or anything that alters the architecture,
  open an issue first so the approach can be agreed before you write code.
- Small fixes, documentation improvements, and obvious bugs can go straight to
  a pull request.
- Do not add third-party dependencies, change tooling, or alter CI without
  discussing it with a maintainer first.
- Gantry requires macOS 26 or later. Changes must keep the app building for
  that deployment target.

## Development setup

Requirements:

- macOS 26 or newer
- Xcode 26/27 toolchain with Swift 6.2 or newer
- [Claude Code](https://docs.anthropic.com/en/docs/claude-code) installed and
  authenticated (needed to exercise the app, not to build it)

```sh
git clone https://github.com/Adrien-Marette/Gantry.git
cd Gantry

swift build
swift test
```

To build the app bundle:

```sh
./Scripts/build-app.sh
open build/Gantry.app
```

The bundle is ad-hoc signed locally. If macOS quarantines a copied build, open
it once with Finder → Open.

Optional integration tests are gated because they touch real external systems:

```sh
# Spends a small amount of API credit against the installed CLI.
Gantry_RUN_CLI_INTEGRATION=1 swift test --filter realClaudeCodeSmokeTest
Gantry_RUN_CLI_INTEGRATION=1 swift test --filter realClaudeCodeReportsSlashCommands
Gantry_RUN_CLI_INTEGRATION=1 swift test --filter modScaffoldCLIValidation

# Uses and removes disposable items in the login Keychain.
Gantry_RUN_KEYCHAIN_TESTS=1 swift test --filter keychainRoundTrip
Gantry_RUN_KEYCHAIN_TESTS=1 swift test --filter pluginKeychainRoundTrip
```

## Project layout

The package has four targets:

| Target | Purpose |
| --- | --- |
| `GantryCore` | Models, Claude Code runtime, provider and Keychain handling, code-host clients, MCP bridge, session review, search, persistence. Keep logic here so it stays testable. |
| `Gantry` | SwiftUI app: app state, design system, views, and orchestration. |
| `GantryPluginMCP` | Bundled stdio MCP helper that forwards tool calls to the app. |
| `GantryCoreTests` | Swift Testing suite for `GantryCore`, using a fake CLI and HTTP fixtures. |

The README's **Project map** lists every file and its responsibility. Read it
before adding a new file, and update it when the structure changes.

## Code guidelines

- Follow the existing patterns and naming. Prefer extending what is already
  there over introducing a parallel abstraction.
- Put behavior in `GantryCore` behind testable types; keep SwiftUI views thin.
- Do not log, print, or pass API keys, tokens, or credentials on command
  lines. Provider keys and code-host tokens belong in the Keychain through the
  existing storage types.
- Keep Claude Code's permission flow intact. Do not add a path that bypasses
  or auto-approves permission requests.
- Keep Review & Ship commits explicit and local. The confirmation sheet must
  list the files, each file is staged with a literal pathspec, and Gantry never
  pushes, amends, or bypasses hooks or signing.
- Streaming output is coalesced at roughly 30 fps; avoid introducing per-token
  UI work.
- UI changes must be checked in light and dark appearance, respect the
  existing Liquid Glass surfaces, and keep accessibility labels meaningful.
- Comments and documentation should explain *why*, not restate the code.
  Update the README when user-facing behavior changes, and avoid duplicating
  documentation across files.

## Tests

- Add or update tests in `Tests/GantryCoreTests` for behavior changes.
- Prefer focused tests over broad integration tests. Use the existing fake CLI
  and transport fixtures instead of calling real services.
- `swift test` must pass before a pull request is ready for review.
- If a change cannot be tested automatically, describe exactly what you ran
  and what you observed in the pull request.

## Commits and pull requests

- Use [Conventional Commits](https://www.conventionalcommits.org/):
  `feat: ...`, `fix: ...`, `docs: ...`, `refactor: ...`, `test: ...`,
  `chore: ...`. Scope is optional, for example `fix(permissions): ...`.
- Keep commits logical and the history readable. Do not mix unrelated changes.
- Branch from `main` and keep pull requests focused on one problem.
- Fill in the pull request template, link the related issue, and include
  screenshots for visible UI changes.
- Redact API keys, tokens, private paths, and personal data from logs and
  screenshots.
- Do not force-push a branch that is under review unless asked to.

## License of contributions

Gantry is distributed under the [Gantry Community License 1.0.0](LICENSE). By
submitting a pull request or any other contribution, you agree that your
contribution is licensed under that license and that you have the right to
grant it. You keep copyright to your work; you are granting the project the
right to use and distribute it under the project license.

## Security

Read [SECURITY.md](SECURITY.md) for the trust model, secret handling, and
reporting instructions. Do not open a public issue for a security
vulnerability; use GitHub's private vulnerability reporting on the
repository's **Security** tab, and never include real credentials, Keychain
contents, or user data in a report. Describe the issue with placeholders
instead.

## Questions

Open an issue using the feature request template for design questions, or ask
in an existing issue about the area you are working on. Small clarifying
questions are welcome; please keep them specific.
