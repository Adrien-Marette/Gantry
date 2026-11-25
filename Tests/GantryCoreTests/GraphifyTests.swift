import Foundation
import Testing
@testable import GantryCore

private func tempRoot() throws -> URL {
    let root = GantryTestTempRoot.url
        .appendingPathComponent("gantry-graphify-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    return root
}

private func makeExecutable(at url: URL) throws {
    try FileManager.default.createDirectory(
        at: url.deletingLastPathComponent(),
        withIntermediateDirectories: true
    )
    try "#!/bin/sh\nexit 0\n".write(to: url, atomically: true, encoding: .utf8)
    try FileManager.default.setAttributes(
        [.posixPermissions: 0o755],
        ofItemAtPath: url.path
    )
}

@Test func graphifyLocatorFindsUVToolInstall() throws {
    let root = try tempRoot()
    let home = root.appendingPathComponent("home", isDirectory: true)
    let mcp = home.appendingPathComponent(".local/bin/graphify-mcp")
    try makeExecutable(at: mcp)

    let environment = ["HOME": home.path, "PATH": ""]
    #expect(GraphifyLocator.locateMCP(environment: environment)?.path == mcp.path)
    #expect(GraphifyLocator.locate(
        "graphify",
        environment: environment,
        includeStandardDirectories: false
    ) == nil)
}

@Test func graphifyMCPEntryRequiresGraphAndServer() throws {
    let root = try tempRoot()
    let project = root.appendingPathComponent("project", isDirectory: true)
    let graph = project.appendingPathComponent("graphify-out/graph.json")
    try FileManager.default.createDirectory(
        at: graph.deletingLastPathComponent(),
        withIntermediateDirectories: true
    )
    try "{}".write(to: graph, atomically: true, encoding: .utf8)

    let home = root.appendingPathComponent("home", isDirectory: true)
    let mcp = home.appendingPathComponent(".local/bin/graphify-mcp")
    try makeExecutable(at: mcp)
    let environment = ["HOME": home.path, "PATH": ""]

    let server = GraphifyIntegration.mcpServer(forProject: project, environment: environment)
    #expect(server?["command"] as? String == mcp.path)
    #expect(server?["args"] as? [String] == [graph.path])

    try FileManager.default.removeItem(at: graph)
    #expect(GraphifyIntegration.mcpServer(forProject: project, environment: environment) == nil)
}

@Test func graphifyStatusReportsGraphAndTools() throws {
    let root = try tempRoot()
    let project = root.appendingPathComponent("project", isDirectory: true)
    let graph = project.appendingPathComponent("graphify-out/graph.json")
    try FileManager.default.createDirectory(
        at: graph.deletingLastPathComponent(),
        withIntermediateDirectories: true
    )
    try "{}".write(to: graph, atomically: true, encoding: .utf8)

    let home = root.appendingPathComponent("home", isDirectory: true)
    try makeExecutable(at: home.appendingPathComponent(".local/bin/graphify"))
    try makeExecutable(at: home.appendingPathComponent(".local/bin/graphify-mcp"))

    let status = GraphifyStatus.read(
        projectURL: project,
        environment: ["HOME": home.path, "PATH": ""]
    )
    #expect(status.graphExists)
    #expect(status.graphByteCount == 2)
    #expect(status.graphModifiedAt != nil)
    #expect(status.cliURL?.path == home.appendingPathComponent(".local/bin/graphify").path)
    #expect(status.mcpURL?.path == home.appendingPathComponent(".local/bin/graphify-mcp").path)
    #expect(status.htmlURL == nil)
}

@Test func graphifyCommandsKeepUserInputOutOfAShell() {
    let graph = URL(fileURLWithPath: "/tmp/graph.json")
    #expect(GraphifyCommand.query("what calls main?", graphURL: graph) == [
        "query", "what calls main?", "--graph", "/tmp/graph.json"
    ])
    #expect(GraphifyCommand.installMCP() == ["tool", "install", "graphifyy[mcp]"])
    #expect(GraphifyCommand.installMCP(force: true) == [
        "tool", "install", "--force", "graphifyy[mcp]"
    ])
}

@Test func graphifyProcessPassesArgumentsWithoutAShell() async throws {
    let result = try await GraphifyProcess.run(
        executable: URL(fileURLWithPath: "/bin/echo"),
        arguments: ["hello; echo injected", "$HOME"],
        timeout: 10
    )
    #expect(result.exitCode == 0)
    #expect(!result.timedOut)
    #expect(result.output == "hello; echo injected $HOME")
}

@Test func graphifyProcessStopsAtTheTimeout() async throws {
    let result = try await GraphifyProcess.run(
        executable: URL(fileURLWithPath: "/bin/sleep"),
        arguments: ["5"],
        timeout: 0.3
    )
    #expect(result.timedOut)
}
