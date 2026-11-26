# QA decision — ci-pipeline

**Date:** 2026-11-26
**Status:** Verified locally and hosted — ruleset application pending
**Scope:** `.github/workflows/ci.yml`, `Scripts/check-version.sh`,
`protect-main.ruleset.json`, CI documentation

## Strategy

Each CI job was mirrored locally: the version guard in both success and failure
modes, YAML and JSON parsing, the default Swift test suite, and the release
bundle build. The hosted workflow cannot be executed without pushing, so it is
explicitly out of local scope.

## Results

| Check | Result |
| --- | --- |
| Version script, matching versions | Pass — `versions match: 0.4.1` |
| Version script, mismatched app version | Pass — exit 1, all values printed |
| Version script, missing plist | Pass — exit 1, missing source named |
| Workflow YAML parse | Pass |
| Ruleset JSON parse | Pass |
| `swift build` | Pass |
| `swift test` | 144/144 pass |
| `./Scripts/build-app.sh` | Pass — `build/Gantry.app` |

## Edge cases covered

- Empty extraction (moved/renamed source) fails closed.
- Mismatch among any pair fails.
- `CFBundleVersion` (`6`) is intentionally excluded; it is a build number.
- Workflow uses no path filters, so required checks cannot be skipped by a
  docs-only change.
- Job `name:` values match the ruleset contexts exactly.

## Bug found and fixed

A missing version source originally aborted the script under `set -e` with awk's
raw error (exit 2). The command substitutions now tolerate a failed read so the
script prints the intended diagnostic naming the missing source (exit 1).

## Hosted run

Run 45771865212 on PR #9 passed all three checks: `Version consistency` in 4 s,
`Build and test` in 1m57s, `Release bundle` in 2m11s.

## Not verified

- Required-check enforcement after the ruleset is applied.

## Gaps

The version script has no automated failure-path test inside `swift test`; it is
a shell script outside the Swift targets. Its happy path runs on every CI
execution, and all three failure modes were exercised manually. Adding a shell
test harness is not justified for a 20-line script unless it grows.
