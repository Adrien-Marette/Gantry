import Foundation
import GantryCore

extension AppModel {
    // MARK: - Command catalog

    /// Starts (or reuses) the session's Claude process so its `initialize`
    /// handshake can report the commands available in this project. That
    /// handshake is the only way to see commands registered at runtime by
    /// plugins and mods, so the picker loads it on demand instead of scanning
    /// command folders.
    func loadSlashCommands(for sessionID: UUID, retry: Bool = false) {
        guard let activity = activities[sessionID],
              !activity.isLoadingSlashCommands,
              activity.slashCommands.isEmpty,
              activity.isRunning != true else { return }
        if activity.slashCommandsError != nil, !retry { return }

        guard claudeAvailability.isReady else {
            activity.slashCommandsError = claudeAvailabilityMessage
            return
        }
        guard let location = locateSession(sessionID),
              FileManager.default.fileExists(atPath: projects[location.projectIndex].path) else {
            activity.slashCommandsError = "This project folder is no longer available."
            return
        }

        if retry, activity.slashCommandsError != nil {
            // The live process already answered its initialize handshake, so
            // retrying against it cannot produce a new catalog.
            recycleRuntime(for: sessionID)
        }

        activity.isLoadingSlashCommands = true
        activity.slashCommandsError = nil
        Task { @MainActor [weak self] in
            guard let self else { return }
            defer {
                self.activities[sessionID]?.isLoadingSlashCommands = false
            }
            do {
                _ = try await self.startOrReuseRuntime(for: sessionID)
                if let activity = self.activities[sessionID],
                   activity.slashCommands.isEmpty,
                   activity.slashCommandsError == nil {
                    activity.slashCommandsError =
                        "Claude Code didn't report any commands for this project."
                }
            } catch is CancellationError {
                // A recycled runtime or a deleted session superseded this load.
            } catch {
                self.activities[sessionID]?.slashCommandsError =
                    (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            }
        }
    }

    /// Consumes the initialize payload for the session's command picker.
    func applyInitialization(_ info: ClaudeControlResponseInfo, sessionID: UUID) {
        guard let activity = activities[sessionID] else { return }
        if info.isSuccess {
            let commands = ClaudeSlashCommand.decode(fromInitializePayload: info.payload)
            if !commands.isEmpty {
                activity.slashCommands = commands
            }
            activity.slashCommandsError = nil
        }
        activity.isLoadingSlashCommands = false
    }

    /// Forgets cached catalogs after the plugin or mod set changes.
    func clearSlashCommandCatalogs(projectID: UUID? = nil) {
        for project in projects where projectID == nil || project.id == projectID {
            for session in project.sessions {
                activities[session.id]?.slashCommands = []
                activities[session.id]?.slashCommandsError = nil
                activities[session.id]?.isLoadingSlashCommands = false
            }
        }
    }

    // MARK: - Local commands

    /// Runs commands that manage Gantry's own session instead of Claude Code's
    /// transcript. `/clear` is important here: Claude Code answers it by
    /// switching to a new session ID, which would leave Gantry resuming the
    /// stale ID after the process is recycled. `/rename` would change Claude
    /// Code's metadata but leave the title shown in Gantry stale.
    func handleLocalSlashCommand(_ prompt: String, in sessionID: UUID) -> Bool {
        guard prompt.hasPrefix("/") else { return false }
        let body = prompt.dropFirst()
        let token = body.prefix { !$0.isWhitespace }
        let argument = body
            .dropFirst(token.count)
            .trimmingCharacters(in: .whitespacesAndNewlines)

        switch token.lowercased() {
        case "clear", "reset", "new":
            guard let location = locateSession(sessionID),
                  activities[sessionID]?.isRunning != true else { return false }

            // An empty chat is already in the state /clear asks for; just honor
            // an optional title instead of leaving another empty session.
            if projects[location.projectIndex].sessions[location.sessionIndex].turns.isEmpty {
                if !argument.isEmpty {
                    renameSession(sessionID, to: argument)
                }
                return true
            }

            guard let newSessionID = newSession(in: projects[location.projectIndex].id) else {
                return false
            }
            if !argument.isEmpty {
                renameSession(newSessionID, to: argument)
            }
            drafts[newSessionID] = ""
            return true

        case "rename", "name":
            guard !argument.isEmpty else { return false }
            renameSession(sessionID, to: argument)
            return true

        default:
            return false
        }
    }
}
