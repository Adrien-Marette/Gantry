import Foundation
import GantryCore

extension AppModel {
    func setTranscriptImportPreference(_ preference: TranscriptImportPreference) {
        settings.transcriptImport = preference
        scheduleSave()
    }

    /// Opens the picker on request, from the project menu.
    func showTranscriptImport(for projectID: UUID) {
        transcriptImportOffersRemember = false
        transcriptImportProjectID = projectID
    }

    func setAutoSyncTranscripts(_ isOn: Bool, for projectID: UUID) {
        guard let index = projects.firstIndex(where: { $0.id == projectID }) else { return }
        projects[index].autoSyncTranscripts = isOn
        scheduleSave()
        if isOn { syncTranscripts(in: projectID) }
    }

    /// Transcripts of this project that no Gantry session (including Gantry's own) owns yet.
    func importableTranscriptURLs(for projectID: UUID) -> [URL] {
        guard let project = projects.first(where: { $0.id == projectID }) else { return [] }
        let known = Set(projects.flatMap(\.sessions).map(\.claudeSessionID))
        return ClaudeTranscriptImporter.transcriptURLs(forProjectPath: project.path, excluding: known)
    }

    /// Parses transcripts away from the main thread; they can be large.
    func loadImportableSessions(for projectID: UUID) async -> [ChatSession] {
        let urls = importableTranscriptURLs(for: projectID)
        let model = settings.defaultModel
        let mode = settings.defaultPermissionMode
        let providerID = defaultProviderID
        let sessions = await Task.detached {
            urls.compactMap {
                ClaudeTranscriptImporter.session(
                    fromTranscript: $0,
                    model: model,
                    permissionMode: mode,
                    providerID: providerID
                )
            }
        }.value
        return sessions.sorted { $0.updatedAt > $1.updatedAt }
    }

    /// Adds sessions to the project, skipping any imported meanwhile, and reports the count in the toast.
    func importSessions(_ sessions: [ChatSession], into projectID: UUID) {
        var imported = 0
        if let index = projects.firstIndex(where: { $0.id == projectID }) {
            let current = Set(projects.flatMap(\.sessions).map(\.claudeSessionID))
            for session in sessions where !current.contains(session.claudeSessionID) {
                projects[index].sessions.append(session)
                activities[session.id] = SessionActivity()
                imported += 1
            }
            scheduleSave()
        }
        let summary = "Imported \(imported) conversation\(imported == 1 ? "" : "s")"
        transcriptImportStatus = (summary, false)
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(3))
            // A newer import may have replaced the message meanwhile.
            if transcriptImportStatus?.text == summary {
                transcriptImportStatus = nil
            }
        }
    }

    /// A project's auto-sync wins; otherwise the remembered choice decides,
    /// and without one the import window lets the person pick.
    func offerTranscriptImport(for projectID: UUID) {
        guard let project = projects.first(where: { $0.id == projectID }) else { return }
        let preference: TranscriptImportPreference = project.autoSyncTranscripts == true
            ? .always
            : settings.transcriptImport ?? .ask
        guard preference != .never else { return }
        let urls = importableTranscriptURLs(for: projectID)
        guard !urls.isEmpty else { return }

        guard preference == .always else {
            transcriptImportOffersRemember = true
            transcriptImportProjectID = projectID
            return
        }

        transcriptImportStatus = ("Importing \(urls.count) conversation\(urls.count == 1 ? "" : "s")…", true)
        Task { @MainActor in
            importSessions(await loadImportableSessions(for: projectID), into: projectID)
        }
    }

    /// Catches up on what changed since the last launch, then lets FSEvents
    /// report new or growing transcripts while Gantry is open.
    func startTranscriptAutoSync() {
        for project in projects where project.autoSyncTranscripts == true {
            syncTranscripts(in: project.id)
        }
        let directory = ClaudeTranscriptImporter.projectsDirectory()
        transcriptWatcher = TranscriptWatcher(directory: directory) { [weak self] urls in
            MainActor.assumeIsolated {
                guard let self else { return }
                let folders = Set(urls.map { $0.deletingLastPathComponent().lastPathComponent })
                for project in self.projects where project.autoSyncTranscripts == true
                    && folders.contains(ClaudeTranscriptImporter.encodedName(forProjectPath: project.path)) {
                    self.syncTranscripts(in: project.id)
                }
            }
        }
    }

    func syncTranscripts(in projectID: UUID) {
        offerTranscriptImport(for: projectID)
        refreshImportedSessions(in: projectID)
    }

    /// A terminal chat imported while it was still going keeps growing on disk;
    /// reload it whenever its size differs from what was last read. Gantry-born sessions (id equals the
    /// Claude session ID) and running ones are left alone.
    func refreshImportedSessions(in projectID: UUID) {
        guard let project = projects.first(where: { $0.id == projectID }) else { return }
        for session in project.sessions where session.id != session.claudeSessionID
            && activities[session.id]?.isRunning != true {
            let url = ClaudeTranscriptImporter.transcriptURL(
                forProjectPath: project.path,
                sessionID: session.claudeSessionID
            )
            // Size, not date: a reply written right after the prompt must not be missed.
            guard let values = try? url.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey]),
                  let size = values.fileSize,
                  size != importedTranscriptSizes[session.id],
                  let fresh = ClaudeTranscriptImporter.session(fromTranscript: url) else { continue }
            importedTranscriptSizes[session.id] = size
            mutateSession(session.id) { current in
                current.turns = fresh.turns
                current.updatedAt = values.contentModificationDate ?? fresh.updatedAt
                current.totalCostUSD = fresh.totalCostUSD
                current.contextTokens = fresh.contextTokens
                current.contextModelName = fresh.contextModelName
                current.actualModelName = fresh.actualModelName ?? current.actualModelName
                if !current.hasCustomTitle { current.title = fresh.title }
            }
            scheduleSave()
        }
    }
}
