# perf-smoothness — architecture decision

**Date:** 2026-11-26
**Status:** Implemented (streaming preview + transcript paragraph runs)

## Scope

- `AppModel.schedulePreviewFlush`: 32 ms → 16 ms (ADR-001).
- `LiveAssistantPreview`: no text selection while text is in flight.
- `MarkdownTextView`: consecutive paragraphs render as one `Text` so selection
  spans paragraph breaks; other block kinds keep their views (ADR-003).

Untouched: lists, quotes, code blocks, tables, scroll follower, glass composer,
permission flow, persistence.

## Evidence

- Panel preferred timing 120 Hz; `APTLimitRefreshRate = No`; Low Power Mode off.
- No `CVDisplayLink`, `CADisplayLink`, `TimelineView`, `drawingGroup`, or
  `preferredFrameRateRange` in the source.
- 32 ms flush was the only hard cap.
- SwiftUI ignores `NSParagraphStyle` inside `Text` (measured with
  `ImageRenderer`), so paragraph spacing comes from tuned line breaks.
- See ADR-001 and ADR-003 for the alternatives.

## Deferred

- Quick-scroll jitter on long transcripts — needs an Animation Hitches profile
  before further changes; suspects are row construction, selectable text,
  nested horizontal scroll views, and the glass dock.
- Selection still breaks at headings, lists, quotes, code blocks, and tables.
- Debug-vs-release comparison — the release bundle was built but not yet
  compared by the user.
