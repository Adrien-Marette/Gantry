import AppKit
import Foundation
import GantryCore

extension AppModel {
    func setTranscriptImportPreference(_ preference: TranscriptImportPreference) {
        settings.transcriptImport = preference
        scheduleSave()
    }

    /// Offers to bring in Claude Code conversations this project already has on
    /// disk. Sessions Gantry already knows (including its own) are skipped.
    func offerTranscriptImport(for projectID: UUID) {
        let preference = settings.transcriptImport ?? .ask
        guard preference != .never,
              let project = projects.first(where: { $0.id == projectID }) else { return }
        let known = Set(projects.flatMap(\.sessions).map(\.claudeSessionID))
        let urls = ClaudeTranscriptImporter.transcriptURLs(forProjectPath: project.path, excluding: known)
        guard !urls.isEmpty else { return }

        if preference == .ask {
            let alert = NSAlert()
            alert.messageText = "Import existing conversations?"
            alert.informativeText = "\(project.name) has \(urls.count) Claude Code conversation\(urls.count == 1 ? "" : "s") that Gantry has not imported. Imported sessions can be continued here."
            alert.addButton(withTitle: "Import")
            alert.addButton(withTitle: "Not Now")
            alert.showsSuppressionButton = true
            alert.suppressionButton?.title = "Remember my choice"
            let accepted = alert.runModal() == .alertFirstButtonReturn
            if alert.suppressionButton?.state == .on {
                setTranscriptImportPreference(accepted ? .always : .never)
            }
            guard accepted else { return }
        }

        let model = settings.defaultModel
        let mode = settings.defaultPermissionMode
        let providerID = defaultProviderID
        transcriptImportStatus = ("Importing \(urls.count) conversation\(urls.count == 1 ? "" : "s")…", true)
        Task { @MainActor in
            // Transcripts can be large; parse them away from the main thread.
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
            try? await Task.sleep(for: .seconds(3))
            // A newer import may have replaced the message meanwhile.
            if transcriptImportStatus?.text == summary {
                transcriptImportStatus = nil
            }
        }
    }
}
