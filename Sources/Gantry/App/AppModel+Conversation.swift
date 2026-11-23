import Foundation
import GantryCore

enum PermissionAction {
    case allowOnce
    case allowAlways
    case deny
}

extension AppModel {
    // MARK: - Sending

    @discardableResult
    func send(_ rawPrompt: String, in sessionID: UUID) -> Bool {
        guard !isAppTerminating else { return false }
        let prompt = rawPrompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !prompt.isEmpty else { return false }
        guard let location = locateSession(sessionID) else { return false }
        guard activities[sessionID]?.isRunning != true else { return false }

        guard claudeAvailability.isReady else {
            activities[sessionID]?.banner = claudeAvailabilityMessage
            return false
        }
        guard FileManager.default.fileExists(atPath: projects[location.projectIndex].path) else {
            activities[sessionID]?.banner = "This project folder is no longer available."
            return false
        }

        var session = projects[location.projectIndex].sessions[location.sessionIndex]
        if session.turns.isEmpty, !session.hasCustomTitle {
            session.title = Self.generatedTitle(from: prompt)
        }
        let startedAtCost = session.totalCostUSD
        session.turns.append(ConversationTurn(role: .user, blocks: [.makeText(prompt)]))
        let assistantTurn = ConversationTurn(role: .assistant, isStreaming: true)
        session.turns.append(assistantTurn)
        session.updatedAt = .now
        projects[location.projectIndex].sessions[location.sessionIndex] = session
        projects[location.projectIndex].lastOpenedAt = .now

        selectedProjectID = projects[location.projectIndex].id
        selectedSessionID = sessionID
        activities[sessionID]?.unread = false
        activities[sessionID]?.resetForSend()
        activeTurnIDs[sessionID] = assistantTurn.id
        processedBlockSignatures[sessionID] = []
        turnStartCosts[sessionID] = startedAtCost
        previewBuffers[sessionID] = StreamPreview()
        resetPreview(sessionID)

        scheduleSave()

        Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                let runtime = try await self.startOrReuseRuntime(for: sessionID)
                try runtime.sendPrompt(prompt)
                self.mutateSession(sessionID) { session in
                    session.claudeStarted = true
                    session.updatedAt = .now
                }
                self.scheduleSave()
                if let activity = self.activities[sessionID], !activity.isStopping {
                    activity.statusText = "Thinking"
                }
            } catch {
                self.failActiveTurn(
                    sessionID: sessionID,
                    error: (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
                )
            }
        }
        return true
    }

    func stop(sessionID: UUID, silently: Bool = false) {
        guard let activity = activities[sessionID] else { return }
        if silently {
            if let runtime = runtimes[sessionID] {
                for request in activity.pendingPermissions {
                    try? runtime.respondPermission(
                        requestID: request.requestID,
                        reply: .deny(request, message: "The user stopped the turn.", interrupt: true)
                    )
                }
                try? runtime.interrupt()
                runtime.terminate()
            }
            activity.pendingPermissions = []
            return
        }
        guard activity.isRunning, !activity.isStopping else { return }
        activity.isStopping = true
        activity.statusText = "Stopping"

        if let runtime = runtimes[sessionID] {
            for request in activity.pendingPermissions {
                try? runtime.respondPermission(
                    requestID: request.requestID,
                    reply: .deny(request, message: "The user stopped the turn.", interrupt: true)
                )
                markTool(
                    sessionID: sessionID,
                    toolID: request.toolUseID,
                    status: .interrupted
                )
            }
            activity.pendingPermissions = []
            do {
                try runtime.interrupt()
            } catch {
                activity.banner = "Could not stop the turn cleanly."
            }

            forceStopTasks[sessionID]?.cancel()
            forceStopTasks[sessionID] = Task { @MainActor [weak self] in
                try? await Task.sleep(for: .seconds(6))
                guard !Task.isCancelled, let self,
                      let activity = self.activities[sessionID],
                      activity.isRunning else { return }
                self.runtimes[sessionID]?.terminate()
                if let turnID = self.activeTurnIDs[sessionID] {
                    self.finishTurn(
                        sessionID: sessionID,
                        turnID: turnID,
                        result: nil,
                        error: nil,
                        stopReason: "Stopped",
                        wasStopped: true
                    )
                }
            }
        } else if let turnID = activeTurnIDs[sessionID] {
            finishTurn(
                sessionID: sessionID,
                turnID: turnID,
                result: nil,
                error: nil,
                stopReason: "Stopped",
                wasStopped: true
            )
        }
    }

    // MARK: - Permissions

    func respond(to request: ClaudePermissionRequest, action: PermissionAction, sessionID: UUID) {
        guard let activity = activities[sessionID] else { return }
        if let index = activity.pendingPermissions.firstIndex(where: { $0.requestID == request.requestID }) {
            activity.pendingPermissions.remove(at: index)
        }

        guard let runtime = runtimes[sessionID] else {
            activity.banner = "Claude Code is no longer running."
            failActiveTurn(sessionID: sessionID, error: "Claude Code is no longer running.")
            return
        }

        let reply: ClaudePermissionReply
        switch action {
        case .allowOnce:
            reply = .allowOnce(request)
            markTool(sessionID: sessionID, toolID: request.toolUseID, status: .running)
        case .allowAlways:
            reply = .allowAlways(request)
            markTool(sessionID: sessionID, toolID: request.toolUseID, status: .running)
            if let implied = request.impliedPermissionMode {
                mutateSession(sessionID) { $0.permissionMode = implied }
            }
        case .deny:
            reply = .deny(request, message: "The user declined this action.")
            markTool(sessionID: sessionID, toolID: request.toolUseID, status: .denied)
        }

        do {
            try runtime.respondPermission(requestID: request.requestID, reply: reply)
            activity.statusText = activity.pendingPermissions.isEmpty ? "Working" : "Waiting for you"
            scheduleSave()
        } catch {
            activity.banner = "Could not deliver your permission choice."
            failActiveTurn(
                sessionID: sessionID,
                error: (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            )
        }
    }

    // MARK: - Runtime lifecycle

    private func startOrReuseRuntime(for sessionID: UUID) async throws -> ClaudeRuntime {
        if let existing = runtimes[sessionID] {
            return existing
        }
        guard let executablePath = claudeAvailability.path else {
            throw RuntimeHostError.claudeUnavailable(claudeAvailabilityMessage)
        }
        guard let location = locateSession(sessionID) else {
            throw RuntimeHostError.sessionMissing
        }
        let project = projects[location.projectIndex]
        let session = project.sessions[location.sessionIndex]
        let provider = provider(for: session)
        let apiKey = try await apiKey(for: provider)

        var extraArguments: [String] = []
        do {
            if let pluginTools = try preparePluginTools(for: sessionID, project: project) {
                extraArguments = pluginTools.extraArguments
            }
        } catch {
            activities[sessionID]?.banner =
                (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }

        let configuration = ClaudeLaunchConfiguration(
            executableURL: URL(fileURLWithPath: executablePath),
            workingDirectory: project.url,
            claudeSessionID: session.claudeSessionID,
            resume: session.claudeStarted,
            model: session.model,
            permissionMode: session.permissionMode,
            extraArguments: extraArguments,
            environmentOverrides: provider.environment(apiKey: apiKey),
            removedEnvironmentKeys: provider.environmentKeysToClear
        )

        let runtime: ClaudeRuntime
        do {
            runtime = try ClaudeRuntime(
                configuration: configuration,
                logURL: dataStore.logURL(for: sessionID)
            )
        } catch {
            stopPluginToolBridge(for: sessionID)
            throw error
        }
        runtimes[sessionID] = runtime

        runtimeTasks[sessionID]?.cancel()
        runtimeTasks[sessionID] = Task { @MainActor [weak self] in
            for await event in runtime.events {
                if Task.isCancelled { break }
                self?.handle(event, sessionID: sessionID)
            }
            self?.runtimeStreamEnded(sessionID: sessionID, runtime: runtime)
        }

        do {
            try await runtime.initialize()
        } catch {
            if runtimes[sessionID] === runtime {
                runtimes.removeValue(forKey: sessionID)
                runtimeTasks[sessionID]?.cancel()
                runtimeTasks.removeValue(forKey: sessionID)
            }
            runtime.terminate()
            stopPluginToolBridge(for: sessionID)
            throw error
        }
        return runtime
    }

    private func runtimeStreamEnded(sessionID: UUID, runtime: ClaudeRuntime) {
        if runtimes[sessionID] === runtime {
            runtimes.removeValue(forKey: sessionID)
            runtimeTasks.removeValue(forKey: sessionID)
            stopPluginToolBridge(for: sessionID)
        }
    }

    /// Called when a process exits before a result. It is idempotent.
    private func handleProcessExit(sessionID: UUID, stderrTail: String) {
        guard let activity = activities[sessionID] else { return }
        activity.lastStderr = stderrTail
        guard !isAppTerminating else { return }

        if let turnID = activeTurnIDs[sessionID] {
            if activity.isStopping {
                finishTurn(
                    sessionID: sessionID,
                    turnID: turnID,
                    result: nil,
                    error: nil,
                    stopReason: "Stopped",
                    wasStopped: true
                )
            } else {
                let detail = stderrTail.trimmingCharacters(in: .whitespacesAndNewlines)
                let message = detail.isEmpty
                    ? "Claude Code stopped unexpectedly."
                    : "Claude Code stopped unexpectedly.\n\(String(detail.suffix(700)))"
                finishTurn(
                    sessionID: sessionID,
                    turnID: turnID,
                    result: nil,
                    error: message,
                    stopReason: nil,
                    wasStopped: false
                )
            }
        } else {
            activity.resetIdle()
            activity.banner = "Claude Code stopped."
        }
    }

    // MARK: - Event handling

    private func handle(_ event: ClaudeEvent, sessionID: UUID) {
        guard let activity = activities[sessionID] else { return }
        switch event {
        case .system(let info):
            mutateSession(sessionID) { session in
                if let model = info.model, !model.isEmpty {
                    session.actualModelName = model
                }
            }
            if !info.slashCommands.isEmpty {
                activity.availableCommands = info.slashCommands
            }
            if activity.statusText == "Starting Claude Code" {
                activity.statusText = "Ready"
            }

        case .status(let status):
            if status == "requesting" {
                if activity.statusText == nil || activity.statusText == "Ready" {
                    activity.statusText = "Thinking"
                }
            }

        case .retry(let attempt, let maxAttempts, _, _):
            if activity.isRunning {
                activity.statusText = maxAttempts > 0
                    ? "Reconnecting… \(attempt)/\(maxAttempts)"
                    : "Reconnecting…"
            }

        case .streamMessageStart:
            break

        case .streamText(let text):
            var buffer = previewBuffers[sessionID] ?? StreamPreview()
            buffer.text.append(text)
            previewBuffers[sessionID] = buffer
            activity.statusText = "Responding"
            schedulePreviewFlush(sessionID)

        case .streamThinking(let text):
            var buffer = previewBuffers[sessionID] ?? StreamPreview()
            buffer.thinking.append(text)
            previewBuffers[sessionID] = buffer
            if activity.statusText != "Responding" {
                activity.statusText = "Thinking"
            }
            schedulePreviewFlush(sessionID)

        case .streamToolStart(_, let name, let displayName):
            flushPreview(sessionID)
            var buffer = previewBuffers[sessionID] ?? StreamPreview()
            buffer.toolName = displayName ?? name
            previewBuffers[sessionID] = buffer
            activity.preview.toolName = displayName ?? name
            activity.statusText = "Preparing \(displayName ?? name)"

        case .streamMessageStop:
            break

        case .assistant(let message):
            guard message.parentToolUseID == nil else { return }
            applyAssistantMessage(message, sessionID: sessionID)

        case .toolResults(let results):
            for result in results where result.parentToolUseID == nil {
                applyToolResult(result, sessionID: sessionID)
            }

        case .permissionRequest(let request):
            flushPreview(sessionID)
            if !activity.pendingPermissions.contains(where: { $0.requestID == request.requestID }) {
                activity.pendingPermissions.append(request)
            }
            markTool(sessionID: sessionID, toolID: request.toolUseID, status: .awaitingPermission)
            activity.statusText = "Waiting for you"

        case .permissionCancelled(let requestID):
            activity.pendingPermissions.removeAll { $0.requestID == requestID }
            if activity.pendingPermissions.isEmpty, activity.isRunning {
                activity.statusText = "Working"
            }

        case .controlResponse:
            break

        case .result(let result):
            guard let turnID = activeTurnIDs[sessionID] else {
                activity.resetIdle()
                return
            }
            let wasStopped = activity.isStopping
            let errorText: String?
            if wasStopped {
                errorText = nil
            } else if result.isError {
                errorText = friendlyResultError(result)
            } else {
                errorText = nil
            }
            finishTurn(
                sessionID: sessionID,
                turnID: turnID,
                result: result,
                error: errorText,
                stopReason: wasStopped ? "Stopped" : (result.terminalReason ?? result.subtype),
                wasStopped: wasStopped
            )

        case .notice(let text, let isError):
            if isError {
                activity.banner = text
            } else if activity.isRunning {
                activity.statusText = text
            }

        case .processExited(_, let stderrTail):
            handleProcessExit(sessionID: sessionID, stderrTail: stderrTail)
        }
    }

    private func applyAssistantMessage(_ message: ClaudeAssistantMessage, sessionID: UUID) {
        guard let activity = activities[sessionID],
              let turnID = activeTurnIDs[sessionID],
              let location = locateSession(sessionID),
              let turnIndex = projects[location.projectIndex].sessions[location.sessionIndex].turns
                .firstIndex(where: { $0.id == turnID }) else { return }

        var signatures = processedBlockSignatures[sessionID] ?? []
        var turn = projects[location.projectIndex].sessions[location.sessionIndex].turns[turnIndex]
        let apiID = message.apiMessageID ?? "local"
        let existingToolIDs = Set(turn.tools.map(\.id))
        var addedAnything = false

        // Claude Code emits one assistant event per completed content block, reusing
        // the same API message id. Merge each chunk, but never repeat identical blocks.
        for content in message.content {
            switch content {
            case .text(let text):
                guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { continue }
                let signature = "\(apiID)|text|\(text)"
                guard signatures.insert(signature).inserted else { continue }
                turn.blocks.append(.makeText(text))
                addedAnything = true
            case .thinking(let text):
                guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { continue }
                let signature = "\(apiID)|thinking|\(text)"
                guard signatures.insert(signature).inserted else { continue }
                turn.blocks.append(.makeThinking(text))
                addedAnything = true
            case .toolUse(let id, let name, let input, let displayName):
                guard !existingToolIDs.contains(id) else { continue }
                let signature = "\(apiID)|tool|\(id)"
                guard signatures.insert(signature).inserted else { continue }
                let tool = ToolActivity(
                    id: id,
                    name: name,
                    displayName: displayName,
                    input: input,
                    status: .running
                )
                turn.blocks.append(.makeTool(tool))
                addedAnything = true
            }
        }
        processedBlockSignatures[sessionID] = signatures

        if let model = message.model, !model.isEmpty, model != "<synthetic>" {
            mutateSession(sessionID) { $0.actualModelName = model }
        }

        projects[location.projectIndex].sessions[location.sessionIndex].turns[turnIndex] = turn
        if addedAnything {
            resetPreview(sessionID)
            activity.statusText = "Working"
            scheduleSave()
        }
    }

    private func applyToolResult(_ result: ClaudeToolResult, sessionID: UUID) {
        guard let turnID = activeTurnIDs[sessionID],
              let location = locateSession(sessionID),
              let turnIndex = projects[location.projectIndex].sessions[location.sessionIndex].turns
                .firstIndex(where: { $0.id == turnID }) else { return }
        var turn = projects[location.projectIndex].sessions[location.sessionIndex].turns[turnIndex]
        guard let blockIndex = turn.blocks.firstIndex(where: { $0.tool?.id == result.toolUseID }) else { return }
        var tool = turn.blocks[blockIndex].tool
        if result.text.count > 250_000 {
            tool?.resultText = String(result.text.prefix(250_000)) + "\n\n[Output truncated by Gantry]"
        } else {
            tool?.resultText = result.text
        }
        tool?.structuredResult = result.structuredResult
        tool?.isError = result.isError
        tool?.completedAt = .now
        if tool?.status == .denied || tool?.status == .interrupted {
            // Keep the user-facing decision status.
        } else {
            tool?.status = result.isError ? .failed : .completed
        }
        if let tool {
            turn.blocks[blockIndex].tool = tool
        }
        projects[location.projectIndex].sessions[location.sessionIndex].turns[turnIndex] = turn
        scheduleSave()
    }

    private func markTool(sessionID: UUID, toolID: String?, status: ToolStatus) {
        guard let toolID,
              let turnID = activeTurnIDs[sessionID],
              let location = locateSession(sessionID),
              let turnIndex = projects[location.projectIndex].sessions[location.sessionIndex].turns
                .firstIndex(where: { $0.id == turnID }) else { return }
        var turn = projects[location.projectIndex].sessions[location.sessionIndex].turns[turnIndex]
        guard let blockIndex = turn.blocks.firstIndex(where: { $0.tool?.id == toolID }),
              var tool = turn.blocks[blockIndex].tool else { return }
        tool.status = status
        if status == .completed || status == .failed || status == .denied || status == .interrupted {
            tool.completedAt = tool.completedAt ?? .now
        }
        turn.blocks[blockIndex].tool = tool
        projects[location.projectIndex].sessions[location.sessionIndex].turns[turnIndex] = turn
    }

    // MARK: - Preview coalescing

    private func schedulePreviewFlush(_ sessionID: UUID) {
        guard previewFlushTasks[sessionID] == nil else { return }
        previewFlushTasks[sessionID] = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(32))
            guard !Task.isCancelled else { return }
            self?.flushPreview(sessionID)
        }
    }

    private func flushPreview(_ sessionID: UUID) {
        previewFlushTasks[sessionID]?.cancel()
        previewFlushTasks.removeValue(forKey: sessionID)
        guard let activity = activities[sessionID],
              let buffer = previewBuffers[sessionID] else { return }
        if activity.preview.text != buffer.text {
            activity.preview.text = buffer.text
        }
        if activity.preview.thinking != buffer.thinking {
            activity.preview.thinking = buffer.thinking
        }
        if let toolName = buffer.toolName, activity.preview.toolName != toolName {
            activity.preview.toolName = toolName
        }
    }

    private func resetPreview(_ sessionID: UUID) {
        previewFlushTasks[sessionID]?.cancel()
        previewFlushTasks.removeValue(forKey: sessionID)
        previewBuffers[sessionID] = StreamPreview()
        activities[sessionID]?.preview.clear()
    }

    // MARK: - Turn completion

    private func failActiveTurn(sessionID: UUID, error: String) {
        guard let turnID = activeTurnIDs[sessionID] else {
            activities[sessionID]?.resetIdle()
            activities[sessionID]?.banner = error
            return
        }
        finishTurn(
            sessionID: sessionID,
            turnID: turnID,
            result: nil,
            error: error,
            stopReason: nil,
            wasStopped: false
        )
    }

    func finishTurn(
        sessionID: UUID,
        turnID: UUID,
        result: ClaudeResultInfo?,
        error: String?,
        stopReason: String?,
        wasStopped: Bool,
        persist: Bool = true
    ) {
        guard let location = locateSession(sessionID),
              let turnIndex = projects[location.projectIndex].sessions[location.sessionIndex].turns
                .firstIndex(where: { $0.id == turnID }) else {
            activeTurnIDs.removeValue(forKey: sessionID)
            return
        }

        // Flush any final streamed text that did not also arrive as a complete message.
        previewFlushTasks[sessionID]?.cancel()
        previewFlushTasks.removeValue(forKey: sessionID)
        let pendingPreview = previewBuffers.removeValue(forKey: sessionID) ?? activities[sessionID]?.preview ?? StreamPreview()
        var turn = projects[location.projectIndex].sessions[location.sessionIndex].turns[turnIndex]

        if turn.isStreaming {
            if !pendingPreview.thinking.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
               !turn.blocks.contains(where: { $0.kind == .thinking }) {
                turn.blocks.append(.makeThinking(pendingPreview.thinking))
            }
            if !pendingPreview.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
               !turn.blocks.contains(where: { $0.kind == .text }) {
                turn.blocks.append(.makeText(pendingPreview.text))
            }
            if let result,
               !result.isError,
               !turn.blocks.contains(where: { $0.kind == .text || $0.kind == .tool }),
               let fallbackText = result.resultText,
               !fallbackText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                turn.blocks.append(.makeText(fallbackText))
            }
        }

        let unresolvedStatus: ToolStatus = wasStopped || error != nil ? .interrupted : .completed
        for blockIndex in turn.blocks.indices where turn.blocks[blockIndex].kind == .tool {
            guard var tool = turn.blocks[blockIndex].tool else { continue }
            if tool.status == .running || tool.status == .awaitingPermission {
                tool.status = unresolvedStatus
                tool.completedAt = tool.completedAt ?? .now
                turn.blocks[blockIndex].tool = tool
            }
        }

        var session = projects[location.projectIndex].sessions[location.sessionIndex]
        let startCost = turnStartCosts[sessionID] ?? max(0, session.totalCostUSD)
        if let result {
            var usage = result.usage
            usage.costUSD = max(0, result.totalCostUSD - startCost)
            if usage.durationMS == nil {
                usage.durationMS = result.durationMS
            }
            turn.usage = usage
            if let modelName = usage.modelName, !modelName.isEmpty {
                session.actualModelName = modelName
            }
            if result.totalCostUSD > 0 || session.totalCostUSD == 0 {
                session.totalCostUSD = result.totalCostUSD
            }
        }
        turn.errorText = error.map { String($0.prefix(2_500)) }
        turn.stopReason = stopReason
        turn.isStreaming = false
        session.turns[turnIndex] = turn
        session.updatedAt = .now
        projects[location.projectIndex].sessions[location.sessionIndex] = session

        activeTurnIDs.removeValue(forKey: sessionID)
        processedBlockSignatures.removeValue(forKey: sessionID)
        turnStartCosts.removeValue(forKey: sessionID)
        forceStopTasks[sessionID]?.cancel()
        forceStopTasks.removeValue(forKey: sessionID)

        let activity = activities[sessionID]
        activity?.resetIdle()
        refreshProviderRuntimeIfNeeded(sessionID: sessionID)
        refreshPluginToolRuntimeIfNeeded(sessionID: sessionID)
        toastCompletionIfNeeded(sessionID: sessionID, hadError: error != nil)

        if persist && !isAppTerminating {
            scheduleSave()
        }
    }

    private func toastCompletionIfNeeded(sessionID: UUID, hadError: Bool) {
        guard selectedSessionID != sessionID, !hadError else { return }
        activities[sessionID]?.unread = true
    }

    // MARK: - Helpers

    private var claudeAvailabilityMessage: String {
        switch claudeAvailability {
        case .checking:
            return "Claude Code is still starting."
        case .missing:
            return "Claude Code isn't installed or couldn't be found. Install it, then rescan in Settings."
        case .failed(let message):
            return message
        case .ready:
            return ""
        }
    }

    private func friendlyResultError(_ result: ClaudeResultInfo) -> String {
        switch result.subtype {
        case "error_max_turns":
            return "Claude reached the turn limit for this message."
        case "error_during_execution":
            if let text = result.resultText, !text.isEmpty {
                return TextSanitizer.stripANSI(text)
            }
            return "Claude Code hit an error while working on this message."
        case "error_max_budget_usd":
            return "This message reached the configured budget limit."
        default:
            if let text = result.resultText, !text.isEmpty {
                return TextSanitizer.stripANSI(text)
            }
            return "The turn ended with an error."
        }
    }

    private static func generatedTitle(from prompt: String) -> String {
        let firstLine = prompt
            .split(whereSeparator: \.isNewline)
            .first
            .map(String.init) ?? prompt
        let collapsed = firstLine
            .replacingOccurrences(of: "`", with: "")
            .replacingOccurrences(of: "#", with: "")
            .split(whereSeparator: \.isWhitespace)
            .joined(separator: " ")
        if collapsed.isEmpty { return "New session" }
        if collapsed.count <= 52 { return collapsed }
        let cutoff = collapsed.index(collapsed.startIndex, offsetBy: 52)
        return String(collapsed[..<cutoff]).trimmingCharacters(in: .whitespacesAndNewlines) + "…"
    }
}

private enum RuntimeHostError: Error, LocalizedError {
    case claudeUnavailable(String)
    case sessionMissing

    var errorDescription: String? {
        switch self {
        case .claudeUnavailable(let message): return message
        case .sessionMissing: return "That session could not be found."
        }
    }
}

extension AppModel {
    func retryLastPrompt(sessionID: UUID) {
        guard activities[sessionID]?.isRunning != true,
              let session = session(withID: sessionID),
              let lastUser = session.turns.last(where: { $0.role == .user }) else { return }
        let prompt = lastUser.textContent
        guard !prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        _ = send(prompt, in: sessionID)
    }
}
