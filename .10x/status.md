# Status

**Active feature:** ci-pipeline
**Phase:** PR #9 merged — ruleset application pending
**Branch:** `main` (PR #9 merged as `a595314`; perf work committed as `69f6693`)
**Updated:** 2026-11-26

## ci-pipeline

### Done

- Scope approved: build + test, release bundle, version consistency; all three
  required on `main`.
- Spec: `.10x/specs/2026-11-26-ci-pipeline-design.md`.
- ADR-002: `.10x/adrs/002-github-actions-ci.md`.
- Implemented `.github/workflows/ci.yml`, `Scripts/check-version.sh`,
  `protect-main.ruleset.json`, and the three docs.
- Local verification green: version script (match, mismatch, missing source),
  YAML/JSON parse, `swift build`, 144/144 tests, `./Scripts/build-app.sh`.
- Committed `bea3d12` (GPG-signed), pushed, opened PR #9.
- First hosted run 45771865212 passed all three checks with the expected names.
- PR #9 merged to `main` as `a595314`.
- QA report: `.10x/reviews/2026-11-26-qa-report-ci.md`.
- Security review: `.10x/reviews/2026-11-26-security-review-ci.md`.

### Open

- Apply `protect-main.ruleset.json` in GitHub; the merge is done.

## perf-smoothness (earlier work)

**Phase:** Committed — manual verification pending
**Branch:** `main` (`69f6693`)

### Done

- Release bundle built (exit 0) at `build/Gantry.app`.
- ADR-001: streaming preview 32 → 16 ms (~60 fps); no selection on the
  transient preview.
- ADR-003: consecutive paragraphs render as one Text so selection spans
  paragraph breaks; 4 pt separator, measured 13 pt gap.
- Docs updated: `AGENTS.md`, `ARCHITECTURE.md`, `DESIGN.md`, `README.md`,
  `CONTRIBUTING.md`.
- `swift build` pass; `swift test` 144/144 pass.
- QA report: `.10x/reviews/2026-11-26-qa-report.md`.
- Static audit: markdown blocks, inline attributes, and code highlighting are
  all NSCache-backed; no uncached per-frame work found in the transcript path.

### Open

- Manual release-build check: streaming, quick scrolling of a long transcript,
  and drag selection across paragraph breaks (user).
- Quick-scroll jitter: needs an Animation Hitches trace if it persists.
- Selection still breaks at headings, lists, quotes, code blocks, and tables.

## Not applicable

- DBA: no schema change.
- Security: no credential, permission, or MCP surface touched by
  perf-smoothness; CI is reviewed in its own security decision.
