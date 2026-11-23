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
    @State private var isHoveringExtensions = false
    @FocusState private var searchFocused: Bool
    @State private var pendingDeleteSession: ChatSession?
    @State private var pendingRemoveProject: Project?

    var body: some View {
        ZStack {
            Palette.sidebarGradient
            Rectangle()
                .fill(.ultraThinMaterial)
                .opacity(0.30)
            LinearGradient(
                colors: [Color.white.opacity(0.07), Color.clear, Color.black.opacity(0.03)],
                startPoint: .top,
                endPoint: .bottom
            )

            VStack(spacing: 0) {
                topContent
                projectList
            }
        }
        .overlay(alignment: .trailing) { Hairline(axis: .vertical) }
        .safeAreaInset(edge: .bottom, spacing: 0) { footer }
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
                    frame: 26
                ) {
                    _ = app.newSession()
                }
                .disabled(app.projects.isEmpty)
                .opacity(app.projects.isEmpty ? 0.45 : 1)
            }
            .padding(.leading, 80)
            .padding(.trailing, 14)
            .padding(.top, 14)

            searchField
                .padding(.horizontal, 12)

            newSessionButton
                .padding(.horizontal, 12)

            extensionsButton
                .padding(.horizontal, 12)

            HStack {
                SectionLabel(title: "Projects")
                Spacer()
                Text("\(app.projects.count)")
                    .font(Typo.micro)
                    .foregroundStyle(Palette.faintInk)
                    .padding(.trailing, 4)
            }
            .padding(.horizontal, 18)
            .padding(.top, 8)
        }
        .padding(.bottom, 2)
        .background(
            LinearGradient(
                colors: [Palette.sidebarTop.opacity(0.92), Palette.sidebarTop.opacity(0.0)],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea(edges: .top)
        )
    }

    private var searchField: some View {
        HStack(spacing: 7) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(Palette.tertiaryInk)

            TextField("Search", text: Binding(
                get: { app.searchText },
                set: { app.searchText = $0 }
            ))
            .textFieldStyle(.plain)
            .font(Typo.ui)
            .foregroundStyle(Palette.ink)
            .focused($searchFocused)

            if !app.searchText.isEmpty {
                Button {
                    app.searchText = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 10.5))
                        .foregroundStyle(Palette.tertiaryInk)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Palette.ink.opacity(0.045))
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .strokeBorder(searchFocused ? Palette.accent.opacity(0.35) : Palette.line, lineWidth: 0.7)
                )
        )
        .animation(.easeOut(duration: 0.15), value: searchFocused)
    }

    private var newSessionButton: some View {
        Button {
            _ = app.newSession()
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "plus")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Palette.accent)
                    .frame(width: 17, height: 17)
                    .background(Circle().fill(Palette.accent.opacity(0.12)))

                Text("New session")
                    .font(Typo.ui)
                    .foregroundStyle(Palette.ink)

                Spacer()

                Text("⌘N")
                    .font(Typo.micro)
                    .foregroundStyle(isHoveringNewSession ? Palette.secondaryInk : Palette.tertiaryInk)
            }
            .padding(.horizontal, 9)
            .padding(.vertical, 7)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Palette.accent.opacity(isHoveringNewSession ? 0.11 : 0.07))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .strokeBorder(Palette.accent.opacity(isHoveringNewSession ? 0.28 : 0.15), lineWidth: 0.7)
                    )
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHoveringNewSession = $0 }
        .disabled(app.projects.isEmpty)
        .opacity(app.projects.isEmpty ? 0.45 : 1)
        .accessibilityLabel("New session")
    }

    private var extensionsButton: some View {
        let isSelected = app.mainDestination == .extensions

        return Button {
            app.showExtensions()
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "puzzlepiece.extension")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(isSelected ? Palette.accent : Palette.tertiaryInk)
                    .frame(width: 17, height: 17)
                    .background(
                        Circle().fill(
                            (isSelected ? Palette.accent : Palette.tertiaryInk).opacity(0.10)
                        )
                    )

                Text("Extensions & Mods")
                    .font(Typo.ui)
                    .foregroundStyle(isSelected ? Palette.ink : Palette.secondaryInk)

                Spacer()

                if isSelected {
                    Circle()
                        .fill(Palette.accent)
                        .frame(width: 5, height: 5)
                }
            }
            .padding(.horizontal, 9)
            .padding(.vertical, 7)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(
                        isSelected
                            ? Palette.sidebarSelection
                            : (isHoveringExtensions ? Palette.sidebarHover : Color.clear)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .strokeBorder(isSelected ? Palette.lineStrong : Color.clear, lineWidth: 0.7)
                    )
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHoveringExtensions = $0 }
        .help("Browse, install, and create extensions and mods (⇧⌘E)")
        .accessibilityLabel("Extensions & Mods")
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
                .font(.system(size: 18, weight: .light))
                .foregroundStyle(Palette.faintInk)
            Text("No projects yet")
                .font(Typo.captionMedium)
                .foregroundStyle(Palette.secondaryInk)
            Button {
                app.chooseProjectFolder()
            } label: {
                Text("Open a Project")
                    .font(Typo.micro)
                    .foregroundStyle(Palette.accent)
            }
            .buttonStyle(.plain)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 44)
    }

    private func projectSection(_ project: Project, sessions: [ChatSession]) -> some View {
        let isCollapsed = collapsedProjects.contains(project.id)
            && app.searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let hasSelection = app.selectedProjectID == project.id

        return VStack(alignment: .leading, spacing: 1) {
            HStack(spacing: 6) {
                Button {
                    withAnimation(.smooth(duration: 0.18)) {
                        if collapsedProjects.contains(project.id) {
                            collapsedProjects.remove(project.id)
                        } else {
                            collapsedProjects.insert(project.id)
                        }
                    }
                } label: {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 8, weight: .semibold))
                        .foregroundStyle(Palette.faintInk)
                        .rotationEffect(.degrees(isCollapsed ? 0 : 90))
                        .frame(width: 12, height: 18)
                }
                .buttonStyle(.plain)
                .help(isCollapsed ? "Expand project" : "Collapse project")

                Button {
                    app.selectProject(project.id)
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "folder.fill")
                            .font(.system(size: 10.5, weight: .regular))
                            .foregroundStyle(hasSelection ? Palette.accent : Palette.tertiaryInk)
                        Text(project.name)
                            .font(Typo.captionMedium)
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
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(Palette.tertiaryInk)
                            .frame(width: 18, height: 18)
                            .background(
                                RoundedRectangle(cornerRadius: 5, style: .continuous)
                                    .fill(Palette.ink.opacity(0.045))
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
                    Divider()
                    Button("Remove Project…", role: .destructive) {
                        pendingRemoveProject = project
                    }
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(Palette.tertiaryInk)
                        .frame(width: 18, height: 18)
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .frame(width: 18)
                .opacity(hoveredProjectID == project.id ? 1 : 0)
            }
            .padding(.leading, 4)
            .padding(.trailing, 4)
            .frame(height: 27)
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
                Divider()
                Button("Remove Project…", role: .destructive) {
                    pendingRemoveProject = project
                }
            }

            if !isCollapsed {
                ForEach(sessions) { session in
                    sessionRow(session, project: project)
                        .transition(.opacity.combined(with: .move(edge: .top)))
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
            HStack(spacing: 7) {
                sessionStatus(activity: activity)
                    .frame(width: 12, alignment: .center)

                Text(session.title.isEmpty ? "New session" : session.title)
                    .font(.system(size: 12.5, weight: isSelected ? .medium : .regular))
                    .foregroundStyle(isSelected ? Palette.ink : Palette.secondaryInk)
                    .lineLimit(1)
                    .truncationMode(.tail)

                Spacer(minLength: 2)

                if isHovering {
                    Menu {
                        Button("Rename…") { app.beginRenamingSession(session.id) }
                        Divider()
                        Button("Delete…", role: .destructive) {
                            pendingDeleteSession = session
                        }
                    } label: {
                        Image(systemName: "ellipsis")
                            .font(.system(size: 9.5, weight: .semibold))
                            .foregroundStyle(Palette.tertiaryInk)
                            .frame(width: 18, height: 18)
                    }
                    .menuStyle(.borderlessButton)
                    .menuIndicator(.hidden)
                    .frame(width: 18)
                } else {
                    Text(Format.relativeTime(session.updatedAt))
                        .font(.system(size: 9.5, weight: .medium, design: .rounded))
                        .foregroundStyle(Palette.faintInk)
                        .lineLimit(1)
                        .padding(.trailing, 2)
                }
            }
            .padding(.leading, 18)
            .padding(.trailing, 7)
            .padding(.vertical, 5.5)
            .background(
                RoundedRectangle(cornerRadius: 7.5, style: .continuous)
                    .fill(
                        isSelected
                            ? Palette.sidebarSelection
                            : (isHovering ? Palette.sidebarHover : Color.clear)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 7.5, style: .continuous)
                            .strokeBorder(isSelected ? Palette.lineStrong : Color.clear, lineWidth: 0.7)
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
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(Palette.accent)
            } else if activity.isRunning {
                ActivityDots(color: Palette.accent, size: 2.4)
            } else if activity.unread {
                Circle()
                    .fill(Palette.accent)
                    .frame(width: 5, height: 5)
            } else {
                Image(systemName: "bubble.left")
                    .font(.system(size: 9, weight: .regular))
                    .foregroundStyle(Palette.faintInk)
                    .opacity(0.65)
            }
        }
    }

    private var searchEmptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 18, weight: .light))
                .foregroundStyle(Palette.faintInk)
            Text("No sessions found")
                .font(Typo.captionMedium)
                .foregroundStyle(Palette.secondaryInk)
            Text("Try another search.")
                .font(Typo.micro)
                .foregroundStyle(Palette.tertiaryInk)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 44)
    }

    private var footer: some View {
        VStack(spacing: 0) {
            Hairline()
            HStack(spacing: 7) {
                SettingsLink {
                    HStack(spacing: 6) {
                        Image(systemName: "gearshape")
                            .font(.system(size: 11, weight: .medium))
                        Text("Settings")
                            .font(Typo.micro)
                    }
                    .foregroundStyle(Palette.secondaryInk)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 5)
                }
                .buttonStyle(.plain)

                Spacer()

                Button {
                    openSettings()
                } label: {
                    HStack(spacing: 5) {
                        Circle()
                            .fill(cliColor)
                            .frame(width: 5, height: 5)
                        Text(cliLabel)
                            .font(Typo.micro)
                            .foregroundStyle(Palette.tertiaryInk)
                            .lineLimit(1)
                    }
                    .padding(.horizontal, 6)
                    .padding(.vertical, 4)
                    .background(
                        Capsule(style: .continuous)
                            .fill(Palette.ink.opacity(0.035))
                    )
                }
                .buttonStyle(.plain)
                .help(cliTooltip)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
        }
        .background(Palette.sidebarBottom.opacity(0.90))
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

