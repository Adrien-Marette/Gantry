# Architect decision — ci-pipeline

**Date:** 2026-11-26
**Status:** Design approved — awaiting spec review
**ADR:** [ADR-002](../../adrs/002-github-actions-ci.md)

## Components

| Component | Boundary |
| --- | --- |
| `.github/workflows/ci.yml` | Orchestration only; one job per concern |
| `Scripts/check-version.sh` | Pure read-and-compare over three files; no network, no build |
| `protect-main.ruleset.json` | Merge policy; consumes the job check names |
| Existing `Scripts/build-app.sh` | Unchanged release-bundle path |

The workflow owns no product logic. The version script mirrors the documented
three-file invariant in `AGENTS.md`; it does not introduce a fourth version
source.

## Data flow

```
pull_request / push to main
        |
        +--> Build and test (macos-26): swift build -> swift test
        +--> Release bundle (macos-26): Scripts/build-app.sh
        +--> Version consistency (ubuntu-latest): Scripts/check-version.sh
        |
        v
GitHub check runs named by job `name:`
        |
        v
Ruleset on main requires all three before merge
```

## Boundaries

- No secrets, Keychain items, or provider tokens are available to the workflow.
- Gated CLI and Keychain tests are excluded by construction; the default
  `swift test` suite is the only test run.
- No artifacts leave the runner, and no workflow writes to the repository.
- UI behavior is untouched; there is no light/dark verification obligation.

## Failure modes

- **Runner/toolchain drift** — image changes can break builds without a code
  change. The workflow prints `swift --version`; reruns discriminate flakiness
  from a real regression.
- **Check-name drift** — renaming a job leaves a required context that never
  posts, which looks like a pending check. Keep names stable.
- **Bootstrap deadlock** — required checks before the workflow reaches `main`
  block every PR. Apply the ruleset after the first successful run.
- **Version extraction drift** — if a version constant moves or changes shape,
  the guard fails closed (empty read), which is the intended behavior.

## Not applicable

- DBA: no data model.
- Runtime architecture: no process, protocol, or persistence change.
