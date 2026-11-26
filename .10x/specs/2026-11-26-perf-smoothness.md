# Perf smoothness — measure first

**Date:** 2026-11-26
**Slug:** perf-smoothness
**Status:** Approach approved — measurement in progress

## Problem

Gantry feels capped at ~60 fps on a 120 Hz display. The user cannot yet
separate streaming replies from idle scrolling ("everywhere / not sure").

## Evidence

### Measured

- Internal panel preferred timing: 120.0 Hz (`SyncRate 7864320`),
  `APTLimitRefreshRate = No`, Low Power Mode not set. The OS is not holding
  the display at 60.
- No frame-pacing API in the source: no `CVDisplayLink`, `CADisplayLink`,
  `TimelineView`, `drawingGroup`, or `preferredFrameRateRange`.

### Code inspection

- `AppModel+Conversation.swift:705` — preview flushes every 32 ms (~30.6 Hz);
  this is the only hard rate limit and a documented invariant.
- `MessageViews.swift:591` — the live preview renders the whole accumulated
  string as one selectable `Text`, relaid out on every flush.
- `ChatWorkspaceView.swift:578` — `PreviewScrollFollower` calls
  `scrollTo("bottom")` on each flush while the user is at the bottom.
- `ChatWorkspaceView.swift:432`, `ComposerView.swift:254` — the Liquid Glass
  composer dock floats over the scrolling transcript.
- `build/` contains no release bundle; a `swift run` or Xcode Run session is a
  debug (-Onone) build, the prime "everywhere" suspect.

## Approaches considered

| Approach | Pros | Cons | Verdict |
| --- | --- | --- | --- |
| Measure first (release build) | Cheapest discriminator; no speculative code; isolates debug build vs code vs system | One user round trip | **Chosen** |
| Fix streaming now | Immediate text-smoothness gain | Changes a four-document invariant and doubles per-tick work; may not be the bottleneck | Deferred until measured |
| Instruments first | Most accurate | Most effort; needs interaction | Fallback if release still feels capped |

## Plan

1. Build the release bundle with `./Scripts/build-app.sh` (no source changes).
2. User compares in `build/Gantry.app`:
   - a streaming reply,
   - idle scrolling of a long transcript.
3. Fix only the implicated path:
   - **Streaming slow** → drop selection from the live preview; consider
     32 → 16 ms flush (requires an ADR plus `AGENTS.md`, `ARCHITECTURE.md`,
     `DESIGN.md`, `README.md` updates).
   - **Idle scroll slow** → Instruments profile before touching glass or
     `textSelection`.
   - **Release fixes it** → no code change; document the release build as the
     way to run.
4. `swift build` and `swift test` green before declaring done.

## Success criteria

- Reply text updates at ≥60 Hz and the transcript follows without visible
  hitches in the release build.
- Idle scrolling of a long transcript is smooth at the display rate.
- No behavior, permission-flow, or persistence changes; `swift test` green.

## Out of scope

- Redesigning the glass composer (`DESIGN.md` mandates it).
- Removing selection from finalized messages.
- Markdown parsing changes.
