# Security decision — ci-pipeline

**Date:** 2026-11-26
**Status:** Reviewed — no blocking findings
**Scope:** GitHub Actions workflow, version script, ruleset change

## Threat model

The repository is public, so pull requests may come from forks and their code
is untrusted. The CI workflow has no access to provider keys, code-host tokens,
the login Keychain, or a write-scoped `GITHUB_TOKEN`. Runners are ephemeral and
GitHub-hosted.

## Controls

- `permissions: contents: read` at workflow level; no job grants more.
- No `pull_request_target`, no `workflow_run`, no repository secrets.
- No `${{ }}` interpolation inside `run:` commands; job names and run steps are
  static, so PR-controlled text cannot reach the shell.
- Only first-party `actions/checkout` is used.
- No artifacts are uploaded and no workflow writes to the repository.
- Gated tests stay out of CI: the default suite early-returns unless
  `Gantry_RUN_CLI_INTEGRATION` or `Gantry_RUN_KEYCHAIN_TESTS` is `1`, and the
  workflow sets neither. No Keychain or API access can occur.
- The release job executes repository code (`swift build`, icon renderer,
  `codesign`) on an ephemeral runner with no secrets; fork PRs gain nothing
  beyond free compute, which GitHub's first-time-contributor approval setting
  also moderates.

## Findings

| Finding | Severity | Disposition |
| --- | --- | --- |
| `actions/checkout@v5` pinned by tag, not commit SHA | Low | Accepted for a first-party action; revisit if SHA pinning becomes repository policy |
| Job names are a merge-gate contract | Low | Documented in the spec and ADR; renaming is an explicit ruleset change |
| Pull-request code runs in the release job | Info | Inherent to build CI; no secrets, ephemeral runner |

## Verdict

No blocking security issues. The workflow adds no credential surface and cannot
approve Claude Code permissions, commit, push, or publish. Required checks
strengthen the existing signed-commit and linear-history rules rather than
weakening them.

## Follow-ups

- After the first hosted run, confirm the three check names and that no extra
  permissions were requested.
- If the repository later adds secrets or release publishing, re-review with a
  dedicated environment and least-privilege job permissions.
