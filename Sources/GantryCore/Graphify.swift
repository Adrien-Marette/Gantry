import Foundation

/// Graphify is an optional local tool that indexes a project into a
/// knowledge graph. Gantry never bundles it: it detects the user's install,
/// can run the documented `uv` install after confirmation, and gives a
/// project's chats the graph MCP server once a graph exists.
public enum GraphifyCommand {
    public static func version() -> [String] {
        ["--version"]
    }

    public static func update(projectURL: URL) -> [String] {
        ["update", projectURL.standardizedFileURL.path]
    }

    public static func query(_ question: String, graphURL: URL) -> [String] {
        ["query", question, "--graph", graphURL.standardizedFileURL.path]
    }

    public static func installMCP(force: Bool = false) -> [String] {
        var arguments = ["tool", "install"]
        if force {
            arguments.append("--force")
        }
        arguments.append("graphifyy[mcp]")
        return arguments
    }

    public static func installMCPDisplay(force: Bool = false) -> String {
        force
            ? "uv tool install --force \"graphifyy[mcp]\""
            : "uv tool install \"graphifyy[mcp]\""
    }
}

public enum GraphifyLocator {
    public static func locateCLI(
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> URL? {
        locate("graphify", environment: environment)
    }

    public static func locateMCP(
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> URL? {
        locate("graphify-mcp", environment: environment)
    }

    public static func locateUV(
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> URL? {
        locate("uv", environment: environment)
    }

    // shortcut: custom install locations outside PATH and the usual bin
    // directories are not found; add a login-shell lookup if that bites.
    static func locate(
        _ name: String,
        environment: [String: String],
        includeStandardDirectories: Bool = true
    ) -> URL? {
        var candidates = (environment["PATH"] ?? "")
            .split(separator: ":")
            .map { "\($0)/\(name)" }
        let home = environment["HOME"] ?? NSHomeDirectory()
        candidates.append("\(home)/.local/bin/\(name)")
        if includeStandardDirectories {
            candidates.append(contentsOf: [
                "/opt/homebrew/bin/\(name)",
                "/usr/local/bin/\(name)"
            ])
        }

        for candidate in candidates where isExecutable(candidate) {
            return URL(fileURLWithPath: candidate)
        }
        return nil
    }

    private static func isExecutable(_ path: String) -> Bool {
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory),
              !isDirectory.boolValue else {
            return false
        }
        return FileManager.default.isExecutableFile(atPath: path)
    }
}

public enum GraphifyIntegration {
    public static func graphURL(forProject projectURL: URL) -> URL {
        projectURL.standardizedFileURL
            .appendingPathComponent("graphify-out", isDirectory: true)
            .appendingPathComponent("graph.json")
    }

    /// The MCP server entry for a project's built graph, or nil when there is
    /// nothing to serve. The graph path is absolute so the server does not
    /// depend on the CLI's working directory.
    public static func mcpServer(
        forProject projectURL: URL,
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> [String: Any]? {
        let graphURL = graphURL(forProject: projectURL)
        guard FileManager.default.fileExists(atPath: graphURL.path),
              let executable = GraphifyLocator.locateMCP(environment: environment) else {
            return nil
        }
        return [
            "command": executable.path,
            "args": [graphURL.path]
        ]
    }
}

public struct GraphifyStatus: Hashable, Sendable {
    public var projectURL: URL
    public var cliURL: URL?
    public var mcpURL: URL?
    public var uvURL: URL?
    public var graphURL: URL
    public var graphExists: Bool
    public var graphModifiedAt: Date?
    public var graphByteCount: Int64?
    public var htmlURL: URL?

    public static func read(
        projectURL: URL,
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> GraphifyStatus {
        let project = projectURL.standardizedFileURL
        let graphURL = GraphifyIntegration.graphURL(forProject: project)
        let attributes = try? FileManager.default.attributesOfItem(atPath: graphURL.path)
        let htmlURL = project
            .appendingPathComponent("graphify-out", isDirectory: true)
            .appendingPathComponent("graph.html")

        return GraphifyStatus(
            projectURL: project,
            cliURL: GraphifyLocator.locateCLI(environment: environment),
            mcpURL: GraphifyLocator.locateMCP(environment: environment),
            uvURL: GraphifyLocator.locateUV(environment: environment),
            graphURL: graphURL,
            graphExists: attributes != nil,
            graphModifiedAt: attributes?[.modificationDate] as? Date,
            graphByteCount: (attributes?[.size] as? NSNumber)?.int64Value,
            htmlURL: FileManager.default.fileExists(atPath: htmlURL.path) ? htmlURL : nil
        )
    }
}

public struct GraphifyProcessResult: Hashable, Sendable {
    public var exitCode: Int32
    public var output: String
    public var timedOut: Bool

    public init(exitCode: Int32, output: String = "", timedOut: Bool = false) {
        self.exitCode = exitCode
        self.output = output
        self.timedOut = timedOut
    }
}

public enum GraphifyProcessError: LocalizedError, Sendable {
    case launchFailed(String)

    public var errorDescription: String? {
        switch self {
        case .launchFailed(let message):
            return message
        }
    }
}

public enum GraphifyProcess {
    /// Runs Graphify without a shell. Output goes to temporary files so a full
    /// pipe can never block the child, matching the Git runner.
    public static func run(
        executable: URL,
        arguments: [String],
        workingDirectory: URL? = nil,
        timeout: TimeInterval = 120,
        environment baseEnvironment: [String: String] = ProcessInfo.processInfo.environment
    ) async throws -> GraphifyProcessResult {
        try await Task.detached(priority: .userInitiated) { () throws -> GraphifyProcessResult in
            guard FileManager.default.isExecutableFile(atPath: executable.path) else {
                throw GraphifyProcessError.launchFailed(
                    "\(executable.lastPathComponent) was not found at \(executable.path)."
                )
            }

            let token = UUID().uuidString
            let temporary = FileManager.default.temporaryDirectory
            let stdoutURL = temporary.appendingPathComponent("gantry-graphify-\(token).out")
            let stderrURL = temporary.appendingPathComponent("gantry-graphify-\(token).err")
            defer {
                try? FileManager.default.removeItem(at: stdoutURL)
                try? FileManager.default.removeItem(at: stderrURL)
            }

            guard FileManager.default.createFile(atPath: stdoutURL.path, contents: nil),
                  FileManager.default.createFile(atPath: stderrURL.path, contents: nil) else {
                throw GraphifyProcessError.launchFailed(
                    "Could not prepare a temporary file for Graphify output."
                )
            }
            let stdoutHandle = try FileHandle(forWritingTo: stdoutURL)
            let stderrHandle = try FileHandle(forWritingTo: stderrURL)

            let process = Process()
            process.executableURL = executable
            process.arguments = arguments
            process.currentDirectoryURL = workingDirectory
            process.standardInput = FileHandle.nullDevice
            process.standardOutput = stdoutHandle
            process.standardError = stderrHandle

            var environment = ClaudeProcessEnvironment.make(
                base: baseEnvironment,
                executableURL: executable
            )
            environment["NO_COLOR"] = "1"
            process.environment = environment

            do {
                try process.run()
            } catch {
                try? stdoutHandle.close()
                try? stderrHandle.close()
                throw GraphifyProcessError.launchFailed(
                    "\(executable.lastPathComponent) could not start: \(error.localizedDescription)"
                )
            }

            let deadline = Date().addingTimeInterval(max(0.05, timeout))
            while process.isRunning && Date() < deadline {
                try? await Task.sleep(for: .milliseconds(50))
            }

            var timedOut = false
            if process.isRunning {
                timedOut = true
                process.terminate()
                let killDeadline = Date().addingTimeInterval(2)
                while process.isRunning && Date() < killDeadline {
                    try? await Task.sleep(for: .milliseconds(50))
                }
                if process.isRunning {
                    kill(process.processIdentifier, SIGKILL)
                }
            }
            process.waitUntilExit()

            try? stdoutHandle.close()
            try? stderrHandle.close()

            let stdout = TextSanitizer.stripANSI(readText(at: stdoutURL))
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let stderr = TextSanitizer.stripANSI(readText(at: stderrURL))
                .trimmingCharacters(in: .whitespacesAndNewlines)

            return GraphifyProcessResult(
                exitCode: process.terminationStatus,
                output: [stdout, stderr].filter { !$0.isEmpty }.joined(separator: "\n"),
                timedOut: timedOut
            )
        }.value
    }

    /// A page never needs a full build log, and capping keeps a runaway
    /// command from filling memory.
    private static let outputLimit = 262_144

    private static func readText(at url: URL) -> String {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return "" }
        defer { try? handle.close() }
        let data = (try? handle.read(upToCount: outputLimit)) ?? Data()
        return String(decoding: data, as: UTF8.self)
    }
}
