# DevOps decision — ci-pipeline

**Date:** 2026-11-26
**Status:** Design approved — implementation pending
**ADR:** [ADR-002](../../adrs/002-github-actions-ci.md)

## Pipeline

| Job | Runner | Timeout | Purpose |
| --- | --- | --- | --- |
| `Build and test` | `macos-26` | 30 min | Package and app target compile; default test suite passes |
| `Release bundle` | `macos-26` | 30 min | `Scripts/build-app.sh` produces a signed `.app` |
| `Version consistency` | `ubuntu-latest` | 5 min | Three version constants agree |

- Triggers: PRs to `main`, pushes to `main`, manual dispatch.
- `permissions: contents: read`; concurrency cancels superseded runs.
- No cache in v1. A `.build` cache can be added if macOS job time becomes a
  problem; the package has no dependencies, so the risk/benefit is currently
  poor.
- No deployment. This is build verification only.

## Toolchain

The workflow uses the `macos-26` image default (Xcode 26.6 at the time of
writing) and logs `swift --version`. Pinning a specific Xcode path would break
when GitHub retires that minor version; following the image default is the
maintenance-free choice.

## Required checks and bootstrap

Required contexts, which equal the job `name:` values:

- `Build and test`
- `Release bundle`
- `Version consistency`

Apply `protect-main.ruleset.json` only after the workflow is on `main` and the
three checks have appeared on a real pull request. Applying earlier blocks
every PR on checks that never post. The ruleset keeps its repository-role
bypass for the bootstrap merge.

## Cost

The repository is public, so standard GitHub-hosted runners are free. Three
macOS job starts per PR is the cost in wall-clock time, not billing.

## Runbook

- **Red on a docs-only PR** — check whether `macos-26` toolchain or runner
  availability changed; rerun the job, then compare `swift --version`.
- **A required check never appears** — the job was renamed or the workflow did
  not trigger. Confirm the `name:` matches the ruleset context and that the
  workflow runs on `pull_request`.
- **Release bundle fails only in CI** — reproduce with
  `./Scripts/build-app.sh` locally; the icon renderer is CoreGraphics-only and
  headless-safe, so a failure is likely a path or toolchain issue.
- **Rollback** — revert the workflow and remove the required checks from the
  ruleset. CI has no state and no deployment to unwind.

## Local verification (2026-11-26)

- `sh Scripts/check-version.sh` → `versions match: 0.4.1`.
- Failure paths: mismatch and missing source both exit 1 with a diagnostic.
- Workflow YAML and ruleset JSON parse.
- `swift build` pass; `swift test` 144/144 pass.
- `./Scripts/build-app.sh` produced `build/Gantry.app`.

## First hosted run (2026-11-26)

Run 45771865212 on PR #9 passed all three checks with the expected names:

| Check | Duration |
| --- | --- |
| `Version consistency` | 4 s |
| `Build and test` | 1m57s |
| `Release bundle` | 2m11s |

## Open

- Merge PR #9, then apply the ruleset; the check names are confirmed.
