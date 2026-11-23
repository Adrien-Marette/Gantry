# CLAUDE.md

@AGENTS.md

`AGENTS.md` is the canonical guide for every coding agent. Put shared build,
architecture, UI, security, test, and Git rules there. Keep this file limited
to Claude Code specifics so the two cannot drift.

## Claude Code specifics

- Gantry is itself a Claude Code host. When testing runtime or protocol
  changes, prefer the fake CLI in
  `Tests/GantryCoreTests/ProtocolAndRuntimeTests.swift`. Do not launch a real
  interactive `claude` session from inside the repository as part of a test.
- Gated tests are opt-in because they spend API credit or touch the login
  Keychain. Run them only when the user asks:
  `Gantry_RUN_CLI_INTEGRATION=1` or `Gantry_RUN_KEYCHAIN_TESTS=1`, with the
  matching `--filter`.
- Use `/check` before declaring work complete and `/commit` when the user asks
  for a commit, when your Claude Code setup provides those commands.
  `swift build` and `swift test` remain the source of truth.
- Tests use Swift Testing (`import Testing`), not XCTest. Keep every target on
  `.swiftLanguageMode(.v5)`.
- For UI changes, launch with `swift run Gantry` (isolated state via
  `Gantry_STATE_DIR`) and verify light and dark appearance. Do not commit
  `build/` or `.build/`.
- Never inspect or print Keychain items, provider keys, code-host tokens, or
  the user's Claude Code credentials. Use fake values in tests and debugging.
- When a fact belongs in `ARCHITECTURE.md`, `DESIGN.md`, `SECURITY.md`, or
  `README.md`, edit that file rather than expanding this one.
- If you change the agent workflow itself, edit `AGENTS.md` and keep the
  `@AGENTS.md` import above intact.
