# ADR-003: Merge consecutive paragraphs into one Text for selection

**Status:** Accepted
**Date:** 2026-11-26
**Feature:** perf-smoothness
**Author:** 10x-Team (Architect + Staff Engineer)

## Context

Each markdown block renders as its own `Text` with `.textSelection(.enabled)`.
SwiftUI selection does not span separate `Text` views, so a drag stops at a
paragraph break — the user reports selecting one paragraph at a time. A long
transcript also instantiates many selectable text views, which is a plausible
contributor to quick-scroll hitches.

A headless `ImageRenderer` test showed SwiftUI ignores `NSParagraphStyle`
inside `Text`: paragraph spacing must come from line breaks.

## Decision

Group consecutive `.paragraph` blocks into one `Text` built from concatenated
`AttributedString`s. Separate paragraphs with a blank line whose run uses a
4 pt font; measured gap is 13 pt against the previous 10 pt block spacing.
All other block kinds keep their dedicated views.

## Alternatives Considered

| Alternative | Pros | Cons | Why Not |
| --- | --- | --- | --- |
| Keep one Text per paragraph | Zero risk | Selection cannot cross paragraph breaks | Does not fix the reported bug |
| TextKit / NSTextView renderer | Full cross-block selection | Large rewrite, loses per-block chrome | Disproportionate now |
| Merge lists, quotes, code too | Maximum selection range | Loses hanging indents, quote bars, code chrome | Visual regression |

## Consequences

### Positive

- Drag selection spans paragraph breaks inside a run.
- Fewer text views per message, which reduces row construction cost during
  scrolling.

### Negative

- Inter-paragraph gap grows from 10 pt to about 13 pt.
- Headings, lists, quotes, code, and tables still break a selection run.

### Risks

- A single very long `Text` lays out all paragraphs at once. Mitigation: keep
  the existing lazy row boundary; measure if a huge answer hitches.

## Dependencies

- `InlineMarkdown.attributed` output must stay concatenation-safe.
