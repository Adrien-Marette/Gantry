# Design

Gantry's visual system: a warm neutral workbench, one terracotta accent, SF
typography, and Apple's real Liquid Glass reserved for the floating layer.
`Sources/Gantry/Design/Theme.swift` and `Components.swift` are the source of
truth; this document explains how to use them and where the lines are.

## Direction

Gantry should feel like a quiet macOS tool that belongs next to Xcode and
Terminal, not like a chat product. The transcript is the interface. Chrome
floats above it; content sits flat. Color is information, not decoration.

The brand is a flat terminal prompt glyph in one solid accent — no gloss, no
sparkle, no colored shadow.

## Principles

1. **The conversation is the interface.** Project navigation and settings stay
   quiet so the work stays legible.
2. **Chrome floats; content sits.** Glass belongs to the sidebar and the
   floating layer. The transcript and cards are flat neutrals with hairlines.
3. **One accent, earned.** Terracotta marks selection, live work, the primary
   action, links, and focus. It never tints a surface.
4. **Hierarchy comes from size and color.** One family, one scale, three
   weights. Figures are tabular.
5. **Motion confirms, never performs.** Short ease-out transitions on state
   changes; no looping decoration, no per-token animation.
6. **Native before custom.** Use system controls, system progress, and real
   Liquid Glass before drawing anything new.

## Palette

All colors are defined as dynamic light/dark pairs in `Palette`. Use the token,
never a literal in a view.

| Token | Light | Dark | Use |
| --- | --- | --- | --- |
| `accent` | `#A9472C` | `#E58B6B` | Selection rail, live work, primary action, links, focus |
| `onAccent` | `#FFFFFF` | `#1A120E` | Content on accent |
| `ink` | `#1F1B16` | `#EFE9DE` | Primary text and icons |
| `secondaryInk` | `#5E554A` | `#AAA398` | Supporting text |
| `tertiaryInk` | `#6F665A` | `#8A847A` | Metadata, quiet icons |
| `faintInk` | `#746B5F` | `#847E74` | Helper text and footnotes |
| `canvas` | `#F7F4EE` | `#161513` | Window background |
| `surface` | `#FDFBF7` | `#1C1A18` | Content cards |
| `surfaceRaised` | `#FFFFFF` | `#262421` | Emphasized content card |
| `field` | `#F2EDE4` | `#201D1A` | Text fields and search |
| `codeSurface` | `#F4EFE8` | `#0F0E0D` | Code block body |
| `codeHeader` | `#EDE6DD` | `#181614` | Code block header |
| `line` | ink at 9% | ink at 10% | Hairlines |
| `lineStrong` | ink at 15% | ink at 16% | Stronger dividers |
| `sidebarSelection` | ink at 6% | white at 7% | Selected sidebar row |
| `sidebarHover` | ink at 3.5% | white at 4% | Hovered sidebar row |
| `scrim` | black at 24% | black at 24% | Command-palette backdrop |

Semantic colors:

| Token | Light | Dark | Use |
| --- | --- | --- | --- |
| `success` | `#3D6B4B` | `#95B99A` | Completed, saved, copied |
| `warning` | `#8A5A12` | `#E0B36A` | Caution, load errors |
| `danger` | `#A83A32` | `#E48277` | Destructive actions and errors |
| `info` | `#3D5F80` | `#94B8DC` | Informational notices |

Code highlighting:

| Token | Light | Dark |
| --- | --- | --- |
| Keyword | `#9A3B27` | `#E68E70` |
| String | `#4A6A44` | `#A6C99A` |
| Number | `#7E5A22` | `#D7B47A` |
| Type | `#3D6182` | `#9DC3E6` |
| Comment | `#7B7266` | `#7A7368` |
| Plain | `#2B2723` | `#E8E2D9` |
| Function | `#6B4D6D` | `#D7A9D8` |

Diff backgrounds are `diffAddition` (`#E3EEE2` / `#17291C`) and `diffDeletion`
(`#F4E2DF` / `#2E1A18`), with matching darker/lighter text tokens.

### Accent rules

The accent is a signal, not a theme:

- **Allowed:** the 2 pt selection rail, live indicator, primary action, links,
  focus rings, and the permission card's allow action.
- **Not allowed:** section backgrounds, card tints, gradients, large type,
  decorative borders, or idle icons.
- Destructive actions use `danger`, not the accent.

## Typography

One family: San Francisco (`Font.system`). Hierarchy comes from size and color,
not from extra weights or families.

| Token | Size / weight | Use |
| --- | --- | --- |
| `display` | 30 semibold | Welcome title, rare empty-state headline |
| `pageTitle` | 22 semibold | Page headers such as Extensions & Mods |
| `sectionTitle` | 17 semibold | Sheet and settings section titles |
| `headline` | 13 semibold | Row titles that need emphasis |
| `body` | 14 regular | Conversation text and prose |
| `bodyMedium` | 14 medium | Emphasized body and primary list text |
| `ui` | 13 medium | Controls and sidebar labels |
| `caption` | 12 regular | Supporting copy and metadata |
| `captionMedium` | 12 medium | Labels and compact buttons |
| `micro` | 11 medium | Hints, badges, footnotes |
| `mono` | 12 monospaced | Code and commands |
| `monoSmall` | 11 monospaced | Dense code and paths |
| `keycap` | 10 medium monospaced | Shortcut hints |
| `figure` | 17 regular, tabular | Cost and token totals |
| `figureSmall` | 14 regular, tabular | Inline figures |

Use `.monospacedDigit()` or the figure tokens wherever numbers change in place.
Do not introduce letter-spacing, uppercase labels, or a second type family.

## Geometry

- **Window:** one main window plus a menu bar extra, minimum 1040 × 700,
  full-size content, transparent title bar. No tabbing. Closing the main window
  hides the app instead of quitting: Claude keeps working and the menu bar extra
  remains. Move the window by dragging the chat header or the sidebar header;
  the drag stays native so the Window Server receives the original mouse-down
  rather than a synthesized gesture.
- **Sidebar:** fixed 264 pt, real glass, trailing hairline.
- **Inspector:** 306 pt, content surfaces, trailing reveal.
- **Settings:** 620 × 460.
- **Radii:** 8 controls, 12 content cards, 16 panels, 20 for floating glass such
  as the composer, permission and question cards, palette, and welcome card.
- **Spacing:** follow the existing 4 / 8 / 12 / 16 / 20 / 24 rhythm. Prefer
  grouping with space and a hairline over nested boxes.
- **Borders:** one hairline, never a double border. Use `Hairline` or
  `hairlineBorder`.

## Materials

### Glass: chrome and the floating layer

Use `glassPanel(radius:interactive:)` or the system modifiers directly for:

- the sidebar rail (`.glassEffect(.regular, in: Rectangle())`)
- the composer (`glassPanel(radius: 20, interactive: true)`)
- permission and question cards (`glassPanel(radius: 20)`)
- the command palette (radius 20) and slash-command menu (radius 16)
- loader and notice banners
- the welcome card
- glass buttons (`.buttonStyle(.glass)`, `.glassProminent`)

Related glass elements that should merge or morph belong in
`GlassEffectContainer` with stable `glassEffectID` values, as the composer,
permission card, and question card do.

**Never decorate the glass material itself.** Do not add a custom fill,
gradient, highlight, shadow, or ornamental stroke on top of glass. The single
accepted stroke is the accent focus ring drawn around the composer's glass
shape; do not introduce more. Do not stack arbitrary glass panels on content.

### Content: flat surfaces

- `surfaceCard(radius:strong:)` — flat neutral fill plus a hairline. Use for
  inspector cards, settings groups, repository details, and extension cards.
- `FieldBackground(radius:focused:)` — neutral field fill with a hairline or an
  accent focus border.
- `CanvasBackground` — the one window fill.
- `Hairline` — separators, one pixel, never a shadow.

No content surface gets a gradient, glow, drop shadow, or accent wash. If a
card needs emphasis, use `strong: true` for one step up, not color.

### Light and dark

Every token is a dynamic pair. Check both appearances before shipping:

- contrast of `secondaryInk` and `tertiaryInk` on `canvas` and `surface`
- hairlines still visible but quiet
- glass retains legibility over the transcript and sidebar content
- code and diff colors remain distinguishable
- the accent stays legible on both canvases

## Components

Reuse these before creating a new control:

| Component | Role |
| --- | --- |
| `BrandMark` / `GantryLockup` | Flat prompt glyph and name lockup |
| `LiveIndicator` | System indeterminate progress in the accent; stops with Reduce Motion |
| `QuietBadge` | Small dot plus label for state |
| `IconButton` | Icon-only action with hover fill, help text, and accessibility label |
| `CopyButton` | Copy with a short “Copied” confirmation |
| `KeyHint` | Keycap-style shortcut hint |
| `ControlLabel` | Icon + title + chevron menu label; no pill |
| `SectionLabel` | Quiet all-context section heading |
| `Spinner` | Small system progress view |
| `SurfaceBackground` | Flat card fill plus hairline |
| `FieldBackground` | Text-field surface |
| `glassPanel` | The only sanctioned glass surface helper |

Icon-only buttons always need `.help(...)` and an accessibility label. Labels
are sentence case.

## Motion

- Use `easeOut` between roughly 0.12 s and 0.20 s. Common values: 0.12 for
  selection, 0.16 for focus and banners, 0.20 for larger reveals.
- Use `.opacity` for content swaps and small controls; use
  `.move(edge:).combined(with: .opacity)` for the sidebar, inspector, and
  banners.
- Animate state changes, not decoration. No springs, bounces, pulses, or
  infinite ambient motion.
- Never animate per token. Streaming text is coalesced at ~30 fps before it
  reaches the view.
- Prefer the system `ProgressView` for live work; it respects Reduce Motion.
  Custom motion must also respect `accessibilityReduceMotion`.

## Screen anatomy

**Welcome** — brand lockup, a short promise, one primary action, and a glass
card. Drag-and-drop a folder is supported; the drop target changes without
moving the layout.

**Sidebar** — a glass rail with the lockup, search, New session, Extensions &
Mods, Graphify, then projects and sessions. The selected row uses
`sidebarSelection` plus a 2 pt accent rail. Hover uses `sidebarHover` and never
moves the row. The footer holds Settings.

**Chat header** — repository/branch control, provider menu, repository panel,
and inspector toggle. The model and permission menus live in the composer.
Menus are quiet `ControlLabel`s, not pills. Disable provider, model, and
permission changes while a turn is running.

**Transcript** — user and assistant turns, thinking, tool rows, errors, and
the live indicator. Tool rows are compact by default and expand in place.
Errors are concise, plain language, and keep technical detail secondary.

**Composer** — a floating glass panel with the text field, slash-command menu,
model and permission controls, and a circular send/stop button. Return sends;
Shift-Return inserts a newline. While a slash token is being typed, Return
chooses the highlighted command instead of sending. Focus is an accent ring.
Above the text field, a quiet context meter shows the prompt tokens Claude Code
last reported against the model's window, sized from the resolved model name of
the response that produced those tokens, with a neutral fill that turns warning
and then danger as the window fills. Files and folders can be dragged onto the
glass or chosen with the paperclip; chips sit above the text field with a quiet
ink wash and hairline, and a drop uses the same accent focus ring. A prompt may
consist of attachments alone.

**Permission card** — a floating glass card above the composer. It names the
tool and target, shows details on demand, and offers **Allow once**, a
contextual always-allow action when Claude Code suggests one, and **Deny**. The
primary allow action uses glass prominent; Deny is quiet but unmistakable.
Never hide the deny path or preselect approval.

**Question card** — the permission card's counterpart for `AskUserQuestion`.
It shows one question at a time with its optional header, offers every choice
with its description, and keeps an “Other” field for a typed answer; text
questions get a field, and number questions get a numeric field with range
hints and inline validation. Multi-question sheets use clickable step chips
plus **Back** and **Next**, so answers can be revisited before sending, and
report how many are answered. **Send answer** appears on the last question and
stays disabled until at least one answer is valid; **Decline** is always
visible. The accent marks the current step, the selected option, and the
primary action, while surfaces stay neutral.

**Command palette and slash menu** — glass panels, keyboard first. Arrow keys
move the highlight; Return runs or completes; Escape closes. Hover highlights a
row but must not scroll the list.

**Conversation search** — a content sheet opened with `⇧⌘F`, not glass. An
auto-focused search field sits above a quiet result list: role icon, session
title, one or two lines of snippet with the match in the accent, project name,
and relative time. Arrow keys move the selection and scroll; hover highlights
without scrolling; Return opens the session and reveals the matching turn. The
empty state explains that titles, prompts, answers, commands, and paths are
searched; the sidebar field remains a session filter.

**Inspector** — content cards for session usage, estimated cost, token totals,
and changed files. Keep figures tabular and labels quiet. **Review** in the
Edited files card opens the review sheet. A **Sub-agents** card appears when
the session delegated work: one row per Task/Agent call with its type,
description, quiet status, and duration; selecting a row opens the sub-agent
detail sheet.

**Sub-agent detail** — a content sheet, not glass. Status, duration, and start
time sit in three small metric cards; the prompt and final report follow as
Markdown in `surfaceCard` surfaces with a copy control. A running delegation
shows a spinner and "Still running…"; a background delegation says its report
is not captured instead of presenting the task id as content.

**Review changes** — a content sheet, not glass, that gathers Claude's file
edits for the session. A quiet file rail on the left shows relative paths,
added/removed counts, a New marker, and a note indicator; the selected file
shows its diffs as code surfaces with a note field. **Send notes** is the
primary action when notes exist; **Commit…** opens a confirmation sheet that
lists exactly the files and message Git will receive. Never auto-commit, never
push, and never hide the file list being committed.

**Settings** — General, Code Hosts, Providers, Claude Code, About. Group rows
in `surfaceCard` sections with hairlines between rows. Destructive actions
confirm by name and consequence.

**Extensions & Mods** — Browse, Installed, Sources, Create. Cards use
`surfaceCard`; the trust sheet is a content surface, not glass. Installed and
source state use quiet badges; install is the primary action, uninstall is
destructive and confirmed.

**Graphify** — one project's knowledge graph. A `surfaceCard` status card shows
the project, graph file, and quiet CLI/MCP badges; **Build Graph** or **Update
Graph** is the primary action, with **Open Graph** secondary. A query card runs
a graph query and shows the result in a code surface. When Graphify is missing,
an install card names the exact `uv` command; its confirmation sheet is a
content surface, not glass.

**Repository panel** — pull requests, checks, comments, and creation. Check
states use semantic colors; write actions confirm what will change on the
remote.

**Menu bar extra** — a system status item, not a glass surface. Its icon and
optional count reflect the highest-priority state: requests waiting, sessions
running, turns finished, or idle. The popover header shows the lockup and a
quiet status badge, then sections for **Needs you**, **Working**, and
**Finished**. Permission cards use native bordered buttons and keep Deny,
the contextual always-allow action, and Allow once. Question cards are compact
forms with the same choice, text, number, and multi-select answers as the main
card, including inline validation for number fields, plus Decline. The footer
holds **Open Gantry**, **Settings**, and **Quit Gantry**. Closing the main
window hides the app while leaving all of this available and does not stop
turns.

## Accessibility

- Every icon-only control has a meaningful `.help` and `.accessibilityLabel`.
- Use `.accessibilityHint` when the result of an action is not obvious.
- Combine composite labels (`GantryLockup`) and hide decorative views
  (`CanvasBackground`) from assistive technology.
- Keep contrast for secondary text; do not use `faintInk` for essential copy.
- Maintain visible keyboard focus. The composer focus ring is the model.
- Keyboard shortcuts: ⌘N new session, ⌘O open project, ⌘0 open Gantry,
  ⌘K command palette, ⇧⌘I inspector, ⇧⌘E Extensions & Mods, ⇧⌘R review
  changes, ⇧⌘F find in conversations, ⌘. stop.
- Hit targets stay at least 28 pt for icon buttons.
- Test both appearances and, for anything that moves, Reduce Motion.

## Markdown, code, and diffs

- `MarkdownParser` in `GantryCore` parses blocks without third-party code;
  `Utilities/MarkdownRendering.swift` renders them.
- Code blocks use `codeSurface` with a `codeHeader` strip, language label, and
  copy action. Highlighting uses the code palette above, not system rainbow
  colors.
- Inline code uses a 6% ink wash and monospaced type, not the accent.
- Tables use hairlines and tabular figures; they scroll horizontally rather
  than compress columns below legibility.
- Diffs use the diff backgrounds and text tokens; additions and deletions keep
  a text label or symbol in addition to color.
- Tool output is truncated in the model and the view; show a clear truncation
  note instead of silently cutting content.

## Voice

- Sentence case for labels, buttons, and headings.
- Plain, direct verbs: “Allow once”, “Deny”, “Create pull request”, “Reload
  extensions”. Not “OK”, “Yes”, or “Submit”.
- Explain consequences where the user is trusting something: installing an
  extension, allowing a tool, posting to a remote, removing a project.
- No exclamation marks, no cuteness, no emoji, no marketing adjectives inside
  the product.
- Keep technical detail available but secondary; errors lead with what
  happened and what the user can do.

## Review checklist

- [ ] Uses `Palette`, `Typo`, `Radius`, `surfaceCard`, and `glassPanel`; no raw
      colors, fonts, or radii.
- [ ] Glass is limited to the sidebar and floating layer; content is flat.
- [ ] No custom fill, gradient, glow, shadow, or ornamental stroke on glass.
- [ ] Accent is limited to selection, live work, primary action, links, focus.
- [ ] Hierarchy comes from size and color; figures are tabular.
- [ ] Hover and selection do not move layout or scroll lists.
- [ ] Motion is short, ease-out, and respects Reduce Motion.
- [ ] Every icon-only control has help text and an accessibility label.
- [ ] Checked in light and dark appearance.
- [ ] Copy names the action and its consequence.

## Related documents

- `ARCHITECTURE.md` — where state and behavior live.
- `SECURITY.md` — what trust copy and permission UI must not weaken.
- `AGENTS.md` — build, test, and contribution rules.
