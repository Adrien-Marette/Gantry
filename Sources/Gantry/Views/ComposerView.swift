import AppKit
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
    @State private var textSelection: TextSelection?
    @State private var commandSelection = 0
    @State private var commandMenuDismissed = false
    @State private var keyboardScrollRevision = 0
    @State private var isDropTargeted = false
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

    private var attachments: [PromptAttachment] {
        app.attachments[session.id] ?? []
    }

    private var hasPrompt: Bool {
        !trimmedDraft.isEmpty || !attachments.isEmpty
    }

    private var canSend: Bool {
        hasPrompt && !isRunning && app.claudeAvailability.isReady && providerReady
    }

    private var isComposerHighlighted: Bool {
        focused || isDropTargeted
    }

    /// Context-window usage from the latest assistant response, when Claude
    /// Code has reported one.
    private var contextUsage: (tokens: Int, limit: Int)? {
        guard let tokens = session.contextTokens, tokens > 0 else { return nil }
        // The latest result carries Claude Code's resolved model name, which
        // includes its `[1m]` marker; the session's requested alias does not.
        let model = session.turns.last(where: { $0.usage?.modelName != nil })?.usage?.modelName
            ?? session.contextModelName
            ?? session.actualModelName
        return (tokens, ModelContextWindow.limit(for: model))
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
            if let contextUsage {
                ContextBar(tokens: contextUsage.tokens, limit: contextUsage.limit)
                    .padding(.horizontal, 4)
            }

            if !attachments.isEmpty {
                attachmentChips
            }

            TextField(placeholder, text: draft, selection: $textSelection, axis: .vertical)
                .textFieldStyle(.plain)
                .font(.system(size: 14, weight: .regular))
                .foregroundStyle(Palette.ink)
                .lineSpacing(3)
                .lineLimit(1...9)
                .focused($focused)
                .onKeyPress(.return, phases: .down) { press in
                    if press.modifiers.contains(.shift) || press.modifiers.contains(.option) {
                        insertLineBreak()
                        return .handled
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
                IconButton(
                    systemName: "paperclip",
                    help: "Attach files or folders",
                    size: 12,
                    frame: 28
                ) {
                    chooseAttachments()
                }

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
        .dropDestination(for: URL.self) { urls, _ in
            addAttachments(urls)
        } isTargeted: { targeted in
            isDropTargeted = targeted
        }
        .overlay {
            if isComposerHighlighted {
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .strokeBorder(Palette.accent, lineWidth: 2)
                    .allowsHitTesting(false)
            }
        }
        .animation(.easeOut(duration: 0.16), value: isComposerHighlighted)
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
        if !attachments.isEmpty, trimmedDraft.isEmpty {
            return "Ask Claude about these files"
        }
        if session.turns.isEmpty {
            return "Ask Claude to build, fix, or explain"
        }
        return "Message Claude"
    }

    // MARK: - Attachments

    private var attachmentChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(attachments) { attachment in
                    attachmentChip(attachment)
                }
            }
            .padding(.vertical, 1)
        }
        .scrollIndicators(.never)
        .padding(.horizontal, 4)
    }

    private func attachmentChip(_ attachment: PromptAttachment) -> some View {
        HStack(spacing: 5) {
            Image(systemName: attachment.isDirectory ? "folder" : "doc.text")
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(Palette.tertiaryInk)

            Text(attachment.name)
                .font(Typo.micro)
                .foregroundStyle(Palette.secondaryInk)
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(maxWidth: 180, alignment: .leading)

            Button {
                removeAttachment(attachment)
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 8, weight: .semibold))
                    .foregroundStyle(Palette.tertiaryInk)
                    .frame(width: 24, height: 24)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Remove \(attachment.name)")
            .accessibilityLabel("Remove \(attachment.name)")
        }
        .padding(.leading, 7)
        .padding(.trailing, 1)
        .padding(.vertical, 1)
        .background(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(Palette.ink.opacity(0.04))
                .overlay(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .strokeBorder(Palette.line, lineWidth: 1)
                )
        )
        .help(attachment.path)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(attachment.isDirectory ? "Folder" : "File") \(attachment.name)")
    }

    @discardableResult
    private func addAttachments(_ urls: [URL]) -> Bool {
        let incoming = PromptAttachment.make(from: urls)
        guard !incoming.isEmpty else { return false }
        app.attachments[session.id] = PromptAttachment.merging(
            attachments,
            with: incoming
        )
        focused = true
        return true
    }

    private func removeAttachment(_ attachment: PromptAttachment) {
        app.attachments[session.id]?.removeAll { $0.id == attachment.id }
        if app.attachments[session.id]?.isEmpty == true {
            app.attachments[session.id] = nil
        }
    }

    private func chooseAttachments() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = true
        panel.canCreateDirectories = false
        panel.prompt = "Attach"
        panel.message = "Choose files or folders to give Claude as context."
        if panel.runModal() == .OK {
            addAttachments(panel.urls)
        }
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
            if hasPrompt, !app.claudeAvailability.isReady {
                activity?.banner = "Claude Code isn't available yet."
            }
            return
        }
        let prompt = PromptAttachmentComposer.compose(
            text: draft.wrappedValue,
            attachments: attachments
        )
        if app.send(prompt, in: session.id) {
            app.drafts[session.id] = ""
            app.attachments[session.id] = nil
            textSelection = TextSelection(insertionPoint: "".endIndex)
            focused = true
        }
    }

    /// Shift-Return and Option-Return insert a line break. AppKit's field
    /// editor treats those chords as editing commands on macOS, so Gantry
    /// inserts the newline itself and consumes the key press.
    private func insertLineBreak() {
        let current = draft.wrappedValue
        guard let range = textSelection?.firstRange,
              range.lowerBound >= current.startIndex,
              range.lowerBound <= current.endIndex,
              range.upperBound <= current.endIndex else {
            var updated = current
            updated.append("\n")
            draft.wrappedValue = updated
            textSelection = TextSelection(insertionPoint: updated.endIndex)
            return
        }

        var updated = current
        updated.replaceSubrange(range, with: "\n")
        let caret = updated.index(after: range.lowerBound)
        draft.wrappedValue = updated
        textSelection = TextSelection(insertionPoint: caret)
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
        textSelection = TextSelection(insertionPoint: "".endIndex)
        focused = true
    }

    /// Completes the selected command in place so arguments can be typed.
    /// Pressing Return again then sends it.
    private func accept(_ command: ClaudeSlashCommand) {
        let invocation = command.invocation + " "
        app.drafts[session.id] = invocation
        textSelection = TextSelection(insertionPoint: invocation.endIndex)
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

/// A quiet meter for the prompt tokens Claude Code last reported, measured
/// against the model's assumed context window. The fill turns warning and then
/// danger as the window fills, while the text stays quiet.
private struct ContextBar: View {
    var tokens: Int
    var limit: Int

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var fraction: Double {
        guard limit > 0 else { return 0 }
        return min(1, max(0, Double(tokens) / Double(limit)))
    }

    private var percent: Int {
        guard limit > 0 else { return 0 }
        return min(100, Int((Double(tokens) / Double(limit) * 100).rounded()))
    }

    private var tint: Color {
        if fraction >= 0.95 { return Palette.danger }
        if fraction >= 0.8 { return Palette.warning }
        return Palette.secondaryInk
    }

    private var helpText: String {
        "Estimated context from Claude's latest response, including cached prompt tokens. "
            + "Measured against a \(Format.tokens(limit))-token window for this model."
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 6) {
                Text("Context")
                    .font(Typo.micro)
                    .foregroundStyle(Palette.tertiaryInk)

                Spacer(minLength: 8)

                Text("\(Format.tokens(tokens)) / \(Format.tokens(limit)) · \(percent)%")
                    .font(Typo.monoSmall)
                    .monospacedDigit()
                    .foregroundStyle(Palette.tertiaryInk)
            }

            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule(style: .continuous)
                        .fill(Palette.lineStrong)
                    Capsule(style: .continuous)
                        .fill(tint)
                        .frame(width: max(fraction > 0 ? 3 : 0, proxy.size.width * fraction))
                }
            }
            .frame(height: 3)
        }
        .animation(reduceMotion ? nil : .easeOut(duration: 0.2), value: fraction)
        .help(helpText)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Context usage")
        .accessibilityValue("\(percent) percent, \(Format.tokens(tokens)) of \(Format.tokens(limit)) tokens")
    }
}

private extension TextSelection {
    /// The first selected range, or the caret position for an insertion point.
    var firstRange: Range<String.Index>? {
        switch indices {
        case .selection(let range):
            return range
        case .multiSelection(let ranges):
            return ranges.ranges.first
        @unknown default:
            return nil
        }
    }
}
