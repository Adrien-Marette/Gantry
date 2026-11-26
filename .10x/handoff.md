# Handoff

**Active feature:** ci-pipeline
**Branch:** `main` — PR #9 merged as `a595314`; perf work committed as `69f6693`
**State:** CI is on `main`; perf and the 0.4.1 release branch are merged.

## Next — ci-pipeline

1. Apply `protect-main.ruleset.json` in GitHub; the three check names are
   confirmed.
2. Optional: confirm a failing job blocks a throwaway test PR.
3. Remove the temporary worktree:
   `git worktree remove /private/tmp/claude-501/gantry-ci-worktree`.
4. Do not apply the ruleset or merge without the user asking.

## Earlier work — perf-smoothness

**State:** committed on `main` as `69f6693`, build and tests green, manual
check pending.

1. Run `open build/Gantry.app`, send a long prompt, scroll a long finished
   transcript quickly, then drag-select across several paragraphs.
2. Streaming smooth, quick scroll smooth, selection spans paragraphs → ready
   to commit or open a PR when the user asks.
3. Quick scroll still jitters → record an Animation Hitches trace; paragraph
   runs already reduced the number of text views per row.
4. Selection still stops at headings, lists, quotes, code blocks, and tables.
5. Streaming still hitches on very long answers → try a 24 ms flush
   (ADR-001 risk).
6. Never push or open a PR without the user asking.
