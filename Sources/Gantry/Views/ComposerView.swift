import SwiftUI
import GantryCore

struct ComposerView: View {
    @Environment(AppModel.self) private var app
    var session: ChatSession
    var project: Project
    var activity: SessionActivity?
    var providerReady = true
    var glassNamespace: Namespace.ID?

    @FocusState private var focused: Bool
    @State private var commandSelection = 0
    @State private var commandMenuDismissed = false
    @State private var keyboardScrollRevision = 0
    @Namespace private var ownGlassNamespace

    private var isRunning: Bool {
        activity?.isRunning == true
    }

    // MARK: - Slash commands

    /// The typed slash token, for example `com` in `/com`. A space ends the
    /// token so arguments can be typed freely.
    private var slashQuery: String? {
        let text = draft.wrappedValue
        guard text.hasPrefix("/") else { return nil }
        let token = text.dropFirst()
        guard !token.contains(where: \.isWhitespace) else { return nil }
        return String(token)
    }

    private var commandEntryActive: Bool {
        slashQuery != nil && !commandMenuDismissed && !isRunning
    }

    private var commandCatalog: [ClaudeSlashCommand] {
        activity?.slashCommands ?? []
    }

    private var filteredCommands: [ClaudeSlashCommand] {
        guard let slashQuery else { return [] }
        return commandCatalog.filter { $0.matches(slashQuery) }
    }

    private var clampedCommandSelection: Int {
        guard !filteredCommands.isEmpty else { return 0 }
        return min(max(commandSelection, 0), filteredCommands.count - 1)
    }

    private var draft: Binding<String> {
        Binding(
            get: { app.drafts[session.id] ?? "" },
            set: { app.drafts[session.id] = $0 }
        )
    }

    private var trimmedDraft: String {
        draft.wrappedValue.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var canSend: Bool {
        !trimmedDraft.isEmpty && !isRunning && app.claudeAvailability.isReady && providerReady
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            if commandEntryActive {
                SlashCommandMenu(
                    commands: filteredCommands,
                    selectedIndex: clampedCommandSelection,
                    isLoading: activity?.isLoadingSlashCommands == true,
                    errorMessage: activity?.slashCommandsError,
                    query: slashQuery ?? "",
                    catalogCount: commandCatalog.count,
                    scrollRevision: keyboardScrollRevision,
                    onSelect: { command in accept(command) },
                    onHighlight: { command in
                        guard let index = filteredCommands.firstIndex(where: { $0.id == command.id }) else {
                            return
                        }
                        commandSelection = index
                    },
                    onRetry: { app.loadSlashCommands(for: session.id, retry: true) }
                )
                .frame(maxWidth: 610, alignment: .leading)
                .transition(.opacity)
            }

            composerSurface
        }
        .animation(.easeOut(duration: 0.14), value: commandEntryActive)
    }

    private var composerSurface: some View {
        VStack(alignment: .leading, spacing: 8) {
            TextField(placeholder, text: draft, axis: .vertical)
                .textFieldStyle(.plain)
                .font(.system(size: 14, weight: .regular))
                .foregroundStyle(Palette.ink)
                .lineSpacing(3)
                .lineLimit(1...9)
                .focused($focused)
                .onKeyPress(.return, phases: .down) { press in
                    if press.modifiers.contains(.shift) || press.modifiers.contains(.option) {
                        return .ignored
                    }
                    if isRunning { return .handled }
                    submit()
                    return .handled
                }
                .onKeyPress(.upArrow) {
                    guard commandEntryActive else { return .ignored }
                    moveCommandSelection(-1)
                    return .handled
                }
                .onKeyPress(.downArrow) {
                    guard commandEntryActive else { return .ignored }
                    moveCommandSelection(1)
                    return .handled
                }
                .onKeyPress(.escape) {
                    guard commandEntryActive else { return .ignored }
                    commandMenuDismissed = true
                    return .handled
                }
                .onChange(of: slashQuery) { _, newValue in
                    commandSelection = 0
                    commandMenuDismissed = false
                    keyboardScrollRevision &+= 1
                    if newValue != nil {
                        app.loadSlashCommands(for: session.id)
                    }
                }
                .onChange(of: app.claudeAvailability) { _, availability in
                    if slashQuery != nil, commandCatalog.isEmpty, availability.isReady {
                        app.loadSlashCommands(for: session.id, retry: true)
                    }
                }
                .onChange(of: isRunning) { _, running in
                    if !running, slashQuery != nil, commandCatalog.isEmpty {
                        app.loadSlashCommands(for: session.id, retry: true)
                    }
                }
                .onAppear {
                    if slashQuery != nil {
                        app.loadSlashCommands(for: session.id)
                    }
                }
                .padding(.horizontal, 4)
                .padding(.top, 2)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 8) {
                permissionMenu
                modelMenu

                Spacer(minLength: 8)

                if isRunning {
                    HStack(spacing: 8) {
                        LiveIndicator(color: Palette.accent, size: 12)
                        Text(activity?.isStopping == true ? "Stopping" : (activity?.statusText ?? "Working"))
                            .font(Typo.micro)
                            .foregroundStyle(Palette.secondaryInk)
                            .lineLimit(1)
                    }
                    .padding(.trailing, 4)
                } else {
                    HStack(spacing: 6) {
                        HStack(spacing: 4) {
                            KeyHint(text: "/")
                            Text("commands")
                        }
                        HStack(spacing: 4) {
                            KeyHint(text: "↵")
                            Text("send")
                        }
                        HStack(spacing: 4) {
                            KeyHint(text: "⇧↵")
                            Text("new line")
                        }
                    }
                    .font(Typo.micro)
                    .foregroundStyle(Palette.tertiaryInk)
                    .padding(.trailing, 4)
                }

                primaryButton
            }
            .padding(.horizontal, 4)
        }
        .padding(.horizontal, 16)
        .padding(.top, 12)
        .padding(.bottom, 12)
        .glassPanel(radius: 20, interactive: true)
        .glassEffectID("composer", in: glassNamespace ?? ownGlassNamespace)
        .overlay {
            if focused {
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .strokeBorder(Palette.accent, lineWidth: 2)
                    .allowsHitTesting(false)
            }
        }
        .animation(.easeOut(duration: 0.16), value: focused)
        .onAppear {
            if session.turns.isEmpty {
                focused = true
            }
        }
    }

    private var placeholder: String {
        if !app.claudeAvailability.isReady {
            return "Claude Code isn't available"
        }
        if !providerReady {
            return "Add an API key to use this provider"
        }
        if isRunning {
            return "Claude is working"
        }
        if session.turns.isEmpty {
            return "Ask Claude to build, fix, or explain"
        }
        return "Message Claude"
    }

    private var permissionMenu: some View {
        Menu {
            Picker("Permission", selection: Binding(
                get: { session.permissionMode },
                set: { app.setPermissionMode($0, for: session.id) }
            )) {
                ForEach(PermissionMode.allCases) { mode in
                    Label(mode.title, systemImage: mode.symbol)
                        .tag(mode)
                }
            }
            Divider()
            Text(session.permissionMode.detail)
            Text(permissionHelp)
        } label: {
            ControlLabel(
                systemName: session.permissionMode.symbol,
                title: session.permissionMode.title,
                tint: Palette.accent
            )
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .disabled(isRunning)
        .opacity(isRunning ? 0.64 : 1)
        .help("Permission mode: \(session.permissionMode.detail)")
    }

    private var modelMenu: some View {
        Menu {
            Picker("Model", selection: Binding(
                get: { session.model },
                set: { app.setModel($0, for: session.id) }
            )) {
                ForEach(ModelChoice.allCases) { model in
                    Text(model.title).tag(model)
                }
            }
            Divider()
            Text(session.model.detail)
            if let actual = session.actualModelName, session.model == .automatic {
                Text("Active: \(actual)")
            }
        } label: {
            ControlLabel(
                systemName: "cpu",
                title: session.displayModelName,
                tint: Palette.secondaryInk
            )
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .disabled(isRunning)
        .opacity(isRunning ? 0.64 : 1)
        .help("Model for this session")
    }

    private var permissionHelp: String {
        switch session.permissionMode {
        case .ask: return "Claude will ask here before running commands or changing files."
        case .autoEdits: return "File edits run automatically; commands still ask."
        case .plan: return "Claude explores and proposes a plan without changing files."
        case .auto: return "Claude Code's classifier approves low-risk actions."
        }
    }

    private var primaryButton: some View {
        Group {
            if isRunning {
                Button {
                    app.stop(sessionID: session.id)
                } label: {
                    Image(systemName: "stop.fill")
                        .font(.system(size: 10, weight: .semibold))
                        .frame(width: 16, height: 16)
                        .padding(7)
                }
                .buttonStyle(.glass)
                .buttonBorderShape(.circle)
                .help("Stop (⌘.)")
                .accessibilityLabel("Stop Claude")
            } else {
                Button {
                    submit()
                } label: {
                    Image(systemName: "arrow.up")
                        .font(.system(size: 12, weight: .semibold))
                        .frame(width: 16, height: 16)
                        .padding(7)
                }
                .buttonStyle(.glassProminent)
                .buttonBorderShape(.circle)
                .tint(Palette.accent)
                .disabled(!canSend)
                .opacity(canSend ? 1 : 0.45)
                .help("Send")
                .accessibilityLabel("Send message")
            }
        }
    }

    private func submit() {
        guard !isRunning, providerReady else { return }

        // While a slash token is being typed, Return chooses from the picker
        // instead of sending the partial command to Claude.
        if commandEntryActive, handleCommandMenuSubmit() {
            return
        }

        guard canSend else {
            if !trimmedDraft.isEmpty, !app.claudeAvailability.isReady {
                activity?.banner = "Claude Code isn't available yet."
            }
            return
        }
        let prompt = draft.wrappedValue
        if app.send(prompt, in: session.id) {
            app.drafts[session.id] = ""
            focused = true
        }
    }

    /// Returns true when the picker consumed the submission.
    private func handleCommandMenuSubmit() -> Bool {
        guard let query = slashQuery else { return false }

        let commands = filteredCommands
        if !commands.isEmpty {
            let highlighted = commands[clampedCommandSelection]
            let lowered = query.lowercased()
            if highlighted.name.lowercased() == lowered
                || highlighted.aliases.contains(where: { $0.lowercased() == lowered }) {
                execute(highlighted)
            } else {
                accept(highlighted)
            }
            return true
        }

        if activity?.isLoadingSlashCommands == true || commandCatalog.isEmpty {
            // Keep the draft intact until the catalog or its error arrives.
            return true
        }

        activity?.banner = "No command matches “/\(query)”."
        return true
    }

    private func execute(_ command: ClaudeSlashCommand) {
        guard app.send(command.invocation, in: session.id) else { return }
        app.drafts[session.id] = ""
        focused = true
    }

    /// Completes the selected command in place so arguments can be typed.
    /// Pressing Return again then sends it.
    private func accept(_ command: ClaudeSlashCommand) {
        app.drafts[session.id] = command.invocation + " "
        commandMenuDismissed = true
        focused = true
    }

    private func moveCommandSelection(_ delta: Int) {
        let commands = filteredCommands
        guard !commands.isEmpty else { return }
        let next = clampedCommandSelection + delta
        commandSelection = (next + commands.count) % commands.count
        keyboardScrollRevision &+= 1
    }
}
