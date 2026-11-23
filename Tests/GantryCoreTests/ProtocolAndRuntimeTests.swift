import Foundation
import Testing
@testable import GantryCore

@Test func parsesAssistantAndToolUse() throws {
    let line = """
    {"type":"assistant","message":{"id":"msg_1","role":"assistant","model":"claude-sonnet","content":[{"type":"text","text":"I'll check."},{"type":"tool_use","id":"tool_1","name":"Bash","input":{"command":"ls -la"}}]},"parent_tool_use_id":null,"session_id":"s1"}
    """
    let events = ClaudeStreamParser.parse(line: line)
    guard case .assistant(let message) = events.first else {
        Issue.record("Expected an assistant event")
        return
    }
    #expect(message.apiMessageID == "msg_1")
    #expect(message.content.count == 2)
    #expect(message.content[0] == .text("I'll check."))
    guard case .toolUse(let id, let name, let input, _) = message.content[1] else {
        Issue.record("Expected a tool use")
        return
    }
    #expect(id == "tool_1")
    #expect(name == "Bash")
    #expect(input["command"]?.stringValue == "ls -la")
}

@Test func parsesStreamingTextDelta() {
    let line = """
    {"type":"stream_event","event":{"type":"content_block_delta","index":1,"delta":{"type":"text_delta","text":"Hello"}},"parent_tool_use_id":null,"session_id":"s1"}
    """
    #expect(ClaudeStreamParser.parse(line: line) == [.streamText("Hello")])
}

@Test func ignoresSubagentStreaming() {
    let line = """
    {"type":"stream_event","event":{"type":"content_block_delta","index":0,"delta":{"type":"text_delta","text":"Nested"}},"parent_tool_use_id":"tool_parent","session_id":"s1"}
    """
    #expect(ClaudeStreamParser.parse(line: line).isEmpty)
}

@Test func parsesPermissionRequest() throws {
    let line = """
    {"type":"control_request","request_id":"req_9","request":{"subtype":"can_use_tool","tool_name":"Write","display_name":"Write","input":{"file_path":"/tmp/test.txt","content":"hello"},"description":"test.txt","permission_suggestions":[{"type":"setMode","mode":"acceptEdits","destination":"session"}],"tool_use_id":"tool_2"}}
    """
    let events = ClaudeStreamParser.parse(line: line)
    guard case .permissionRequest(let request) = events.first else {
        Issue.record("Expected a permission request")
        return
    }
    #expect(request.requestID == "req_9")
    #expect(request.toolName == "Write")
    #expect(request.input["file_path"]?.stringValue == "/tmp/test.txt")
    #expect(request.suggestions.count == 1)
    #expect(request.impliedPermissionMode == .autoEdits)
    #expect(request.alwaysAllowSuggestion != nil)
}

@Test func parsesToolResult() throws {
    let line = """
    {"type":"user","message":{"role":"user","content":[{"tool_use_id":"tool_2","type":"tool_result","content":[{"type":"text","text":"File created"}]}]},"parent_tool_use_id":null,"tool_use_result":{"type":"create","filePath":"/tmp/test.txt"},"session_id":"s1"}
    """
    let events = ClaudeStreamParser.parse(line: line)
    guard case .toolResults(let results) = events.first, let result = results.first else {
        Issue.record("Expected tool results")
        return
    }
    #expect(result.toolUseID == "tool_2")
    #expect(result.text == "File created")
    #expect(result.structuredResult?["filePath"]?.stringValue == "/tmp/test.txt")
}

@Test func parsesResultUsage() throws {
    let line = """
    {"type":"result","subtype":"success","is_error":false,"duration_ms":1200,"result":"Done","session_id":"s1","total_cost_usd":0.042,"usage":{"input_tokens":100,"output_tokens":50,"cache_read_input_tokens":20,"cache_creation_input_tokens":10},"modelUsage":{"claude-sonnet":{"inputTokens":100}},"terminal_reason":"completed","permission_denials":[]}
    """
    let events = ClaudeStreamParser.parse(line: line)
    guard case .result(let result) = events.first else {
        Issue.record("Expected a result")
        return
    }
    #expect(result.subtype == "success")
    #expect(result.isError == false)
    #expect(result.durationMS == 1200)
    #expect(result.totalCostUSD == 0.042)
    #expect(result.usage.inputTokens == 100)
    #expect(result.usage.cacheReadTokens == 20)
    #expect(result.usage.modelName == "claude-sonnet")
}

@Test func encodesPermissionResponse() throws {
    let request = ClaudePermissionRequest(
        requestID: "req_1",
        toolName: "Bash",
        input: .object(["command": .string("echo hi")]),
        suggestions: [.object(["type": .string("setMode"), "mode": .string("acceptEdits")])],
        toolUseID: "tool_5"
    )
    let data = try ClaudeWire.permissionResponse(
        requestID: request.requestID,
        reply: .allowAlways(request)
    )
    let json = try #require(
        try JSONSerialization.jsonObject(with: data) as? [String: Any]
    )
    #expect(json["type"] as? String == "control_response")
    let response = try #require(json["response"] as? [String: Any])
    #expect(response["request_id"] as? String == "req_1")
    #expect(response["subtype"] as? String == "success")
    let payload = try #require(response["response"] as? [String: Any])
    #expect(payload["behavior"] as? String == "allow")
    #expect((payload["updatedPermissions"] as? [Any])?.count == 1)
    #expect(payload["toolUseID"] as? String == "tool_5")
}

@Test func encodesUserMessageAsStreamJSON() throws {
    let data = try ClaudeWire.userMessage("Hello\nworld")
    let json = try #require(
        try JSONSerialization.jsonObject(with: data) as? [String: Any]
    )
    #expect(json["type"] as? String == "user")
    let message = try #require(json["message"] as? [String: Any])
    #expect(message["role"] as? String == "user")
    let content = try #require(message["content"] as? [[String: Any]])
    #expect(content.first?["text"] as? String == "Hello\nworld")
    #expect(json["parent_tool_use_id"] is NSNull)
}

@Test func storesAndLoadsSnapshot() throws {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("Gantry-test-\(UUID().uuidString)", isDirectory: true)
    defer { try? FileManager.default.removeItem(at: root) }
    let paths = GantryPaths(supportDirectory: root, logsDirectory: root.appendingPathComponent("logs"))
    let store = AppDataStore(paths: paths)

    let plugin = PluginConnection(
        kind: .github,
        name: "Personal GitHub",
        serverURL: "https://github.com",
        accountName: "octocat",
        keychainServer: "github.com",
        keychainAccount: "Gantry Plugins · GitHub · octocat · test"
    )
    var session = ChatSession(title: "Build a thing", model: .sonnet, permissionMode: .autoEdits)
    session.turns.append(ConversationTurn(role: .user, blocks: [.makeText("Hello")]))
    var project = Project(path: "/tmp/project", name: "Project", pluginID: plugin.id)
    project.sessions = [session]
    let snapshot = AppSnapshot(
        projects: [project],
        selectedProjectID: project.id,
        selectedSessionID: session.id,
        settings: AppSettings(
            defaultModel: .opus,
            defaultPermissionMode: .plan,
            appearance: .dark,
            plugins: [plugin]
        )
    )

    try store.save(snapshot)
    let loaded = try #require(try store.load())
    #expect(loaded.projects.count == 1)
    #expect(loaded.projects[0].name == "Project")
    #expect(loaded.projects[0].sessions[0].title == "Build a thing")
    #expect(loaded.projects[0].sessions[0].turns[0].textContent == "Hello")
    #expect(loaded.settings.defaultModel == .opus)
    #expect(loaded.settings.appearance == .dark)
    #expect(loaded.settings.plugins?.first?.accountName == "octocat")
    #expect(loaded.projects[0].pluginID == plugin.id)
    #expect(loaded.selectedSessionID == session.id)
}

@Test func runsFakeClaudePermissionFlow() async throws {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("Gantry-runtime-test-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }

    let scriptURL = root.appendingPathComponent("fake-claude")
    try fakeClaudeScript.write(to: scriptURL, atomically: true, encoding: .utf8)
    try FileManager.default.setAttributes(
        [.posixPermissions: 0o755],
        ofItemAtPath: scriptURL.path
    )

    let configuration = ClaudeLaunchConfiguration(
        executableURL: scriptURL,
        workingDirectory: root,
        claudeSessionID: UUID(),
        resume: false,
        model: .automatic,
        permissionMode: .ask
    )
    let runtime = try ClaudeRuntime(
        configuration: configuration,
        logURL: root.appendingPathComponent("claude.log")
    )
    try await runtime.initialize(timeout: 5)
    try runtime.sendPrompt("Make a file")

    struct Probe: Sendable {
        var sawPermission = false
        var sawToolResult = false
        var sawAssistantText = false
        var sawResult = false
        var cost = 0.0
        var text = ""
    }

    let probe = try await withThrowingTaskGroup(of: Probe.self) { group in
        group.addTask {
            var probe = Probe()
            for await event in runtime.events {
                switch event {
                case .permissionRequest(let request):
                    probe.sawPermission = true
                    try runtime.respondPermission(
                        requestID: request.requestID,
                        reply: .allowOnce(request)
                    )
                case .toolResults(let results):
                    probe.sawToolResult = results.contains { $0.toolUseID == "tool_fake_1" }
                case .assistant(let message):
                    if message.content.contains(where: {
                        if case .text(let text) = $0 { return text.contains("Finished") }
                        return false
                    }) {
                        probe.sawAssistantText = true
                    }
                case .result(let result):
                    probe.sawResult = true
                    probe.cost = result.totalCostUSD
                    probe.text = result.resultText ?? ""
                    return probe
                case .streamText:
                    continue
                default:
                    continue
                }
            }
            return probe
        }
        group.addTask {
            try await Task.sleep(for: .seconds(8))
            runtime.terminate()
            throw RuntimeTestTimeout()
        }
        guard let result = try await group.next() else {
            throw RuntimeTestTimeout()
        }
        group.cancelAll()
        return result
    }

    runtime.terminate()
    #expect(probe.sawPermission)
    #expect(probe.sawToolResult)
    #expect(probe.sawAssistantText)
    #expect(probe.sawResult)
    #expect(abs(probe.cost - 0.0123) < 0.0001)
    #expect(probe.text == "Finished")
}

private struct RuntimeTestTimeout: Error {}

private let fakeClaudeScript = """
#!/usr/bin/env python3
import json
import sys

sent_turn = False
permission_request_id = "perm_fake_1"
tool_id = "tool_fake_1"

def send(obj):
    sys.stdout.write(json.dumps(obj) + "\\n")
    sys.stdout.flush()

for raw in sys.stdin:
    raw = raw.strip()
    if not raw:
        continue
    try:
        obj = json.loads(raw)
    except Exception:
        continue

    if obj.get("type") == "control_request":
        request = obj.get("request", {})
        if request.get("subtype") == "initialize":
            send({
                "type": "control_response",
                "response": {
                    "subtype": "success",
                    "request_id": obj.get("request_id"),
                    "response": {"commands": [], "agents": []}
                }
            })
        elif request.get("subtype") == "interrupt":
            send({
                "type": "control_response",
                "response": {
                    "subtype": "success",
                    "request_id": obj.get("request_id"),
                    "response": {}
                }
            })
        continue

    if obj.get("type") == "user" and not sent_turn:
        sent_turn = True
        session_id = "fake-session"
        send({
            "type": "system",
            "subtype": "init",
            "cwd": ".",
            "session_id": session_id,
            "tools": ["Write"],
            "model": "fake-model",
            "permissionMode": "default",
            "slash_commands": []
        })
        send({
            "type": "stream_event",
            "event": {"type": "message_start", "message": {"id": "msg_1", "model": "fake-model"}},
            "parent_tool_use_id": None,
            "session_id": session_id
        })
        send({
            "type": "stream_event",
            "event": {"type": "content_block_delta", "index": 0, "delta": {"type": "text_delta", "text": "Working"}},
            "parent_tool_use_id": None,
            "session_id": session_id
        })
        send({
            "type": "assistant",
            "message": {
                "id": "msg_1",
                "role": "assistant",
                "model": "fake-model",
                "content": [{
                    "type": "tool_use",
                    "id": tool_id,
                    "name": "Write",
                    "input": {"file_path": "test.txt", "content": "hello"}
                }]
            },
            "parent_tool_use_id": None,
            "session_id": session_id
        })
        send({
            "type": "control_request",
            "request_id": permission_request_id,
            "request": {
                "subtype": "can_use_tool",
                "tool_name": "Write",
                "display_name": "Write",
                "input": {"file_path": "test.txt", "content": "hello"},
                "tool_use_id": tool_id,
                "descriptions": "test.txt",
                "permission_suggestions": []
            }
        })
        continue

    if obj.get("type") == "control_response" and obj.get("response", {}).get("request_id") == permission_request_id:
        session_id = "fake-session"
        send({
            "type": "user",
            "message": {
                "role": "user",
                "content": [{
                    "type": "tool_result",
                    "tool_use_id": tool_id,
                    "content": "File written"
                }]
            },
            "parent_tool_use_id": None,
            "tool_use_result": {"type": "create", "filePath": "test.txt"},
            "session_id": session_id
        })
        send({
            "type": "assistant",
            "message": {
                "id": "msg_2",
                "role": "assistant",
                "model": "fake-model",
                "content": [{"type": "text", "text": "Finished"}]
            },
            "parent_tool_use_id": None,
            "session_id": session_id
        })
        send({
            "type": "result",
            "subtype": "success",
            "is_error": False,
            "duration_ms": 123,
            "result": "Finished",
            "session_id": session_id,
            "total_cost_usd": 0.0123,
            "usage": {
                "input_tokens": 10,
                "output_tokens": 5,
                "cache_read_input_tokens": 0,
                "cache_creation_input_tokens": 0
            },
            "terminal_reason": "completed",
            "permission_denials": []
        })
        break

sys.exit(0)
"""

@Test func realClaudeCodeSmokeTest() async throws {
    guard ProcessInfo.processInfo.environment["Gantry_RUN_CLI_INTEGRATION"] == "1" else {
        return
    }
    guard let executable = ClaudeLocator.locate() else {
        Issue.record("Claude Code executable was not found")
        return
    }
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("Gantry-real-cli-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }

    let configuration = ClaudeLaunchConfiguration(
        executableURL: executable,
        workingDirectory: root,
        claudeSessionID: UUID(),
        resume: false,
        model: .automatic,
        permissionMode: .ask
    )
    let runtime = try ClaudeRuntime(
        configuration: configuration,
        logURL: root.appendingPathComponent("claude.log")
    )
    try await runtime.initialize(timeout: 35)
    try runtime.sendPrompt("Reply with exactly the single word: hello")

    struct RealProbe: Sendable {
        var result: ClaudeResultInfo?
        var assistantText = ""
        var streamedText = ""
    }

    let probe = try await withThrowingTaskGroup(of: RealProbe.self) { group in
        group.addTask {
            var probe = RealProbe()
            for await event in runtime.events {
                switch event {
                case .assistant(let message):
                    for content in message.content {
                        if case .text(let text) = content {
                            probe.assistantText += text
                        }
                    }
                case .streamText(let text):
                    probe.streamedText += text
                case .result(let result):
                    probe.result = result
                    return probe
                default:
                    continue
                }
            }
            return probe
        }
        group.addTask {
            try await Task.sleep(for: .seconds(90))
            runtime.terminate()
            throw RuntimeTestTimeout()
        }
        guard let result = try await group.next() else { throw RuntimeTestTimeout() }
        group.cancelAll()
        return result
    }

    runtime.terminate()
    let result = try #require(probe.result)
    #expect(result.isError == false)
    #expect(probe.assistantText.lowercased().contains("hello") || probe.streamedText.lowercased().contains("hello"))
    #expect(result.usage.inputTokens > 0)
}
