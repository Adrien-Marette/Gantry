import AppKit
import Foundation
import Observation
import SwiftUI
import GantryCore

@MainActor
@Observable
final class SessionActivity {
    var isRunning = false
    var isStopping = false
    var statusText: String?
    var preview = StreamPreview()
    var pendingPermissions: [ClaudePermissionRequest] = []
    var unread = false
    var banner: String?
    /// Slash commands reported by this session's Claude Code process. The
    /// catalog is per session because project and dev-mod commands depend on
    /// the session's working directory.
    var slashCommands: [ClaudeSlashCommand] = []
    var isLoadingSlashCommands = false
    var slashCommandsError: String?
    var lastStderr: String = ""

    var hasPendingPermission: Bool { !pendingPermissions.isEmpty }

    func resetForSend() {
        isRunning = true
        isStopping = false
        statusText = "Starting Claude Code"
        preview = StreamPreview()
        pendingPermissions = []
        banner = nil
        unread = false
    }

    func resetIdle() {
        isRunning = false
        isStopping = false
        statusText = nil
        preview = StreamPreview()
        pendingPermissions = []
    }
}

struct StreamPreview: Hashable, Sendable {
    var text = ""
    var thinking = ""
    var toolName: String?

    var isEmpty: Bool {
        text.isEmpty && thinking.isEmpty && toolName == nil
    }

    mutating func clear() {
        text = ""
        thinking = ""
        toolName = nil
    }
}

/// A request to reveal one turn after a search result selects its session.
struct PendingTurnScroll: Equatable {
    var sessionID: UUID
    var turnID: UUID
}

enum ClaudeAvailability: Equatable {
    case checking
    case ready(path: String, version: String?)
    case missing
    case failed(String)

    var isReady: Bool {
        if case .ready = self { return true }
        return false
    }

    var path: String? {
        if case .ready(let path, _) = self { return path }
        return nil
    }
}

enum MainDestination: Hashable {
    case workspace
    case extensions
    case graphify
}

/// One pending permission or question, paired with its session for the menu
/// bar and any other global surface.
struct PendingPermissionItem: Identifiable {
    var project: Project
    var session: ChatSession
    var request: ClaudePermissionRequest

    var id: String {
        "\(session.id.uuidString)-\(request.requestID)"
    }
}

/// A session with live activity state, used by the menu bar.
struct SessionActivityItem: Identifiable {
    var project: Project
    var session: ChatSession
    var activity: SessionActivity

    var id: UUID { session.id }
}

@MainActor
@Observable
final class AppModel {
    static let appVersion = "0.4.1"

    var projects: [Project]
    var selectedProjectID: UUID?
    var selectedSessionID: UUID?
    var settings: AppSettings
    var activities: [UUID: SessionActivity]
    var claudeAvailability: ClaudeAvailability = .checking
    var loadError: String?
    /// Progress of a Claude Code history import; `isWorking` shows the spinner.
    var transcriptImportStatus: (text: String, isWorking: Bool)?
    /// Project whose import picker is open.
    var transcriptImportProjectID: UUID?
    /// True when the picker opened because a project was opened, the only case
    /// where remembering the answer makes sense.
    var transcriptImportOffersRemember = false
    var commandPalettePresented = false
    var reviewRequested = false
    var searchRequested = false
    var pendingTurnScroll: PendingTurnScroll?
    var mainDestination: MainDestination = .workspace
    var searchText = ""
    var isAppTerminating = false
    var showInspector: Bool
    var renamingSessionID: UUID?
    var drafts: [UUID: String] = [:]
    /// Files and folders staged for the next prompt, per session. Transient,
    /// like drafts; attachments are prompt context, not persisted state.
    var attachments: [UUID: [PromptAttachment]] = [:]
    var providers: [AIProvider]
    var defaultProviderID: UUID
    var plugins: [PluginConnection]
    var requestedSettingsTab: String?
    var providerKeyRevision = 0

    @ObservationIgnored let dataStore: AppDataStore
    @ObservationIgnored var runtimes: [UUID: ClaudeRuntime] = [:]
    @ObservationIgnored var runtimeStarts: [UUID: Task<ClaudeRuntime, Error>] = [:]
    @ObservationIgnored var runtimeTasks: [UUID: Task<Void, Never>] = [:]
    @ObservationIgnored var activeTurnIDs: [UUID: UUID] = [:]
    @ObservationIgnored var processedBlockSignatures: [UUID: Set<String>] = [:]
    @ObservationIgnored var previewBuffers: [UUID: StreamPreview] = [:]
    @ObservationIgnored var previewFlushTasks: [UUID: Task<Void, Never>] = [:]
    @ObservationIgnored var forceStopTasks: [UUID: Task<Void, Never>] = [:]
    @ObservationIgnored var turnStartCosts: [UUID: Double] = [:]
    @ObservationIgnored var turnStartModelUsage: [UUID: [String: ModelTokenUsage]] = [:]
    @ObservationIgnored var saveTask: Task<Void, Never>?
    @ObservationIgnored var terminationObserver: NSObjectProtocol?
    @ObservationIgnored var staleProviderSessions: Set<UUID> = []
    @ObservationIgnored var staleRuntimeSessions: Set<UUID> = []
    @ObservationIgnored var pluginToolBridges: [UUID: PluginToolBridge] = [:]
    @ObservationIgnored var pluginToolConfigURLs: [UUID: URL] = [:]
    @ObservationIgnored var started = false

    init(dataStore: AppDataStore = AppDataStore()) {
        self.dataStore = dataStore
        var snapshot = AppSnapshot()
        var loadErrorText: String?
        do {
            if let loaded = try dataStore.load() {
                snapshot = loaded
            }
        } catch {
            if let backup = dataStore.quarantineUnreadableState() {
                loadErrorText = "Your saved sessions could not be loaded. A recoverable copy was saved at \(backup.lastPathComponent)."
            } else {
                loadErrorText = "Your saved sessions could not be loaded: \(error.localizedDescription)"
            }
        }

        // A process cannot survive an app launch, so no turn is genuinely streaming.
        for projectIndex in snapshot.projects.indices {
            for sessionIndex in snapshot.projects[projectIndex].sessions.indices {
                snapshot.projects[projectIndex].sessions[sessionIndex].turns.indices.forEach { turnIndex in
                    snapshot.projects[projectIndex].sessions[sessionIndex].turns[turnIndex].isStreaming = false
                }
            }
        }

        var loadedProviders = snapshot.settings.providers ?? []
        loadedProviders.removeAll { $0.isBuiltIn || $0.id == AIProvider.claudeCodeID }
        loadedProviders.insert(.claudeCodeDefault, at: 0)
        for index in loadedProviders.indices where !loadedProviders[index].isBuiltIn {
            if loadedProviders[index].keychainServer.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                loadedProviders[index].keychainServer = AIProvider.host(from: loadedProviders[index].baseURL) ?? "Gantry.local"
            }
            if loadedProviders[index].keychainAccount.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                loadedProviders[index].keychainAccount = "Gantry · \(loadedProviders[index].name)"
            }
        }
        let providerIDs = Set(loadedProviders.map(\.id))
        let resolvedDefaultProviderID: UUID = {
            if let stored = snapshot.settings.defaultProviderID, providerIDs.contains(stored) {
                return stored
            }
            return AIProvider.claudeCodeID
        }()
        for projectIndex in snapshot.projects.indices {
            for sessionIndex in snapshot.projects[projectIndex].sessions.indices {
                let currentID = snapshot.projects[projectIndex].sessions[sessionIndex].providerID
                if currentID == nil || !providerIDs.contains(currentID!) {
                    snapshot.projects[projectIndex].sessions[sessionIndex].providerID = resolvedDefaultProviderID
                }
            }
        }

        var seenPluginIDs = Set<UUID>()
        var loadedPlugins = (snapshot.settings.plugins ?? []).filter {
            seenPluginIDs.insert($0.id).inserted
        }
        for index in loadedPlugins.indices {
            if loadedPlugins[index].keychainServer.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                loadedPlugins[index].keychainServer = URL(string: loadedPlugins[index].serverURL)?.host ?? "Gantry.local"
            }
            if loadedPlugins[index].keychainAccount.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                let account = loadedPlugins[index].accountName.isEmpty
                    ? loadedPlugins[index].name
                    : loadedPlugins[index].accountName
                loadedPlugins[index].keychainAccount =
                    "Gantry Plugins · \(loadedPlugins[index].kind.title) · \(account) · \(loadedPlugins[index].id.uuidString.prefix(8))"
            }
        }
        let pluginIDs = Set(loadedPlugins.map(\.id))
        for projectIndex in snapshot.projects.indices {
            if let pluginID = snapshot.projects[projectIndex].pluginID,
               !pluginIDs.contains(pluginID) {
                snapshot.projects[projectIndex].pluginID = nil
            }
        }

        snapshot.settings.favoriteMarketplaces =
            Self.normalizedFavoriteMarketplaces(snapshot.settings.favoriteMarketplaces)
        // Keep the stored path byte-for-byte; only drop an empty setting, so a
        // folder whose name begins or ends with a space still resolves.
        snapshot.settings.modsDirectory = snapshot.settings.modsDirectory.flatMap {
            $0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : $0
        }

        self.projects = snapshot.projects
        self.settings = snapshot.settings
        self.providers = loadedProviders
        self.defaultProviderID = resolvedDefaultProviderID
        self.plugins = loadedPlugins
        self.showInspector = snapshot.settings.showsInspector
        self.selectedProjectID = snapshot.selectedProjectID
        self.selectedSessionID = snapshot.selectedSessionID
        self.activities = [:]
        self.loadError = loadErrorText

        for project in projects {
            for session in project.sessions {
                activities[session.id] = SessionActivity()
            }
        }

        normalizeSelection(preferredProjectID: snapshot.selectedProjectID, preferredSessionID: snapshot.selectedSessionID)

        terminationObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.willTerminateNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.shutdown()
            }
        }
    }

    deinit {
        if let terminationObserver {
            NotificationCenter.default.removeObserver(terminationObserver)
        }
    }

    // MARK: - Lifecycle

    func start() {
        guard !started else { return }
        started = true
        resolveClaude()
        startTranscriptAutoSync()
    }

    func shutdown() {
        guard !isAppTerminating else { return }
        isAppTerminating = true
        activeTurnIDs.forEach { sessionID, turnID in
            finishTurn(
                sessionID: sessionID,
                turnID: turnID,
                result: nil,
                error: nil,
                stopReason: "App closed",
                wasStopped: true,
                persist: false
            )
        }
        runtimeStarts.values.forEach { $0.cancel() }
        runtimeStarts.removeAll()
        runtimeTasks.values.forEach { $0.cancel() }
        runtimeTasks.removeAll()
        runtimes.values.forEach { $0.terminate() }
        runtimes.removeAll()
        stopAllPluginToolBridges()
        staleRuntimeSessions.removeAll()
        saveNow()
    }

    func resolveClaude() {
        claudeAvailability = .checking
        let override = settings.claudePathOverride
        Task { [weak self] in
            let result: (ClaudeAvailability, String) = await Task.detached(priority: .userInitiated) {
                guard let url = ClaudeLocator.locate(override: override) else {
                    return (.missing, "")
                }
                let version = ClaudeLocator.version(at: url)
                return (.ready(path: url.path, version: version), url.path)
            }.value
            guard let self, !self.isAppTerminating else { return }
            self.claudeAvailability = result.0
            if case .failed(let message) = result.0 {
                self.loadError = message
            } else if result.0.isReady, self.loadError?.contains("Claude Code") == true {
                self.loadError = nil
            }
        }
    }

    func setClaudePathOverride(_ path: String?) {
        settings.claudePathOverride = path?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
        scheduleSave()
        resolveClaude()
    }

    // MARK: - Derived values

    var selectedProject: Project? {
        guard let selectedProjectID else { return nil }
        return projects.first { $0.id == selectedProjectID }
    }

    var selectedSession: ChatSession? {
        guard let selectedSessionID else { return nil }
        return projects.lazy.flatMap(\.sessions).first { $0.id == selectedSessionID }
    }

    var selectedActivity: SessionActivity? {
        guard let selectedSessionID else { return nil }
        return activities[selectedSessionID]
    }

    /// True when the person is looking at the main window, so a turn that
    /// finishes in the selected session does not need an unread marker.
    var isMainWindowFocused: Bool {
        NSApp.isActive && NSApp.keyWindow?.title == "Gantry"
    }

    var selectedProjectLocation: (projectIndex: Int, sessionIndex: Int)? {
        guard let selectedSessionID else { return nil }
        for (projectIndex, project) in projects.enumerated() {
            if let sessionIndex = project.sessions.firstIndex(where: { $0.id == selectedSessionID }) {
                return (projectIndex, sessionIndex)
            }
        }
        return nil
    }

    /// Pending permission and question requests across every session, newest
    /// session first. The menu bar uses this when the main window is closed.
    var pendingPermissionItems: [PendingPermissionItem] {
        projects.flatMap { project in
            project.sessions.flatMap { session in
                (activities[session.id]?.pendingPermissions ?? []).map { request in
                    PendingPermissionItem(
                        project: project,
                        session: session,
                        request: request
                    )
                }
            }
        }
        .sorted { $0.session.updatedAt > $1.session.updatedAt }
    }

    var pendingPermissionCount: Int {
        pendingPermissionItems.count
    }

    var activeSessionItems: [SessionActivityItem] {
        projects.flatMap { project in
            project.sessions.compactMap { session in
                guard let activity = activities[session.id],
                      activity.isRunning,
                      activity.pendingPermissions.isEmpty else {
                    return nil
                }
                return SessionActivityItem(
                    project: project,
                    session: session,
                    activity: activity
                )
            }
        }
        .sorted { $0.session.updatedAt > $1.session.updatedAt }
    }

    var runningSessionCount: Int {
        activeSessionItems.count
    }

    /// Sessions that finished while you were elsewhere. Limited by the caller.
    var finishedSessionItems: [SessionActivityItem] {
        projects.flatMap { project in
            project.sessions.compactMap { session in
                guard let activity = activities[session.id],
                      activity.unread,
                      !activity.isRunning,
                      activity.pendingPermissions.isEmpty else {
                    return nil
                }
                return SessionActivityItem(
                    project: project,
                    session: session,
                    activity: activity
                )
            }
        }
        .sorted { $0.session.updatedAt > $1.session.updatedAt }
    }

    var finishedSessionCount: Int {
        finishedSessionItems.count
    }

    func activity(for sessionID: UUID) -> SessionActivity {
        if let activity = activities[sessionID] { return activity }
        let activity = SessionActivity()
        activities[sessionID] = activity
        return activity
    }

    func project(for sessionID: UUID) -> Project? {
        projects.first { project in
            project.sessions.contains { $0.id == sessionID }
        }
    }

    func session(withID sessionID: UUID) -> ChatSession? {
        projects.lazy.flatMap(\.sessions).first { $0.id == sessionID }
    }

    func locateSession(_ sessionID: UUID) -> (projectIndex: Int, sessionIndex: Int)? {
        for (projectIndex, project) in projects.enumerated() {
            if let sessionIndex = project.sessions.firstIndex(where: { $0.id == sessionID }) {
                return (projectIndex, sessionIndex)
            }
        }
        return nil
    }

    func mutateSession(_ sessionID: UUID, _ transform: (inout ChatSession) -> Void) {
        guard let location = locateSession(sessionID) else { return }
        transform(&projects[location.projectIndex].sessions[location.sessionIndex])
    }

    var inspectorVisible: Bool {
        get { showInspector }
        set {
            showInspector = newValue
            settings.showsInspector = newValue
            scheduleSave()
        }
    }

    var appearance: AppearanceMode {
        settings.appearance ?? .system
    }

    func setAppearance(_ mode: AppearanceMode) {
        guard appearance != mode else { return }
        settings.appearance = mode
        scheduleSave()
    }

    // MARK: - Projects & sessions

    func chooseProjectFolder() {
        let panel = NSOpenPanel()
        panel.title = "Choose a project"
        panel.prompt = "Open Project"
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = true
        panel.begin { [weak self] response in
            guard response == .OK, let url = panel.url else { return }
            Task { @MainActor in
                self?.addProject(at: url)
            }
        }
    }

    @discardableResult
    func addProject(at url: URL) -> UUID? {
        let normalized = url.resolvingSymlinksInPath().standardizedFileURL
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: normalized.path, isDirectory: &isDirectory),
              isDirectory.boolValue else {
            loadError = "That folder could not be opened."
            return nil
        }

        if let existing = projects.first(where: { $0.path == normalized.path }) {
            offerTranscriptImport(for: existing.id)
            if let sessionID = existing.sortedSessions.first?.id {
                select(sessionID: sessionID)
                return sessionID
            }
            return newSession(in: existing.id)
        }

        var project = Project(
            path: normalized.path,
            name: normalized.lastPathComponent.isEmpty ? "Project" : normalized.lastPathComponent
        )
        let session = makeSession()
        project.sessions = [session]
        projects.insert(project, at: 0)
        activities[session.id] = SessionActivity()
        select(sessionID: session.id)
        scheduleSave()
        offerTranscriptImport(for: project.id)
        return session.id
    }

    @discardableResult
    func newSession(in projectID: UUID? = nil) -> UUID? {
        let targetProjectID = projectID ?? selectedProjectID ?? projects.first?.id
        guard let targetProjectID,
              let projectIndex = projects.firstIndex(where: { $0.id == targetProjectID }) else {
            return nil
        }
        let session = makeSession()
        projects[projectIndex].sessions.append(session)
        projects[projectIndex].lastOpenedAt = .now
        activities[session.id] = SessionActivity()
        select(sessionID: session.id)
        scheduleSave()
        return session.id
    }

    private func makeSession() -> ChatSession {
        ChatSession(
            model: settings.defaultModel,
            permissionMode: settings.defaultPermissionMode,
            providerID: defaultProviderID
        )
    }

    func select(sessionID: UUID) {
        guard let location = locateSession(sessionID) else { return }
        selectedSessionID = sessionID
        selectedProjectID = projects[location.projectIndex].id
        projects[location.projectIndex].lastOpenedAt = .now
        activities[sessionID]?.unread = false
        commandPalettePresented = false
        mainDestination = .workspace
        scheduleSave()
    }

    func selectProject(_ projectID: UUID) {
        guard let project = projects.first(where: { $0.id == projectID }) else { return }
        if let session = project.sortedSessions.first {
            select(sessionID: session.id)
        } else {
            selectedProjectID = projectID
            selectedSessionID = nil
            mainDestination = .workspace
            scheduleSave()
        }
    }

    func renameSession(_ sessionID: UUID, to newTitle: String) {
        let trimmed = newTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        mutateSession(sessionID) { session in
            session.title = String(trimmed.prefix(80))
            session.hasCustomTitle = true
            session.updatedAt = .now
        }
        scheduleSave()
    }

    func deleteSession(_ sessionID: UUID) {
        guard let location = locateSession(sessionID) else { return }
        stop(sessionID: sessionID, silently: true)
        runtimeStarts.removeValue(forKey: sessionID)?.cancel()
        runtimeTasks[sessionID]?.cancel()
        runtimeTasks.removeValue(forKey: sessionID)
        runtimes.removeValue(forKey: sessionID)?.terminate()
        stopPluginToolBridge(for: sessionID)
        staleRuntimeSessions.remove(sessionID)
        activities.removeValue(forKey: sessionID)
        previewBuffers.removeValue(forKey: sessionID)
        previewFlushTasks.removeValue(forKey: sessionID)?.cancel()
        activeTurnIDs.removeValue(forKey: sessionID)
        processedBlockSignatures.removeValue(forKey: sessionID)

        let project = projects[location.projectIndex]
        let remaining = project.sessions.filter { $0.id != sessionID }
        projects[location.projectIndex].sessions = remaining
        if selectedSessionID == sessionID {
            selectedSessionID = nil
            if let next = remaining.sorted(by: { $0.updatedAt > $1.updatedAt }).first {
                select(sessionID: next.id)
            } else {
                selectedProjectID = project.id
            }
        }
        scheduleSave()
    }

    func removeProject(_ projectID: UUID) {
        guard let projectIndex = projects.firstIndex(where: { $0.id == projectID }) else { return }
        let sessionIDs = projects[projectIndex].sessions.map(\.id)
        for sessionID in sessionIDs {
            stop(sessionID: sessionID, silently: true)
            runtimeStarts.removeValue(forKey: sessionID)?.cancel()
            runtimeTasks[sessionID]?.cancel()
            runtimeTasks.removeValue(forKey: sessionID)
            runtimes.removeValue(forKey: sessionID)?.terminate()
            stopPluginToolBridge(for: sessionID)
            staleRuntimeSessions.remove(sessionID)
            activities.removeValue(forKey: sessionID)
            previewBuffers.removeValue(forKey: sessionID)
            previewFlushTasks.removeValue(forKey: sessionID)?.cancel()
            activeTurnIDs.removeValue(forKey: sessionID)
            processedBlockSignatures.removeValue(forKey: sessionID)
        }
        projects.remove(at: projectIndex)
        if selectedProjectID == projectID {
            selectedSessionID = nil
            selectedProjectID = projects.first?.id
            if let firstSession = projects.first?.sortedSessions.first {
                selectedSessionID = firstSession.id
            }
        }
        scheduleSave()
    }

    func revealProjectInFinder() {
        guard let project = selectedProject else { return }
        NSWorkspace.shared.activateFileViewerSelecting([project.url])
    }

    func setModel(_ model: ModelChoice, for sessionID: UUID) {
        mutateSession(sessionID) { $0.model = model }
        if runtimes[sessionID] != nil {
            do {
                try runtimes[sessionID]?.setModel(model)
            } catch {
                activities[sessionID]?.banner = "The model will change on the next message."
            }
        }
        scheduleSave()
    }

    func setPermissionMode(_ mode: PermissionMode, for sessionID: UUID) {
        mutateSession(sessionID) { $0.permissionMode = mode }
        if let runtime = runtimes[sessionID] {
            do {
                try runtime.setPermissionMode(mode)
            } catch {
                activities[sessionID]?.banner = "The permission mode will change on the next message."
            }
        }
        scheduleSave()
    }

    func beginRenamingSession(_ sessionID: UUID) {
        renamingSessionID = sessionID
    }

    func setDefaultModel(_ model: ModelChoice) {
        settings.defaultModel = model
        scheduleSave()
    }

    func setDefaultPermissionMode(_ mode: PermissionMode) {
        settings.defaultPermissionMode = mode
        scheduleSave()
    }

    func markSettingsChanged() {
        scheduleSave()
    }

    // MARK: - Persistence

    func currentSnapshot() -> AppSnapshot {
        var persistedSettings = settings
        persistedSettings.providers = providers
        persistedSettings.defaultProviderID = defaultProviderID
        persistedSettings.plugins = plugins
        persistedSettings.showsInspector = showInspector
        return AppSnapshot(
            version: 2,
            projects: projects,
            selectedProjectID: selectedProjectID,
            selectedSessionID: selectedSessionID,
            settings: persistedSettings
        )
    }

    func scheduleSave() {
        guard !isAppTerminating else { return }
        let snapshot = currentSnapshot()
        let previous = saveTask
        previous?.cancel()
        saveTask = Task { [dataStore] in
            // Keep writes serial so an older snapshot can never land after a newer one.
            await previous?.value
            try? await Task.sleep(for: .milliseconds(350))
            guard !Task.isCancelled else { return }
            do {
                try await Task.detached(priority: .utility) {
                    try dataStore.save(snapshot)
                }.value
            } catch {
                // The next save gets another chance. The UI keeps working in memory.
            }
        }
    }

    func saveNow() {
        try? dataStore.save(currentSnapshot())
    }

    // MARK: - Selection repair

    private func normalizeSelection(preferredProjectID: UUID?, preferredSessionID: UUID?) {
        if let preferredSessionID,
           let location = locateSession(preferredSessionID) {
            selectedProjectID = projects[location.projectIndex].id
            selectedSessionID = preferredSessionID
            return
        }
        if let preferredProjectID,
           let project = projects.first(where: { $0.id == preferredProjectID }) {
            selectedProjectID = project.id
            selectedSessionID = project.sortedSessions.first?.id
            return
        }
        if let project = projects.sorted(by: { $0.lastOpenedAt > $1.lastOpenedAt }).first {
            selectedProjectID = project.id
            selectedSessionID = project.sortedSessions.first?.id
        }
    }
}

struct AppCommands: Commands {
    let app: AppModel

    var body: some Commands {
        CommandGroup(replacing: .newItem) {
            Button("New Session") {
                _ = app.newSession()
            }
            .keyboardShortcut("n", modifiers: .command)
            .disabled(app.projects.isEmpty)

            Button("Open Project…") {
                app.chooseProjectFolder()
            }
            .keyboardShortcut("o", modifiers: .command)
        }

        CommandGroup(after: .sidebar) {
            Button("Open Gantry") {
                NotificationCenter.default.post(name: .gantryShowMainWindow, object: nil)
            }
            .keyboardShortcut("0", modifiers: .command)

            Button("Command Palette…") {
                app.commandPalettePresented = true
            }
            .keyboardShortcut("k", modifiers: .command)

            Button("Toggle Inspector") {
                app.inspectorVisible.toggle()
            }
            .keyboardShortcut("i", modifiers: [.command, .shift])
            .disabled(app.selectedSessionID == nil)

            Button("Review Changes…") {
                app.mainDestination = .workspace
                app.reviewRequested = true
            }
            .keyboardShortcut("r", modifiers: [.command, .shift])
            .disabled(app.selectedSession?.changedFilePaths.isEmpty ?? true)

            Button("Find in Conversations…") {
                app.searchRequested = true
            }
            .keyboardShortcut("f", modifiers: [.command, .shift])

            Button("Extensions & Mods") {
                app.showExtensions()
            }
            .keyboardShortcut("e", modifiers: [.command, .shift])
        }

        CommandMenu("Conversation") {
            Button("Stop") {
                if let sessionID = app.selectedSessionID {
                    app.stop(sessionID: sessionID)
                }
            }
            .keyboardShortcut(".", modifiers: .command)
            .disabled(app.selectedActivity?.isRunning != true)

            Button("Rename Session…") {
                if let sessionID = app.selectedSessionID {
                    app.beginRenamingSession(sessionID)
                }
            }
            .disabled(app.selectedSessionID == nil)

            Divider()

            Button("Reveal Project in Finder") {
                app.revealProjectInFinder()
            }
            .disabled(app.selectedProject == nil)
        }
    }
}

extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}
