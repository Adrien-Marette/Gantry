import AppKit
import SwiftUI
import GantryCore

struct CommandPaletteView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.openSettings) private var openSettings

    @State private var query = ""
    @State private var selectedIndex = 0
    @FocusState private var searchFocused: Bool

    var body: some View {
        ZStack(alignment: .top) {
            Color.black.opacity(0.24)
                .ignoresSafeArea()
                .onTapGesture { close() }

            panel
                .padding(.top, 82)
                .frame(maxWidth: 620)
                .padding(.horizontal, 24)
                .transition(.move(edge: .top).combined(with: .opacity))
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
        }
    }

    private var panel: some View {
        VStack(spacing: 0) {
            HStack(spacing: 9) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Palette.tertiaryInk)
                TextField("Search sessions or commands…", text: $query)
                    .textFieldStyle(.plain)
                    .font(.system(size: 15))
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
            .padding(.horizontal, 17)
            .frame(height: 51)

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
                    .padding(.horizontal, 7)
                    .padding(.vertical, 7)
                }
                .frame(height: listHeight)
                .scrollIndicators(.never)
                .onChange(of: selectedIndex) { _, newValue in
                    guard !entries.isEmpty else { return }
                    let clamped = min(max(newValue, 0), entries.count - 1)
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
                        .foregroundStyle(Palette.faintInk)
                }
                HStack(spacing: 4) {
                    KeyHint(text: "↵")
                    Text("open")
                        .font(Typo.micro)
                        .foregroundStyle(Palette.faintInk)
                }
                Spacer()
                GantryLockup(compact: true)
                    .opacity(0.65)
            }
            .padding(.horizontal, 15)
            .frame(height: 38)
        }
        .background(
            RoundedRectangle(cornerRadius: 21, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            Palette.canvasTop.opacity(0.82),
                            Palette.canvasBottom.opacity(0.76)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
        )
        .glassEffect(
            .regular.tint(Palette.accent.opacity(0.025)),
            in: RoundedRectangle(cornerRadius: 21, style: .continuous)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 21, style: .continuous)
                .strokeBorder(Palette.lineStrong, lineWidth: 0.8)
        )
        .shadow(color: .black.opacity(0.28), radius: 44, y: 18)
    }

    private var listHeight: CGFloat {
        if entries.isEmpty { return 168 }
        return min(CGFloat(entries.count) * 41 + 14, 392)
    }

    private var emptyState: some View {
        VStack(spacing: 7) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 19, weight: .light))
                .foregroundStyle(Palette.faintInk)
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
                id: "action.plugins",
                kind: .action,
                title: "Manage Plugins…",
                subtitle: "Connect GitHub, GitLab, or Gitea",
                icon: "puzzlepiece",
                tint: Palette.success,
                hint: nil,
                searchText: "plugins integrations github gitlab gitea pull requests comments checks",
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
                ZStack {
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(entry.tint.opacity(isSelected ? 0.14 : 0.08))
                    Image(systemName: entry.icon)
                        .font(.system(size: 11.5, weight: .medium))
                        .foregroundStyle(entry.tint)
                }
                .frame(width: 27, height: 27)

                VStack(alignment: .leading, spacing: 1) {
                    Text(entry.title)
                        .font(.system(size: 12.5, weight: .medium))
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
                } else if isSelected {
                    Image(systemName: "arrow.turn.down.left")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(Palette.tertiaryInk)
                        .padding(.trailing, 3)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(isSelected ? Palette.accent.opacity(0.10) : Color.clear)
                    .overlay(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .strokeBorder(
                                isSelected ? Palette.accent.opacity(0.22) : Color.clear,
                                lineWidth: 0.7
                            )
                    )
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            if hovering { onHover() }
        }
    }
}
