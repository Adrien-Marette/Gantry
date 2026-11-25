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
        if isOn { offerTranscriptImport(for: projectID) }
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

    /// Picks up conversations started in the terminal since the last launch.
    func syncTranscriptsAtLaunch() {
        for project in projects where project.autoSyncTranscripts == true {
            offerTranscriptImport(for: project.id)
        }
    }
}
