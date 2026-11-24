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
    @State private var showingReview = false
    @Namespace private var dockNamespace

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

    private var hasReviewableChanges: Bool {
        !session.changedFilePaths.isEmpty
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
        .sheet(isPresented: $showingReview) {
            ReviewChangesSheet(
                session: session,
                project: project,
                activity: activity
            )
        }
        .onAppear {
            consumeReviewRequest()
        }
        .onChange(of: app.reviewRequested) { _, _ in
            consumeReviewRequest()
        }
    }

    private func consumeReviewRequest() {
        guard app.reviewRequested else { return }
        app.reviewRequested = false
        showingReview = true
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
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(Palette.ink)
                        .lineLimit(1)
                        .truncationMode(.tail)

                    HStack(spacing: 6) {
                        Image(systemName: "folder")
                            .font(.system(size: 10, weight: .regular))
                        Text(project.name)
                            .font(.system(size: 11))
                            .lineLimit(1)
                        if let branch {
                            Text("·")
                                .font(.system(size: 10))
                                .foregroundStyle(Palette.faintInk)
                            Image(systemName: "arrow.triangle.branch")
                                .font(.system(size: 10, weight: .regular))
                            Text(branch)
                                .font(.system(size: 11, weight: .regular, design: .monospaced))
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

            Spacer(minLength: 12)

            providerMenu

            IconButton(
                systemName: "text.badge.checkmark",
                help: hasReviewableChanges
                    ? "Review changes (⇧⌘R)"
                    : "No file changes to review",
                frame: 28
            ) {
                app.reviewRequested = true
            }
            .disabled(!hasReviewableChanges)
            .opacity(hasReviewableChanges ? 1 : 0.45)

            IconButton(
                systemName: "arrow.triangle.branch",
                help: "Repository, pull requests, and checks",
                frame: 28
            ) {
                showingRepository = true
            }

            if let activity, activity.isRunning {
                runStatus(activity)
                    .transition(.opacity)
            }

            IconButton(
                systemName: "sidebar.right",
                help: app.inspectorVisible ? "Hide inspector (⇧⌘I)" : "Show inspector (⇧⌘I)",
                frame: 28
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
                    .frame(width: 28, height: 28)
                    .contentShape(Rectangle())
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .frame(width: 28)
            .help("Session actions")
        }
        .padding(.leading, 24)
        .padding(.trailing, 20)
        .frame(height: 56)
        .background(WindowDragSurface())
        .overlay(alignment: .bottom) { Hairline() }
        .animation(.easeOut(duration: 0.16), value: activity?.isRunning)
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
            HStack(spacing: 6) {
                Image(systemName: ProviderPresentation.symbol(for: provider.preset))
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Palette.tertiaryInk)
                Text(provider.name)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Palette.secondaryInk)
                    .lineLimit(1)
                Image(systemName: "chevron.down")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(Palette.tertiaryInk)
            }
            .frame(maxWidth: 160, alignment: .leading)
            .padding(.horizontal, 4)
            .padding(.vertical, 4)
            .contentShape(Rectangle())
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .disabled(activity?.isRunning == true)
        .opacity(activity?.isRunning == true ? 0.5 : 1)
        .help(activity?.isRunning == true
              ? "Finish the current turn to switch AI providers"
              : "AI provider for this session")
        .accessibilityLabel("AI provider: \(provider.name)")
    }

    private func runStatus(_ activity: SessionActivity) -> some View {
        HStack(spacing: 8) {
            if activity.hasPendingPermission {
                Image(systemName: "hand.raised.fill")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(Palette.accent)
            } else {
                LiveIndicator(color: Palette.accent, size: 12)
            }
            Text(activity.statusText ?? "Working")
                .font(Typo.micro)
                .foregroundStyle(Palette.secondaryInk)
                .lineLimit(1)
        }
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
                                        let composed = PromptAttachmentComposer.compose(
                                            text: prompt,
                                            attachments: app.attachments[session.id] ?? []
                                        )
                                        if app.send(composed, in: session.id) {
                                            app.drafts[session.id] = ""
                                            app.attachments[session.id] = nil
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
                        .padding(.horizontal, 32)
                        .padding(.top, session.turns.isEmpty ? 0 : 24)
                    }
                    .scrollIndicators(.never)
                    .scrollEdgeEffectStyle(.soft, for: .top)
                    .background {
                        PreviewScrollFollower(
                            sessionID: session.id,
                            proxy: proxy,
                            isAtBottom: isAtBottom
                        )
                    }
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
                    .onChange(of: dockHeight) { _, _ in
                        if isAtBottom { scrollToBottom(proxy, animated: false) }
                    }
                    .onChange(of: app.pendingTurnScroll) { _, _ in
                        scrollToPendingTurn(proxy)
                    }
                    .onAppear {
                        DispatchQueue.main.async {
                            if !scrollToPendingTurn(proxy) {
                                proxy.scrollTo("bottom", anchor: .bottom)
                            }
                        }
                    }
                }

                bottomFade
                    .allowsHitTesting(false)

                dock
                    .padding(.horizontal, 32)
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
        let firstTurnID = session.turns.first?.id
        return LazyVStack(alignment: .leading, spacing: 0) {
            Text(Format.dayLabel(session.createdAt))
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(Palette.tertiaryInk)
                .frame(maxWidth: .infinity)
                .padding(.bottom, 24)

            ForEach(session.turns) { turn in
                if turn.role == .user {
                    UserTurnView(turn: turn)
                        .padding(.top, turn.id == firstTurnID ? 0 : 32)
                        .id(turn.id)
                } else {
                    AssistantTurnView(
                        turn: turn,
                        activity: activity,
                        isLatest: isLatestAssistantTurn(turn),
                        projectPath: project.path,
                        onRetry: { app.retryLastPrompt(sessionID: session.id) }
                    )
                    .padding(.top, turn.id == firstTurnID ? 0 : 16)
                    .id(turn.id)
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
                .init(color: Palette.canvas.opacity(0), location: 0),
                .init(color: Palette.canvas.opacity(0.55), location: 0.42),
                .init(color: Palette.canvas.opacity(0.92), location: 1)
            ],
            startPoint: .top,
            endPoint: .bottom
        )
        .frame(height: max(208, dockHeight + 88))
    }

    // MARK: - Floating dock

    private var dock: some View {
        GlassEffectContainer(spacing: 8) {
            VStack(spacing: 8) {
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
                    .transition(.opacity)
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
                    .transition(.opacity)
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
                    .transition(.opacity)
                }

                if let pendingPermission, let activity {
                    Group {
                        if let questionnaire = pendingPermission.questionnaire {
                            QuestionRequestCard(
                                request: pendingPermission,
                                questionnaire: questionnaire,
                                queuedCount: max(0, activity.pendingPermissions.count - 1),
                                glassNamespace: dockNamespace,
                                onSubmit: { answers in
                                    app.answer(pendingPermission, with: answers, sessionID: session.id)
                                },
                                onDecline: {
                                    app.declineQuestion(pendingPermission, sessionID: session.id)
                                }
                            )
                        } else {
                            PermissionRequestCard(
                                request: pendingPermission,
                                project: project,
                                queuedCount: max(0, activity.pendingPermissions.count - 1),
                                glassNamespace: dockNamespace
                            ) { action in
                                app.respond(to: pendingPermission, action: action, sessionID: session.id)
                            }
                        }
                    }
                    .id(pendingPermission.requestID)
                    .transition(.opacity)
                }

                ComposerView(
                    session: session,
                    project: project,
                    activity: activity,
                    providerReady: providerIsReady,
                    glassNamespace: dockNamespace
                )
            }
        }
        .animation(.easeOut(duration: 0.2), value: activity?.pendingPermissions.count)
        .animation(.easeOut(duration: 0.16), value: activity?.banner)
        .animation(.easeOut(duration: 0.16), value: app.claudeAvailability)
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

    /// Reveals a turn selected from conversation search. The request carries
    /// its session so a workspace that is being replaced ignores it.
    @discardableResult
    private func scrollToPendingTurn(_ proxy: ScrollViewProxy) -> Bool {
        guard let request = app.pendingTurnScroll,
              request.sessionID == session.id else {
            return false
        }
        app.pendingTurnScroll = nil
        withAnimation(.easeOut(duration: 0.2)) {
            proxy.scrollTo(request.turnID, anchor: .center)
        }
        return true
    }

    private func scrollToBottom(_ proxy: ScrollViewProxy, animated: Bool) {
        if animated {
            withAnimation(.easeOut(duration: 0.2)) {
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

/// Observes only the streaming preview and scrolls the transcript, so preview
/// ticks never invalidate the full conversation hierarchy.
private struct PreviewScrollFollower: View {
    @Environment(AppModel.self) private var app
    var sessionID: UUID
    var proxy: ScrollViewProxy
    var isAtBottom: Bool

    private var previewRevision: Int {
        guard let preview = app.activities[sessionID]?.preview else { return 0 }
        return preview.text.count &* 31 &+ preview.thinking.count
    }

    var body: some View {
        Color.clear
            .frame(width: 1, height: 1)
            .allowsHitTesting(false)
            .onChange(of: previewRevision) { _, _ in
                guard isAtBottom else { return }
                proxy.scrollTo("bottom", anchor: .bottom)
            }
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
        HStack(alignment: .top, spacing: 8) {
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
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(Palette.accent)
                        .padding(.horizontal, 4)
                        .padding(.vertical, 2)
                }
                .buttonStyle(.plain)
            }

            if let onDismiss {
                Button(action: onDismiss) {
                    Image(systemName: "xmark")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(Palette.tertiaryInk)
                        .frame(width: 20, height: 20)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .glassPanel(radius: 16)
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
        VStack(spacing: 24) {
            VStack(spacing: 12) {
                HStack(spacing: 6) {
                    Image(systemName: "folder")
                        .font(.system(size: 10, weight: .regular))
                    Text(project.name)
                        .font(Typo.micro)
                    if let branch {
                        Text("·").font(.system(size: 10))
                            .foregroundStyle(Palette.tertiaryInk)
                        Image(systemName: "arrow.triangle.branch")
                            .font(.system(size: 10))
                        Text(branch)
                            .font(.system(size: 11, weight: .regular, design: .monospaced))
                    }
                }
                .foregroundStyle(Palette.tertiaryInk)

                Text("What should we make?")
                    .font(.system(size: 28, weight: .semibold))
                    .tracking(-0.5)
                    .foregroundStyle(Palette.ink)

                Text("Start with an idea, a bug, or a question.")
                    .font(Typo.caption)
                    .foregroundStyle(Palette.secondaryInk)
            }

            LazyVGrid(
                columns: [
                    GridItem(.flexible(), spacing: 8),
                    GridItem(.flexible(), spacing: 8)
                ],
                spacing: 8
            ) {
                ForEach(Array(suggestions.enumerated()), id: \.offset) { _, suggestion in
                    SuggestionCard(suggestion: suggestion, enabled: isAvailable) {
                        onSuggestion(suggestion.prompt)
                    }
                }
            }
            .frame(maxWidth: 610)

            HStack(spacing: 10) {
                HStack(spacing: 4) {
                    KeyHint(text: "⌘K")
                    Text("Commands").font(Typo.micro).foregroundStyle(Palette.faintInk)
                }
                HStack(spacing: 4) {
                    KeyHint(text: "/")
                    Text("Slash commands").font(Typo.micro).foregroundStyle(Palette.faintInk)
                }
                HStack(spacing: 4) {
                    KeyHint(text: "⇧⌘I")
                    Text("Inspector").font(Typo.micro).foregroundStyle(Palette.faintInk)
                }
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 24)
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
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: suggestion.icon)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Palette.secondaryInk)
                    .frame(width: 16, height: 16)
                    .padding(.top, 1)

                VStack(alignment: .leading, spacing: 2) {
                    Text(suggestion.title)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(Palette.ink)
                        .lineLimit(1)
                    Text(suggestion.subtitle)
                        .font(Typo.micro)
                        .foregroundStyle(Palette.tertiaryInk)
                        .lineLimit(1)
                }

                Spacer(minLength: 4)

                Image(systemName: "arrow.up.right")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(Palette.tertiaryInk)
                    .padding(.top, 2)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
                    .fill(isHovering ? Palette.surfaceRaised : Palette.surface)
                    .overlay(
                        RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
                            .strokeBorder(isHovering ? Palette.lineStrong : Palette.line, lineWidth: 1)
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
        VStack(spacing: 16) {
            BrandMark(size: 44)
            Text(project.name)
                .font(Typo.pageTitle)
                .foregroundStyle(Palette.ink)
            Text("Create a session to start working in this project.")
                .font(Typo.caption)
                .foregroundStyle(Palette.secondaryInk)
            Button {
                _ = app.newSession(in: project.id)
            } label: {
                Text("New session")
                    .font(Typo.ui)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
            }
            .buttonStyle(.glassProminent)
            .tint(Palette.accent)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
