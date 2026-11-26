# SDE decision — ci-pipeline

**Date:** 2026-11-26
**Status:** Implemented — local verification green
**ADR:** [ADR-002](../../adrs/002-github-actions-ci.md)

## Built

- `.github/workflows/ci.yml` — three jobs with the required check names,
  `macos-26` for build/test and release bundle, `ubuntu-latest` for the version
  check, read-only permissions, per-ref concurrency.
- `Scripts/check-version.sh` — POSIX `sh`, executable, compares
  `AppModel.appVersion`, `Info.plist` `CFBundleShortVersionString`, and the MCP
  helper version.
- `protect-main.ruleset.json` — `required_status_checks` with `Build and test`,
  `Release bundle`, `Version consistency`.
- `AGENTS.md`, `CONTRIBUTING.md`, `README.md` — CI contract and project map.

## Local verification

- `sh Scripts/check-version.sh` → `versions match: 0.4.1`.
- Temp copy with a mismatched app version → exit 1 with all three values.
- Temp copy with a missing plist → exit 1 with the missing-source diagnostic.
- YAML parses; ruleset JSON parses.
- `swift build` → pass.
- `swift test` → 144 tests, 144 passed.
- `./Scripts/build-app.sh` → `build/Gantry.app` built and ad-hoc signed.

## Deviations

- Added `|| true` inside the command substitutions so a missing file reaches the
  explicit diagnostic instead of aborting under `set -e` with a raw tool error.

## Limits and tech debt

- Version sources are matched by exact text patterns. Refactoring those
  declarations fails CI closed until the patterns are updated; that is
  intentional.
- No SwiftPM cache, no artifact upload, and actions are tag-pinned rather than
  SHA-pinned. All three are deliberate v1 choices recorded in the spec.
- The first hosted run and the ruleset application remain user steps.

## Files touched

- New: `.github/workflows/ci.yml`, `Scripts/check-version.sh`.
- Modified: `protect-main.ruleset.json`, `AGENTS.md`, `CONTRIBUTING.md`,
  `README.md`.
- State: spec, ADR-002, architect, devops, sde, qa, security, reports.
