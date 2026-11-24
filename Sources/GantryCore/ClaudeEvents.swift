import Foundation

// MARK: - Parsed Claude Code events

public struct ClaudeSystemInfo: Hashable, Sendable {
    public var sessionID: String?
    public var model: String?
    public var permissionMode: String?
    public var cwd: String?
    public var tools: [String]
    public var slashCommands: [String]
    public var mcpServers: [String]

    public init(
        sessionID: String? = nil,
        model: String? = nil,
        permissionMode: String? = nil,
        cwd: String? = nil,
        tools: [String] = [],
        slashCommands: [String] = [],
        mcpServers: [String] = []
    ) {
        self.sessionID = sessionID
        self.model = model
        self.permissionMode = permissionMode
        self.cwd = cwd
        self.tools = tools
        self.slashCommands = slashCommands
        self.mcpServers = mcpServers
    }
}

public enum AssistantContent: Hashable, Sendable {
    case text(String)
    case thinking(String)
    case toolUse(id: String, name: String, input: JSONValue, displayName: String?)
}

/// Token counts reported by Claude Code for one assistant response. The prompt
/// side — uncached input plus cache reads and writes — is the number that
/// counts against the model's context window.
public struct ClaudeMessageUsage: Hashable, Sendable {
    public var inputTokens: Int
    public var outputTokens: Int
    public var cacheReadTokens: Int
    public var cacheCreationTokens: Int

    public init(
        inputTokens: Int = 0,
        outputTokens: Int = 0,
        cacheReadTokens: Int = 0,
        cacheCreationTokens: Int = 0
    ) {
        self.inputTokens = inputTokens
        self.outputTokens = outputTokens
        self.cacheReadTokens = cacheReadTokens
        self.cacheCreationTokens = cacheCreationTokens
    }

    public var contextTokens: Int {
        inputTokens + cacheReadTokens + cacheCreationTokens
    }
}

public struct ClaudeAssistantMessage: Hashable, Sendable {
    public var apiMessageID: String?
    public var model: String?
    public var parentToolUseID: String?
    public var content: [AssistantContent]
    public var usage: ClaudeMessageUsage?

    public init(
        apiMessageID: String? = nil,
        model: String? = nil,
        parentToolUseID: String? = nil,
        content: [AssistantContent] = [],
        usage: ClaudeMessageUsage? = nil
    ) {
        self.apiMessageID = apiMessageID
        self.model = model
        self.parentToolUseID = parentToolUseID
        self.content = content
        self.usage = usage
    }
}

public struct ClaudeToolResult: Hashable, Sendable {
    public var toolUseID: String
    public var text: String
    public var isError: Bool
    public var structuredResult: JSONValue?
    public var parentToolUseID: String?

    public init(
        toolUseID: String,
        text: String,
        isError: Bool = false,
        structuredResult: JSONValue? = nil,
        parentToolUseID: String? = nil
    ) {
        self.toolUseID = toolUseID
        self.text = text
        self.isError = isError
        self.structuredResult = structuredResult
        self.parentToolUseID = parentToolUseID
    }
}

public struct ClaudePermissionRequest: Hashable, Identifiable, Sendable {
    public var requestID: String
    public var toolName: String
    public var displayName: String?
    public var description: String?
    public var input: JSONValue
    public var suggestions: [JSONValue]
    public var decisionReason: String?
    public var blockedPath: String?
    public var toolUseID: String?
    public var title: String?

    public var id: String { requestID }

    public init(
        requestID: String,
        toolName: String,
        displayName: String? = nil,
        description: String? = nil,
        input: JSONValue = .object([:]),
        suggestions: [JSONValue] = [],
        decisionReason: String? = nil,
        blockedPath: String? = nil,
        toolUseID: String? = nil,
        title: String? = nil
    ) {
        self.requestID = requestID
        self.toolName = toolName
        self.displayName = displayName
        self.description = description
        self.input = input
        self.suggestions = suggestions
        self.decisionReason = decisionReason
        self.blockedPath = blockedPath
        self.toolUseID = toolUseID
        self.title = title
    }

    /// A permission update that would stop this prompt from recurring, when Claude Code offers one.
    public var alwaysAllowSuggestion: JSONValue? {
        guard let suggestion = suggestions.first else { return nil }
        switch suggestion["type"]?.stringValue {
        case "addRules", "setMode":
            return suggestion
        default:
            return nil
        }
    }

    public var alwaysAllowLabel: String {
        guard let suggestion = suggestions.first else { return "Always allow" }
        if suggestion["type"]?.stringValue == "setMode",
           let mode = suggestion["mode"]?.stringValue {
            if mode == PermissionMode.autoEdits.cliValue {
                return "Allow edits this session"
            }
            return "Change permission mode"
        }
        return "Always allow this"
    }

    public var impliedPermissionMode: PermissionMode? {
        guard let suggestion = suggestions.first,
              suggestion["type"]?.stringValue == "setMode",
              let mode = suggestion["mode"]?.stringValue else {
            return nil
        }
        return PermissionMode.allCases.first { $0.cliValue == mode }
    }
}

public struct ClaudeResultInfo: Hashable, Sendable {
    public var subtype: String
    public var isError: Bool
    public var resultText: String?
    public var sessionID: String?
    public var durationMS: Int?
    public var totalCostUSD: Double
    public var usage: TurnUsage
    /// Cumulative per-model usage for the session. Claude Code reports this
    /// across the whole conversation, including subagents and resumed history.
    public var modelUsage: [String: ModelTokenUsage]
    public var terminalReason: String?
    public var permissionDenials: [JSONValue]

    public init(
        subtype: String,
        isError: Bool,
        resultText: String? = nil,
        sessionID: String? = nil,
        durationMS: Int? = nil,
        totalCostUSD: Double = 0,
        usage: TurnUsage = TurnUsage(),
        modelUsage: [String: ModelTokenUsage] = [:],
        terminalReason: String? = nil,
        permissionDenials: [JSONValue] = []
    ) {
        self.subtype = subtype
        self.isError = isError
        self.resultText = resultText
        self.sessionID = sessionID
        self.durationMS = durationMS
        self.totalCostUSD = totalCostUSD
        self.usage = usage
        self.modelUsage = modelUsage
        self.terminalReason = terminalReason
        self.permissionDenials = permissionDenials
    }
}

public struct ClaudeControlResponseInfo: Hashable, Sendable {
    public var requestID: String
    public var isSuccess: Bool
    public var error: String?
    public var payload: JSONValue

    public init(requestID: String, isSuccess: Bool, error: String? = nil, payload: JSONValue = .null) {
        self.requestID = requestID
        self.isSuccess = isSuccess
        self.error = error
        self.payload = payload
    }
}

public enum ClaudeEvent: Hashable, Sendable {
    case system(ClaudeSystemInfo)
    case status(String)
    case retry(attempt: Int, maxAttempts: Int, delayMS: Int?, error: String?)
    case streamMessageStart(apiMessageID: String?, model: String?)
    case streamText(String)
    case streamThinking(String)
    case streamToolStart(toolID: String?, name: String, displayName: String?)
    case streamMessageStop
    case assistant(ClaudeAssistantMessage)
    case toolResults([ClaudeToolResult])
    case permissionRequest(ClaudePermissionRequest)
    case permissionCancelled(requestID: String)
    case controlResponse(ClaudeControlResponseInfo)
    case result(ClaudeResultInfo)
    case notice(String, isError: Bool)

    // Emitted by the host process, not by the stream parser.
    case processExited(code: Int32, stderrTail: String)
}

public enum ClaudeStreamParser {
    public static func parse(line: String) -> [ClaudeEvent] {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let data = trimmed.data(using: .utf8) else { return [] }
        let value: JSONValue
        do {
            value = try JSONDecoder().decode(JSONValue.self, from: data)
        } catch {
            return []
        }
        guard let object = value.objectValue, let type = object["type"]?.stringValue else {
            return []
        }

        switch type {
        case "system":
            return parseSystem(object)
        case "assistant":
            return parseAssistant(object)
        case "user":
            return parseUser(object)
        case "stream_event":
            return parseStreamEvent(object)
        case "result":
            return parseResult(object)
        case "control_request":
            return parseControlRequest(object)
        case "control_response":
            return parseControlResponse(object)
        case "control_cancel_request":
            guard let requestID = object["request_id"]?.stringValue else { return [] }
            return [.permissionCancelled(requestID: requestID)]
        default:
            return []
        }
    }

    private static func parseSystem(_ object: [String: JSONValue]) -> [ClaudeEvent] {
        guard let subtype = object["subtype"]?.stringValue else { return [] }
        switch subtype {
        case "init":
            let tools = object["tools"]?.arrayValue?.compactMap(\.stringValue) ?? []
            let slashCommands = object["slash_commands"]?.arrayValue?.compactMap(\.stringValue) ?? []
            let mcpServers = object["mcp_servers"]?.arrayValue?
                .compactMap { $0["name"]?.stringValue ?? $0.stringValue } ?? []
            return [.system(ClaudeSystemInfo(
                sessionID: object["session_id"]?.stringValue,
                model: object["model"]?.stringValue,
                permissionMode: object["permissionMode"]?.stringValue,
                cwd: object["cwd"]?.stringValue,
                tools: tools,
                slashCommands: slashCommands,
                mcpServers: mcpServers
            ))]
        case "status":
            guard let status = object["status"]?.stringValue else { return [] }
            return [.status(status)]
        case "api_retry":
            let attempt = Int(object["attempt"]?.numberValue ?? 0)
            let maxAttempts = Int(object["max_retries"]?.numberValue ?? 0)
            let delay = object["retry_delay_ms"]?.numberValue.map(Int.init)
            let error = object["error"]?.stringValue
            return [.retry(attempt: attempt, maxAttempts: maxAttempts, delayMS: delay, error: error)]
        case "compact_boundary":
            return [.notice("Conversation compacted", isError: false)]
        default:
            return []
        }
    }

    private static func parseAssistant(_ object: [String: JSONValue]) -> [ClaudeEvent] {
        guard let message = object["message"]?.objectValue else { return [] }
        let contents = message["content"]?.arrayValue ?? []
        let wireInputs = object["wire_tool_inputs"]?.objectValue ?? [:]
        var blocks: [AssistantContent] = []

        for content in contents {
            guard let block = content.objectValue, let blockType = block["type"]?.stringValue else { continue }
            switch blockType {
            case "text":
                if let text = block["text"]?.stringValue, !text.isEmpty {
                    blocks.append(.text(text))
                }
            case "thinking":
                if let thinking = block["thinking"]?.stringValue, !thinking.isEmpty {
                    blocks.append(.thinking(thinking))
                }
            case "tool_use":
                guard let id = block["id"]?.stringValue,
                      let name = block["name"]?.stringValue else { continue }
                let input = nonEmptyObject(block["input"]) ?? nonEmptyObject(wireInputs[id]) ?? .object([:])
                blocks.append(.toolUse(
                    id: id,
                    name: name,
                    input: input,
                    displayName: block["display_name"]?.stringValue
                ))
            default:
                continue
            }
        }

        return [.assistant(ClaudeAssistantMessage(
            apiMessageID: message["id"]?.stringValue,
            model: message["model"]?.stringValue,
            parentToolUseID: nullString(object["parent_tool_use_id"]),
            content: blocks,
            usage: parseAssistantUsage(message["usage"]?.objectValue)
        ))]
    }

    private static func parseAssistantUsage(
        _ object: [String: JSONValue]?
    ) -> ClaudeMessageUsage? {
        guard let object else { return nil }
        return ClaudeMessageUsage(
            inputTokens: Int(object["input_tokens"]?.numberValue ?? 0),
            outputTokens: Int(object["output_tokens"]?.numberValue ?? 0),
            cacheReadTokens: Int(object["cache_read_input_tokens"]?.numberValue ?? 0),
            cacheCreationTokens: Int(object["cache_creation_input_tokens"]?.numberValue ?? 0)
        )
    }

    private static func parseUser(_ object: [String: JSONValue]) -> [ClaudeEvent] {
        guard let message = object["message"]?.objectValue else { return [] }
        let contentBlocks = message["content"]?.arrayValue ?? []
        let structured = object["tool_use_result"]
        var results: [ClaudeToolResult] = []

        for content in contentBlocks {
            guard let block = content.objectValue,
                  block["type"]?.stringValue == "tool_result",
                  let toolUseID = block["tool_use_id"]?.stringValue else { continue }
            let text = toolResultText(block["content"])
            let isError = block["is_error"]?.boolValue ?? false
            results.append(ClaudeToolResult(
                toolUseID: toolUseID,
                text: TextSanitizer.stripANSI(text),
                isError: isError,
                structuredResult: structured,
                parentToolUseID: nullString(object["parent_tool_use_id"])
            ))
        }

        return results.isEmpty ? [] : [.toolResults(results)]
    }

    private static func parseStreamEvent(_ object: [String: JSONValue]) -> [ClaudeEvent] {
        guard nullString(object["parent_tool_use_id"]) == nil,
              let event = object["event"]?.objectValue,
              let eventType = event["type"]?.stringValue else { return [] }

        switch eventType {
        case "message_start":
            guard let message = event["message"]?.objectValue else { return [] }
            return [.streamMessageStart(
                apiMessageID: message["id"]?.stringValue,
                model: message["model"]?.stringValue
            )]
        case "content_block_start":
            guard let block = event["content_block"]?.objectValue else { return [] }
            if block["type"]?.stringValue == "tool_use", let name = block["name"]?.stringValue {
                return [.streamToolStart(
                    toolID: block["id"]?.stringValue,
                    name: name,
                    displayName: block["display_name"]?.stringValue
                )]
            }
            return []
        case "content_block_delta":
            guard let delta = event["delta"]?.objectValue,
                  let deltaType = delta["type"]?.stringValue else { return [] }
            if deltaType == "text_delta", let text = delta["text"]?.stringValue, !text.isEmpty {
                return [.streamText(text)]
            }
            if deltaType == "thinking_delta", let text = delta["thinking"]?.stringValue, !text.isEmpty {
                return [.streamThinking(text)]
            }
            return []
        case "message_stop":
            return [.streamMessageStop]
        default:
            return []
        }
    }

    private static func parseResult(_ object: [String: JSONValue]) -> [ClaudeEvent] {
        guard let subtype = object["subtype"]?.stringValue else { return [] }
        let usageObject = object["usage"]?.objectValue ?? [:]
        let modelUsageObject = object["modelUsage"]?.objectValue ?? [:]
        let modelUsage = parseModelUsage(modelUsageObject)
        let modelName = modelUsage.max { lhs, rhs in
            lhs.value.totalTokens < rhs.value.totalTokens
        }?.key
        let usage = TurnUsage(
            inputTokens: Int(usageObject["input_tokens"]?.numberValue ?? 0),
            outputTokens: Int(usageObject["output_tokens"]?.numberValue ?? 0),
            cacheReadTokens: Int(usageObject["cache_read_input_tokens"]?.numberValue ?? 0),
            cacheCreationTokens: Int(usageObject["cache_creation_input_tokens"]?.numberValue ?? 0),
            costUSD: object["total_cost_usd"]?.numberValue ?? 0,
            durationMS: object["duration_ms"]?.numberValue.map(Int.init),
            modelName: modelName
        )
        let denials = object["permission_denials"]?.arrayValue ?? []
        return [.result(ClaudeResultInfo(
            subtype: subtype,
            isError: object["is_error"]?.boolValue ?? (subtype != "success"),
            resultText: object["result"]?.stringValue,
            sessionID: object["session_id"]?.stringValue,
            durationMS: object["duration_ms"]?.numberValue.map(Int.init),
            totalCostUSD: object["total_cost_usd"]?.numberValue ?? 0,
            usage: usage,
            modelUsage: modelUsage,
            terminalReason: object["terminal_reason"]?.stringValue,
            permissionDenials: denials
        ))]
    }

    private static func parseModelUsage(
        _ object: [String: JSONValue]
    ) -> [String: ModelTokenUsage] {
        var usage: [String: ModelTokenUsage] = [:]
        for (model, value) in object {
            guard let entry = value.objectValue else { continue }
            func number(_ camel: String, _ snake: String) -> Int {
                Int((entry[camel] ?? entry[snake])?.numberValue ?? 0)
            }
            usage[model] = ModelTokenUsage(
                inputTokens: number("inputTokens", "input_tokens"),
                outputTokens: number("outputTokens", "output_tokens"),
                cacheReadTokens: number("cacheReadInputTokens", "cache_read_input_tokens"),
                cacheCreationTokens: number("cacheCreationInputTokens", "cache_creation_input_tokens"),
                reportedCostUSD: entry["costUSD"]?.numberValue
                    ?? entry["cost_usd"]?.numberValue
                    ?? 0
            )
        }
        return usage
    }

    private static func parseControlRequest(_ object: [String: JSONValue]) -> [ClaudeEvent] {
        guard let requestID = object["request_id"]?.stringValue,
              let request = object["request"]?.objectValue,
              let subtype = request["subtype"]?.stringValue else { return [] }
        guard subtype == "can_use_tool" else { return [] }
        guard let toolName = request["tool_name"]?.stringValue else { return [] }
        let suggestions = request["permission_suggestions"]?.arrayValue ?? []
        return [.permissionRequest(ClaudePermissionRequest(
            requestID: requestID,
            toolName: toolName,
            displayName: request["display_name"]?.stringValue,
            description: request["description"]?.stringValue,
            input: request["input"] ?? .object([:]),
            suggestions: suggestions,
            decisionReason: request["decision_reason"]?.stringValue.map(TextSanitizer.stripANSI),
            blockedPath: request["blocked_path"]?.stringValue,
            toolUseID: request["tool_use_id"]?.stringValue,
            title: request["title"]?.stringValue
        ))]
    }

    private static func parseControlResponse(_ object: [String: JSONValue]) -> [ClaudeEvent] {
        guard let response = object["response"]?.objectValue,
              let requestID = response["request_id"]?.stringValue,
              let subtype = response["subtype"]?.stringValue else { return [] }
        return [.controlResponse(ClaudeControlResponseInfo(
            requestID: requestID,
            isSuccess: subtype == "success",
            error: response["error"]?.stringValue,
            payload: response["response"] ?? .null
        ))]
    }

    private static func toolResultText(_ value: JSONValue?) -> String {
        guard let value else { return "" }
        switch value {
        case .string(let string):
            return string
        case .array(let blocks):
            return blocks.compactMap { block -> String? in
                guard let object = block.objectValue else { return block.stringValue }
                if object["type"]?.stringValue == "text" {
                    return object["text"]?.stringValue
                }
                if object["type"]?.stringValue == "image" {
                    return "[image]"
                }
                return block.displayString
            }.joined(separator: "\n")
        default:
            return value.displayString
        }
    }

    private static func nonEmptyObject(_ value: JSONValue?) -> JSONValue? {
        guard let value, case .object(let object) = value, !object.isEmpty else { return nil }
        return value
    }

    private static func nullString(_ value: JSONValue?) -> String? {
        guard let value else { return nil }
        return value.stringValue
    }
}

public enum TextSanitizer {
    // ICU regex syntax takes \uHHHH, not Swift's \u{...}; the latter made this
    // initializer throw, and the former `try!` trapped the runtime queue on the
    // first ANSI-containing tool result. Sanitizing is cosmetic: never crash.
    private static let ansiPattern = try? NSRegularExpression(
        pattern: #"\u001B(?:\[[0-?]*[ -/]*[@-~]|\][^\u0007]*(?:\u0007|\u001B\\)|[@-_])"#
    )

    public static func stripANSI(_ text: String) -> String {
        guard text.contains("\u{001B}"), let ansiPattern else { return text }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        return ansiPattern.stringByReplacingMatches(in: text, range: range, withTemplate: "")
    }
}
