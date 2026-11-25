# Architecture

This document describes how Gantry is put together: its targets, the Claude
Code process and protocol flow, persistence, provider and plugin systems, the
MCP bridge, and the extension surface. For product behavior see `README.md`;
for the visual system see `DESIGN.md`; for the trust model see `SECURITY.md`.

## Summary

Gantry is a SwiftUI macOS app that hosts the `claude` CLI. It does not
reimplement Claude Code. Each chat owns one long-lived child process speaking
Claude Code's bidirectional `stream-json` protocol; the app parses that stream,
renders it natively, and answers permission requests. Around that core it adds
provider profiles, code-host tools, Claude Code extension management, session
review and commits, cross-conversation search, and background menu bar
operation.

The design rules are:

- **Claude Code remains the authority.** Gantry renders and forwards; it does
  not decide which tool calls are safe.
- **One process per chat.** Sessions are isolated and resumable, not multiplexed.
- **Testable logic in `GantryCore`.** SwiftUI views stay thin.
- **Secrets stay in the Keychain.** Tokens are read late and scoped narrowly.

## Targets and dependency direction

| Target | Kind | Depends on | Purpose |
| --- | --- | --- | --- |
| `GantryCore` | library | — | Models, protocol, runtime, providers, Keychain, code-host clients, MCP bridge, extension manager, review, search, persistence |
| `Gantry` | executable | `GantryCore` | SwiftUI app, observable state, orchestration, design system, views |
| `GantryPluginMCP` | executable | `GantryCore` | Bundled `Gantry-plugins` stdio MCP helper |
| `GantryCoreTests` | test | `GantryCore` | Unit tests with a fake CLI and HTTP fixtures |

`Package.swift` declares two products: `Gantry` and `Gantry-plugins`. The app
target is the only one that imports SwiftUI; `GantryCore` stays UI-free so its
behavior can be tested headlessly. `GantryPluginMCP` reuses only the wire types
and tool catalog, never the app's models or credentials.

## Runtime topology

```
┌───────────────────────────── Gantry.app ──────────────────────────────┐
│                                                                       │
│  RootView / views                                                     │
│      │ observes                                                       │
│      ▼                                                                │
│  AppModel (@MainActor, @Observable)                                   │
│      ├── SessionActivity per chat    (preview, permissions, status)   │
│      ├── AppDataStore ──────────────► state.json (0600)               │
│      ├── ProviderKeychain ──────────► macOS Keychain                  │
│      ├── PluginKeychain ────────────► macOS Keychain                  │
│      ├── ClaudePluginManager ───────► `claude plugin ...`             │
│      │                                                                │
│      ├── ClaudeRuntime (one per session) ──► child `claude` process   │
│      │        ▲ stdout stream-json / stdin control                    │
│      │                                                                │
│      └── PluginToolBridge (Unix socket, 0600, random token)           │
│               ▲                                                       │
│               │ JSON lines                                            │
│         Gantry-plugins MCP helper ──► launched by Claude Code         │
│               │                                                       │
│               └── stdio MCP ──► child `claude` process                │
└───────────────────────────────────────────────────────────────────────┘
```

The Claude Code child may also launch the MCP helper. The helper has no
code-host token; it can only send a tool name and arguments to the app's
per-session socket, and the app performs the API call.

## Claude Code process model

`ClaudeRuntime` (`Sources/GantryCore/ClaudeRuntime.swift`) owns one `Process`
with stdin, stdout, and stderr pipes. `AppModel.runtimes` holds at most one
runtime per session, and `runtimeStarts` deduplicates concurrent starts so two
callers cannot launch two processes or send a prompt before initialization.

### Launch configuration

`ClaudeLaunchConfiguration.arguments` produces:

```text
--output-format stream-json
--verbose
--input-format stream-json
--permission-prompt-tool=stdio
--include-partial-messages
--permission-mode <manual|acceptEdits|plan|auto>
[--model <fable|opus|sonnet|haiku>]
--session-id <uuid>          # first launch
| --resume <uuid>            # later launches
[--mcp-config <temp path> --append-system-prompt <text>]
[--plugin-dir <path>]        # project is a mod under development
```

The working directory is the project folder. `ClaudeLocator` finds the
executable from an explicit override, `Gantry_CLAUDE_PATH` (or
`CLAUDE_CODE_PATH`), `PATH`, common install locations, and finally the login
shell; it runs off the main thread because the shell fallback can be slow.

### Environment

`ClaudeProcessEnvironment.make` starts from the app's environment, then:

1. Removes Claude Code's nested-session variables (`CLAUDECODE`,
   `CLAUDE_CODE_ENTRYPOINT`, `CLAUDE_CODE_SESSION_ID`, `CLAUDE_CODE_SSE_PORT`,
   `CLAUDE_CODE_ADDITIONAL_DIRECTORIES`, `CLAUDE_CODE_ASYNC_AGENT_STDOUT`) so a
   host app launched by Claude Code does not leak its context into the child.
2. Prepends the executable's directory, `~/.local/bin`, `~/.bun/bin`, and
   standard Homebrew/system paths to `PATH`, de-duplicated.
3. Defaults `TERM` to `xterm-256color` when absent.

Provider overrides are applied last, and the opposite auth variable is removed
so a key intended for one endpoint cannot be sent to another. The credential
exists only in that child process's environment.

### Handshake

After launch, `initialize()` writes a control request with a fresh request ID
and waits up to 25 seconds. The runtime intercepts the matching
`control_response` instead of yielding it as UI event, then returns the
payload. The payload can carry the session's slash-command catalog, agents,
models, and output styles; Gantry currently uses the command catalog for the
`/` picker.

### Event stream and coalescing

stdout is buffered until complete newline-terminated lines are available, then
parsed by `ClaudeStreamParser`. The runtime keeps its own serial `stateQueue`,
so pipe callbacks never mutate shared state concurrently.

| Event | App behavior |
| --- | --- |
| `system` | Session model name, slash-command names from older CLIs, ready status |
| `status` / `retry` | Status text such as Thinking or Reconnecting |
| `streamText` / `streamThinking` | Appended to a preview buffer; flushed at most every 32 ms (about 30 fps) |
| `streamToolStart` | Flushes the preview and shows the tool name |
| `assistant` | Merges text, thinking, and tool-use blocks into the streaming turn; duplicate blocks are suppressed by signature, and its reported usage updates the composer's context meter |
| `toolResults` | Attaches results to the matching tool; result text is capped at 250,000 characters |
| `permissionRequest` | Adds a permission or question card and marks the tool as awaiting permission |
| `permissionCancelled` | Removes the card |
| `result` | Finalizes the turn, usage, and cost estimate |
| `notice` | Banner or status text |
| `processExited` | Finalizes or fails the active turn with a stderr tail |

Preview buffers are flushed immediately on tool start, permission requests,
and turn completion, so the UI never lags behind a boundary event.

The context meter counts uncached input plus cache reads and writes from the
assistant message that reported it. `ChatSession.contextModelName` records the
model that produced those tokens; a result's cumulative `modelUsage` snapshot
may be dominated by a subagent, so it can only resolve a `[1m]` spelling for
that assistant model and never replaces it. A model switch therefore cannot
leave a stale context window behind. `ModelContextWindow` sizes a `[1m]` marker
and unknown custom names at 1M, and standard-window Anthropic families at 200K.

### Composer attachments

The composer stages files and folders per session as `PromptAttachment` values.
Gantry does not read, copy, or persist their contents, and the staged list is
cleared after sending. On send, `PromptAttachmentComposer` appends their
absolute paths to the user's text as a short context block, and the result goes
to Claude as a normal user turn. Claude reads the paths with its own tools, so
its permission rules and instruction-file limits still apply.

### Permission flow

1. Claude Code emits a `can_use_tool` request and blocks.
2. The app appends it to `SessionActivity.pendingPermissions` and shows a glass
   permission or question card.
3. The user chooses **Allow once**, the contextual always-allow action when
   Claude Code offers one (for example **Always allow this** or **Allow edits
   this session**), or **Deny**.
4. `ClaudeWire.permissionResponse` sends a `control_response` with behavior
   `allow` or `deny`.
5. The always-allow action forwards Claude Code's own permission suggestions;
   if the request implies a permission mode, the session adopts it.
6. Stopping a turn denies every pending request, marks its tools interrupted,
   interrupts the turn, and force-terminates the process after 6 seconds if it
   does not settle.

There is no auto-approval path. Gantry's permission modes ultimately map to
Claude Code's own modes, and Claude Code's classifier, hooks, and rules still
apply.

An `AskUserQuestion` call uses the same `can_use_tool` transport but is rendered
as an answer sheet instead of an allow/deny card. `ClaudeQuestionnaire` parses
the questions (choice, single- or multi-select, text, and number). Submitting
answers sends an `allow` whose `updatedInput` keeps the original questions and
adds the user's `answers`, keyed by question text; multi-select labels are
joined into one comma-separated string. Declining sends a `deny`. Gantry never
invents an answer or submits a question without the user.

| Gantry mode | CLI value |
| --- | --- |
| Ask first | `manual` (reported as `default`) |
| Auto-edit | `acceptEdits` |
| Plan | `plan` |
| Auto | `auto` |

### Turn lifecycle, stop, and exit

`AppModel.send` appends a user turn and a placeholder streaming assistant turn,
records the turn ID, and captures cost/usage baselines. The runtime is started
or reused, then the prompt is written.

The turn ends when a `result` arrives, the process exits, or the user stops it.
Completion is idempotent: a result and a process exit can race, and only the
first may price the turn. Pending preview text becomes a final block if Claude
Code did not also send a complete message. Unresolved tools become completed or
interrupted.

A process exit without a result ends the turn with an error and a truncated
stderr tail. If no turn is active, the session returns to idle with a banner.

## Review and commit

`SessionReview` builds the **Review changes** sheet from the session transcript,
not from Git. It walks every turn and collects the input of completed `Edit`,
`MultiEdit`, `Write`, and `NotebookEdit` tool calls, grouping them by
standardized file path. Changes made by shell commands or other tools are not in
the transcript and are not listed. A `Write` replacement uses the original file
Claude Code reports in the tool result; when that is absent, only the written
content is shown.

Notes are a normal user turn: **Send notes** calls `AppModel.send` with the
file notes and the overall note, so the permission flow and running-turn rules
are unchanged.

**Commit…** is user-initiated and confirmed in a sheet that lists every file and
the commit message. `GitCommitService` resolves reviewed paths against the
project root and drops paths outside it. It also drops a reviewed path that has
since become a directory, because committing that pathspec would sweep in
unreviewed descendants. The remaining files are passed to
`git add -- ":(literal)<path>"` followed by
`git commit -m <message> -- ":(literal)<path>"`, one literal pathspec per file,
without a shell. The pathspec keeps unrelated staged work out of the commit, and
the literal magic keeps file names with glob characters exact without changing
global Git behavior for hooks. It never pushes, amends, force-updates, or passes
`--no-verify` / `--no-gpg-sign`, so hooks and signing behave as they do in a
terminal. Git output is captured to temporary files, stripped of ANSI, and shown
in the sheet on failure.

## Background operation and menu bar

`AppModel` is owned by the app, not by the main window. Closing the window
hides the app and does not quit: Claude Code child processes, plugin bridges,
turns, and their pending permission requests keep running. `AppDelegate` holds
a reference to the model (set when the root view or menu bar label appears) so
`applicationWillTerminate` can call `shutdown()` and save even when no window is
open. The main window is reopened with SwiftUI's `openWindow`, from the menu bar
or the Dock reopen handler.

The menu bar extra is a projection of the same state: `pendingPermissionItems`,
`activeSessionItems`, and `finishedSessionItems` gather sessions across every
project. Its actions call the same `respond`, `answer`, and `declineQuestion`
paths as the in-window cards, so permission handling stays single-sourced and
there is still no auto-approval. A turn that finishes while the main window is
not focused marks its session unread so it can appear under Finished.

## Persistence

`AppDataStore` writes `~/Library/Application Support/Gantry/state.json` with
mode `0600`.

- Encoding is pretty-printed, sorted-keys JSON with ISO-8601 dates.
- Writes are atomic.
- `AppModel` debounces saves by 350 ms and serializes them so an older snapshot
  cannot land after a newer one.
- The app saves on resign-active, background, and termination.
- An unreadable file is copied to `state-unreadable-<timestamp>.json` before
  the app can overwrite it.

`AppSnapshot` is version 2 and contains projects, sessions, turns, tools, and
settings. Persisted additions must decode with defaults when absent; examples
include `ChatSession.modelUsage`, `ChatSession.contextTokens`,
`ChatSession.contextModelName`, `ChatSession.claudeReportedCostUSD`,
`Project.pluginID`, `Project.devModPath`, `AppSettings.appearance`,
`AppSettings.plugins`, `AppSettings.providers`,
`AppSettings.favoriteMarketplaces`, `AppSettings.modsDirectory`, and
`Project.autoSyncTranscripts`. State
written by 0.1.0 must keep decoding.

At launch, the app repairs what it can:

- Every `isStreaming` flag is reset because no process survived the launch.
- The built-in Claude Code provider is inserted and unknown provider IDs are
  replaced with the default.
- Missing Keychain server/account references are backfilled from the provider
  or plugin identity.
- Unknown plugin references and duplicate favorites are dropped.
- Selection is repaired to a session, then a project, then the most recently
  opened project.

`ChatSession.id` identifies the chat in Gantry; `claudeSessionID` identifies the
Claude Code transcript. They start equal. `claudeStarted` decides whether the
next launch uses `--session-id` or `--resume`.

## Providers

`AIProvider` is a named, Anthropic-compatible backend profile. It stores a base
URL, auth mode, model mappings, non-secret environment variables, and a Keychain
reference. It never stores the key itself.

| Auth mode | Environment | Notes |
| --- | --- | --- |
| `inherit` | none | Built-in Claude Code profile; uses the CLI's existing login and settings |
| `authToken` | `ANTHROPIC_AUTH_TOKEN` | For gateways such as DeepSeek's Anthropic-compatible endpoint |
| `apiKey` | `ANTHROPIC_API_KEY` | For `api.anthropic.com` and compatible APIs |

`AIProvider.environment(apiKey:)` adds `ANTHROPIC_BASE_URL`, the model aliases
(`ANTHROPIC_MODEL`, `ANTHROPIC_DEFAULT_OPUS_MODEL`,
`ANTHROPIC_DEFAULT_SONNET_MODEL`, `ANTHROPIC_DEFAULT_HAIKU_MODEL`,
`CLAUDE_CODE_SUBAGENT_MODEL`), and the credential. `environmentKeysToClear`
removes the other auth variable.

Provider switching is allowed only while a session is idle. The app updates the
session, clears the stale model name, and recycles the runtime; the next message
resumes the same Claude Code transcript under the new environment. If a provider
is edited or deleted while a turn is running, the session is marked stale and
the runtime is recycled after the turn ends.

## Code-host plugins

`PluginConnection` stores the host kind, server URL, account display name, and
Keychain reference. `GitRepositoryReader` reads the project's `origin` remote;
`PluginConnection.matches(host:)` chooses a connected account. The project can
pin one connection with `Project.pluginID`, otherwise the first match is used.

`CodeHostClient` is a small provider-independent facade over three backends:
GitHub, GitLab, and Gitea. Each backend implements the same operations:

- verify the token and return the account
- read the repository
- list pull requests / merge requests
- read CI checks
- post a conversation comment
- create a pull request / merge request

`PluginHTTPClient` sets JSON headers, a `Gantry` user agent, a 30-second
timeout, and the host-specific authorization header. It maps status codes to
typed errors and truncates error messages. It does not log requests or tokens.
Transport is injectable, so tests use fixtures instead of real services.

Connecting an account verifies the token against the host's `/user` endpoint,
stores it in `PluginKeychain` only after verification, and records the returned
login. Tokens are never written to `state.json`.

## MCP tool bridge

When a project's `origin` remote matches a connected plugin and the bundled
helper exists next to the app executable, `AppModel.prepareSessionTools` starts
a per-session bridge before launching Claude Code:

1. `PluginToolBridge` creates a Unix domain socket in the temporary directory,
   restricts it to the user (`0600`), and generates a random bridge token.
2. The app writes a temporary MCP config with mode `0600`:

   ```json
   {
     "mcpServers": {
       "Gantry_plugins": {
         "command": "<app dir>/Gantry-plugins",
         "args": ["mcp"],
         "env": {
           "Gantry_PLUGIN_SOCKET": "<socket path>",
           "Gantry_PLUGIN_AUTH": "<random token>"
         }
       }
     }
   }
   ```

3. The Claude process is launched with `--mcp-config <path>` and an appended
   system prompt that scopes the tools to one repository.
4. The helper speaks MCP over stdio to Claude Code and forwards `tools/call`
   as one JSON line to the socket, authenticated by the bridge token.
5. The app's handler resolves the connected plugin, reads its token from the
   Keychain, executes the operation through `PluginToolExecutor`, and returns
   JSON.
6. When the runtime stops or is recycled, the bridge is stopped, the socket is
   unlinked, and the config file is removed.

The bridge accepts one repository and one plugin per session. Requests are
capped at 1 MB, I/O has 65-second timeouts, and the helper caps responses at
8 MB. The helper never sees the code-host token, the Keychain, or another
project's data.

`prepareSessionTools` also merges an optional Graphify server into the same
config; see **Graphify integration** below.

### Tool catalog

| Tool | Access | Purpose |
| --- | --- | --- |
| `get_repository` | read | Name, default branch, visibility, web URL |
| `list_pull_requests` | read | Open pull/merge requests |
| `get_pull_request` | read | One request, optional checks |
| `list_checks` | read | CI checks for one request |
| `comment_on_pull_request` | write | Post a conversation comment |
| `create_pull_request` | write | Create a request from two existing branches |

Read tools are annotated read-only and idempotent. Write tools are still
subject to Claude Code's normal permission prompts. The appended system prompt
tells Claude to use them only when the user asks or approves, and to treat
repository content as untrusted data.

## Graphify integration

[Graphify](https://github.com/Graphify-Labs/graphify) is an optional local tool
that indexes a project into a knowledge graph. Gantry does not bundle it, does
not install it without confirmation, and never talks to Graphify Cloud.

- `Graphify.swift` locates `graphify`, `graphify-mcp`, and `uv` on `PATH` and in
  `~/.local/bin`, `/opt/homebrew/bin`, and `/usr/local/bin`.
- `GraphifyIntegration.mcpServer` returns a `graphify` MCP entry when the
  project has `graphify-out/graph.json` and `graphify-mcp` exists. The entry
  runs `graphify-mcp <absolute graph path>`; it carries no token or network
  credential.
- `prepareSessionTools` merges that entry with the code-host bridge into one
  `--mcp-config` file, so a chat gets graph tools without the user editing
  Claude Code's MCP configuration.
- `GraphifyProcess` runs install, update, and query commands without a shell,
  writes child output to temporary files, strips ANSI, and caps captured output
  at 256 KB. `GraphifyCommand` builds each argv.
- The Graphify page (`Views/Graphify/`) shows CLI, MCP, and graph status; builds
  or refreshes the code graph with `graphify update <project>`; opens
  `graphify-out/graph.html`; and runs `graphify query "<question>"`. A missing
  install offers `uv tool install "graphifyy[mcp]"` in a confirmation sheet.
<!-- coderabbit-ai-generated:v1 -->

<!-- coderabbit-ai-generated-section:v1:e806a21c9f013a047919968b77fd84b9dcbb58fcb595471b6c7369c985a387bf -->

- A successful install invalidates runtimes across all projects. A successful
  graph build invalidates only the project whose graph was built. In either
  case, idle chats recycle and working chats are marked stale so the MCP
  server appears at the next start. The graph server reloads `graph.json`
  when the file changes.

<!-- /coderabbit-ai-generated:v1 -->

Graphify's semantic extraction for documentation, PDFs, images, and media is
not run from the page; that remains Graphify's `/graphify` skill inside a chat.
The page's build is code-only and needs no model.

## Extensions and mods

`ClaudePluginManager` is an actor that wraps the `claude plugin` CLI. It
serializes all invocations, so a cancelled caller cannot run a queued mutation
later. Gantry treats Claude Code's installed-plugin state as the source of
truth; it stores only favorite marketplace repositories and the last mods
folder.

| Operation | CLI shape |
| --- | --- |
| List installed / catalog | `plugin list --json [--available]` |
| Marketplaces | `plugin marketplace list/add/remove/update` |
| Install / update | `plugin install|update ... --scope user` |
| Enable / disable | `plugin enable|disable ... --scope user` |
| Uninstall | `plugin uninstall ... --scope user --keep-data` |
| Authoring | `plugin validate <path> [--json]`, `plugin test <path>` |

Gantry parses the last JSON value from CLI output, tolerates individual
malformed entries, and detects older CLIs without JSON or plugin support.
Command failures are redacted for credential-looking URLs before they are
shown or persisted.

Installing third-party code always goes through a trust sheet. If a marketplace
declares an install command, Gantry shows the exact command and its SHA-256 and
requires a second explicit approval; it never passes `-y` or auto-accepts. Only
user-scope plugins are managed; project and local scopes are read-only.

`ModScaffolder` creates a valid plugin from a status-line, slash-command, pane,
tool-guard, or blank template. It validates the name, prevents path traversal,
and writes `.claude-plugin/plugin.json`, a hooks module, a README, and, when
the wizard's test option is enabled for a pane, a starter test. The wizard runs
`claude plugin validate` (and optionally `claude plugin test`), then can open
the folder in Gantry. A project whose folder is the mod itself launches chats
with `--plugin-dir`.

After any plugin or mod change, idle runtimes are recycled and running ones are
marked stale, so the new plugin set is picked up after the current turn.

## Slash command catalog

The catalog comes from each session's `initialize` control response, not from
scanning folders, because plugins and mods can register commands at runtime.
Older CLIs also list names in the `init` system event; the app merges those
names without overwriting richer entries. The catalog is per session because
project commands and dev mods depend on the working directory.

`/clear` (aliases `/reset`, `/new`) and `/rename` (alias `/name`) are handled
locally so Gantry's session identity and title stay in sync. Every other slash
command is sent to Claude Code unchanged.

## Transcript import

`ClaudeTranscriptImporter` reads Claude Code's own transcripts from
`<config>/projects/<path with non-alphanumerics as ->/<session-id>.jsonl`.
Assistant and tool-result lines go through `ClaudeStreamParser`; meta and
sidechain lines and command echoes are skipped. Each file becomes a
`ChatSession` whose `claudeSessionID` is the file's UUID with
`claudeStarted = true`, so the next prompt resumes it with `--resume`. Files
whose ID already belongs to a Gantry session (including Gantry's own chats)
are never imported twice. `AppModel.offerTranscriptImport` runs when a project
is opened and, for auto-sync projects, at launch. Unless
`Project.autoSyncTranscripts` imports directly, it opens
`TranscriptImportSheet` (also in the project menu), which lists the sessions
with a read-only preview and imports only the checked ones. Parsing runs off
the main actor. Import is read-only on Claude Code's
files.

## Conversation search

`SessionSearch` runs in memory over the persisted models; it has no index file
and makes no network calls. It matches session titles, user and assistant text
blocks, and tool commands or file paths. It skips thinking blocks and tool
output, and returns the best hit per turn. Both the query and the searchable
text collapse whitespace, so runs of spaces match a single space. The search
sheet debounces typing, normalizes the query with
`SessionSearch.normalizedQuery`, runs the search off the main actor, and
highlights the matched range. Selecting a turn sets
`AppModel.pendingTurnScroll` with both the session and turn IDs, so a workspace
that is being replaced ignores a request for another session.

## Cost estimation

Claude Code reports cumulative per-model usage on each result. Gantry stores
that snapshot on the session and prices the next turn from the delta, using
`ModelPricingTable`. A result without a snapshot clears the stored baseline, so
a later cumulative report cannot price the turns in between twice. If the delta
is zero or unavailable, Gantry falls back to pricing the turn's own `TurnUsage`,
then to Claude Code's reported cumulative cost delta for unknown models. The session total adds the turn estimate to the
larger of the stored total and the sum of the other turns' estimates, which
keeps history imported from versions that did not price every turn.

These values are estimates, not billing data.

## Concurrency model

- `AppModel` is `@MainActor` and `@Observable`; UI state is read synchronously
  from the main actor.
- `SessionActivity` holds per-session UI state: preview, status, pending
  permissions, unread flag, slash catalog, and stderr tail.
- `ClaudeRuntime` isolates process and buffer state on a private serial queue
  and exposes events through an `AsyncStream`.
- Per-session `Task`s consume events, start runtimes, flush previews, force
  stop, and debounce saves. Dictionaries guarded by the main actor track them.
- Keychain reads/writes, state writes, CLI discovery, and `claude plugin`
  commands run off the main thread.
- `AppDataStore` writes are serialized through the save task, not through a
  lock, to prevent out-of-order snapshots.

## Where to make changes

| Change | Start here |
| --- | --- |
| Protocol or launch behavior | `ClaudeWire.swift`, `ClaudeEvents.swift`, `ClaudeRuntime.swift`, `ClaudeLocator.swift` |
| Turn/UI orchestration | `AppModel+Conversation.swift`, `SessionActivity` |
| `AskUserQuestion` parsing and answers | `ClaudeQuestionnaire.swift`, `QuestionRequestCard.swift` |
| Slash commands | `SlashCommands.swift`, `AppModel+SlashCommands.swift`, `SlashCommandMenu.swift` |
| Persisted model | `Models.swift`, then persistence tests |
| Provider behavior | `AIProvider.swift`, `ProviderKeychain.swift`, `AppModel+Providers.swift` |
| Code-host API | `CodeHostClient.swift` plus the host backend, `Plugins.swift` |
| MCP tool | `PluginTools.swift`, `PluginToolBridge.swift`, `AppModel+PluginTools.swift` |
| Extensions | `ClaudePluginManager.swift`, `AppModel+Extensions.swift`, `ExtensionsModel.swift` |
| Mod creation | `ModScaffolder.swift`, `Views/Extensions/CreateModView.swift` |
| Review and commit | `SessionReview.swift`, `GitCommit.swift`, `ReviewChangesSheet.swift` |
| Conversation search | `SessionSearch.swift`, `SessionSearchSheet.swift` |
| Sub-agent rows | `ToolActivity.subagent*`, `InspectorView.swift`, `SubagentDetailSheet.swift` |
| Context meter | `ModelContextWindow.swift`, `ComposerView.swift` |
| Menu bar and background behavior | `GantryApp.swift`, `MenuBarView.swift`, `AppModel` activity projections |
| Graphify | `Graphify.swift`, `AppModel+PluginTools.swift`, `Views/Graphify/` |
| Visual system | `Design/Theme.swift`, `Design/Components.swift`, `DESIGN.md` |

## Known limits

The README's **Current limits** section is the canonical list. Architecturally
important ones: one main window plus a menu bar extra, provider switching only
between turns, user-scope extension management only, no inline review threads
or merges, and terminal-only slash commands that have no visual effect in
Gantry.

## Related documents

- `README.md` — features, protocol flow summary, storage/privacy summary,
  full project map, current limits.
- `DESIGN.md` — visual system and UI review checklist.
- `SECURITY.md` — trust boundaries, secret handling, permission model.
- `AGENTS.md` — build commands and contribution invariants.
