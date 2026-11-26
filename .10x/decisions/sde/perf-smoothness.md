# perf-smoothness — implementation notes

**Date:** 2026-11-26
**Branch:** `fix/streaming-preview-60fps`

## Built

- `AppModel+Conversation.swift` — preview flush 32 ms → 16 ms (~60 fps).
- `MessageViews.swift` — live preview thinking/text no longer selectable;
  finalized messages keep selection.
- `MessageViews.swift` — consecutive paragraph blocks render as one `Text`
  (blank-line separator with a 4 pt run) so drag selection spans paragraph
  breaks; measured gap 13 pt against the previous 10 pt.
- Invariant text updated: `AGENTS.md`, `ARCHITECTURE.md`, `DESIGN.md`,
  `README.md`, `CONTRIBUTING.md`.
- Decisions recorded: ADR-001, ADR-003.

## Deviations

- The release-build comparison was not reported by the user, so I proceeded
  with the streaming cap fix (certain, independent of perception) and deferred
  idle-scroll/glass work until it is measured.
- No schema or database changes (DBA not applicable). No security-sensitive
  surface touched.

## Verification

- `swift build` — pass.
- `swift test` — 144 tests pass.
- Manual check pending: streaming smoothness in the release bundle, light and
  dark appearance (selection behaviour changed on the transient preview only).

## Follow-ups

- Idle-scroll cost (glass dock + selectable finalized text) is unprofiled.
- Per-tick cost doubles on the streaming path; if long answers hitch, fall back
  to 24 ms per ADR-001.
