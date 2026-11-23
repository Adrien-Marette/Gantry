import Foundation

public final class ClaudeRuntime: @unchecked Sendable {
    public let id: UUID
    public let configuration: ClaudeLaunchConfiguration
    public let events: AsyncStream<ClaudeEvent>

    private let continuation: AsyncStream<ClaudeEvent>.Continuation
    private let process = Process()
    private let inputPipe = Pipe()
    private let outputPipe = Pipe()
    private let errorPipe = Pipe()
    private let stateQueue = DispatchQueue(label: "fr.soundwise.Gantry.claude-runtime")
    private let logURL: URL?
    private let logFormatter = ISO8601DateFormatter()
    private var logHandle: FileHandle?
    private var outputBuffer = Data()
    private var errorBuffer = Data()
    private var stderrTail = ""
    private var pendingInitialize: PendingInitialize?
    private var closed = false
    private var sawExit = false

    private struct PendingInitialize {
        var requestID: String
        var continuation: CheckedContinuation<ClaudeControlResponseInfo, Error>
    }

    public init(configuration: ClaudeLaunchConfiguration, logURL: URL? = nil) throws {
        self.id = configuration.claudeSessionID
        self.configuration = configuration
        self.logURL = logURL

        let stream = AsyncStream<ClaudeEvent>.makeStream(bufferingPolicy: .unbounded)
        self.events = stream.stream
        self.continuation = stream.continuation

        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(
            atPath: configuration.workingDirectory.path,
            isDirectory: &isDirectory
        ), isDirectory.boolValue else {
            stream.continuation.finish()
            throw ClaudeRuntimeError.invalidWorkingDirectory(configuration.workingDirectory.path)
        }
        guard FileManager.default.isExecutableFile(atPath: configuration.executableURL.path) else {
            stream.continuation.finish()
            throw ClaudeRuntimeError.claudeNotFound(configuration.executableURL.path)
        }

        process.executableURL = configuration.executableURL
        process.arguments = configuration.arguments
        process.currentDirectoryURL = configuration.workingDirectory
        var processEnvironment = ClaudeProcessEnvironment.make(
            executableURL: configuration.executableURL
        )
        for key in configuration.removedEnvironmentKeys {
            processEnvironment.removeValue(forKey: key)
        }
        for (key, value) in configuration.environmentOverrides {
            processEnvironment[key] = value
        }
        process.environment = processEnvironment
        process.standardInput = inputPipe
        process.standardOutput = outputPipe
        process.standardError = errorPipe
        process.qualityOfService = .userInitiated

        if let logURL {
            let directory = logURL.deletingLastPathComponent()
            try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            if !FileManager.default.fileExists(atPath: logURL.path) {
                FileManager.default.createFile(
                    atPath: logURL.path,
                    contents: nil,
                    attributes: [.posixPermissions: 0o600]
                )
            }
            logHandle = try? FileHandle(forWritingTo: logURL)
            _ = try? logHandle?.seekToEnd()
        }

        process.terminationHandler = { [weak self] process in
            let code = process.terminationStatus
            // Give the pipe readers a moment to deliver the final chunk.
            DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 0.12) {
                self?.stateQueue.async {
                    self?.finishExit(code: code)
                }
            }
        }

        do {
            try process.run()
        } catch {
            stream.continuation.finish()
            closeLog()
            throw ClaudeRuntimeError.launchFailed(error.localizedDescription)
        }

        log("launched pid \(process.processIdentifier): \(configuration.executableURL.path)")

        outputPipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty else { return }
            self?.stateQueue.async {
                self?.consumeOutput(data)
            }
        }
        errorPipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty else { return }
            self?.stateQueue.async {
                self?.consumeError(data)
            }
        }
    }

    // MARK: - Control handshake

    /// Sends the control handshake and returns its payload. The payload carries
    /// the session's slash-command catalog, agents, models, and output styles.
    @discardableResult
    public func initialize(timeout: TimeInterval = 25) async throws -> ClaudeControlResponseInfo {
        let requestID = UUID().uuidString
        let data = try ClaudeWire.initializeRequest(requestID: requestID)

        return try await withCheckedThrowingContinuation {
            (continuation: CheckedContinuation<ClaudeControlResponseInfo, Error>) in
            stateQueue.async {
                guard !self.closed else {
                    continuation.resume(throwing: ClaudeRuntimeError.closed)
                    return
                }
                guard self.pendingInitialize == nil else {
                    continuation.resume(throwing: ClaudeRuntimeError.busy)
                    return
                }
                self.pendingInitialize = PendingInitialize(
                    requestID: requestID,
                    continuation: continuation
                )
                do {
                    try self.writeUnsafe(data)
                } catch {
                    self.pendingInitialize = nil
                    continuation.resume(throwing: ClaudeRuntimeError.writeFailed(error.localizedDescription))
                    return
                }
                self.stateQueue.asyncAfter(deadline: .now() + timeout) {
                    guard let pending = self.pendingInitialize,
                          pending.requestID == requestID else { return }
                    self.pendingInitialize = nil
                    self.log("initialize timed out")
                    pending.continuation.resume(throwing: ClaudeRuntimeError.initializationTimedOut)
                }
            }
        }
    }

    // MARK: - Input

    public func sendPrompt(_ text: String) throws {
        let data = try ClaudeWire.userMessage(text)
        try write(data)
    }

    public func respondPermission(requestID: String, reply: ClaudePermissionReply) throws {
        let data = try ClaudeWire.permissionResponse(requestID: requestID, reply: reply)
        try write(data)
    }

    public func interrupt() throws {
        let data = try ClaudeWire.interruptRequest(requestID: UUID().uuidString)
        try write(data)
    }

    public func setPermissionMode(_ mode: PermissionMode) throws {
        let data = try ClaudeWire.setPermissionModeRequest(
            requestID: UUID().uuidString,
            mode: mode
        )
        try write(data)
    }

    public func setModel(_ model: ModelChoice) throws {
        let data = try ClaudeWire.setModelRequest(
            requestID: UUID().uuidString,
            model: model
        )
        try write(data)
    }

    public func terminate() {
        stateQueue.async {
            guard !self.closed else { return }
            self.log("terminating pid \(self.process.processIdentifier)")
            if self.process.isRunning {
                self.process.terminate()
                let pid = self.process.processIdentifier
                DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 2.5) {
                    if self.process.isRunning {
                        kill(pid, SIGKILL)
                    }
                }
            }
        }
    }

    public var isRunning: Bool {
        process.isRunning
    }

    // MARK: - Output

    private func write(_ data: Data) throws {
        try stateQueue.sync {
            guard !closed else { throw ClaudeRuntimeError.closed }
            try writeUnsafe(data)
        }
    }

    private func writeUnsafe(_ data: Data) throws {
        try inputPipe.fileHandleForWriting.write(contentsOf: data)
    }

    private func consumeOutput(_ data: Data) {
        guard !closed else { return }
        outputBuffer.append(data)
        drainCompleteLines(&outputBuffer) { line in
            for event in ClaudeStreamParser.parse(line: line) {
                handleParsedEvent(event)
            }
        }
    }

    /// Consumes every complete newline-terminated line in one pass, removing the
    /// consumed prefix once instead of shifting the buffer after each line.
    private func drainCompleteLines(_ buffer: inout Data, _ body: (String) -> Void) {
        guard let lastNewline = buffer.lastIndex(of: 0x0A) else { return }
        let consumedEnd = buffer.index(after: lastNewline)
        var start = buffer.startIndex
        while start < consumedEnd {
            guard let newline = buffer[start..<consumedEnd].firstIndex(of: 0x0A) else { break }
            if newline > start {
                body(String(decoding: buffer[start..<newline], as: UTF8.self))
            }
            start = buffer.index(after: newline)
        }
        buffer.removeSubrange(buffer.startIndex..<consumedEnd)
    }

    private func handleParsedEvent(_ event: ClaudeEvent) {
        if case .controlResponse(let response) = event {
            if let pending = pendingInitialize, pending.requestID == response.requestID {
                pendingInitialize = nil
                if response.isSuccess {
                    pending.continuation.resume(returning: response)
                } else {
                    pending.continuation.resume(
                        throwing: ClaudeRuntimeError.initializationFailed(
                            response.error ?? "Claude Code could not initialize this session."
                        )
                    )
                }
            }
            return
        }
        continuation.yield(event)
    }

    private func consumeError(_ data: Data) {
        errorBuffer.append(data)
        drainCompleteLines(&errorBuffer) { appendStderr($0) }
    }

    private func appendStderr(_ line: String) {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        log("stderr: \(trimmed)")
        stderrTail.append(trimmed)
        stderrTail.append("\n")
        if stderrTail.count > 8_000 {
            stderrTail = String(stderrTail.suffix(8_000))
        }
    }

    private func finishExit(code: Int32) {
        guard !sawExit else { return }
        sawExit = true
        closed = true
        if !errorBuffer.isEmpty {
            drainCompleteLines(&errorBuffer) { appendStderr($0) }
            if !errorBuffer.isEmpty {
                appendStderr(String(decoding: errorBuffer, as: UTF8.self))
                errorBuffer.removeAll(keepingCapacity: false)
            }
        }
        if !outputBuffer.isEmpty {
            drainCompleteLines(&outputBuffer) { line in
                for event in ClaudeStreamParser.parse(line: line) {
                    handleParsedEvent(event)
                }
            }
            if !outputBuffer.isEmpty {
                let trailing = String(decoding: outputBuffer, as: UTF8.self)
                outputBuffer.removeAll(keepingCapacity: false)
                for event in ClaudeStreamParser.parse(line: trailing) {
                    handleParsedEvent(event)
                }
            }
        }
        if let pending = pendingInitialize {
            pendingInitialize = nil
            pending.continuation.resume(
                throwing: ClaudeRuntimeError.exitedBeforeInitialization(stderrTail)
            )
        }
        outputPipe.fileHandleForReading.readabilityHandler = nil
        errorPipe.fileHandleForReading.readabilityHandler = nil
        log("exited with code \(code)")
        continuation.yield(.processExited(code: code, stderrTail: stderrTail))
        continuation.finish()
        closeLog()
    }

    private func log(_ message: String) {
        guard let logHandle else { return }
        let timestamp = logFormatter.string(from: Date())
        let text = "[\(timestamp)] [\(id.uuidString.prefix(8))] \(message)\n"
        try? logHandle.write(contentsOf: Data(text.utf8))
    }

    private func closeLog() {
        try? logHandle?.close()
        logHandle = nil
    }

    deinit {
        if process.isRunning {
            process.terminate()
        }
        closeLog()
    }
}

public enum ClaudeRuntimeError: Error, LocalizedError {
    case invalidWorkingDirectory(String)
    case claudeNotFound(String)
    case launchFailed(String)
    case initializationFailed(String)
    case initializationTimedOut
    case exitedBeforeInitialization(String)
    case writeFailed(String)
    case closed
    case busy

    public var errorDescription: String? {
        switch self {
        case .invalidWorkingDirectory(let path):
            return "The project folder no longer exists: \(path)"
        case .claudeNotFound(let path):
            return "Claude Code was not found at \(path)."
        case .launchFailed(let message):
            return "Claude Code could not start: \(message)"
        case .initializationFailed(let message):
            return message
        case .initializationTimedOut:
            return "Claude Code took too long to start. Check your connection and try again."
        case .exitedBeforeInitialization(let stderr):
            let detail = stderr.trimmingCharacters(in: .whitespacesAndNewlines)
            return detail.isEmpty
                ? "Claude Code exited before the session started."
                : "Claude Code exited before the session started.\n\(detail)"
        case .writeFailed(let message):
            return "Could not talk to Claude Code: \(message)"
        case .closed:
            return "The Claude Code process has ended."
        case .busy:
            return "Claude Code is still starting."
        }
    }
}
