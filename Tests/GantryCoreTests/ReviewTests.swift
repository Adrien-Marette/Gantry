import Foundation
import Testing
@testable import GantryCore

private func tool(
    id: String,
    name: String,
    input: [String: JSONValue],
    status: ToolStatus = .completed,
    isError: Bool = false,
    structured: JSONValue? = nil
) -> ToolActivity {
    ToolActivity(
        id: id,
        name: name,
        input: .object(input),
        status: status,
        structuredResult: structured,
        isError: isError
    )
}

private func session(with tools: [ToolActivity]) -> ChatSession {
    ChatSession(turns: [
        ConversationTurn(
            role: .assistant,
            blocks: tools.map(MessageBlock.makeTool)
        )
    ])
}

private func reviewedFile(_ path: String, displayPath: String) -> ReviewedFile {
    ReviewedFile(
        path: path,
        displayPath: displayPath,
        changes: [
            ReviewedChange(
                id: "\(path)-0",
                toolName: "Edit",
                oldText: "old",
                newText: "new"
            )
        ]
    )
}

@Test func buildsReviewFromCompletedFileTools() {
    let project = "/tmp/gantry-review"
    let review = SessionReview.build(
        session: session(with: [
            tool(
                id: "e1",
                name: "Edit",
                input: [
                    "file_path": .string("\(project)/Sources/A.swift"),
                    "old_string": .string("let a = 1"),
                    "new_string": .string("let a = 2\nlet b = 3")
                ]
            ),
            tool(
                id: "w1",
                name: "Write",
                input: [
                    "file_path": .string("\(project)/Sources/B.swift"),
                    "content": .string("struct B {}\n")
                ],
                structured: .object(["type": .string("create")])
            ),
            tool(
                id: "m1",
                name: "MultiEdit",
                input: [
                    "file_path": .string("\(project)/Sources/A.swift"),
                    "edits": .array([
                        .object([
                            "file_path": .string("\(project)/Sources/A.swift"),
                            "old_string": .string("x"),
                            "new_string": .string("y")
                        ]),
                        .object([
                            "file_path": .string("\(project)/Sources/C.swift"),
                            "old_string": .string("c"),
                            "new_string": .string("d")
                        ])
                    ])
                ]
            ),
            // Failed, running, and non-file tools must not appear.
            tool(
                id: "failed",
                name: "Edit",
                input: [
                    "file_path": .string("\(project)/Nope.swift"),
                    "new_string": .string("x")
                ],
                status: .failed,
                isError: true
            ),
            tool(
                id: "running",
                name: "Write",
                input: [
                    "file_path": .string("\(project)/Running.swift"),
                    "content": .string("x")
                ],
                status: .running
            ),
            tool(id: "bash", name: "Bash", input: ["command": .string("echo hi")])
        ]),
        projectPath: project
    )

    #expect(review.files.map(\.displayPath) == [
        "Sources/A.swift",
        "Sources/B.swift",
        "Sources/C.swift"
    ])
    #expect(review.fileCount == 3)
    #expect(review.addedLines == 5)
    #expect(review.removedLines == 3)

    let a = review.files[0]
    #expect(a.changes.count == 2)
    #expect(a.addedLines == 3)
    #expect(a.removedLines == 2)
    #expect(a.toolNames == ["Edit", "MultiEdit"])

    let b = review.files[1]
    #expect(b.wasCreated)
    #expect(b.changes.first?.isCreation == true)
    #expect(b.addedLines == 1)

    let c = review.files[2]
    #expect(c.wasCreated == false)
    #expect(c.changes.count == 1)
}

@Test func resolvesRelativeToolPathsInsideTheProject() {
    let project = "/tmp/gantry-review"
    let review = SessionReview.build(
        session: session(with: [
            tool(
                id: "relative",
                name: "Edit",
                input: [
                    "file_path": .string("Sources/Relative.swift"),
                    "old_string": .string("a"),
                    "new_string": .string("b")
                ]
            )
        ]),
        projectPath: project
    )

    #expect(review.files.first?.path == "/tmp/gantry-review/Sources/Relative.swift")
    #expect(review.files.first?.displayPath == "Sources/Relative.swift")
}

@Test func writeUpdateUsesTheOriginalFileForTheDiff() {
    let project = "/tmp/gantry-review"
    let review = SessionReview.build(
        session: session(with: [
            tool(
                id: "w2",
                name: "Write",
                input: [
                    "file_path": .string("\(project)/A.swift"),
                    "content": .string("let a = 2\n")
                ],
                structured: .object([
                    "type": .string("update"),
                    "originalFile": .string("let a = 1\n")
                ])
            )
        ]),
        projectPath: project
    )

    let change = review.files[0].changes[0]
    #expect(change.isCreation == false)
    #expect(change.oldText == "let a = 1\n")
    #expect(change.newText == "let a = 2\n")
    #expect(change.removedLines == 1)
    #expect(change.addedLines == 1)
}

@Test func reviewMessageUsesOnlyNonEmptyNotes() {
    let review = SessionReview(
        projectPath: "/tmp/p",
        files: [
            reviewedFile("/tmp/p/A.swift", displayPath: "A.swift"),
            reviewedFile("/tmp/p/B.swift", displayPath: "B.swift")
        ]
    )

    let message = review.reviewMessage(
        notes: [
            "/tmp/p/A.swift": "Keep the guard clause.",
            "/tmp/p/B.swift": "   "
        ],
        overallNote: "Looks good otherwise."
    )

    #expect(message?.contains("Overall:\nLooks good otherwise.") == true)
    #expect(message?.contains("A.swift:\nKeep the guard clause.") == true)
    #expect(message?.contains("B.swift") == false)
    #expect(review.reviewMessage(notes: [:], overallNote: " ") == nil)

    let overallOnly = review.reviewMessage(notes: [:], overallNote: "Just the overall note.")
    #expect(overallOnly?.contains("Overall:\nJust the overall note.") == true)
}

@Test func plainTextSummarizesEveryChange() {
    let review = SessionReview(
        projectPath: "/tmp/p",
        files: [reviewedFile("/tmp/p/A.swift", displayPath: "A.swift")]
    )
    let text = review.plainText()
    #expect(text.contains("Review summary — 1 file · +1 −1"))
    #expect(text.contains("A.swift  (+1 −1)"))
    #expect(text.contains("[Edit]"))
    #expect(text.contains("- old"))
    #expect(text.contains("+ new"))
}

@Test func commitPlanKeepsOnlyPathsInsideTheProject() {
    let files = [
        reviewedFile("/tmp/project/Sources/A.swift", displayPath: "Sources/A.swift"),
        reviewedFile("/tmp/elsewhere/B.swift", displayPath: "/tmp/elsewhere/B.swift"),
        reviewedFile("/tmp/project/Sources/A.swift", displayPath: "Sources/A.swift")
    ]

    let plan = GitCommitService.plan(files: files, projectPath: "/tmp/project")

    #expect(plan.paths == ["Sources/A.swift"])
    #expect(plan.excludedDisplayPaths == ["/tmp/elsewhere/B.swift"])
    #expect(plan.includedFileIDs == ["/tmp/project/Sources/A.swift"])
    #expect(plan.isEmpty == false)

    let relative = GitCommitService.plan(
        files: [reviewedFile("Sources/C.swift", displayPath: "Sources/C.swift")],
        projectPath: "/tmp/project"
    )
    #expect(relative.paths == ["Sources/C.swift"])
}

@Test func commitPlanExcludesDirectories() throws {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("Gantry-commit-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }

    let replaced = root.appendingPathComponent("Change.swift", isDirectory: true)
    try FileManager.default.createDirectory(at: replaced, withIntermediateDirectories: true)

    let plan = GitCommitService.plan(
        files: [reviewedFile(replaced.path, displayPath: "Change.swift")],
        projectPath: root.path
    )

    #expect(plan.isEmpty)
    #expect(plan.excludedDisplayPaths == ["Change.swift"])
}

private final class FakeGitRunner: GitCommandRunning, @unchecked Sendable {
    private let lock = NSLock()
    private var results: [GitCommandResult]
    private var recordedCalls: [[String]] = []

    init(results: [GitCommandResult]) {
        self.results = results
    }

    var calls: [[String]] {
        lock.lock()
        defer { lock.unlock() }
        return recordedCalls
    }

    func runGit(_ arguments: [String], in directory: URL) async throws -> GitCommandResult {
        lock.lock()
        recordedCalls.append(arguments)
        let result = results.isEmpty
            ? GitCommandResult(exitCode: 0)
            : results.removeFirst()
        lock.unlock()
        return result
    }
}

@Test func commitsOnlyReviewedPathsWithoutBypassingHooks() async throws {
    let runner = FakeGitRunner(results: [
        GitCommandResult(exitCode: 0),
        GitCommandResult(exitCode: 0, stdout: "[main abc123] feat: review changes")
    ])
    let service = GitCommitService(runner: runner)
    let files = [reviewedFile("/tmp/project/Sources/A.swift", displayPath: "Sources/A.swift")]

    let output = try await service.commit(
        message: "feat: review changes",
        files: files,
        in: URL(fileURLWithPath: "/tmp/project")
    )

    #expect(output.contains("feat: review changes"))
    #expect(runner.calls == [
        ["add", "--", ":(literal)Sources/A.swift"],
        ["commit", "-m", "feat: review changes", "--", ":(literal)Sources/A.swift"]
    ])
    let flattened = runner.calls.flatMap { $0 }
    #expect(!flattened.contains("--no-verify"))
    #expect(!flattened.contains("--no-gpg-sign"))
    #expect(!flattened.contains("push"))
}

@Test func commitSkipsFilesOutsideTheProject() async throws {
    let runner = FakeGitRunner(results: [
        GitCommandResult(exitCode: 0),
        GitCommandResult(exitCode: 0, stdout: "done")
    ])
    let service = GitCommitService(runner: runner)
    let files = [
        reviewedFile("/tmp/project/A.swift", displayPath: "A.swift"),
        reviewedFile("/tmp/elsewhere/B.swift", displayPath: "/tmp/elsewhere/B.swift")
    ]

    _ = try await service.commit(
        message: "fix: only the project file",
        files: files,
        in: URL(fileURLWithPath: "/tmp/project")
    )

    #expect(runner.calls[0] == ["add", "--", ":(literal)A.swift"])
    #expect(runner.calls[1] == [
        "commit",
        "-m",
        "fix: only the project file",
        "--",
        ":(literal)A.swift"
    ])
}

@Test func commitRejectsEmptyMessagesAndMissingFiles() async {
    let service = GitCommitService(runner: FakeGitRunner(results: []))
    let files = [reviewedFile("/tmp/project/A.swift", displayPath: "A.swift")]
    let project = URL(fileURLWithPath: "/tmp/project")

    await #expect(throws: GitCommitError.self) {
        try await service.commit(message: "  \n ", files: files, in: project)
    }
    await #expect(throws: GitCommitError.self) {
        try await service.commit(
            message: "fix: nothing",
            files: [reviewedFile("/tmp/elsewhere/B.swift", displayPath: "B.swift")],
            in: project
        )
    }
}

@Test func commitSurfacesGitFailure() async {
    let runner = FakeGitRunner(results: [
        GitCommandResult(exitCode: 128, stderr: "fatal: not a git repository")
    ])
    let service = GitCommitService(runner: runner)
    let files = [reviewedFile("/tmp/project/A.swift", displayPath: "A.swift")]

    await #expect(throws: GitCommitError.self) {
        try await service.commit(
            message: "fix: nope",
            files: files,
            in: URL(fileURLWithPath: "/tmp/project")
        )
    }
}

@Test func gitRunnerRunsTheSystemGit() async throws {
    let executable = URL(fileURLWithPath: "/usr/bin/git")
    guard FileManager.default.isExecutableFile(atPath: executable.path) else { return }
    let result = try await GitProcessRunner(executableURL: executable)
        .runGit(["--version"], in: FileManager.default.temporaryDirectory)
    #expect(result.exitCode == 0)
    #expect(result.stdout.contains("git version"))
}

@Test func gitRunnerStagesAPathspecInATemporaryRepository() async throws {
    let executable = URL(fileURLWithPath: "/usr/bin/git")
    guard FileManager.default.isExecutableFile(atPath: executable.path) else { return }

    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("Gantry-git-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }
    let name = "a[1].txt"
    try "hello\n".write(
        to: root.appendingPathComponent(name),
        atomically: true,
        encoding: .utf8
    )

    let runner = GitProcessRunner(executableURL: executable)
    let initialized = try await runner.runGit(["init", "-q"], in: root)
    #expect(initialized.exitCode == 0)
    let staged = try await runner.runGit(
        ["add", "--", ":(literal)\(name)"],
        in: root
    )
    #expect(staged.exitCode == 0)

    let status = try await runner.runGit(
        ["status", "--porcelain", "--", ":(literal)\(name)"],
        in: root
    )
    #expect(status.stdout.contains("A  \(name)"))
}
