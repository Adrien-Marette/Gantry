# Security

Gantry runs Claude Code locally, stores provider credentials, and can act on
code-host repositories. This document describes the trust boundaries, how
secrets are handled, and how to report a vulnerability.

## Reporting a vulnerability

Do not open a public issue for a security problem.

Use GitHub's private vulnerability reporting on the repository's **Security**
tab:

<https://github.com/Adrien-Marette/Gantry/security/advisories/new>

Please include:

- the affected version (`Gantry → Settings → About`) and macOS version
- a description of the issue and its impact
- reproduction steps or a proof of concept
- any suggested fix or mitigation

Never include real API keys, access tokens, Keychain contents, private project
paths, or personal data. Use placeholders or redacted values. If a credential
may have been exposed, revoke it with the provider first.

Gantry is pre-1.0 and ships from `main`; security fixes target the latest
release. Reports are reviewed on a best-effort basis. Please allow time for a
fix before public disclosure.

## Trust model

Gantry is a local client, not a security boundary between you and Claude Code.
Claude Code remains the authority on which tool calls are safe, and Gantry
never answers a permission request on your behalf.

| Component | Trust and access |
| --- | --- |
| Gantry app (`Gantry`) | Runs as you, without App Sandbox. Reads/writes chosen projects and its own state, and reads Keychain items it stored. |
| Claude Code child (`claude`) | Runs as you in the project folder. Receives the selected provider's credential through its environment, in addition to your normal environment. Enforces permissions. |
| MCP helper (`Gantry-plugins`) | Runs as a child of Claude Code. Gantry gives it a socket path and random bridge token; it never receives a code-host token. |
| Graphify (`graphify`, `graphify-mcp`) | Optional local tool installed by you. Serves a project's `graphify-out/graph.json`; receives no Gantry secret. |
| Code-host APIs | Receive the stored token as an authorization header and the requested repository action. |
| Installed extensions and mods | Third-party code that runs with your permissions inside Claude Code. |
| macOS Keychain | Stores provider keys and code-host tokens. Items are accessible when the login keychain is unlocked. |
| `state.json` and logs | User-only files on disk, containing conversation and project metadata. |

Gantry intentionally does not use App Sandbox because it must launch your CLI
and open the folders you choose. Review the source before running it on a
sensitive machine.

## Secret handling

### Provider API keys

- Stored only through `ProviderKeychain` as Keychain internet-password items,
  keyed by the provider's server and account.
- Marked synchronizable when iCloud Keychain is available, so they can appear
  in Apple Passwords. Ad-hoc local builds that cannot create synchronizable
  items fall back to the local login keychain rather than writing the key
  elsewhere.
- Read only when launching a Claude Code process. The key is placed in that
  child's environment as `ANTHROPIC_API_KEY` or `ANTHROPIC_AUTH_TOKEN`; the
  opposite auth variable is removed.
- Never written to `state.json`, logs, or command-line arguments, and never
  passed to the MCP helper by Gantry.

### Code-host access tokens

- Stored only through `PluginKeychain` as Keychain internet-password items.
- Verified against the host's `/user` endpoint before being stored.
- Read only when the app performs an operation for that connection; sent only
  as the host-specific authorization header.
- Never written to `state.json`, logs, the MCP config, or command-line
  arguments, and never passed to the MCP helper.

### Rules that apply to all secrets

- Do not log, print, persist, or display a secret.
- Do not put a secret in a URL, query string, process argument, crash message,
  or fixture. Use obvious fakes such as `token-123`.
- Redact credential-looking text before showing CLI output or persisting it.
  `ClaudePluginManager` already redacts plugin CLI errors and truncates them
  after redaction.
- Never inspect the user's Keychain or Claude Code credentials during
  development or debugging.

## Permission model

Claude Code emits `can_use_tool` requests and waits. Gantry turns each request
into a permission or question card and sends a `control_response` with allow or
deny. There is no auto-approval path.

| Gantry mode | Claude Code mode | Effect |
| --- | --- | --- |
| Ask first | `manual` (reported as `default`) | Approve commands and file changes |
| Auto-edit | `acceptEdits` | Apply file edits; still ask before commands |
| Plan | `plan` | Explore and propose without changing files |
| Auto | `auto` | Claude Code's safety classifier decides |

“Allow once” sends a one-time allow. The contextual always-allow action (for
example “Always allow this” or “Allow edits this session”) forwards Claude
Code's own permission suggestion and may adopt the suggested permission mode;
it does not invent broader rules. Stopping a turn denies every pending request
and interrupts the process. Claude Code's hooks, settings, and permission
rules still apply in every mode.

`AskUserQuestion` follows the same rule. Gantry renders the choices and fields
the user must fill, sends only what the user submitted, and always offers an
explicit decline. It never synthesizes or preselects an answer.

The menu bar popover exposes the same allow, always-allow, deny, answer, and
decline actions for the same requests. They are still explicit user actions:
closing the window does not auto-approve anything, and every request continues
to wait for the person. Background turns that hit a permission request remain
paused until answered.

### Prompt attachments

Files and folders attached in the composer are sent to Claude as absolute paths
inside the user's prompt. Gantry does not read, copy, upload, log, or persist
their contents; the staged attachment list is discarded after sending. Claude
still needs its own Read permission for each path, so the permission cards and
deny path remain authoritative.

### Review and commit

The Review changes sheet is read-only until you act. **Send notes** is a normal
user message and goes through Claude Code's permission model. **Commit…** is
explicit, lists every file and the message before running, and never happens
automatically.

- Only paths inside the project are committed; paths outside it, and reviewed
  paths that have since become directories, are shown as excluded and never
  passed to Git.
- The commit uses a literal pathspec for each reviewed file, so unrelated
  staged work is left out and file names with glob characters stay exact.
- Gantry never pushes, amends, force-updates, or bypasses hooks or signing
  (`--no-verify` and `--no-gpg-sign` are never passed).
- Git output is stripped of ANSI before it is shown.

### Extensions and mods

Extensions are third-party code. Installing one always requires a trust review
that names the marketplace and source and warns that the code runs with your
permissions.

If a marketplace declares an install command, Gantry shows the exact command
and its SHA-256 and requires a second explicit approval. It never passes `-y`
or accepts the command automatically. Installed state belongs to Claude Code's
own `claude plugin` commands, so the same plugin is trusted (or not) in the
terminal.

Only user-scope plugins are managed. Project and local scopes are displayed
read-only because their state belongs to a project. A project can load a mod
with `--plugin-dir` only when that mod folder is the project folder itself.

## Graphify

Graphify is optional third-party software. Gantry detects an install; it never
bundles it or installs it silently.

- The Graphify page's **Install** action runs
  `uv tool install "graphifyy[mcp]"` only after a confirmation sheet shows the
  exact command. Without `uv`, it shows the command for the user to run.
- Install, update, and query commands run without a shell, with argument
  arrays. They inherit the user's environment plus `NO_COLOR`; no Gantry secret
  is added.
- `graphify update` reads project files and writes `graphify-out/` inside the
  project. It is local and code-only; semantic extraction for docs, PDFs,
  images, and media remains the user's `/graphify` workflow in Claude Code.
- When `graphify-out/graph.json` exists and `graphify-mcp` is installed, Gantry
  adds `graphify-mcp <absolute graph path>` to the session's MCP config. The
  server receives no token or credential.
- **Open Graph** opens the generated `graph.html` in the default browser at the
  user's request. Gantry does not execute or embed it.

## MCP bridge

The bridge is a narrow, per-session channel from Claude Code to the app:

- A Unix domain socket is created in the temporary directory and restricted to
  the user (`0600`).
- Each bridge has a random UUID token, checked on every request.
- Gantry passes only `Gantry_PLUGIN_SOCKET` and `Gantry_PLUGIN_AUTH` to the
  helper through its MCP configuration. The app reads the code-host token from
  the Keychain and sends it only to the configured code host; the helper never
  receives it.
- The temporary MCP config is mode `0600` and contains only the helper path,
  socket path, and bridge token. It is removed when the runtime stops, as is
  the socket.
- The handler is bound to one repository and one connected account. It cannot
  be asked to act on another repository or another session's plugin.
- The app's bridge caps requests at 1 MB; the helper caps responses at 8 MB.
  Socket I/O has 65-second timeouts.

Read tools are read-only. Write tools (commenting and creating a pull request)
are still subject to Claude Code's normal permission prompts, and the appended
system prompt tells Claude to use them only when the user asks or approves.
Repository content, pull-request text, comments, and check output are treated
as untrusted data, not instructions.

This protects against other local users and accidental cross-session use. It is
not a defense against malware running as the same user.

## Data at rest

| Data | Location | Protection |
| --- | --- | --- |
| Sessions, projects, settings, provider/plugin metadata | `~/Library/Application Support/Gantry/state.json` | Mode `0600`, atomic writes, ISO-8601 JSON |
| Claude Code stderr logs | `~/Library/Logs/Gantry/claude-<session>.log` | Mode `0600` |
| Provider keys and code-host tokens | macOS Keychain | Internet-password items, accessible when unlocked |
| MCP config and socket | Temporary directory | Mode `0600`, removed on runtime stop |
| Installed extensions and marketplaces | Claude Code's own directories | Managed by the CLI |

`state.json` contains conversation text, tool inputs and results, file paths,
project paths, and account display names. It does not contain API keys or
code-host tokens, but it can contain sensitive project information. Composer
attachments are transient: the staged list is not saved, though absolute paths
written into a sent prompt become part of the conversation. Logs can contain
project paths and CLI diagnostics. Treat both as private data and redact them
before sharing screenshots or reports.

An unreadable state file is copied to `state-unreadable-<timestamp>.json`
before it can be overwritten, so a recovery attempt does not destroy the
original.

## Network and code hosts

- HTTPS is recommended for every provider and code-host URL. HTTP is accepted
  only where App Transport Security permits it; the app bundle enables local
  networking, and public HTTP hosts may be rejected.
- Provider credentials go to the selected Anthropic-compatible endpoint only.
- Code-host tokens go to the configured server in the host-specific header:
  GitHub `Authorization: Bearer`, GitLab `PRIVATE-TOKEN`, Gitea
  `Authorization: token`.
- Requests use a 30-second timeout, a `Gantry` user agent, and no credential
  logging. Error bodies are truncated before display.
- There is no browser-based OAuth flow; code-host access uses personal access
  tokens. Use the narrowest scopes that fit your workflow:
  - GitHub: repository access plus pull-request, issue, and checks access.
  - GitLab: `api`.
  - Gitea: repository and issue read/write.

## Build and supply chain

- The package has no third-party dependencies; everything is Swift and system
  frameworks.
- `Scripts/build-app.sh` builds with SwiftPM, bundles the `Gantry-plugins`
  helper, generates the icon, and ad-hoc signs the helper and the app. The
  build is not notarized or distributed through an auto-update channel.
- Build from source or verify any binary you download before running it.
  Ad-hoc signatures identify integrity for a local build, not publisher
  identity.
- `GantryPluginMCP` is signed as part of the bundle and launched by Claude Code
  from the app's directory.
- Do not commit `.env*` files, credentials, Keychain exports, or build output.

## Secure development rules

Changes that touch any of these areas need extra review:

- `ProviderKeychain.swift`, `PluginKeychain.swift`
- `ClaudeRuntime.swift`, `ClaudeWire.swift`, `ClaudeEvents.swift`
- `PluginToolBridge.swift`, `PluginTools.swift`,
  `AppModel+PluginTools.swift`, `GantryPluginMCP/main.swift`
- `Graphify.swift`, `Views/Graphify/`
- `ClaudePluginManager.swift`, `ModScaffolder.swift`
- `CodeHostClient.swift` and the host backends
- `SessionReview.swift`, `GitCommit.swift`, and the Review changes sheet
- the permission flow in `AppModel+Conversation.swift`

Rules:

1. Never add an auto-approval path or weaken a permission card.
2. Never pass a secret to the MCP helper, a subprocess argument, a URL, or a
   log line.
3. Keep state, log, config, and socket permissions user-only.
4. Redact before truncating or displaying external CLI/API output.
5. Keep new network clients on HTTPS by default, with timeouts, scoped tokens,
   and typed errors.
6. Add tests with fake tokens and local fixtures. Do not call real services or
   the user's Keychain in the default suite.
7. Do not broaden the bridge's scope beyond one repository and one plugin.
8. Never install or update a third-party tool without showing the exact command
   and getting an explicit confirmation.
9. If a change alters what a trust dialog or permission card promises, update
   the UI copy and this document together.

## User hardening checklist

- Review every extension before installing it; prefer sources you trust.
- Use least-privilege code-host tokens and revoke ones you no longer need.
- Use HTTPS for self-hosted providers and code hosts.
- Keep macOS and Claude Code updated.
- Protect your login keychain and lock your Mac when unattended.
- Redact conversation content, project paths, and account names from
  screenshots and reports.
- Remember that Gantry is an unofficial client and is not affiliated with
  Anthropic.

## Known limitations

- Gantry is not App-Sandboxed and has the same filesystem access as your user.
- Code-host support is token-based; there is no OAuth or fine-grained
  per-repository consent beyond the token scopes.
- Extension code runs with your permissions inside Claude Code; Gantry can
  warn, not sandbox it.
- The MCP bridge trusts the local user boundary; it is not isolation from
  same-user malware.
- Some slash commands are terminal-only and have no visual effect in Gantry.
- No security certification or third-party audit is claimed.

## Related documents

- `ARCHITECTURE.md` — process, protocol, provider, plugin, and bridge design.
- `README.md` — storage and privacy summary.
- `AGENTS.md` — contributor invariants and test rules.
