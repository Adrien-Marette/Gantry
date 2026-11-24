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

        if handleLocalSlashCommand(prompt, in: sessionID) {
            return true
        }

        var session = projects[location.projectIndex].sessions[location.sessionIndex]
        let hadPriorTurns = !session.turns.isEmpty
        if session.turns.isEmpty, !session.hasCustomTitle {
            session.title = Self.generatedTitle(from: prompt)
        }
        // Older state stored only Claude Code's cumulative cost in
        // `totalCostUSD`; use it as the reported baseline until the first
        // result records a dedicated value.
        let startedAtCost = session.claudeReportedCostUSD ?? session.totalCostUSD
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
        if let storedUsage = session.modelUsage {
            turnStartModelUsage[sessionID] = storedUsage
        } else if hadPriorTurns {
            // Legacy session with no cumulative snapshot: price this turn from
            // its per-turn usage instead of treating the session as new.
            turnStartModelUsage.removeValue(forKey: sessionID)
        } else {
            turnStartModelUsage[sessionID] = [:]
        }
        previewBuffers[sessionID] = StreamPreview()
        resetPreview(sessionID)

        scheduleSave()

        Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                let runtime = try await self.startOrReuseRuntime(for: sessionID)
                // The user may have stopped this turn while the process was
                // starting; do not send a prompt whose turn is already over.
                guard self.activeTurnIDs[sessionID] == assistantTurn.id,
                      self.activities[sessionID]?.isStopping != true else { return }
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
                // A stop or a recycled start may have finished the turn while
                // this task was awaiting the process.
                guard self.activeTurnIDs[sessionID] == assistantTurn.id,
                      self.activities[sessionID]?.isStopping != true else { return }
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
        // A start may still be in flight before the runtime is published.
        // Cancelling it keeps the send task from writing a prompt after stop.
        runtimeStarts.removeValue(forKey: sessionID)?.cancel()
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
        let reply: ClaudePermissionReply
        let status: ToolStatus
        switch action {
        case .allowOnce:
            reply = .allowOnce(request)
            status = .running
        case .allowAlways:
            reply = .allowAlways(request)
            status = .running
            if let implied = request.impliedPermissionMode {
                mutateSession(sessionID) { $0.permissionMode = implied }
            }
        case .deny:
            reply = .deny(request, message: "The user declined this action.")
            status = .denied
        }
        deliver(
            reply,
            for: request,
            sessionID: sessionID,
            toolStatus: status,
            failureMessage: "Could not deliver your permission choice."
        )
    }

    /// Answers an `AskUserQuestion` request. The allow response replaces the
    /// tool input with one that includes Claude Code's `answers` map.
    func answer(
        _ request: ClaudePermissionRequest,
        with answers: [String: String],
        sessionID: UUID
    ) {
        deliver(
            .answer(request, answers: answers),
            for: request,
            sessionID: sessionID,
            toolStatus: .running,
            failureMessage: "Could not send your answer."
        )
    }

    func declineQuestion(_ request: ClaudePermissionRequest, sessionID: UUID) {
        deliver(
            .deny(request, message: "The user declined to answer."),
            for: request,
            sessionID: sessionID,
            toolStatus: .denied,
            failureMessage: "Could not decline the question."
        )
    }

    private func deliver(
        _ reply: ClaudePermissionReply,
        for request: ClaudePermissionRequest,
        sessionID: UUID,
        toolStatus: ToolStatus,
        failureMessage: String
    ) {
        guard let activity = activities[sessionID] else { return }
        if let index = activity.pendingPermissions.firstIndex(where: { $0.requestID == request.requestID }) {
            activity.pendingPermissions.remove(at: index)
        }

        guard let runtime = runtimes[sessionID] else {
            activity.banner = "Claude Code is no longer running."
            failActiveTurn(sessionID: sessionID, error: "Claude Code is no longer running.")
            return
        }

        markTool(sessionID: sessionID, toolID: request.toolUseID, status: toolStatus)

        do {
            try runtime.respondPermission(requestID: request.requestID, reply: reply)
            activity.statusText = activity.pendingPermissions.isEmpty ? "Working" : "Waiting for you"
            scheduleSave()
        } catch {
            activity.banner = failureMessage
            failActiveTurn(
                sessionID: sessionID,
                error: (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            )
        }
    }

    // MARK: - Runtime lifecycle

    func startOrReuseRuntime(for sessionID: UUID) async throws -> ClaudeRuntime {
        // A start already in flight owns the process. The in-flight check comes
        // first because a runtime is published before its initialize handshake
        // completes; handing that half-started process to a second caller would
        // send a prompt before the command catalog arrives.
        if let inFlight = runtimeStarts[sessionID] {
            return try await inFlight.value
        }
        if let existing = runtimes[sessionID] {
            return existing
        }

        let task = Task { @MainActor [self] in
            try await makeRuntime(for: sessionID)
        }
        runtimeStarts[sessionID] = task
        defer {
            if runtimeStarts[sessionID] == task {
                runtimeStarts.removeValue(forKey: sessionID)
            }
        }
        return try await task.value
    }

    private func makeRuntime(for sessionID: UUID) async throws -> ClaudeRuntime {
        try Task.checkCancellation()
        guard let executablePath = claudeAvailability.path else {
            throw RuntimeHostError.claudeUnavailable(claudeAvailabilityMessage)
        }
        guard let location = locateSession(sessionID) else {
            throw RuntimeHostError.sessionMissing
        }
        let provider = provider(for: projects[location.projectIndex].sessions[location.sessionIndex])
        let apiKey = try await apiKey(for: provider)
        // The Keychain read can suspend long enough for a plugin change or a
        // provider switch to recycle this start; never publish its process.
        try Task.checkCancellation()

        // Model and permission mode can change while the Keychain read is pending.
        guard let currentLocation = locateSession(sessionID) else {
            throw RuntimeHostError.sessionMissing
        }
        let project = projects[currentLocation.projectIndex]
        let session = project.sessions[currentLocation.sessionIndex]

        var extraArguments: [String] = []
        do {
            if let pluginTools = try preparePluginTools(for: sessionID, project: project) {
                extraArguments = pluginTools.extraArguments
            }
        } catch {
            activities[sessionID]?.banner =
                (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }

        if let devModPath = project.devModPath {
            let modURL = URL(fileURLWithPath: devModPath)
                .resolvingSymlinksInPath()
                .standardizedFileURL
            let projectURL = project.url
                .resolvingSymlinksInPath()
                .standardizedFileURL
            if modURL.path == projectURL.path,
               FileManager.default.fileExists(atPath: modURL.path) {
                extraArguments.append(contentsOf: ["--plugin-dir", modURL.path])
            }
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
            let initialization = try await runtime.initialize()
            // A plugin change or provider switch may have recycled this start
            // while the handshake was pending; never publish its catalog.
            try Task.checkCancellation()
            applyInitialization(initialization, sessionID: sessionID)
        } catch {
            // Only the start that still owns the session may clear its state.
            // A recycled start can resume after a newer start has taken over.
            let ownsRuntime = runtimes[sessionID] === runtime
            if ownsRuntime {
                runtimes.removeValue(forKey: sessionID)
                runtimeTasks[sessionID]?.cancel()
                runtimeTasks.removeValue(forKey: sessionID)
            }
            runtime.terminate()
            if ownsRuntime {
                stopPluginToolBridge(for: sessionID)
            }
            if Task.isCancelled { throw CancellationError() }
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
            if let model = info.model, !model.isEmpty,
               session(withID: sessionID)?.actualModelName != model {
                mutateSession(sessionID) { $0.actualModelName = model }
            }
            if !info.slashCommands.isEmpty {
                // Older CLI versions list command names here instead of in the
                // initialize payload; keep richer entries from the payload.
                let merged = ClaudeSlashCommand.merging(
                    names: info.slashCommands,
                    into: activity.slashCommands
                )
                if merged != activity.slashCommands {
                    activity.slashCommands = merged
                }
                activity.slashCommandsError = nil
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
            previewBuffers[sessionID, default: StreamPreview()].text.append(text)
            if activity.statusText != "Responding" {
                activity.statusText = "Responding"
            }
            schedulePreviewFlush(sessionID)

        case .streamThinking(let text):
            previewBuffers[sessionID, default: StreamPreview()].thinking.append(text)
            if activity.statusText != "Responding", activity.statusText != "Thinking" {
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
        var session = projects[location.projectIndex].sessions[location.sessionIndex]
        var turn = session.turns[turnIndex]
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

        let modelChanged: Bool
        if let model = message.model,
           !model.isEmpty,
           model != "<synthetic>",
           session.actualModelName != model {
            session.actualModelName = model
            modelChanged = true
        } else {
            modelChanged = false
        }

        // Each assistant response reports the prompt that produced it. The
        // newest one is the best snapshot of how full the context window is.
        let contextChanged: Bool
        if let usage = message.usage,
           usage.contextTokens > 0,
           usage.contextTokens != session.contextTokens {
            session.contextTokens = usage.contextTokens
            if let model = message.model,
               !model.isEmpty,
               model != "<synthetic>" {
                // Context belongs to the model that produced this response.
                // Keep a resolved `[1m]` spelling for the same model, but do
                // not let a model switch leave a stale context window behind.
                let existing = session.contextModelName
                let existingBase = existing?
                    .replacingOccurrences(of: "[1m]", with: "", options: .caseInsensitive)
                let keepsResolvedName = existing?.lowercased().contains("[1m]") == true
                    && existingBase?.caseInsensitiveCompare(model) == .orderedSame
                if !keepsResolvedName {
                    session.contextModelName = model
                }
            } else if session.contextModelName == nil {
                session.contextModelName = session.actualModelName
            }
            contextChanged = true
        } else {
            contextChanged = false
        }

        guard addedAnything || modelChanged || contextChanged else { return }
        if addedAnything {
            session.turns[turnIndex] = turn
        }
        projects[location.projectIndex].sessions[location.sessionIndex] = session
        if addedAnything {
            resetPreview(sessionID)
            activity.statusText = "Working"
        }
        scheduleSave()
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
        var preview = activity.preview
        if preview.text != buffer.text {
            preview.text = buffer.text
        }
        if preview.thinking != buffer.thinking {
            preview.thinking = buffer.thinking
        }
        if let toolName = buffer.toolName, preview.toolName != toolName {
            preview.toolName = toolName
        }
        if preview != activity.preview {
            activity.preview = preview
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
            turnStartCosts.removeValue(forKey: sessionID)
            turnStartModelUsage.removeValue(forKey: sessionID)
            return
        }
        // A result event and a process exit can both try to finish the turn.
        // Only the first one may price it.
        guard activeTurnIDs[sessionID] == turnID else { return }

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
        let startCost = turnStartCosts[sessionID] ?? 0
        if let result {
            var usage = result.usage
            let modelName = session.actualModelName ?? usage.modelName
            let incrementalCost = ModelCostEstimator.incrementalCost(
                from: turnStartModelUsage[sessionID],
                to: result.modelUsage
            )
            // A zero delta with non-zero per-turn usage means the cumulative
            // snapshot was stale; prefer the per-turn estimate.
            let incremental = (incrementalCost ?? 0) > 0 ? incrementalCost : nil
            let perTurn = result.usage.totalTokens > 0
                ? ModelCostEstimator.cost(of: result.usage, model: modelName)
                : nil
            usage.costUSD = incremental
                ?? perTurn
                ?? max(0, result.totalCostUSD - startCost)
            if usage.durationMS == nil {
                usage.durationMS = result.durationMS
            }
            turn.usage = usage
            if session.actualModelName == nil,
               let reportedModel = usage.modelName,
               !reportedModel.isEmpty {
                session.actualModelName = reportedModel
            }
            // `modelUsage` is cumulative and may be dominated by a subagent.
            // It must not choose the context model. Only resolve a `[1m]`
            // spelling for the assistant model that produced the context.
            if let contextModel = session.contextModelName,
               !contextModel.lowercased().contains("[1m]"),
               let resolved = result.modelUsage.keys.first(where: {
                   $0.caseInsensitiveCompare(contextModel + "[1m]") == .orderedSame
               }) {
                session.contextModelName = resolved
            }
            // A result without a cumulative snapshot must not keep a stale
            // baseline: the next cumulative report would otherwise price the
            // turns in between a second time.
            session.modelUsage = result.modelUsage.isEmpty ? nil : result.modelUsage
            session.claudeReportedCostUSD = result.totalCostUSD

            // Add this turn's estimate to the running total. Keeping the larger
            // of the stored total and the turns' sum preserves history imported
            // from older versions that did not price every turn.
            let priorTurnCosts = session.turns.enumerated()
                .filter { $0.offset != turnIndex }
                .compactMap { $0.element.usage?.costUSD }
                .reduce(0, +)
            session.totalCostUSD = max(session.totalCostUSD, priorTurnCosts) + max(0, usage.costUSD)
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
        turnStartModelUsage.removeValue(forKey: sessionID)
        forceStopTasks[sessionID]?.cancel()
        forceStopTasks.removeValue(forKey: sessionID)

        let activity = activities[sessionID]
        activity?.resetIdle()
        refreshProviderRuntimeIfNeeded(sessionID: sessionID)
        refreshRuntimeIfNeeded(sessionID: sessionID)
        toastCompletionIfNeeded(sessionID: sessionID, hadError: error != nil)

        if persist && !isAppTerminating {
            scheduleSave()
        }
    }

    private func toastCompletionIfNeeded(sessionID: UUID, hadError: Bool) {
        guard !hadError else { return }
        // The menu bar is the only status surface when the window is closed,
        // so mark finishes as unread unless the person is looking at that
        // session in the key main window.
        guard !(isMainWindowFocused && selectedSessionID == sessionID) else { return }
        activities[sessionID]?.unread = true
    }

    // MARK: - Helpers

    var claudeAvailabilityMessage: String {
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
