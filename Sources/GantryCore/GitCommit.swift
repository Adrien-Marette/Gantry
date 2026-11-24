import Foundation

/// The result of one `git` invocation.
public struct GitCommandResult: Hashable, Sendable {
    public var exitCode: Int32
    public var stdout: String
    public var stderr: String

    public init(exitCode: Int32, stdout: String = "", stderr: String = "") {
        self.exitCode = exitCode
        self.stdout = stdout
        self.stderr = stderr
    }

    public var combinedOutput: String {
        let out = stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        let err = stderr.trimmingCharacters(in: .whitespacesAndNewlines)
        if out.isEmpty { return err }
        if err.isEmpty { return out }
        return out + "\n" + err
    }
}

/// A seam for tests. The app uses `GitProcessRunner`.
public protocol GitCommandRunning: Sendable {
    func runGit(_ arguments: [String], in directory: URL) async throws -> GitCommandResult
}

public enum GitCommitError: LocalizedError, Hashable, Sendable {
    case gitUnavailable(String)
    case emptyMessage
    case noFiles
    case commandFailed(String)

    public var errorDescription: String? {
        switch self {
        case .gitUnavailable(let message):
            return message
        case .emptyMessage:
            return "Add a commit message first."
        case .noFiles:
            return "There are no project files to commit."
        case .commandFailed(let output):
            let trimmed = TextSanitizer.stripANSI(output)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? "Git could not complete the commit." : trimmed
        }
    }
}

/// The files Gantry will commit. Only paths inside the project are included;
/// files outside it are reported separately instead of being silently skipped.
public struct GitCommitPlan: Hashable, Sendable {
    public var paths: [String]
    public var excludedDisplayPaths: [String]
    public var includedFileIDs: Set<String>

    public init(
        paths: [String],
        excludedDisplayPaths: [String],
        includedFileIDs: Set<String> = []
    ) {
        self.paths = paths
        self.excludedDisplayPaths = excludedDisplayPaths
        self.includedFileIDs = includedFileIDs
    }

    public var isEmpty: Bool { paths.isEmpty }
}

/// Stages and commits exactly the reviewed files.
///
/// Safety rules:
/// - only paths inside the project are committed;
/// - the commit uses a pathspec, so unrelated staged work is left alone;
/// - it never passes `--no-verify`, `--no-gpg-sign`, or any signing override;
/// - it never pushes, amends, or rewrites history.
public struct GitCommitService: Sendable {
    private let runner: any GitCommandRunning

    public init(runner: any GitCommandRunning = GitProcessRunner()) {
        self.runner = runner
    }

    public static func plan(
        files: [ReviewedFile],
        projectPath: String
    ) -> GitCommitPlan {
        let root = URL(fileURLWithPath: projectPath).standardizedFileURL
        let rootPath = root.path
        let prefix = rootPath.hasSuffix("/") ? rootPath : rootPath + "/"

        var seen = Set<String>()
        var paths: [String] = []
        var excluded: [String] = []
        var includedFileIDs = Set<String>()

        for file in files {
            let expanded = (file.path as NSString).expandingTildeInPath
            let resolved: URL
            if expanded.hasPrefix("/") {
                resolved = URL(fileURLWithPath: expanded)
            } else {
                resolved = root.appendingPathComponent(expanded)
            }
            let standardized = resolved.standardizedFileURL.path

            guard standardized == rootPath || standardized.hasPrefix(prefix) else {
                excluded.append(file.displayPath)
                continue
            }
            // A reviewed file that has since become a directory would make a
            // pathspec commit sweep in unreviewed descendants.
            var isDirectory: ObjCBool = false
            if FileManager.default.fileExists(atPath: standardized, isDirectory: &isDirectory),
               isDirectory.boolValue {
                excluded.append(file.displayPath)
                continue
            }
            let relative = standardized == rootPath
                ? URL(fileURLWithPath: standardized).lastPathComponent
                : String(standardized.dropFirst(prefix.count))
            guard !relative.isEmpty, relative != "..", !relative.hasPrefix("../") else {
                excluded.append(file.displayPath)
                continue
            }
            if seen.insert(relative).inserted {
                paths.append(relative)
                includedFileIDs.insert(file.id)
            }
        }

        return GitCommitPlan(
            paths: paths,
            excludedDisplayPaths: excluded,
            includedFileIDs: includedFileIDs
        )
    }

    @discardableResult
    public func commit(
        message: String,
        files: [ReviewedFile],
        in projectURL: URL
    ) async throws -> String {
        let trimmedMessage = message.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedMessage.isEmpty else { throw GitCommitError.emptyMessage }

        let plan = Self.plan(files: files, projectPath: projectURL.path)
        guard !plan.isEmpty else { throw GitCommitError.noFiles }

        // Literal pathspec magic keeps filenames containing glob characters
        // exact without changing global Git behavior for hooks.
        let literalPaths = plan.paths.map { ":(literal)\($0)" }
        let add = try await runner.runGit(
            ["add", "--"] + literalPaths,
            in: projectURL
        )
        guard add.exitCode == 0 else {
            throw GitCommitError.commandFailed(add.combinedOutput)
        }

        let commit = try await runner.runGit(
            ["commit", "-m", trimmedMessage, "--"] + literalPaths,
            in: projectURL
        )
        guard commit.exitCode == 0 else {
            throw GitCommitError.commandFailed(commit.combinedOutput)
        }

        let output = TextSanitizer.stripANSI(commit.combinedOutput)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if output.isEmpty {
            let noun = plan.paths.count == 1 ? "file" : "files"
            return "Committed \(plan.paths.count) \(noun)."
        }
        return output
    }
}

/// Runs `/usr/bin/git` without a shell. Output is written to temporary files
/// so a full pipe can never block the child process.
public struct GitProcessRunner: GitCommandRunning {
    public var executableURL: URL

    public init(executableURL: URL = URL(fileURLWithPath: "/usr/bin/git")) {
        self.executableURL = executableURL
    }

    public func runGit(_ arguments: [String], in directory: URL) async throws -> GitCommandResult {
        guard FileManager.default.isExecutableFile(atPath: executableURL.path) else {
            throw GitCommitError.gitUnavailable(
                "Git was not found at \(executableURL.path). Install the Xcode command-line tools and try again."
            )
        }

        let token = UUID().uuidString
        let temp = FileManager.default.temporaryDirectory
        let stdoutURL = temp.appendingPathComponent("gantry-git-\(token).out")
        let stderrURL = temp.appendingPathComponent("gantry-git-\(token).err")
        defer {
            try? FileManager.default.removeItem(at: stdoutURL)
            try? FileManager.default.removeItem(at: stderrURL)
        }
        let stdoutHandle = try makeOutputFile(at: stdoutURL)
        let stderrHandle = try makeOutputFile(at: stderrURL)

        let process = Process()
        process.executableURL = executableURL
        process.arguments = arguments
        process.currentDirectoryURL = directory
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = stdoutHandle
        process.standardError = stderrHandle

        var environment = ClaudeProcessEnvironment.make(executableURL: executableURL)
        environment["GIT_TERMINAL_PROMPT"] = "0"
        environment["GIT_PAGER"] = "cat"
        environment["NO_COLOR"] = "1"
        process.environment = environment

        do {
            try await withCheckedThrowingContinuation { continuation in
                process.terminationHandler = { _ in
                    continuation.resume()
                }
                do {
                    try process.run()
                } catch {
                    process.terminationHandler = nil
                    continuation.resume(throwing: GitCommitError.gitUnavailable(
                        "Git could not start: \(error.localizedDescription)"
                    ))
                }
            }
        } catch {
            try? stdoutHandle.close()
            try? stderrHandle.close()
            throw error
        }

        try? stdoutHandle.close()
        try? stderrHandle.close()

        return GitCommandResult(
            exitCode: process.terminationStatus,
            stdout: readText(at: stdoutURL),
            stderr: readText(at: stderrURL)
        )
    }

    private func makeOutputFile(at url: URL) throws -> FileHandle {
        guard FileManager.default.createFile(atPath: url.path, contents: nil) else {
            throw GitCommitError.commandFailed("Could not prepare a temporary file for Git output.")
        }
        return try FileHandle(forWritingTo: url)
    }

    private func readText(at url: URL) -> String {
        (try? String(contentsOf: url, encoding: .utf8)) ?? ""
    }
}
