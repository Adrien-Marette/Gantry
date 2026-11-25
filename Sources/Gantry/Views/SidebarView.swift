import AppKit
import SwiftUI
import GantryCore

struct SidebarView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.openSettings) private var openSettings

    @State private var collapsedProjects: Set<UUID> = []
    @State private var hoveredProjectID: UUID?
    @State private var hoveredSessionID: UUID?
    @State private var isHoveringNewSession = false
    @FocusState private var searchFocused: Bool
    @State private var pendingDeleteSession: ChatSession?
    @State private var pendingRemoveProject: Project?

    var body: some View {
        ZStack {
            Color.clear
                .glassEffect(.regular, in: Rectangle())
                .ignoresSafeArea(edges: .top)

            VStack(spacing: 0) {
                topContent
                    .background(WindowDragSurface())
                projectList
            }
            .safeAreaInset(edge: .bottom, spacing: 0) { footer }
        }
        .overlay(alignment: .trailing) {
            Hairline(axis: .vertical)
                .ignoresSafeArea(edges: .top)
        }
        .alert(
            "Delete session?",
            isPresented: Binding(
                get: { pendingDeleteSession != nil },
                set: { if !$0 { pendingDeleteSession = nil } }
            ),
            presenting: pendingDeleteSession
        ) { session in
            Button("Delete", role: .destructive) {
                app.deleteSession(session.id)
                pendingDeleteSession = nil
            }
            Button("Cancel", role: .cancel) { pendingDeleteSession = nil }
        } message: { _ in
            Text("This removes the conversation from Gantry. Your project files are not touched.")
        }
        .alert(
            "Remove project?",
            isPresented: Binding(
                get: { pendingRemoveProject != nil },
                set: { if !$0 { pendingRemoveProject = nil } }
            ),
            presenting: pendingRemoveProject
        ) { project in
            Button("Remove", role: .destructive) {
                app.removeProject(project.id)
                pendingRemoveProject = nil
            }
            Button("Cancel", role: .cancel) { pendingRemoveProject = nil }
        } message: { project in
            Text("“\(project.name)” and its \(project.sessions.count) session\(project.sessions.count == 1 ? "" : "s") will be removed from Gantry. Files on disk are untouched.")
        }
    }

    // MARK: - Top

    private var topContent: some View {
        VStack(spacing: 12) {
            HStack(spacing: 8) {
                GantryLockup(compact: true)
                Spacer()
                IconButton(
                    systemName: "square.and.pencil",
                    help: "New session (⌘N)",
                    frame: 28
                ) {
                    _ = app.newSession()
                }
                .disabled(app.projects.isEmpty)
                .opacity(app.projects.isEmpty ? 0.45 : 1)
            }
            .padding(.leading, 80)
            .padding(.trailing, 16)
            .padding(.top, 16)

            searchField
                .padding(.horizontal, 12)

            newSessionButton
                .padding(.horizontal, 12)

            SidebarDestinationButton(
                title: "Extensions & Mods",
                systemName: "puzzlepiece.extension",
                isSelected: app.mainDestination == .extensions,
                help: "Browse, install, and create extensions and mods (⇧⌘E)"
            ) {
                app.showExtensions()
            }
            .padding(.horizontal, 12)

            SidebarDestinationButton(
                title: "Graphify",
                systemName: "network",
                isSelected: app.mainDestination == .graphify,
                help: "Build and query a knowledge graph of this project"
            ) {
                app.showGraphify()
            }
            .padding(.horizontal, 12)

            HStack {
                SectionLabel(title: "Projects")
                Spacer()
                Text("\(app.projects.count)")
                    .font(Typo.micro)
                    .monospacedDigit()
                    .foregroundStyle(Palette.tertiaryInk)
                    .padding(.trailing, 4)
            }
            .padding(.horizontal, 20)
            .padding(.top, 8)
        }
        .padding(.bottom, 4)
    }

    private var searchField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(Palette.tertiaryInk)

            TextField("Search sessions", text: Binding(
                get: { app.searchText },
                set: { app.searchText = $0 }
            ))
            .textFieldStyle(.plain)
            .font(.system(size: 12))
            .foregroundStyle(Palette.ink)
            .focused($searchFocused)
            .help("Filter the sidebar. Use ⇧⌘F to search inside all conversations.")

            if !app.searchText.isEmpty {
                Button {
                    app.searchText = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 11))
                        .foregroundStyle(Palette.tertiaryInk)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(FieldBackground(radius: 8, focused: searchFocused))
        .animation(.easeOut(duration: 0.15), value: searchFocused)
    }

    private var newSessionButton: some View {
        Button {
            _ = app.newSession()
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "plus")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Palette.accent)
                    .frame(width: 16, height: 16)

                Text("New session")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Palette.ink)

                Spacer()

                Text("⌘N")
                    .font(Typo.keycap)
                    .foregroundStyle(Palette.tertiaryInk)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: Radius.control, style: .continuous)
                    .fill(isHoveringNewSession ? Palette.sidebarHover : Color.clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHoveringNewSession = $0 }
        .disabled(app.projects.isEmpty)
        .opacity(app.projects.isEmpty ? 0.45 : 1)
        .accessibilityLabel("New session")
    }

    // MARK: - Project list

    private var filteredProjects: [(project: Project, sessions: [ChatSession])] {
        let query = app.searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return app.projects.compactMap { project in
            let sessions = project.sortedSessions
            if query.isEmpty {
                return sessions.isEmpty ? nil : (project, sessions)
            }
            let projectMatches = project.name.lowercased().contains(query)
                || project.path.lowercased().contains(query)
            let matchedSessions = projectMatches ? sessions : sessions.filter { session in
                session.title.lowercased().contains(query)
                    || session.turns.contains { turn in
                        turn.role == .user && turn.textContent.lowercased().contains(query)
                    }
            }
            guard projectMatches || !matchedSessions.isEmpty else { return nil }
            return (project, projectMatches ? sessions : matchedSessions)
        }
    }

    private var projectList: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 2) {
                if app.projects.isEmpty {
                    noProjectsState
                } else if filteredProjects.isEmpty {
                    searchEmptyState
                } else {
                    ForEach(filteredProjects, id: \.project.id) { entry in
                        projectSection(entry.project, sessions: entry.sessions)
                    }
                }
            }
            .padding(.horizontal, 8)
            .padding(.top, 2)
            .padding(.bottom, 16)
        }
        .scrollIndicators(.never)
    }

    private var noProjectsState: some View {
        VStack(spacing: 8) {
            Image(systemName: "folder.badge.plus")
                .font(.system(size: 18, weight: .regular))
                .foregroundStyle(Palette.tertiaryInk)
            Text("No projects yet")
                .font(Typo.captionMedium)
                .foregroundStyle(Palette.secondaryInk)
            Button {
                app.chooseProjectFolder()
            } label: {
                Text("Open a project")
                    .font(Typo.captionMedium)
                    .foregroundStyle(Palette.accent)
            }
            .buttonStyle(.plain)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 48)
    }

    private func projectSection(_ project: Project, sessions: [ChatSession]) -> some View {
        let isCollapsed = collapsedProjects.contains(project.id)
            && app.searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let hasSelection = app.selectedProjectID == project.id

        return VStack(alignment: .leading, spacing: 1) {
            HStack(spacing: 6) {
                Button {
                    withAnimation(.easeOut(duration: 0.18)) {
                        if collapsedProjects.contains(project.id) {
                            collapsedProjects.remove(project.id)
                        } else {
                            collapsedProjects.insert(project.id)
                        }
                    }
                } label: {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(Palette.tertiaryInk)
                        .rotationEffect(.degrees(isCollapsed ? 0 : 90))
                        .frame(width: 12, height: 20)
                }
                .buttonStyle(.plain)
                .help(isCollapsed ? "Expand project" : "Collapse project")

                Button {
                    app.selectProject(project.id)
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "folder")
                            .font(.system(size: 11, weight: .regular))
                            .foregroundStyle(Palette.tertiaryInk)
                        Text(project.name)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(hasSelection ? Palette.ink : Palette.secondaryInk)
                            .lineLimit(1)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                if hoveredProjectID == project.id || app.selectedProjectID == project.id {
                    Button {
                        _ = app.newSession(in: project.id)
                    } label: {
                        Image(systemName: "plus")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(Palette.tertiaryInk)
                            .frame(width: 20, height: 20)
                            .background(
                                RoundedRectangle(cornerRadius: 5, style: .continuous)
                                    .fill(Palette.ink.opacity(0.05))
                            )
                    }
                    .buttonStyle(.plain)
                    .help("New session in \(project.name)")
                }

                Menu {
                    Button("New Session") { _ = app.newSession(in: project.id) }
                    Button("Show in Finder") {
                        NSWorkspace.shared.activateFileViewerSelecting([project.url])
                    }
                    Button("Import Claude Code Conversations…") {
                        app.transcriptImportProjectID = project.id
                    }
                    Divider()
                    Button("Remove Project…", role: .destructive) {
                        pendingRemoveProject = project
                    }
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(Palette.tertiaryInk)
                        .frame(width: 20, height: 20)
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .frame(width: 20)
                .opacity(hoveredProjectID == project.id ? 1 : 0)
            }
            .padding(.leading, 4)
            .padding(.trailing, 4)
            .frame(height: 32)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(hoveredProjectID == project.id ? Palette.sidebarHover : Color.clear)
            )
            .onHover { hovering in
                hoveredProjectID = hovering ? project.id : nil
            }
            .contextMenu {
                Button("New Session") { _ = app.newSession(in: project.id) }
                Button("Show in Finder") {
                    NSWorkspace.shared.activateFileViewerSelecting([project.url])
                }
                Button("Import Claude Code Conversations…") {
                    app.transcriptImportProjectID = project.id
                }
                Divider()
                Button("Remove Project…", role: .destructive) {
                    pendingRemoveProject = project
                }
            }

            if !isCollapsed {
                ForEach(sessions) { session in
                    sessionRow(session, project: project)
                        .transition(.opacity)
                }
            }
        }
        .padding(.bottom, 8)
    }

    private func sessionRow(_ session: ChatSession, project: Project) -> some View {
        let isSelected = app.selectedSessionID == session.id
        let activity = app.activities[session.id]
        let isHovering = hoveredSessionID == session.id

        return Button {
            app.select(sessionID: session.id)
        } label: {
            HStack(spacing: 8) {
                RoundedRectangle(cornerRadius: 1, style: .continuous)
                    .fill(Palette.accent)
                    .frame(width: 2, height: 16)
                    .opacity(isSelected ? 1 : 0)

                sessionStatus(activity: activity)
                    .frame(width: 14, alignment: .center)

                Text(session.title.isEmpty ? "New session" : session.title)
                    .font(.system(size: 13, weight: isSelected ? .medium : .regular))
                    .foregroundStyle(isSelected ? Palette.ink : Palette.secondaryInk)
                    .lineLimit(1)
                    .truncationMode(.tail)

                Spacer(minLength: 4)

                if isHovering {
                    Menu {
                        Button("Rename…") { app.beginRenamingSession(session.id) }
                        Divider()
                        Button("Delete…", role: .destructive) {
                            pendingDeleteSession = session
                        }
                    } label: {
                        Image(systemName: "ellipsis")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(Palette.tertiaryInk)
                            .frame(width: 20, height: 20)
                    }
                    .menuStyle(.borderlessButton)
                    .menuIndicator(.hidden)
                    .frame(width: 20)
                } else {
                    Text(Format.relativeTime(session.updatedAt))
                        .font(.system(size: 10, weight: .medium).monospacedDigit())
                        .foregroundStyle(Palette.tertiaryInk)
                        .lineLimit(1)
                }
            }
            .padding(.horizontal, 8)
            .frame(height: 32)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(
                        isSelected
                            ? Palette.sidebarSelection
                            : (isHovering ? Palette.sidebarHover : Color.clear)
                    )
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            hoveredSessionID = hovering ? session.id : nil
        }
        .contextMenu {
            Button("Rename…") { app.beginRenamingSession(session.id) }
            Button("Show Project in Finder") {
                NSWorkspace.shared.activateFileViewerSelecting([project.url])
            }
            Divider()
            Button("Delete Session…", role: .destructive) {
                pendingDeleteSession = session
            }
        }
    }

    @ViewBuilder
    private func sessionStatus(activity: SessionActivity?) -> some View {
        if let activity {
            if activity.hasPendingPermission {
                Image(systemName: "hand.raised.fill")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(Palette.accent)
            } else if activity.isRunning {
                LiveIndicator(color: Palette.accent, size: 12)
            } else if activity.unread {
                Circle()
                    .fill(Palette.accent)
                    .frame(width: 5, height: 5)
            } else {
                Image(systemName: "bubble.left")
                    .font(.system(size: 10, weight: .regular))
                    .foregroundStyle(Palette.tertiaryInk)
            }
        }
    }

    private var searchEmptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 18, weight: .regular))
                .foregroundStyle(Palette.tertiaryInk)
            Text("No sessions found")
                .font(Typo.captionMedium)
                .foregroundStyle(Palette.secondaryInk)
            Text("Try another search.")
                .font(Typo.micro)
                .foregroundStyle(Palette.tertiaryInk)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 48)
    }

    private var footer: some View {
        VStack(spacing: 0) {
            Hairline()
            HStack(spacing: 8) {
                SettingsLink {
                    HStack(spacing: 6) {
                        Image(systemName: "gearshape")
                            .font(.system(size: 11, weight: .medium))
                        Text("Settings")
                            .font(.system(size: 11, weight: .medium))
                    }
                    .foregroundStyle(Palette.secondaryInk)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 4)
                }
                .buttonStyle(.plain)

                Spacer()

                Button {
                    openSettings()
                } label: {
                    HStack(spacing: 6) {
                        Circle()
                            .fill(cliColor)
                            .frame(width: 5, height: 5)
                        Text(cliLabel)
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(Palette.tertiaryInk)
                            .lineLimit(1)
                    }
                    .padding(.horizontal, 6)
                    .padding(.vertical, 4)
                }
                .buttonStyle(.plain)
                .help(cliTooltip)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
        }
    }

    private var cliColor: Color {
        switch app.claudeAvailability {
        case .checking: return Palette.warning
        case .ready: return Palette.success
        case .missing, .failed: return Palette.danger
        }
    }

    private var cliLabel: String {
        switch app.claudeAvailability {
        case .checking: return "Finding CLI"
        case .ready: return "Claude Code ready"
        case .missing: return "CLI not found"
        case .failed: return "CLI error"
        }
    }

    private var cliTooltip: String {
        switch app.claudeAvailability {
        case .ready(let path, let version):
            return [path, version].compactMap { $0 }.joined(separator: "\n")
        case .missing:
            return "Claude Code wasn't found. Choose its path in Settings."
        case .checking:
            return "Looking for the Claude Code executable."
        case .failed(let message):
            return message
        }
    }
}

private struct SidebarDestinationButton: View {
    var title: String
    var systemName: String
    var isSelected: Bool
    var help: String
    var action: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                RoundedRectangle(cornerRadius: 1, style: .continuous)
                    .fill(Palette.accent)
                    .frame(width: 2, height: 16)
                    .opacity(isSelected ? 1 : 0)

                Image(systemName: systemName)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(isSelected ? Palette.ink : Palette.tertiaryInk)
                    .frame(width: 16, height: 16)

                Text(title)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(isSelected ? Palette.ink : Palette.secondaryInk)

                Spacer()
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: Radius.control, style: .continuous)
                    .fill(
                        isSelected
                            ? Palette.sidebarSelection
                            : (isHovering ? Palette.sidebarHover : Color.clear)
                    )
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
        .help(help)
        .accessibilityLabel(title)
    }
}
