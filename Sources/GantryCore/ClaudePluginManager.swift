import Darwin
import Foundation

// MARK: - Models

/// One entry from `claude plugin list --json`.
public struct ClaudeInstalledPlugin: Codable, Hashable, Identifiable, Sendable {
    public var id: String
    public var version: String?
    /// Raw scope string; unknown values are preserved rather than coerced.
    public var scope: String?
    public var enabled: Bool
    public var installPath: String?
    public var readFromFolder: String?
    public var folderVersion: String?
    /// Kept as strings: the CLI emits fractional-second ISO-8601, which
    /// `JSONDecoder.dateDecodingStrategy = .iso8601` does not parse.
    public var installedAt: String?
    public var lastUpdated: String?
    public var projectEnabled: Bool?
    public var hasUserConfig: Bool?

    public init(
        id: String,
        version: String? = nil,
        scope: String? = nil,
        enabled: Bool,
        installPath: String? = nil,
        readFromFolder: String? = nil,
        folderVersion: String? = nil,
        installedAt: String? = nil,
        lastUpdated: String? = nil,
        projectEnabled: Bool? = nil,
        hasUserConfig: Bool? = nil
    ) {
        self.id = id
        self.version = version
        self.scope = scope
        self.enabled = enabled
        self.installPath = installPath
        self.readFromFolder = readFromFolder
        self.folderVersion = folderVersion
        self.installedAt = installedAt
        self.lastUpdated = lastUpdated
        self.projectEnabled = projectEnabled
        self.hasUserConfig = hasUserConfig
    }

    public var name: String {
        let parts = id.split(separator: "@", maxSplits: 1, omittingEmptySubsequences: false)
        return parts.first.map(String.init) ?? id
    }

    public var marketplaceName: String? {
        let parts = id.split(separator: "@", maxSplits: 1, omittingEmptySubsequences: false)
        return parts.count > 1 ? String(parts[1]) : nil
    }

    public var knownScope: ClaudePluginScope? {
        guard let scope else { return nil }
        return ClaudePluginScope(rawValue: scope)
    }

    /// Identity including scope, for lists where the same plugin id can exist
    /// more than once (for example user and project scopes).
    public var identity: String {
        "\(scope ?? "unknown"):\(id)"
    }
}

/// One entry from the `available` array of `claude plugin list --json --available`.
public struct ClaudeAvailablePlugin: Decodable, Hashable, Identifiable, Sendable {
    public var pluginId: String
    public var name: String
    public var description: String?
    public var marketplaceName: String
    public var source: ClaudePluginSource?

    public var id: String { pluginId }

    public init(
        pluginId: String,
        name: String,
        description: String? = nil,
        marketplaceName: String,
        source: ClaudePluginSource? = nil
    ) {
        self.pluginId = pluginId
        self.name = name
        self.description = description
        self.marketplaceName = marketplaceName
        self.source = source
    }
}

/// A marketplace source can be a plain string or an object such as
/// `{"source":"git-subdir","url":"…","path":"…"}`.
public struct ClaudePluginSource: Decodable, Hashable, Sendable {
    public enum Kind: String, Sendable {
        case directory
        case url
        case git
        case gitSubdir = "git-subdir"
        case github
        case unknown
    }

    public var kind: Kind
    public var url: String?
    public var repo: String?
    public var path: String?
    public var ref: String?
    public var sha: String?
    public var literal: String?

    private enum CodingKeys: String, CodingKey {
        case source
        case url
        case repo
        case path
        case ref
        case sha
    }

    public init(from decoder: Decoder) throws {
        if let single = try? decoder.singleValueContainer(),
           let value = try? single.decode(String.self) {
            kind = .unknown
            literal = value
            return
        }

        let container = try decoder.container(keyedBy: CodingKeys.self)
        let rawKind = (try? container.decodeIfPresent(String.self, forKey: .source)) ?? nil
        kind = rawKind.flatMap(Kind.init(rawValue:)) ?? .unknown
        url = try? container.decodeIfPresent(String.self, forKey: .url)
        repo = try? container.decodeIfPresent(String.self, forKey: .repo)
        path = try? container.decodeIfPresent(String.self, forKey: .path)
        ref = try? container.decodeIfPresent(String.self, forKey: .ref)
        sha = try? container.decodeIfPresent(String.self, forKey: .sha)
    }

    public var displayLocation: String {
        if let url, !url.isEmpty {
            let base = ClaudePluginText.redactingCredentials(in: url)
            if let path, !path.isEmpty {
                return "\(base)/\(path.trimmingCharacters(in: CharacterSet(charactersIn: "/")))"
            }
            return base
        }
        if let repo, !repo.isEmpty { return repo }
        if let literal, !literal.isEmpty {
            return ClaudePluginText.redactingCredentials(in: literal)
        }
        if let path, !path.isEmpty { return path }
        return "Unknown source"
    }
}

/// One entry from `claude plugin marketplace list --json`.
public struct ClaudeMarketplace: Decodable, Hashable, Identifiable, Sendable {
    public var name: String
    public var source: String?
    public var repo: String?
    public var url: String?
    public var path: String?
    public var installLocation: String?

    public var id: String { stableKey }

    /// Stable identity for favorites: a repository, URL, or path survives a rename.
    public var stableKey: String {
        if let repo = repo?.trimmingCharacters(in: .whitespacesAndNewlines), !repo.isEmpty {
            return "repo:\(repo)"
        }
        if let url, let location = ClaudePluginText.credentialFreeURL(url) {
            return "url:\(location)"
        }
        if let path = path?.trimmingCharacters(in: .whitespacesAndNewlines), !path.isEmpty {
            return "path:\(path)"
        }
        return "name:\(name)"
    }

    public var displayLocation: String {
        let value: String
        if let repo, !repo.isEmpty {
            value = repo
        } else if let url = url?.trimmingCharacters(in: .whitespacesAndNewlines), !url.isEmpty {
            value = url
        } else if let path, !path.isEmpty {
            value = path
        } else if let source, !source.isEmpty {
            value = source
        } else {
            value = name
        }
        return ClaudePluginText.redactingCredentials(in: value)
    }
}

public struct ClaudePluginCatalog: Sendable {
    public var installed: [ClaudeInstalledPlugin]
    public var available: [ClaudeAvailablePlugin]

    public init(installed: [ClaudeInstalledPlugin], available: [ClaudeAvailablePlugin]) {
        self.installed = installed
        self.available = available
    }
}

public enum ClaudePluginScope: String, Codable, CaseIterable, Sendable {
    case user
    case project
    case local
}

public struct ClaudePluginCommandResult: Sendable, Hashable {
    public var exitCode: Int32
    public var stdout: String
    public var stderr: String

    public init(exitCode: Int32, stdout: String, stderr: String) {
        self.exitCode = exitCode
        self.stdout = stdout
        self.stderr = stderr
    }
}

public struct ClaudePluginValidationResult: Sendable, Hashable {
    public var succeeded: Bool
    public var output: String

    public init(succeeded: Bool, output: String) {
        self.succeeded = succeeded
        self.output = output
    }
}

// MARK: - Errors and input validation

public enum ClaudePluginError: Error, LocalizedError, Sendable {
    case cliUnavailable(String)
    case commandFailed(arguments: [String], exitCode: Int32, message: String)
    case unexpectedOutput(String)
    case confirmationRequired(command: String, sha256: String?)
    case timedOut(String)
    case unsupportedCLI

    public var errorDescription: String? {
        switch self {
        case .cliUnavailable(let message):
            return "Claude Code is unavailable. \(message)"
        case .commandFailed(_, let exitCode, let message):
            return message.isEmpty
                ? "Claude Code exited with status \(exitCode)."
                : message
        case .unexpectedOutput(let message):
            return "Claude Code returned an unexpected response. \(message)"
        case .confirmationRequired:
            return "This install needs an extra confirmation step."
        case .timedOut(let message):
            return message
        case .unsupportedCLI:
            return "This version of Claude Code does not support plugin management. Update Claude Code and try again."
        }
    }
}

public enum ClaudePluginInputError: Error, LocalizedError, Sendable {
    case missingSource
    case embeddedCredentials

    public var errorDescription: String? {
        switch self {
        case .missingSource:
            return "Enter a marketplace repository or path."
        case .embeddedCredentials:
            return "Remove the username or token from that URL. Use a credential helper or an SSH URL instead."
        }
    }
}

public enum ClaudeMarketplaceSource {
    /// Trims an add-source input and rejects inline credentials before the
    /// value is sent to the CLI or persisted as a favorite.
    public static func sanitized(_ raw: String) throws -> String {
        let value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { throw ClaudePluginInputError.missingSource }
        if let components = URLComponents(string: value),
           components.scheme != nil,
           components.user != nil || components.password != nil ||
               components.queryItems?.contains(where: { ClaudePluginText.isSensitiveQueryName($0.name) }) == true {
            throw ClaudePluginInputError.embeddedCredentials
        }
        return value
    }
}

public enum ClaudePluginText {
    private static let sensitiveQueryNames: Set<String> = [
        "token", "access_token", "auth", "authorization", "key", "apikey",
        "api_key", "password", "secret", "signature"
    ]

    fileprivate static func isSensitiveQueryName(_ name: String) -> Bool {
        sensitiveQueryNames.contains(name.lowercased())
    }

    fileprivate static func credentialFreeURL(_ text: String) -> String? {
        guard var components = URLComponents(string: text.trimmingCharacters(in: .whitespacesAndNewlines)),
              components.scheme != nil else { return nil }
        components.user = nil
        components.password = nil
        if let query = components.percentEncodedQueryItems {
            let safe = query.filter { !isSensitiveQueryName($0.name.removingPercentEncoding ?? $0.name) }
            if safe.count != query.count {
                components.percentEncodedQueryItems = safe.isEmpty ? nil : safe
            }
        }
        return components.string
    }

    /// Removes URL userinfo and redacts likely secret query values for display
    /// in errors and trust sheets. URLs embedded in longer messages are handled
    /// too, because CLI failures often put the URL mid-sentence.
    public static func redactingCredentials(in text: String) -> String {
        let direct = redactingSingleURL(in: text)
        if direct != text {
            return direct
        }

        guard let regex = try? NSRegularExpression(
            pattern: #"(?:https?|ssh|git)://[^\s"'<>]+"#
        ) else {
            return text
        }
        let fullRange = NSRange(text.startIndex..<text.endIndex, in: text)
        let matches = regex.matches(in: text, range: fullRange)
        guard !matches.isEmpty else { return text }

        var result = text
        for match in matches.reversed() {
            guard let range = Range(match.range, in: result) else { continue }
            let candidate = String(result[range])
            let redacted = redactingSingleURL(in: candidate)
            if redacted != candidate {
                result.replaceSubrange(range, with: redacted)
            }
        }
        return result
    }

    private static func redactingSingleURL(in text: String) -> String {
        guard var components = URLComponents(string: text) else { return text }
        var changed = false
        if components.user != nil || components.password != nil {
            components.user = nil
            components.password = nil
            changed = true
        }
        if let queryItems = components.queryItems {
            components.queryItems = queryItems.map { item in
                if isSensitiveQueryName(item.name) {
                    changed = true
                    return URLQueryItem(name: item.name, value: "REDACTED")
                }
                return item
            }
        }
        guard changed else { return text }
        return components.string ?? text
    }
}

// MARK: - Failable decoding

private struct FailableDecodable<Value: Decodable>: Decodable {
    let value: Value?

    init(from decoder: Decoder) throws {
        value = try? Value(from: decoder)
    }
}

// MARK: - Running the CLI

public protocol ClaudePluginCommandRunning: Sendable {
    func run(arguments: [String], timeout: TimeInterval) async throws -> ClaudePluginCommandResult
}

public struct ProcessClaudePluginRunner: ClaudePluginCommandRunning {
    public let executableURL: URL
    public let environment: [String: String]
    public let workingDirectory: URL
    private let outputLimit: Int

    public init(
        executableURL: URL,
        environment: [String: String],
        workingDirectory: URL,
        outputLimit: Int = 8 * 1024 * 1024
    ) {
        self.executableURL = executableURL
        self.environment = environment
        self.workingDirectory = workingDirectory
        self.outputLimit = outputLimit
    }

    /// Convenience initializer used by the app: sanitizes the login environment
    /// and runs from the home directory so project/local plugin settings are not
    /// picked up by user-scope management.
    public init(executableURL: URL) {
        var environment = ClaudeProcessEnvironment.make(executableURL: executableURL)
        for key in ["ANTHROPIC_API_KEY", "ANTHROPIC_AUTH_TOKEN", "ANTHROPIC_BASE_URL"] {
            environment.removeValue(forKey: key)
        }
        environment["GIT_TERMINAL_PROMPT"] = "0"
        environment["NO_COLOR"] = "1"
        self.init(
            executableURL: executableURL,
            environment: environment,
            workingDirectory: FileManager.default.homeDirectoryForCurrentUser
        )
    }

    public func run(arguments: [String], timeout: TimeInterval) async throws -> ClaudePluginCommandResult {
        guard FileManager.default.isExecutableFile(atPath: executableURL.path) else {
            throw ClaudePluginError.cliUnavailable(
                "The executable could not be found at \(executableURL.path)."
            )
        }

        let process = Process()
        process.executableURL = executableURL
        process.arguments = arguments
        process.currentDirectoryURL = workingDirectory
        process.environment = environment
        process.standardInput = FileHandle.nullDevice
        process.qualityOfService = .userInitiated

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        let stdout = BoundedOutput(limit: outputLimit)
        let stderr = BoundedOutput(limit: outputLimit)
        stdoutPipe.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            guard !data.isEmpty else {
                handle.readabilityHandler = nil
                stdout.markEndOfFile()
                return
            }
            stdout.append(data)
        }
        stderrPipe.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            guard !data.isEmpty else {
                handle.readabilityHandler = nil
                stderr.markEndOfFile()
                return
            }
            stderr.append(data)
        }

        do {
            defer {
                stdoutPipe.fileHandleForReading.readabilityHandler = nil
                stderrPipe.fileHandleForReading.readabilityHandler = nil
            }
            do {
                try process.run()
            } catch {
                throw ClaudePluginError.cliUnavailable(error.localizedDescription)
            }

            let deadline = Date().addingTimeInterval(max(timeout, 1))
            while process.isRunning {
                if Task.isCancelled {
                    await stop(process)
                    throw CancellationError()
                }
                if Date() >= deadline {
                    await stop(process)
                    throw ClaudePluginError.timedOut(
                        "Claude Code did not respond within \(Int(timeout)) seconds."
                    )
                }
                try? await Task.sleep(nanoseconds: 30_000_000)
            }

            // A descendant may still hold a write end open after Claude exits.
            let clock = ContinuousClock()
            let drainDeadline = clock.now + .seconds(1)
            while !(stdout.reachedEndOfFile && stderr.reachedEndOfFile), clock.now < drainDeadline {
                try await Task.sleep(for: .milliseconds(10))
            }
            try Task.checkCancellation()
        }

        if stdout.isTruncated || stderr.isTruncated {
            throw ClaudePluginError.unexpectedOutput(
                "Command output exceeded \(outputLimit) bytes."
            )
        }

        return ClaudePluginCommandResult(
            exitCode: process.terminationStatus,
            stdout: stdout.string,
            stderr: stderr.string
        )
    }

    private func stop(_ process: Process) async {
        guard process.isRunning else { return }
        process.terminate()

        let graceDeadline = Date().addingTimeInterval(1)
        while process.isRunning && Date() < graceDeadline {
            try? await Task.sleep(nanoseconds: 30_000_000)
        }
        if process.isRunning {
            kill(process.processIdentifier, SIGKILL)
        }
    }
}

private final class BoundedOutput: @unchecked Sendable {
    private let lock = NSLock()
    private let limit: Int
    private var data = Data()
    private var truncated = false
    private var endOfFile = false

    init(limit: Int) {
        self.limit = limit
    }

    func append(_ chunk: Data) {
        guard !chunk.isEmpty else { return }
        lock.lock()
        defer { lock.unlock() }
        let remaining = limit - data.count
        if remaining > 0 {
            data.append(chunk.prefix(remaining))
        }
        if chunk.count > remaining {
            truncated = true
        }
    }

    var isTruncated: Bool {
        lock.lock()
        defer { lock.unlock() }
        return truncated
    }

    func markEndOfFile() {
        lock.lock()
        defer { lock.unlock() }
        endOfFile = true
    }

    var reachedEndOfFile: Bool {
        lock.lock()
        defer { lock.unlock() }
        return endOfFile
    }

    var string: String {
        lock.lock()
        defer { lock.unlock() }
        return String(decoding: data, as: UTF8.self)
    }
}

// MARK: - Manager

/// Serializes `claude plugin` invocations and turns their JSON output into
/// models. Installed state belongs to Claude Code; this type never writes to
/// Claude's configuration itself.
public actor ClaudePluginManager {
    private let runner: any ClaudePluginCommandRunning
    private var isBusy = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    public init(runner: any ClaudePluginCommandRunning) {
        self.runner = runner
    }

    // MARK: Reads

    public func installedPlugins() async throws -> [ClaudeInstalledPlugin] {
        let arguments = ["plugin", "list", "--json"]
        let result = try await perform(arguments, timeout: 90)
        try Self.requireSuccess(result, arguments: arguments)
        return try Self.decodeInstalledList(result.stdout)
    }

    public func catalog() async throws -> ClaudePluginCatalog {
        let arguments = ["plugin", "list", "--json", "--available"]
        let result = try await perform(arguments, timeout: 90)
        try Self.requireSuccess(result, arguments: arguments)
        return try Self.decodeCatalog(result.stdout)
    }

    public func marketplaces() async throws -> [ClaudeMarketplace] {
        let arguments = ["plugin", "marketplace", "list", "--json"]
        let result = try await perform(arguments, timeout: 90)
        try Self.requireSuccess(result, arguments: arguments)
        return try Self.decodeMarketplaces(result.stdout)
    }

    // MARK: Marketplaces

    public func addMarketplace(_ source: String) async throws {
        let sanitized = try ClaudeMarketplaceSource.sanitized(source)
        let arguments = ["plugin", "marketplace", "add", sanitized, "--json", "--scope", "user"]
        let result = try await perform(arguments, timeout: 180)
        try Self.requireSuccess(result, arguments: arguments)
    }

    public func removeMarketplace(name: String) async throws {
        let arguments = ["plugin", "marketplace", "remove", name, "--json", "--scope", "user"]
        let result = try await perform(arguments, timeout: 60)
        try Self.requireSuccess(result, arguments: arguments)
    }

    public func refreshMarketplaces(name: String? = nil) async throws {
        var arguments = ["plugin", "marketplace", "update"]
        if let name, !name.isEmpty {
            arguments.append(name)
            arguments.append("--json")
        }
        let result = try await perform(arguments, timeout: 90)
        try Self.requireSuccess(result, arguments: arguments)
    }

    // MARK: Plugins

    public func install(pluginID: String, acceptCommandSHA256: String? = nil) async throws {
        var arguments = ["plugin", "install", pluginID, "--json", "--scope", "user"]
        if let acceptCommandSHA256, !acceptCommandSHA256.isEmpty {
            arguments.append(contentsOf: ["--accept-command", acceptCommandSHA256])
        }
        let result = try await perform(arguments, timeout: 180)
        try Self.requireSuccess(result, arguments: arguments)
    }

    public func uninstall(
        pluginID: String,
        scope: ClaudePluginScope = .user,
        keepData: Bool = true
    ) async throws {
        var arguments = ["plugin", "uninstall", pluginID, "--json", "--scope", scope.rawValue]
        if keepData {
            arguments.append("--keep-data")
        }
        let result = try await perform(arguments, timeout: 120)
        try Self.requireSuccess(result, arguments: arguments)
    }

    public func enable(pluginID: String, scope: ClaudePluginScope = .user) async throws {
        let arguments = ["plugin", "enable", pluginID, "--json", "--scope", scope.rawValue]
        let result = try await perform(arguments, timeout: 60)
        try Self.requireSuccess(result, arguments: arguments)
    }

    public func disable(pluginID: String, scope: ClaudePluginScope = .user) async throws {
        let arguments = ["plugin", "disable", pluginID, "--json", "--scope", scope.rawValue]
        let result = try await perform(arguments, timeout: 60)
        try Self.requireSuccess(result, arguments: arguments)
    }

    public func update(
        pluginID: String,
        scope: ClaudePluginScope = .user,
        acceptCommandSHA256: String? = nil
    ) async throws {
        var arguments = ["plugin", "update", pluginID, "--json", "--scope", scope.rawValue]
        if let acceptCommandSHA256, !acceptCommandSHA256.isEmpty {
            arguments.append(contentsOf: ["--accept-command", acceptCommandSHA256])
        }
        let result = try await perform(arguments, timeout: 180)
        try Self.requireSuccess(result, arguments: arguments)
    }

    // MARK: Authoring

    public func validate(path: URL) async throws -> ClaudePluginValidationResult {
        let jsonArguments = ["plugin", "validate", path.path, "--json"]
        let first = try await perform(jsonArguments, timeout: 60)

        if first.exitCode == 0 {
            return ClaudePluginValidationResult(succeeded: true, output: Self.displayOutput(first))
        }

        if Self.indicatesUnknownJSONOption(first) {
            let plainArguments = ["plugin", "validate", path.path]
            let second = try await perform(plainArguments, timeout: 60)
            if Self.indicatesUnsupportedCLI(second) {
                throw ClaudePluginError.unsupportedCLI
            }
            return ClaudePluginValidationResult(
                succeeded: second.exitCode == 0,
                output: Self.displayOutput(second)
            )
        }

        if Self.indicatesUnsupportedCLI(first) {
            throw ClaudePluginError.unsupportedCLI
        }
        return ClaudePluginValidationResult(succeeded: false, output: Self.displayOutput(first))
    }

    public func test(path: URL) async throws -> ClaudePluginValidationResult {
        let arguments = ["plugin", "test", path.path]
        let result = try await perform(arguments, timeout: 300)
        if Self.indicatesUnsupportedCLI(result) {
            throw ClaudePluginError.unsupportedCLI
        }
        return ClaudePluginValidationResult(
            succeeded: result.exitCode == 0,
            output: Self.displayOutput(result)
        )
    }

    // MARK: Serialization

    private func perform(
        _ arguments: [String],
        timeout: TimeInterval
    ) async throws -> ClaudePluginCommandResult {
        await acquire()
        defer { release() }
        return try await runner.run(arguments: arguments, timeout: timeout)
    }

    private func acquire() async {
        if !isBusy {
            isBusy = true
            return
        }
        await withCheckedContinuation { continuation in
            waiters.append(continuation)
        }
    }

    private func release() {
        if waiters.isEmpty {
            isBusy = false
        } else {
            waiters.removeFirst().resume()
        }
    }

    // MARK: Parsing

    private struct RawCatalog: Decodable {
        var installed: [FailableDecodable<ClaudeInstalledPlugin>]?
        var available: [FailableDecodable<ClaudeAvailablePlugin>]?
    }

    private struct ConfirmationEnvelope: Decodable {
        var shownCommand: ShownCommand?
        var message: String?
        var error: String?
    }

    private struct ShownCommand: Decodable {
        var command: String
        var sha256: String?
    }

    static func decodeInstalledList(_ stdout: String) throws -> [ClaudeInstalledPlugin] {
        guard let data = lastJSONData(in: stdout) else {
            throw ClaudePluginError.unexpectedOutput("The plugin list was empty or not JSON.")
        }
        do {
            let entries = try JSONDecoder().decode([FailableDecodable<ClaudeInstalledPlugin>].self, from: data)
            return entries.compactMap(\.value)
        } catch {
            throw ClaudePluginError.unexpectedOutput("The plugin list could not be read.")
        }
    }

    static func decodeCatalog(_ stdout: String) throws -> ClaudePluginCatalog {
        guard let data = lastJSONData(in: stdout) else {
            throw ClaudePluginError.unexpectedOutput("The plugin catalog was empty or not JSON.")
        }
        do {
            let raw = try JSONDecoder().decode(RawCatalog.self, from: data)
            return ClaudePluginCatalog(
                installed: (raw.installed ?? []).compactMap(\.value),
                available: (raw.available ?? []).compactMap(\.value)
            )
        } catch {
            throw ClaudePluginError.unexpectedOutput("The plugin catalog could not be read.")
        }
    }

    static func decodeMarketplaces(_ stdout: String) throws -> [ClaudeMarketplace] {
        guard let data = lastJSONData(in: stdout) else {
            throw ClaudePluginError.unexpectedOutput("The marketplace list was empty or not JSON.")
        }
        do {
            let entries = try JSONDecoder().decode([FailableDecodable<ClaudeMarketplace>].self, from: data)
            return entries.compactMap(\.value)
        } catch {
            throw ClaudePluginError.unexpectedOutput("The marketplace list could not be read.")
        }
    }

    static func lastJSONData(in output: String) -> Data? {
        let trimmed = output.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        if let data = trimmed.data(using: .utf8), isJSON(data) {
            return data
        }
        for line in trimmed.split(whereSeparator: \.isNewline).reversed() {
            let candidate = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard candidate.hasPrefix("{") || candidate.hasPrefix("[") else { continue }
            if let data = candidate.data(using: .utf8), isJSON(data) {
                return data
            }
        }
        return nil
    }

    private static func isJSON(_ data: Data) -> Bool {
        (try? JSONSerialization.jsonObject(with: data)) != nil
    }

    // MARK: Success and errors

    private static func requireSuccess(
        _ result: ClaudePluginCommandResult,
        arguments: [String]
    ) throws {
        guard result.exitCode != 0 else { return }

        if let prompt = confirmationPrompt(in: result) {
            throw ClaudePluginError.confirmationRequired(
                command: prompt.command,
                sha256: prompt.sha256
            )
        }
        if indicatesUnsupportedCLI(result) {
            throw ClaudePluginError.unsupportedCLI
        }
        throw ClaudePluginError.commandFailed(
            arguments: arguments,
            exitCode: result.exitCode,
            message: errorMessage(from: result)
        )
    }

    private static func confirmationPrompt(in result: ClaudePluginCommandResult) -> ShownCommand? {
        for output in [result.stdout, result.stderr] {
            guard let data = lastJSONData(in: output),
                  let envelope = try? JSONDecoder().decode(ConfirmationEnvelope.self, from: data),
                  let command = envelope.shownCommand?.command,
                  !command.isEmpty else { continue }
            return envelope.shownCommand
        }
        return nil
    }

    private static func errorMessage(from result: ClaudePluginCommandResult) -> String {
        for output in [result.stdout, result.stderr] {
            guard let data = lastJSONData(in: output),
                  let envelope = try? JSONDecoder().decode(ConfirmationEnvelope.self, from: data) else {
                continue
            }
            if let error = envelope.error, !error.isEmpty {
                return ClaudePluginText.redactingCredentials(in: truncated(error, limit: 2_000))
            }
            if let message = envelope.message, !message.isEmpty {
                return ClaudePluginText.redactingCredentials(in: truncated(message, limit: 2_000))
            }
        }

        let combined = result.stderr.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? result.stdout
            : result.stderr
        let message = combined.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !message.isEmpty else { return "" }
        return ClaudePluginText.redactingCredentials(in: truncated(message, limit: 2_000))
    }

    private static func indicatesUnsupportedCLI(_ result: ClaudePluginCommandResult) -> Bool {
        guard result.exitCode != 0 else { return false }
        let text = "\(result.stdout)\n\(result.stderr)".lowercased()
        return text.contains("unknown command")
            || text.contains("unknown option")
            || text.contains("unknown argument")
            || text.contains("unrecognized command")
            || text.contains("unrecognized option")
            || text.contains("not a recognized")
    }

    private static func indicatesUnknownJSONOption(_ result: ClaudePluginCommandResult) -> Bool {
        let text = "\(result.stdout)\n\(result.stderr)".lowercased()
        guard text.contains("--json") else { return false }
        return text.contains("unknown option")
            || text.contains("unknown argument")
            || text.contains("unrecognized option")
            || text.contains("unrecognized argument")
    }

    private static func displayOutput(_ result: ClaudePluginCommandResult) -> String {
        let combined = [result.stdout, result.stderr]
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: "\n\n")
        return combined.isEmpty ? "Claude Code exited with status \(result.exitCode)." : combined
    }

    private static func truncated(_ text: String, limit: Int) -> String {
        guard text.count > limit else { return text }
        return String(text.prefix(limit)) + "…"
    }
}

// MARK: - Favorites matching

extension FavoriteMarketplace {
    public init(marketplace: ClaudeMarketplace) {
        self.init(name: marketplace.name, source: marketplace.stableKey)
    }

    public func matches(_ marketplace: ClaudeMarketplace) -> Bool {
        matches(name: marketplace.name, sourceKey: marketplace.stableKey)
    }

    public func matches(name: String, sourceKey: String?) -> Bool {
        // Older favorites used the source kind when the location was unknown.
        if source?.hasPrefix("source:") == true {
            return self.name == name
        }
        if let source, !source.isEmpty, let sourceKey, !sourceKey.isEmpty {
            return source == sourceKey
        }
        return self.name == name
    }
}
