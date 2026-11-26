# QA report — ci-pipeline

**Date:** 2026-11-26
**Branch:** `fix/streaming-preview-60fps` (same commit as `main`; not committed)
**Scope:** GitHub Actions workflow, version guard, ruleset, CI documentation

## Automated

- `sh Scripts/check-version.sh` — pass (`versions match: 0.4.1`).
- Temp-copy failure tests — mismatch exit 1; missing source exit 1 with a named
  diagnostic. Temp copies lived under `$TMPDIR`; the repository was untouched.
- Workflow YAML — parses with Ruby Psych.
- Ruleset JSON — parses with `python3 -m json.tool`.
- `git diff --check` on the modified tracked files — clean.
- `swift build` — pass.
- `swift test` — 144 tests, 144 passed, 0 failed.
- `./Scripts/build-app.sh` — release build, icon, helper, and ad-hoc signature
  completed; `build/Gantry.app` present.

## Static review

- Job names `Build and test`, `Release bundle`, and `Version consistency` match
  the required contexts added to `protect-main.ruleset.json` exactly.
- Workflow triggers on both `pull_request` and `push` to `main`; no path filter
  can skip a required check.
- `permissions: contents: read`; no secrets are referenced.
- Gated tests early-return without their environment flags; the workflow sets
  neither flag.
- The version script fails closed when a source cannot be read.

## Defect found

The missing-source path originally exited 2 with awk's raw error because
`set -e` aborted inside the command substitution. Fixed by tolerating the failed
read and emitting the intended diagnostic. Retested.

## Manual checks outstanding

- First hosted run (45771865212) — passed: `Version consistency` 4 s,
  `Build and test` 1m57s, `Release bundle` 2m11s.
- Apply `protect-main.ruleset.json` after merge, then confirm a PR blocks while
  a required job is failing.
- Confirm the `macos-26` image default toolchain still satisfies
  `Package.swift` at that time.

## Release readiness

Hosted run green; ruleset application and merge are user steps.
