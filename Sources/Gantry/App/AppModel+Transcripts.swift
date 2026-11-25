import AppKit
import Foundation
import GantryCore

extension AppModel {
    func setTranscriptImportPreference(_ preference: TranscriptImportPreference) {
        settings.transcriptImport = preference
        scheduleSave()
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

    /// Offers to bring in Claude Code conversations this project already has on disk.
    func offerTranscriptImport(for projectID: UUID) {
        let preference = settings.transcriptImport ?? .ask
        guard preference != .never,
              let project = projects.first(where: { $0.id == projectID }) else { return }
        let urls = importableTranscriptURLs(for: projectID)
        guard !urls.isEmpty else { return }

        if preference == .ask {
            let alert = NSAlert()
            alert.messageText = "Import existing conversations?"
            alert.informativeText = "\(project.name) has \(urls.count) Claude Code conversation\(urls.count == 1 ? "" : "s") that Gantry has not imported. Imported sessions can be continued here."
            alert.addButton(withTitle: "Import All")
            alert.addButton(withTitle: "Not Now")
            alert.addButton(withTitle: "Choose…")
            alert.showsSuppressionButton = true
            alert.suppressionButton?.title = "Remember my choice"
            let response = alert.runModal()
            if response == .alertThirdButtonReturn {
                transcriptImportProjectID = projectID
                return
            }
            let accepted = response == .alertFirstButtonReturn
            if alert.suppressionButton?.state == .on {
                setTranscriptImportPreference(accepted ? .always : .never)
            }
            guard accepted else { return }
        }

        transcriptImportStatus = ("Importing \(urls.count) conversation\(urls.count == 1 ? "" : "s")…", true)
        Task { @MainActor in
            importSessions(await loadImportableSessions(for: projectID), into: projectID)
        }
    }
}
