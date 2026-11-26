# Security review — ci-pipeline

**Date:** 2026-11-26
**Branch:** `fix/streaming-preview-60fps` (same commit as `main`; not committed)
**Scope:** `.github/workflows/ci.yml`, `Scripts/check-version.sh`,
`protect-main.ruleset.json`

## Model

Public repository, untrusted fork PRs, ephemeral GitHub-hosted runners, no
secrets. The change is build verification only.

## Checks performed

| Check | Result |
| --- | --- |
| Workflow token scope | `contents: read`, workflow-level |
| Secret references | None |
| Dangerous triggers (`pull_request_target`, `workflow_run`) | None |
| Shell injection from PR-controlled values | None; no expressions in `run:` |
| Third-party actions | None; only `actions/checkout` |
| Artifact/repository writes | None |
| Keychain or API access from tests | None; gated tests early-return without env flags |
| Version script input handling | Reads fixed repository paths; no `eval`, no network |
| Ruleset effect | Adds required checks; does not remove signed-commit, linear-history, or PR rules |

## Findings

1. **Tag-pinned first-party action (low, accepted).** `actions/checkout@v5`
   could theoretically be retagged upstream. SHA pinning is the stricter
   control; deferred because the action is first-party, read-only, and the
   repository has no secret to lose.
2. **PR code executes during build (info).** Inherent to any build CI. No
   credentials exist on the runner and GitHub's first-time-contributor approval
   setting can gate unknown authors.
3. **Check-name contract (low).** Renaming a job silently leaves a required
   context that never posts. Documented in the spec, ADR, and the workflow
   comment.

## Verdict

No blocking issues. No new credential, permission, permission-prompt, MCP, or
push surface is introduced. Required checks reinforce the existing `main`
protection.

## Follow-ups

- Re-review if CI gains secrets, release publishing, artifacts, or any action
  that is not first-party.
- After the first hosted run, confirm the workflow requested only the declared
  permission and that no unexpected checks were added.
