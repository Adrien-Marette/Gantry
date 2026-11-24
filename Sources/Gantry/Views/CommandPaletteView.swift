import AppKit
import SwiftUI
import GantryCore

struct CommandPaletteView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.openSettings) private var openSettings

    @State private var query = ""
    @State private var selectedIndex = 0
    @State private var keyboardScrollRevision = 0
    @FocusState private var searchFocused: Bool

    var body: some View {
        ZStack(alignment: .top) {
            Palette.scrim
                .ignoresSafeArea()
                .onTapGesture { close() }

            panel
                .padding(.top, 80)
                .frame(maxWidth: 620)
                .padding(.horizontal, 24)
                .transition(.opacity)
        }
        .onAppear {
            searchFocused = true
            selectedIndex = 0
        }
        .onKeyPress(.escape) {
            close()
            return .handled
        }
        .onKeyPress(.downArrow) {
            moveSelection(1)
            return .handled
        }
        .onKeyPress(.upArrow) {
            moveSelection(-1)
            return .handled
        }
        .onChange(of: query) { _, _ in
            selectedIndex = 0
            keyboardScrollRevision &+= 1
        }
    }

    private var panel: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Palette.tertiaryInk)
                TextField("Search sessions or commands", text: $query)
                    .textFieldStyle(.plain)
                    .font(.system(size: 14))
                    .foregroundStyle(Palette.ink)
                    .focused($searchFocused)
                    .onSubmit { performSelected() }
                if !query.isEmpty {
                    Button {
                        query = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 11))
                            .foregroundStyle(Palette.tertiaryInk)
                    }
                    .buttonStyle(.plain)
                }
                KeyHint(text: "esc")
            }
            .padding(.horizontal, 16)
            .frame(height: 52)

            Hairline()

            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 1) {
                        if entries.isEmpty {
                            emptyState
                        } else {
                            ForEach(Array(entries.enumerated()), id: \.element.id) { index, entry in
                                PaletteRow(
                                    entry: entry,
                                    isSelected: index == selectedIndex,
                                    onHover: { selectedIndex = index },
                                    action: {
                                        selectedIndex = index
                                        perform(entry)
                                    }
                                )
                                .id(entry.id)
                            }
                        }
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 8)
                }
                .frame(height: listHeight)
                .scrollIndicators(.never)
                .onChange(of: keyboardScrollRevision) { _, _ in
                    guard !entries.isEmpty else { return }
                    let clamped = min(max(selectedIndex, 0), entries.count - 1)
                    withAnimation(.easeOut(duration: 0.12)) {
                        proxy.scrollTo(entries[clamped].id, anchor: .center)
                    }
                }
            }

            Hairline()

            HStack(spacing: 12) {
                HStack(spacing: 4) {
                    KeyHint(text: "↑↓")
                    Text("navigate")
                        .font(Typo.micro)
                        .foregroundStyle(Palette.tertiaryInk)
                }
                HStack(spacing: 4) {
                    KeyHint(text: "↵")
                    Text("open")
                        .font(Typo.micro)
                        .foregroundStyle(Palette.tertiaryInk)
                }
                Spacer()
                GantryLockup(compact: true)
                    .opacity(0.55)
            }
            .padding(.horizontal, 16)
            .frame(height: 40)
        }
        .glassPanel(radius: 20)
    }

    private var listHeight: CGFloat {
        if entries.isEmpty { return 168 }
        return min(CGFloat(entries.count) * 44 + 16, 392)
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 18, weight: .regular))
                .foregroundStyle(Palette.tertiaryInk)
            Text("No matches")
                .font(Typo.captionMedium)
                .foregroundStyle(Palette.secondaryInk)
            Text("Try a session title, project name, or command.")
                .font(Typo.micro)
                .foregroundStyle(Palette.tertiaryInk)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
    }

    struct PaletteEntry: Identifiable {
        enum Kind {
            case action
            case session
        }

        var id: String
        var kind: Kind
        var title: String
        var subtitle: String
        var icon: String
        var tint: Color
        var hint: String?
        var searchText: String = ""
        var action: () -> Void
    }

    private var entries: [PaletteEntry] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        var items: [PaletteEntry] = []

        if !app.projects.isEmpty {
            items.append(PaletteEntry(
                id: "action.new",
                kind: .action,
                title: "New Session",
                subtitle: "Start a fresh conversation",
                icon: "plus.bubble",
                tint: Palette.accent,
                hint: "⌘N",
                searchText: "new session chat start",
                action: { dismissAnd { _ = app.newSession() } }
            ))
        }

        items.append(contentsOf: [
            PaletteEntry(
                id: "action.open",
                kind: .action,
                title: "Open Project…",
                subtitle: "Add a folder to Gantry",
                icon: "folder.badge.plus",
                tint: Palette.accent,
                hint: "⌘O",
                searchText: "open add project folder",
                action: { dismissAnd { app.chooseProjectFolder() } }
            ),
            PaletteEntry(
                id: "action.find",
                kind: .action,
                title: "Find in Conversations",
                subtitle: "Search every project and session",
                icon: "magnifyingglass",
                tint: Palette.info,
                hint: "⇧⌘F",
                searchText: "find search conversations messages transcripts history",
                action: { dismissAnd { app.searchRequested = true } }
            ),
            PaletteEntry(
                id: "action.inspector",
                kind: .action,
                title: "Toggle Inspector",
                subtitle: "Show session details and changed files",
                icon: "sidebar.right",
                tint: Palette.info,
                hint: "⇧⌘I",
                searchText: "inspector details files usage",
                action: { dismissAnd { app.inspectorVisible.toggle() } }
            ),
            PaletteEntry(
                id: "action.providers",
                kind: .action,
                title: "Manage AI Providers…",
                subtitle: "Switch backends and add API keys",
                icon: "server.rack",
                tint: Palette.info,
                hint: nil,
                searchText: "providers api keys deepseek anthropic gateway openrouter models",
                action: {
                    dismissAnd {
                        app.requestedSettingsTab = "providers"
                        openSettings()
                    }
                }
            ),
            PaletteEntry(
                id: "action.extensions",
                kind: .action,
                title: "Extensions & Mods",
                subtitle: "Install plugins, favorite sources, create a mod",
                icon: "puzzlepiece.extension",
                tint: Palette.accent,
                hint: "⇧⌘E",
                searchText: "extensions mods plugins marketplace sources skills hooks agents mcp install create",
                action: {
                    dismissAnd {
                        app.showExtensions()
                    }
                }
            ),
            PaletteEntry(
                id: "action.plugins",
                kind: .action,
                title: "Manage Code Hosts…",
                subtitle: "Connect GitHub, GitLab, or Gitea",
                icon: "puzzlepiece",
                tint: Palette.success,
                hint: nil,
                searchText: "code hosts plugins integrations github gitlab gitea pull requests comments checks",
                action: {
                    dismissAnd {
                        app.requestedSettingsTab = "plugins"
                        openSettings()
                    }
                }
            ),
            PaletteEntry(
                id: "action.settings",
                kind: .action,
                title: "Settings…",
                subtitle: "Models, permissions, and Claude Code",
                icon: "gearshape",
                tint: Palette.secondaryInk,
                hint: "⌘,",
                searchText: "settings preferences configuration",
                action: { dismissAnd { openSettings() } }
            ),
            PaletteEntry(
                id: "action.rescan",
                kind: .action,
                title: "Rescan for Claude Code",
                subtitle: "Look for the CLI again",
                icon: "arrow.clockwise",
                tint: Palette.success,
                hint: nil,
                searchText: "rescan find cli claude path",
                action: { dismissAnd { app.resolveClaude() } }
            )
        ])

        if let selectedSession = app.selectedSession,
           !selectedSession.changedFilePaths.isEmpty {
            items.append(PaletteEntry(
                id: "action.review",
                kind: .action,
                title: "Review Changes",
                subtitle: "Review Claude's file edits, leave notes, and commit",
                icon: "text.badge.checkmark",
                tint: Palette.accent,
                hint: "⇧⌘R",
                searchText: "review changes diff files notes commit ship",
                action: {
                    dismissAnd {
                        app.mainDestination = .workspace
                        app.reviewRequested = true
                    }
                }
            ))
        }

        let matchingActions = items.filter { entry in
            trimmed.isEmpty
                || entry.title.lowercased().contains(trimmed)
                || entry.subtitle.lowercased().contains(trimmed)
                || entry.searchText.lowercased().contains(trimmed)
        }

        var sessionItems: [PaletteEntry] = []
        for project in app.projects {
            for session in project.sortedSessions {
                let subtitle = "\(project.name) · \(Format.relativeTime(session.updatedAt))"
                sessionItems.append(PaletteEntry(
                    id: "session.\(session.id.uuidString)",
                    kind: .session,
                    title: session.title.isEmpty ? "New session" : session.title,
                    subtitle: subtitle,
                    icon: "bubble.left",
                    tint: app.selectedSessionID == session.id ? Palette.accent : Palette.tertiaryInk,
                    hint: nil,
                    searchText: [
                        session.title,
                        project.name,
                        session.firstUserPrompt ?? ""
                    ].joined(separator: " "),
                    action: {
                        dismissAnd {
                            app.select(sessionID: session.id)
                        }
                    }
                ))
            }
        }

        let matchingSessions = sessionItems.filter { entry in
            trimmed.isEmpty
                || entry.title.lowercased().contains(trimmed)
                || entry.subtitle.lowercased().contains(trimmed)
                || entry.searchText.lowercased().contains(trimmed)
        }
        let limitedSessions = trimmed.isEmpty
            ? Array(matchingSessions.prefix(6))
            : Array(matchingSessions.prefix(20))
        return matchingActions + limitedSessions
    }

    private func moveSelection(_ delta: Int) {
        guard !entries.isEmpty else { return }
        let next = selectedIndex + delta
        selectedIndex = (next + entries.count) % entries.count
        keyboardScrollRevision &+= 1
    }

    private func performSelected() {
        guard !entries.isEmpty else { return }
        let index = min(max(selectedIndex, 0), entries.count - 1)
        perform(entries[index])
    }

    private func perform(_ entry: PaletteEntry) {
        entry.action()
    }

    private func dismissAnd(_ action: @escaping () -> Void) {
        app.commandPalettePresented = false
        DispatchQueue.main.async {
            action()
        }
    }

    private func close() {
        app.commandPalettePresented = false
    }
}

private struct PaletteRow: View {
    var entry: CommandPaletteView.PaletteEntry
    var isSelected: Bool
    var onHover: () -> Void
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: entry.icon)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(isSelected ? Palette.ink : Palette.secondaryInk)
                    .frame(width: 18, height: 18)

                VStack(alignment: .leading, spacing: 2) {
                    Text(entry.title)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(Palette.ink)
                        .lineLimit(1)
                    Text(entry.subtitle)
                        .font(Typo.micro)
                        .foregroundStyle(Palette.tertiaryInk)
                        .lineLimit(1)
                }

                Spacer(minLength: 4)

                if let hint = entry.hint {
                    KeyHint(text: hint)
                }
            }
            .padding(.horizontal, 12)
            .frame(height: 40)
            .background(
                RoundedRectangle(cornerRadius: Radius.control, style: .continuous)
                    .fill(isSelected ? Palette.ink.opacity(0.06) : Color.clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            if hovering { onHover() }
        }
    }
}
