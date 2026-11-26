# ADR-001: Raise streaming preview coalescing to ~60 fps

**Status:** Accepted
**Date:** 2026-11-26
**Feature:** perf-smoothness
**Author:** 10x-Team (Architect + Staff Engineer)

## Context

Streaming previews flush every 32 ms (~30.6 fps) in
`AppModel.schedulePreviewFlush`. That is the only hard rate limit in the app:
the panel reports 120 Hz, `APTLimitRefreshRate = No`, Low Power Mode is off,
and no frame-pacing API exists in the source. The 30 fps rule exists to keep
long answers from redrawing per token, not to cap the visible rate — but 30 fps
reads as steppy on a 120 Hz display. The live preview also enables text
selection on text that changes on every flush, which makes each relayout more
expensive.

## Decision

Flush the preview at 16 ms (~60 fps) and drop `.textSelection(.enabled)` from
the transient live preview only. Finalized messages, reasoning disclosures, and
every other surface keep selection.

## Alternatives Considered

| Alternative | Pros | Cons | Why Not |
| --- | --- | --- | --- |
| 8 ms (~120 fps) | Matches the panel | Approaches per-token redraw; doubles main-thread work again for no legibility gain | Token arrival is far below 120/s; 60 fps is enough |
| Keep 32 ms (~30 fps) | Zero risk | The visible cap remains | Does not address the complaint |
| Incremental text view (TextKit) | Avoids relayout of the whole string | New rendering architecture, large change | Disproportionate to the problem |

## Consequences

### Positive

- Reply text updates at 60 fps; bursts still coalesce, so per-token work is
  still forbidden.
- Cheaper per-tick layout because the transient text is no longer selectable.

### Negative

- Per-second layout cost doubles on the streaming path.
- Very long in-flight answers do more main-thread work than before.

### Risks

- A tick on a huge in-flight message may exceed 16 ms on slower machines.
  Mitigation: measure the release build; fall back to 24 ms if hitches appear.

## Dependencies

- Invariant text in `AGENTS.md`, `ARCHITECTURE.md`, `DESIGN.md`, `README.md`.
