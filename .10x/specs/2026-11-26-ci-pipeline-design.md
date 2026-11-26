# CI pipeline on GitHub Actions

**Date:** 2026-11-26
**Slug:** ci-pipeline
**Status:** Design approved — awaiting spec review

## Problem

The repository has no automated checks. `AGENTS.md` makes `swift build` and
`swift test` the source of truth, but a pull request can merge without either
running. The release path — `Scripts/build-app.sh` and the version constants
spread across three files — is only exercised by hand.

## Goal

A GitHub Actions pipeline that runs on every pull request to `main` and every
push to `main`, with three required checks:

1. **Build and test** — `swift build`, then `swift test`.
2. **Release bundle** — `./Scripts/build-app.sh` builds the `.app` end to end.
3. **Version consistency** — the three version locations agree.

## Non-goals

- No gated CLI or Keychain tests. They spend API credit or touch the login
  Keychain and stay opt-in by project rule.
- No release publishing, Developer ID signing, or notarization.
- No third-party dependencies, linters, or formatters. The project has none;
  adding one is a separate tooling decision.
- No artifact upload. The bundle job proves the release path builds.
- CI never commits, pushes, opens pull requests, or touches repository
  settings.

## Platform

GitHub-hosted `macos-26` (arm64) runners are GA and ship Xcode 26.6, which
satisfies `Package.swift` (`macOS 26.0`, Swift tools 6.2, language mode v5).
The repository is public, so standard runners are free. The version check does
not need macOS: `ubuntu-latest` runs the POSIX shell script.

## Workflow

File: `.github/workflows/ci.yml`

- **Triggers:** `pull_request` to `main`, `push` to `main`,
  `workflow_dispatch`.
- **Permissions:** `contents: read` only.
- **Concurrency:** one group per ref, cancel superseded runs.
- **Jobs** (the job `name:` is the required check context):
  - `Build and test` — `macos-26`, 30-minute timeout:
    `actions/checkout@v5`, `swift --version`, `swift build`, `swift test`.
  - `Release bundle` — `macos-26`, 30-minute timeout:
    `actions/checkout@v5`, `./Scripts/build-app.sh`.
  - `Version consistency` — `ubuntu-latest`, 5-minute timeout:
    `actions/checkout@v5`, `Scripts/check-version.sh`.

`actions/checkout@v5` is the only action. It is pinned by major tag, not commit
SHA; accepted for a first-party action.

## Version guard

File: `Scripts/check-version.sh` (POSIX `sh`, executable).

Sources compared:

| Source | Location |
| --- | --- |
| App version | `Sources/Gantry/App/AppModel.swift` → `static let appVersion` |
| Bundle version | `Resources/Info.plist` → `CFBundleShortVersionString` |
| MCP helper version | `Sources/GantryPluginMCP/main.swift` → `"version": .string(...)` |

The script fails when a value cannot be read or when the three differ, and
prints the compared values on failure. `CFBundleVersion` is a build number
(`6`), not the marketing version, and is not compared. The script runs on
macOS and Linux so it works locally and in the Ubuntu job.

## Ruleset

`protect-main.ruleset.json` gains a `required_status_checks` rule with contexts
`Build and test`, `Release bundle`, and `Version consistency`.

GitHub matches the context against the job-level check name, not
`Workflow / Job`. The three job names are therefore part of the interface and
must not be renamed casually. `strict_required_status_checks_policy` stays
false: history is already linear and requiring branches to be up to date would
add rebase churn.

Bootstrap order matters. Merge the workflow first, confirm the three check
names on a pull request, then apply the ruleset. The ruleset's existing
repository-role bypass covers that first merge.

## Documentation

- `AGENTS.md` — record the CI jobs under "Build and test" and state that gated
  tests never run in CI.
- `CONTRIBUTING.md` — one line describing the required checks for contributors.
- `README.md` — add `Scripts/check-version.sh` to the project map and mention
  CI in Verification.

## Verification

Planned locally before handing off:

- `sh Scripts/check-version.sh` passes and fails correctly on mismatched input.
- YAML parses.
- `swift build` and `swift test` pass.
- `./Scripts/build-app.sh` produces `build/Gantry.app`.

The GitHub-hosted run can only be observed after the workflow is pushed; that
is the user's step, not part of this change.

## Risks

- GitHub can change the installed toolchain on `macos-26`; the workflow follows
  the image default. A toolchain regression surfaces on the next PR.
- Renaming a job silently breaks its required check; the name is a ruleset
  contract and is documented here.
- The macOS jobs cost a few minutes each and the release job repeats a build.
  Acceptable on free public-repo runners.
- Tag-pinned `actions/checkout` is not full supply-chain pinning; revisit with
  SHA pinning if the repository adopts that policy.

## Open questions

None.
