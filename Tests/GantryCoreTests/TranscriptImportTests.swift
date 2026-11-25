import Foundation
import Testing
@testable import GantryCore

@Test func encodesProjectPathLikeClaudeCode() {
    #expect(ClaudeTranscriptImporter.encodedName(forProjectPath: "/Volumes/Disque Dev/my.app") == "-Volumes-Disque-Dev-my-app")
}

@Test func importsTranscriptAsResumableSession() throws {
    let root = GantryTestTempRoot.url.appendingPathComponent("transcripts-\(UUID().uuidString)")
    let projectPath = "/tmp/Demo Project"
    let directory = root.appendingPathComponent(ClaudeTranscriptImporter.encodedName(forProjectPath: projectPath))
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }

    let sessionID = UUID()
    let known = UUID()
    let lines = [
        #"{"type":"summary","summary":"Ignored"}"#,
        #"{"type":"user","isMeta":true,"timestamp":"2026-01-01T10:00:00.000Z","message":{"role":"user","content":"<local-command-caveat>x</local-command-caveat>"}}"#,
        #"{"type":"user","timestamp":"2026-01-01T10:00:01.000Z","message":{"role":"user","content":"List the files\nplease"}}"#,
        #"{"type":"assistant","timestamp":"2026-01-01T10:00:02.000Z","message":{"model":"claude-opus-5-5","content":[{"type":"text","text":"Listing."}]}}"#,
        #"{"type":"assistant","timestamp":"2026-01-01T10:00:03.000Z","message":{"model":"claude-opus-5-5","content":[{"type":"tool_use","id":"t1","name":"Bash","input":{"command":"ls"}}]}}"#,
        #"{"type":"user","timestamp":"2026-01-01T10:00:04.000Z","message":{"role":"user","content":[{"type":"tool_result","tool_use_id":"t1","content":"README.md"}]}}"#,
        #"{"type":"assistant","isSidechain":true,"message":{"content":[{"type":"text","text":"subagent"}]}}"#,
        "not json",
    ]
    try lines.joined(separator: "\n").write(
        to: directory.appendingPathComponent("\(sessionID.uuidString.lowercased()).jsonl"),
        atomically: true,
        encoding: .utf8
    )
    try "{}".write(to: directory.appendingPathComponent("\(known.uuidString).jsonl"), atomically: true, encoding: .utf8)
    try "{}".write(to: directory.appendingPathComponent("notes.jsonl"), atomically: true, encoding: .utf8)

    let urls = ClaudeTranscriptImporter.transcriptURLs(
        forProjectPath: projectPath,
        excluding: [known],
        projectsDirectory: root
    )
    #expect(urls.count == 1)

    let session = try #require(ClaudeTranscriptImporter.session(fromTranscript: urls[0]))
    #expect(session.claudeSessionID == sessionID)
    #expect(session.claudeStarted)
    #expect(session.title == "List the files")
    #expect(session.turns.map(\.role) == [.user, .assistant])
    #expect(session.turns[1].textContent == "Listing.")
    let tool = try #require(session.turns[1].tools.first)
    #expect(tool.status == .completed)
    #expect(tool.resultText == "README.md")
    #expect(session.actualModelName == "claude-opus-5-5")
}

@Test func defaultsConfigDirectoryAndHonoursOverride() {
    let home = URL(fileURLWithPath: "/Users/test")
    #expect(ClaudeTranscriptImporter.projectsDirectory(environment: [:], home: home).path == "/Users/test/.claude/projects")
    #expect(ClaudeTranscriptImporter.projectsDirectory(environment: ["CLAUDE_CONFIG_DIR": "/tmp/cc"], home: home).path == "/tmp/cc/projects")
}

@Test func settingsWithoutTranscriptPreferenceDecode() throws {
    let json = #"{"defaultModel":"automatic","defaultPermissionMode":"ask","showsInspector":true,"sidebarWidth":274}"#
    let settings = try JSONDecoder().decode(AppSettings.self, from: Data(json.utf8))
    #expect(settings.transcriptImport == nil)
}
