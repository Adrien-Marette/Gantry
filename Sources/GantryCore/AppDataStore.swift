import Foundation

public struct GantryPaths: Sendable {
    public var supportDirectory: URL
    public var stateFile: URL
    public var logsDirectory: URL

    public init(
        supportDirectory: URL = GantryPaths.defaultSupportDirectory(),
        logsDirectory: URL? = nil
    ) {
        self.supportDirectory = supportDirectory
        self.stateFile = supportDirectory.appendingPathComponent("state.json", isDirectory: false)
        self.logsDirectory = logsDirectory ?? GantryPaths.defaultLogsDirectory()
    }

    public static func defaultSupportDirectory() -> URL {
        if let override = ProcessInfo.processInfo.environment["Gantry_STATE_DIR"], !override.isEmpty {
            return URL(fileURLWithPath: ClaudeLocator.expandTilde(override), isDirectory: true)
        }
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Application Support")
        return base.appendingPathComponent("Gantry", isDirectory: true)
    }

    public static func defaultLogsDirectory() -> URL {
        let base = FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library")
        return base.appendingPathComponent("Logs/Gantry", isDirectory: true)
    }
}

public struct AppDataStore: Sendable {
    public let paths: GantryPaths

    public init(paths: GantryPaths = GantryPaths()) {
        self.paths = paths
    }

    public func load() throws -> AppSnapshot? {
        guard FileManager.default.fileExists(atPath: paths.stateFile.path) else {
            return nil
        }
        let data = try Data(contentsOf: paths.stateFile)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(AppSnapshot.self, from: data)
    }

    public func save(_ snapshot: AppSnapshot) throws {
        try FileManager.default.createDirectory(
            at: paths.supportDirectory,
            withIntermediateDirectories: true
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(snapshot)
        try data.write(to: paths.stateFile, options: .atomic)
        try? FileManager.default.setAttributes(
            [.posixPermissions: 0o600],
            ofItemAtPath: paths.stateFile.path
        )
    }

    public func quarantineUnreadableState() -> URL? {
        guard FileManager.default.fileExists(atPath: paths.stateFile.path) else { return nil }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        let stamp = formatter.string(from: Date())
            .replacingOccurrences(of: ":", with: "-")
        let destination = paths.supportDirectory
            .appendingPathComponent("state-unreadable-\(stamp).json")
        do {
            try FileManager.default.copyItem(at: paths.stateFile, to: destination)
            return destination
        } catch {
            return nil
        }
    }

    public func logURL(for sessionID: UUID) -> URL {
        paths.logsDirectory.appendingPathComponent("claude-\(sessionID.uuidString).log")
    }
}
