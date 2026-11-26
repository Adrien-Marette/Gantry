import Foundation

public struct ClaudePermissionReply: Sendable {
    public enum Behavior: Sendable {
        case allow
        case deny
    }

    public var behavior: Behavior
    public var updatedInput: JSONValue?
    public var updatedPermissions: [JSONValue]?
    public var denialMessage: String
    public var interrupt: Bool
    public var toolUseID: String?

    public init(
        behavior: Behavior,
        updatedInput: JSONValue? = nil,
        updatedPermissions: [JSONValue]? = nil,
        denialMessage: String = "The user declined this action.",
        interrupt: Bool = false,
        toolUseID: String? = nil
    ) {
        self.behavior = behavior
        self.updatedInput = updatedInput
        self.updatedPermissions = updatedPermissions
        self.denialMessage = denialMessage
        self.interrupt = interrupt
        self.toolUseID = toolUseID
    }

    public static func allowOnce(_ request: ClaudePermissionRequest) -> ClaudePermissionReply {
        ClaudePermissionReply(
            behavior: .allow,
            updatedInput: request.input,
            toolUseID: request.toolUseID
        )
    }

    public static func allowAlways(_ request: ClaudePermissionRequest) -> ClaudePermissionReply {
        ClaudePermissionReply(
            behavior: .allow,
            updatedInput: request.input,
            updatedPermissions: request.suggestions.isEmpty ? nil : request.suggestions,
            toolUseID: request.toolUseID
        )
    }

    public static func deny(
        _ request: ClaudePermissionRequest,
        message: String = "The user declined this action.",
        interrupt: Bool = false
    ) -> ClaudePermissionReply {
        ClaudePermissionReply(
            behavior: .deny,
            denialMessage: message,
            interrupt: interrupt,
            toolUseID: request.toolUseID
        )
    }

    /// Allows an `AskUserQuestion` call with the user's answers. Claude Code
    /// reads them from `updatedInput.answers`, keyed by the exact question
    /// text; multi-select labels are already joined into one string.
    public static func answer(
        _ request: ClaudePermissionRequest,
        answers: [String: String]
    ) -> ClaudePermissionReply {
        var input = request.input.objectValue ?? [:]
        input["answers"] = .object(answers.mapValues(JSONValue.string))
        return ClaudePermissionReply(
            behavior: .allow,
            updatedInput: .object(input),
            toolUseID: request.toolUseID
        )
    }
}

public enum ClaudeWire {
    public static func initializeRequest(requestID: String) throws -> Data {
        try line([
            "type": "control_request",
            "request_id": requestID,
            "request": ["subtype": "initialize"]
        ])
    }

    /// Attached images listed in the prompt are also sent inline as image
    /// blocks, like a paste into the `claude` terminal, so Claude sees them
    /// without a Read call. The path stays in the text as a fallback.
    public static func userMessage(_ text: String) throws -> Data {
        var content: [[String: Any]] = [["type": "text", "text": text]]
        for path in PromptAttachmentComposer.imagePaths(in: text) {
            if let block = imageBlock(path: path) { content.append(block) }
        }
        return try line([
            "type": "user",
            "message": [
                "role": "user",
                "content": content
            ],
            "parent_tool_use_id": NSNull()
        ])
    }

    /// The API accepts these formats up to 5 MB each after base64 (4/3
    /// growth); anything else is left to Claude's Read tool via the path.
    static let inlineImageLimit = 3_750_000
    static let inlineImageTypes = ["png": "image/png", "jpg": "image/jpeg", "jpeg": "image/jpeg",
                                   "gif": "image/gif", "webp": "image/webp"]

    static func imageBlock(path: String) -> [String: Any]? {
        guard let mediaType = inlineImageTypes[(path as NSString).pathExtension.lowercased()],
              let data = FileManager.default.contents(atPath: path),
              !data.isEmpty, data.count <= inlineImageLimit else { return nil }
        return [
            "type": "image",
            "source": ["type": "base64", "media_type": mediaType, "data": data.base64EncodedString()]
        ]
    }

    public static func permissionResponse(requestID: String, reply: ClaudePermissionReply) throws -> Data {
        var payload: [String: Any] = [
            "behavior": reply.behavior == .allow ? "allow" : "deny"
        ]
        switch reply.behavior {
        case .allow:
            if let updatedInput = reply.updatedInput {
                payload["updatedInput"] = updatedInput.anyValue
            }
            if let updatedPermissions = reply.updatedPermissions, !updatedPermissions.isEmpty {
                payload["updatedPermissions"] = updatedPermissions.map(\.anyValue)
            }
        case .deny:
            payload["message"] = reply.denialMessage
            if reply.interrupt {
                payload["interrupt"] = true
            }
        }
        if let toolUseID = reply.toolUseID {
            payload["toolUseID"] = toolUseID
        }
        return try line([
            "type": "control_response",
            "response": [
                "subtype": "success",
                "request_id": requestID,
                "response": payload
            ]
        ])
    }

    public static func interruptRequest(requestID: String) throws -> Data {
        try line([
            "type": "control_request",
            "request_id": requestID,
            "request": ["subtype": "interrupt"]
        ])
    }

    public static func setPermissionModeRequest(requestID: String, mode: PermissionMode) throws -> Data {
        try line([
            "type": "control_request",
            "request_id": requestID,
            "request": [
                "subtype": "set_permission_mode",
                "mode": mode.cliValue
            ]
        ])
    }

    public static func setModelRequest(requestID: String, model: ModelChoice) throws -> Data {
        var request: [String: Any] = ["subtype": "set_model"]
        request["model"] = model.cliValue ?? NSNull()
        return try line([
            "type": "control_request",
            "request_id": requestID,
            "request": request
        ])
    }

    public static func line(_ object: [String: Any]) throws -> Data {
        guard JSONSerialization.isValidJSONObject(object) else {
            throw ClaudeWireError.invalidPayload
        }
        var data = try JSONSerialization.data(
            withJSONObject: object,
            options: [.withoutEscapingSlashes]
        )
        data.append(0x0A)
        return data
    }
}

public enum ClaudeWireError: Error, LocalizedError {
    case invalidPayload

    public var errorDescription: String? {
        switch self {
        case .invalidPayload: return "Could not encode a message for Claude Code."
        }
    }
}
