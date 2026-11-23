import Foundation

public enum ClaudeLocator {
    /// Finds the Claude Code executable. Call from a background task: the login-shell
    /// fallback can take a moment on machines with a large shell profile.
    public static func locate(
        override: String? = nil,
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> URL? {
        var candidates: [String] = []
        if let override, !override.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            candidates.append(expandTilde(override.trimmingCharacters(in: .whitespacesAndNewlines)))
        }
        if let envPath = environment["Gantry_CLAUDE_PATH"] ?? environment["CLAUDE_CODE_PATH"] {
            candidates.append(expandTilde(envPath))
        }
        if let path = environment["PATH"] {
            for directory in path.split(separator: ":") {
                candidates.append(String(directory) + "/claude")
            }
        }
        let home = environment["HOME"] ?? NSHomeDirectory()
        candidates.append(contentsOf: [
            "\(home)/.local/bin/claude",
            "\(home)/.claude/local/claude",
            "\(home)/.bun/bin/claude",
            "\(home)/.volta/bin/claude",
            "/opt/homebrew/bin/claude",
            "/usr/local/bin/claude",
            "/usr/bin/claude"
        ])

        for candidate in candidates {
            if isExecutable(candidate) {
                return URL(fileURLWithPath: candidate)
            }
        }

        if let fromShell = locateViaLoginShell(environment: environment) {
            return fromShell
        }
        return nil
    }

    public static func version(at executableURL: URL) -> String? {
        guard let result = runAndCapture(
            executable: executableURL,
            arguments: ["--version"],
            timeout: 5
        ) else { return nil }
        let value = result.trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }

    public static func expandTilde(_ path: String) -> String {
        NSString(string: path).expandingTildeInPath
    }

    private static func isExecutable(_ path: String) -> Bool {
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory), !isDirectory.boolValue else {
            return false
        }
        return FileManager.default.isExecutableFile(atPath: path)
    }

    private static func locateViaLoginShell(environment: [String: String]) -> URL? {
        let shell = environment["SHELL"] ?? "/bin/zsh"
        for shellArgs in [["-lc", "command -v claude"], ["-ic", "command -v claude"]] {
            guard let result = runAndCapture(
                executable: URL(fileURLWithPath: shell),
                arguments: shellArgs,
                timeout: 4,
                environment: environment
            ) else { continue }
            let lines = result
                .split(whereSeparator: \.isNewline)
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { $0.hasPrefix("/") }
            for path in lines.reversed() where isExecutable(path) {
                return URL(fileURLWithPath: path)
            }
        }
        return nil
    }

    private static func runAndCapture(
        executable: URL,
        arguments: [String],
        timeout: TimeInterval,
        environment: [String: String]? = nil
    ) -> String? {
        let process = Process()
        process.executableURL = executable
        process.arguments = arguments
        if let environment {
            process.environment = environment
        }
        let output = Pipe()
        let errors = Pipe()
        process.standardOutput = output
        process.standardError = errors
        process.standardInput = FileHandle.nullDevice

        do {
            try process.run()
        } catch {
            return nil
        }

        let deadline = Date().addingTimeInterval(timeout)
        while process.isRunning, Date() < deadline {
            Thread.sleep(forTimeInterval: 0.04)
        }
        if process.isRunning {
            process.terminate()
            Thread.sleep(forTimeInterval: 0.1)
            if process.isRunning {
                kill(process.processIdentifier, SIGKILL)
            }
            return nil
        }

        let data = output.fileHandleForReading.readDataToEndOfFile()
        _ = errors.fileHandleForReading.readDataToEndOfFile()
        return String(data: data, encoding: .utf8)
    }
}

public struct ClaudeLaunchConfiguration: Sendable {
    public var executableURL: URL
    public var workingDirectory: URL
    public var claudeSessionID: UUID
    public var resume: Bool
    public var model: ModelChoice
    public var permissionMode: PermissionMode
    public var extraArguments: [String]
    public var environmentOverrides: [String: String]
    public var removedEnvironmentKeys: [String]

    public init(
        executableURL: URL,
        workingDirectory: URL,
        claudeSessionID: UUID,
        resume: Bool,
        model: ModelChoice,
        permissionMode: PermissionMode,
        extraArguments: [String] = [],
        environmentOverrides: [String: String] = [:],
        removedEnvironmentKeys: [String] = []
    ) {
        self.executableURL = executableURL
        self.workingDirectory = workingDirectory
        self.claudeSessionID = claudeSessionID
        self.resume = resume
        self.model = model
        self.permissionMode = permissionMode
        self.extraArguments = extraArguments
        self.environmentOverrides = environmentOverrides
        self.removedEnvironmentKeys = removedEnvironmentKeys
    }

    public var arguments: [String] {
        var args = [
            "--output-format", "stream-json",
            "--verbose",
            "--input-format", "stream-json",
            "--permission-prompt-tool=stdio",
            "--include-partial-messages",
            "--permission-mode", permissionMode.cliValue
        ]
        if let model = model.cliValue {
            args.append(contentsOf: ["--model", model])
        }
        if resume {
            args.append(contentsOf: ["--resume", claudeSessionID.uuidString])
        } else {
            args.append(contentsOf: ["--session-id", claudeSessionID.uuidString])
        }
        args.append(contentsOf: extraArguments)
        return args
    }
}

public enum ClaudeProcessEnvironment {
    public static func make(
        base: [String: String] = ProcessInfo.processInfo.environment,
        executableURL: URL
    ) -> [String: String] {
        var environment = base
        // A host app may itself have been launched by Claude Code. Do not let that
        // nested context leak into the background agent process.
        for key in [
            "CLAUDECODE",
            "CLAUDE_CODE_ENTRYPOINT",
            "CLAUDE_CODE_SESSION_ID",
            "CLAUDE_CODE_SSE_PORT",
            "CLAUDE_CODE_ADDITIONAL_DIRECTORIES",
            "CLAUDE_CODE_ASYNC_AGENT_STDOUT"
        ] {
            environment.removeValue(forKey: key)
        }

        let home = base["HOME"] ?? NSHomeDirectory()
        let required = [
            executableURL.deletingLastPathComponent().path,
            "\(home)/.local/bin",
            "\(home)/.bun/bin",
            "/opt/homebrew/bin",
            "/usr/local/bin",
            "/usr/bin",
            "/bin",
            "/usr/sbin",
            "/sbin"
        ]
        let existing = (base["PATH"] ?? "").split(separator: ":").map(String.init)
        var seen = Set<String>()
        let merged = (required + existing).filter { path in
            !path.isEmpty && seen.insert(path).inserted
        }
        environment["PATH"] = merged.joined(separator: ":")
        if environment["TERM"] == nil {
            environment["TERM"] = "xterm-256color"
        }
        return environment
    }
}
