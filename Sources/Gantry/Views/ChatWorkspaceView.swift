import AppKit
import SwiftUI
import GantryCore

struct ChatWorkspaceView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.openSettings) private var openSettings

    var session: ChatSession
    var project: Project

    @State private var isAtBottom = true
    @State private var dockHeight: CGFloat = 170
    @State private var branch: String?
    @State private var providerHasKey: Bool?
    @State private var showingRepository = false

    private var activity: SessionActivity? {
        app.activities[session.id]
    }

    private var activeTurnID: UUID? {
        session.turns.last(where: { $0.isStreaming })?.id
    }

    private var pendingPermission: ClaudePermissionRequest? {
        activity?.pendingPermissions.first
    }

    private var provider: AIProvider {
        app.provider(for: session)
    }

    private var providerIsReady: Bool {
        !provider.requiresAPIKey || providerHasKey != false
    }

    var body: some View {
        VStack(spacing: 0) {
            topBar
            conversation
        }
        .background(Color.clear)
        .task(id: project.path) {
            branch = GitContext.read(from: project.url).branch
        }
        .task(id: providerStatusTaskID) {
            await refreshProviderKeyStatus()
        }
        .sheet(isPresented: $showingRepository) {
            RepositoryPluginSheet(app: app, project: project)
        }
    }

    private var providerStatusTaskID: String {
        "\(provider.id.uuidString)-\(app.providerKeyRevision)-\(provider.keychainServer)-\(provider.keychainAccount)"
    }

    private func refreshProviderKeyStatus() async {
        let provider = provider
        guard provider.requiresAPIKey else {
            providerHasKey = true
            return
        }
        providerHasKey = nil
        let hasKey = await Task.detached(priority: .utility) {
            ProviderKeychain.hasKey(for: provider)
        }.value
        guard !Task.isCancelled else { return }
        providerHasKey = hasKey
    }

    // MARK: - Top bar

    private var topBar: some View {
        HStack(spacing: 12) {
            Button {
                app.beginRenamingSession(session.id)
            } label: {
                VStack(alignment: .leading, spacing: 2) {
                    Text(session.title)
                        .font(.system(size: 13.5, weight: .semibold))
                        .foregroundStyle(Palette.ink)
                        .lineLimit(1)
                        .truncationMode(.tail)

                    HStack(spacing: 5) {
                        Image(systemName: "folder.fill")
                            .font(.system(size: 8.5, weight: .regular))
                        Text(project.name)
                            .font(.system(size: 10.5))
                            .lineLimit(1)
                        if let branch {
                            Text("·")
                                .font(.system(size: 9))
                                .foregroundStyle(Palette.faintInk)
                            Image(systemName: "arrow.triangle.branch")
                                .font(.system(size: 8, weight: .medium))
                            Text(branch)
                                .font(.system(size: 10, weight: .medium, design: .monospaced))
                                .lineLimit(1)
                        }
                    }
                    .foregroundStyle(Palette.tertiaryInk)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Rename session")
            .layoutPriority(1)

            Spacer(minLength: 10)

            providerMenu

            IconButton(
                systemName: "arrow.triangle.branch",
                help: "Repository, pull requests, and checks",
                frame: 27
            ) {
                showingRepository = true
            }

            if let activity, activity.isRunning {
                runStatusPill(activity)
                    .transition(.opacity.combined(with: .scale(scale: 0.96)))
            }

            IconButton(
                systemName: "sidebar.right",
                help: app.inspectorVisible ? "Hide inspector (⇧⌘I)" : "Show inspector (⇧⌘I)",
                frame: 27
            ) {
                app.inspectorVisible.toggle()
            }

            Menu {
                Button("Rename Session…") { app.beginRenamingSession(session.id) }
                Button("Show Project in Finder") {
                    NSWorkspace.shared.activateFileViewerSelecting([project.url])
                }
                Button("Copy Conversation") {
                    let transcript = session.turns.map { turn in
                        let prefix = turn.role == .user ? "You" : "Claude"
                        return "\(prefix):\n\(turn.textContent)"
                    }.joined(separator: "\n\n")
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(transcript, forType: .string)
                }
                Divider()
                Button("Toggle Inspector") { app.inspectorVisible.toggle() }
                Button("Open Settings…") { openSettings() }
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Palette.secondaryInk)
                    .frame(width: 27, height: 27)
                    .contentShape(Rectangle())
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .frame(width: 24)
            .help("Session actions")
        }
        .padding(.leading, 24)
        .padding(.trailing, 18)
        .frame(height: 55)
        .background(
            LinearGradient(
                colors: [Palette.canvasTop.opacity(0.78), Palette.canvasTop.opacity(0.25)],
                startPoint: .top,
                endPoint: .bottom
            )
        )
        .overlay(alignment: .bottom) { Hairline() }
        .animation(.smooth(duration: 0.2), value: activity?.isRunning)
    }

    private var providerMenu: some View {
        Menu {
            Picker("AI Provider", selection: Binding(
                get: { provider.id },
                set: { app.setProvider($0, for: session.id) }
            )) {
                ForEach(app.providers) { candidate in
                    Label(candidate.name, systemImage: ProviderPresentation.symbol(for: candidate.preset))
                        .tag(candidate.id)
                }
            }

            if provider.requiresAPIKey, providerHasKey == false {
                Button("Add API Key…") {
                    app.requestedSettingsTab = "providers"
                    openSettings()
                }
            }

            Divider()

            Button("Set as Default for New Sessions") {
                app.setDefaultProvider(provider.id)
            }
            .disabled(app.defaultProviderID == provider.id)

            Button("Manage Providers…") {
                app.requestedSettingsTab = "providers"
                openSettings()
            }
        } label: {
            HStack(spacing: 5) {
                Image(systemName: ProviderPresentation.symbol(for: provider.preset))
                    .font(.system(size: 9.5, weight: .medium))
                    .foregroundStyle(ProviderPresentation.tint(for: provider.preset))
                Text(provider.name)
                    .font(Typo.micro)
                    .foregroundStyle(Palette.secondaryInk)
                    .lineLimit(1)
                Image(systemName: "chevron.down")
                    .font(.system(size: 7, weight: .semibold))
                    .foregroundStyle(Palette.faintInk)
            }
            .frame(maxWidth: 145, alignment: .leading)
            .padding(.horizontal, 9)
            .padding(.vertical, 5.5)
            .background(
                Capsule(style: .continuous)
                    .fill(Palette.surface.opacity(0.45))
                    .overlay(
                        Capsule(style: .continuous)
                            .strokeBorder(Palette.lineStrong, lineWidth: 0.7)
                    )
            )
            .contentShape(Capsule(style: .continuous))
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .disabled(activity?.isRunning == true)
        .opacity(activity?.isRunning == true ? 0.58 : 1)
        .help(activity?.isRunning == true
              ? "Finish the current turn to switch AI providers"
              : "AI provider for this session")
        .accessibilityLabel("AI provider: \(provider.name)")
    }

    private func runStatusPill(_ activity: SessionActivity) -> some View {
        HStack(spacing: 7) {
            if activity.hasPendingPermission {
                Image(systemName: "hand.raised.fill")
                    .font(.system(size: 9.5, weight: .semibold))
                    .foregroundStyle(Palette.accent)
            } else {
                ActivityDots(color: Palette.accent, size: 2.7)
            }
            Text(activity.statusText ?? "Working")
                .font(Typo.micro)
                .foregroundStyle(Palette.secondaryInk)
                .lineLimit(1)
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 5)
        .background(
            Capsule(style: .continuous)
                .fill(Palette.surface.opacity(0.45))
                .overlay(
                    Capsule(style: .continuous)
                        .strokeBorder(Palette.lineStrong, lineWidth: 0.7)
                )
        )
    }

    // MARK: - Conversation

    private var conversation: some View {
        GeometryReader { geometry in
            ZStack(alignment: .bottom) {
                ScrollViewReader { proxy in
                    ScrollView {
                        VStack(alignment: .leading, spacing: 0) {
                            if session.turns.isEmpty {
                                EmptySessionView(
                                    session: session,
                                    project: project,
                                    isAvailable: app.claudeAvailability.isReady && providerIsReady,
                                    onSuggestion: { prompt in
                                        if app.send(prompt, in: session.id) {
                                            app.drafts[session.id] = ""
                                        }
                                    }
                                )
                                .frame(
                                    minHeight: max(120, geometry.size.height - dockHeight - 34),
                                    alignment: .center
                                )
                            } else {
                                transcript
                            }

                            Color.clear
                                .frame(height: dockHeight + 36)
                                .id("bottom")
                        }
                        .frame(maxWidth: 816)
                        .frame(maxWidth: .infinity)
                        .padding(.horizontal, 30)
                        .padding(.top, session.turns.isEmpty ? 0 : 22)
                    }
                    .scrollIndicators(.never)
                    .scrollEdgeEffectStyle(.soft, for: .top)
                    .onScrollGeometryChange(for: Bool.self) { scrollGeometry in
                        let distance = scrollGeometry.contentSize.height
                            - (scrollGeometry.contentOffset.y + scrollGeometry.containerSize.height)
                        return distance < 110
                    } action: { _, newValue in
                        if isAtBottom != newValue { isAtBottom = newValue }
                    }
                    .onChange(of: session.turns.count) { _, _ in
                        scrollToBottom(proxy, animated: true)
                    }
                    .onChange(of: pendingPermission?.requestID) { _, _ in
                        if isAtBottom { scrollToBottom(proxy, animated: true) }
                    }
                    .onChange(of: activity?.preview.text.count ?? 0) { _, _ in
                        if isAtBottom {
                            proxy.scrollTo("bottom", anchor: .bottom)
                        }
                    }
                    .onChange(of: dockHeight) { _, _ in
                        if isAtBottom { scrollToBottom(proxy, animated: false) }
                    }
                    .onAppear {
                        DispatchQueue.main.async {
                            proxy.scrollTo("bottom", anchor: .bottom)
                        }
                    }
                }

                bottomFade
                    .allowsHitTesting(false)

                dock
                    .padding(.horizontal, 28)
                    .padding(.bottom, 16)
                    .frame(maxWidth: 880)
                    .background(
                        GeometryReader { proxy in
                            Color.clear.preference(key: DockHeightKey.self, value: proxy.size.height)
                        }
                    )
            }
            .onPreferenceChange(DockHeightKey.self) { value in
                if abs(dockHeight - value) > 1 {
                    dockHeight = value
                }
            }
        }
    }

    private var transcript: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(Format.dayLabel(session.createdAt).uppercased())
                .font(.system(size: 9, weight: .semibold))
                .tracking(0.8)
                .foregroundStyle(Palette.tertiaryInk)
                .frame(maxWidth: .infinity)
                .padding(.bottom, 22)

            ForEach(Array(session.turns.enumerated()), id: \.element.id) { index, turn in
                if turn.role == .user {
                    UserTurnView(turn: turn)
                        .padding(.top, index == 0 ? 0 : 28)
                } else {
                    AssistantTurnView(
                        turn: turn,
                        activity: activity,
                        isLatest: isLatestAssistantTurn(turn),
                        projectPath: project.path,
                        onRetry: { app.retryLastPrompt(sessionID: session.id) }
                    )
                    .padding(.top, index == 0 ? 0 : 14)
                }
            }
        }
    }

    private func isLatestAssistantTurn(_ turn: ConversationTurn) -> Bool {
        session.turns.last(where: { $0.role == .assistant })?.id == turn.id
    }

    private var bottomFade: some View {
        LinearGradient(
            stops: [
                .init(color: Palette.canvasBottom.opacity(0), location: 0),
                .init(color: Palette.canvasBottom.opacity(0.58), location: 0.42),
                .init(color: Palette.canvasBottom.opacity(0.93), location: 1)
            ],
            startPoint: .top,
            endPoint: .bottom
        )
        .frame(height: max(210, dockHeight + 86))
    }

    // MARK: - Floating dock

    private var dock: some View {
        VStack(spacing: 9) {
            if provider.requiresAPIKey, providerHasKey == false {
                InlineNotice(
                    icon: "key.slash",
                    title: "API key needed",
                    message: "Add an API key for \(provider.name) in Settings → Providers before sending a message.",
                    tint: Palette.warning,
                    actionTitle: "Add Key",
                    action: {
                        app.requestedSettingsTab = "providers"
                        openSettings()
                    }
                )
                .transition(.opacity.combined(with: .move(edge: .bottom)))
            }

            if let availabilityNotice {
                InlineNotice(
                    icon: availabilityNotice.icon,
                    title: availabilityNotice.title,
                    message: availabilityNotice.message,
                    tint: availabilityNotice.tint,
                    actionTitle: "Settings",
                    action: { openSettings() }
                )
                .transition(.opacity.combined(with: .move(edge: .bottom)))
            }

            if let banner = activity?.banner {
                InlineNotice(
                    icon: "exclamationmark.circle.fill",
                    title: "Something needs attention",
                    message: banner,
                    tint: Palette.danger,
                    actionTitle: nil,
                    action: nil,
                    onDismiss: { activity?.banner = nil }
                )
                .transition(.opacity.combined(with: .move(edge: .bottom)))
            }

            GlassEffectContainer(spacing: 9) {
                VStack(spacing: 9) {
                    if let pendingPermission, let activity {
                        PermissionRequestCard(
                            request: pendingPermission,
                            project: project,
                            queuedCount: max(0, activity.pendingPermissions.count - 1)
                        ) { action in
                            app.respond(to: pendingPermission, action: action, sessionID: session.id)
                        }
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                    }

                    ComposerView(
                        session: session,
                        project: project,
                        activity: activity,
                        providerReady: providerIsReady
                    )
                }
            }
        }
        .animation(.smooth(duration: 0.24), value: activity?.pendingPermissions.count)
        .animation(.smooth(duration: 0.20), value: activity?.banner)
        .animation(.smooth(duration: 0.20), value: app.claudeAvailability)
    }

    private var availabilityNotice: (icon: String, title: String, message: String, tint: Color)? {
        switch app.claudeAvailability {
        case .checking:
            return nil
        case .ready:
            return nil
        case .missing:
            return (
                "terminal",
                "Claude Code isn't available",
                "Install Claude Code or point Gantry at its executable in Settings.",
                Palette.danger
            )
        case .failed(let message):
            return (
                "exclamationmark.triangle.fill",
                "Claude Code couldn't start",
                message,
                Palette.danger
            )
        }
    }

    private func scrollToBottom(_ proxy: ScrollViewProxy, animated: Bool) {
        if animated {
            withAnimation(.smooth(duration: 0.24)) {
                proxy.scrollTo("bottom", anchor: .bottom)
            }
        } else {
            proxy.scrollTo("bottom", anchor: .bottom)
        }
    }
}

private struct DockHeightKey: PreferenceKey {
    static var defaultValue: CGFloat = 170

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

struct InlineNotice: View {
    var icon: String
    var title: String
    var message: String
    var tint: Color
    var actionTitle: String?
    var action: (() -> Void)?
    var onDismiss: (() -> Void)?

    var body: some View {
        HStack(alignment: .top, spacing: 9) {
            Image(systemName: icon)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(tint)
                .padding(.top, 1)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(Typo.captionMedium)
                    .foregroundStyle(Palette.ink)
                Text(message)
                    .font(Typo.micro)
                    .foregroundStyle(Palette.secondaryInk)
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 4)

            if let actionTitle, let action {
                Button(action: action) {
                    Text(actionTitle)
                        .font(Typo.micro)
                        .foregroundStyle(Palette.secondaryInk)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(
                            Capsule(style: .continuous)
                                .fill(Palette.ink.opacity(0.055))
                                .overlay(Capsule(style: .continuous).strokeBorder(Palette.line, lineWidth: 0.7))
                        )
                }
                .buttonStyle(.plain)
            }

            if let onDismiss {
                Button(action: onDismiss) {
                    Image(systemName: "xmark")
                        .font(.system(size: 8.5, weight: .semibold))
                        .foregroundStyle(Palette.tertiaryInk)
                        .frame(width: 18, height: 18)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Palette.surfaceRaised.opacity(0.86))
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(Palette.lineStrong, lineWidth: 0.7)
                )
                .shadow(color: Palette.shadow.opacity(0.16), radius: 10, y: 4)
        )
    }
}

struct EmptySessionView: View {
    var session: ChatSession
    var project: Project
    var isAvailable: Bool
    var onSuggestion: (String) -> Void

    @State private var branch: String?

    private let suggestions: [(title: String, subtitle: String, icon: String, prompt: String)] = [
        (
            "Explore this project",
            "Get the shape of the codebase",
            "map",
            "Give me a concise map of this codebase: architecture, key entry points, and how the main pieces fit together."
        ),
        (
            "Review my changes",
            "Look for bugs before I commit",
            "checkmark.seal",
            "Review my uncommitted changes for bugs, regressions, and missing tests. Prioritize the findings."
        ),
        (
            "Run the checks",
            "Lint, typecheck, and test",
            "checklist",
            "Run the project's lint, typecheck, and tests, then fix anything that fails."
        ),
        (
            "Draft a CLAUDE.md",
            "Capture this project's conventions",
            "doc.text",
            "Create or update CLAUDE.md with the essentials I need to work efficiently in this project."
        )
    ]

    var body: some View {
        VStack(spacing: 22) {
            VStack(spacing: 8) {
                HStack(spacing: 7) {
                    Image(systemName: "folder.fill")
                        .font(.system(size: 9, weight: .regular))
                    Text(project.name)
                        .font(Typo.micro)
                    if let branch {
                        Text("·").font(.system(size: 8))
                        Image(systemName: "arrow.triangle.branch")
                            .font(.system(size: 8.5))
                        Text(branch)
                            .font(.system(size: 10, weight: .medium, design: .monospaced))
                    }
                }
                .foregroundStyle(Palette.tertiaryInk)
                .padding(.horizontal, 9)
                .padding(.vertical, 4)
                .background(
                    Capsule(style: .continuous)
                        .fill(Palette.surface.opacity(0.42))
                        .overlay(Capsule(style: .continuous).strokeBorder(Palette.line, lineWidth: 0.7))
                )

                Text("What should we make?")
                    .font(.system(size: 30, weight: .semibold))
                    .tracking(-0.7)
                    .foregroundStyle(Palette.ink)

                Text("Start with an idea, a bug, or a question.")
                    .font(Typo.caption)
                    .foregroundStyle(Palette.secondaryInk)
            }

            LazyVGrid(
                columns: [
                    GridItem(.flexible(), spacing: 10),
                    GridItem(.flexible(), spacing: 10)
                ],
                spacing: 10
            ) {
                ForEach(Array(suggestions.enumerated()), id: \.offset) { _, suggestion in
                    SuggestionCard(suggestion: suggestion, enabled: isAvailable) {
                        onSuggestion(suggestion.prompt)
                    }
                }
            }
            .frame(maxWidth: 610)

            Text("⌘K  Commands     ⇧⌘I  Inspector")
                .font(Typo.micro)
                .foregroundStyle(Palette.faintInk)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 26)
        .task(id: project.path) {
            branch = GitContext.read(from: project.url).branch
        }
    }
}

private struct SuggestionCard: View {
    var suggestion: (title: String, subtitle: String, icon: String, prompt: String)
    var enabled: Bool
    var action: () -> Void
    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            HStack(alignment: .top, spacing: 10) {
                ZStack {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Palette.accent.opacity(isHovering ? 0.14 : 0.085))
                    Image(systemName: suggestion.icon)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(Palette.accent)
                }
                .frame(width: 28, height: 28)

                VStack(alignment: .leading, spacing: 2) {
                    Text(suggestion.title)
                        .font(.system(size: 12.5, weight: .medium))
                        .foregroundStyle(Palette.ink)
                        .lineLimit(1)
                    Text(suggestion.subtitle)
                        .font(Typo.micro)
                        .foregroundStyle(Palette.tertiaryInk)
                        .lineLimit(1)
                }

                Spacer(minLength: 2)

                Image(systemName: "arrow.up.right")
                    .font(.system(size: 8.5, weight: .semibold))
                    .foregroundStyle(isHovering ? Palette.accent : Palette.faintInk)
                    .padding(.top, 2)
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Palette.surface.opacity(isHovering ? 0.62 : 0.40))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .strokeBorder(
                                isHovering ? Palette.accent.opacity(0.28) : Palette.line,
                                lineWidth: 0.7
                            )
                    )
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .opacity(enabled ? 1 : 0.5)
        .onHover { isHovering = $0 }
    }
}

struct ProjectLandingView: View {
    @Environment(AppModel.self) private var app
    var project: Project

    var body: some View {
        VStack(spacing: 18) {
            EmptyStateSpark()
            Text(project.name)
                .font(.system(size: 28, weight: .semibold))
                .foregroundStyle(Palette.ink)
            Text("Create a session to start working in this project.")
                .font(Typo.caption)
                .foregroundStyle(Palette.secondaryInk)
            Button {
                _ = app.newSession(in: project.id)
            } label: {
                Text("New Session")
                    .font(Typo.ui)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
            }
            .buttonStyle(.glassProminent)
            .tint(Palette.accent)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
