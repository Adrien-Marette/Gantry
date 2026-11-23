import Foundation

// MARK: - Tool catalog

public enum PluginToolName: String, CaseIterable, Codable, Sendable {
    case getRepository = "get_repository"
    case listPullRequests = "list_pull_requests"
    case getPullRequest = "get_pull_request"
    case listChecks = "list_checks"
    case commentOnPullRequest = "comment_on_pull_request"
    case createPullRequest = "create_pull_request"

    public var title: String {
        switch self {
        case .getRepository: return "Get repository"
        case .listPullRequests: return "List pull requests"
        case .getPullRequest: return "Get pull request"
        case .listChecks: return "List checks"
        case .commentOnPullRequest: return "Comment on pull request"
        case .createPullRequest: return "Create pull request"
        }
    }

    public var isWrite: Bool {
        switch self {
        case .commentOnPullRequest, .createPullRequest: return true
        default: return false
        }
    }
}

public struct PluginToolDescriptor: Sendable {
    public var name: PluginToolName
    public var description: String
    public var inputSchema: JSONValue
    public var annotations: JSONValue

    public init(
        name: PluginToolName,
        description: String,
        inputSchema: JSONValue,
        annotations: JSONValue
    ) {
        self.name = name
        self.description = description
        self.inputSchema = inputSchema
        self.annotations = annotations
    }

    public var mcpValue: JSONValue {
        .object([
            "name": .string(name.rawValue),
            "description": .string(description),
            "inputSchema": inputSchema,
            "annotations": annotations
        ])
    }
}

public enum PluginToolCatalog {
    public static let all: [PluginToolDescriptor] = [
        PluginToolDescriptor(
            name: .getRepository,
            description: "Get the connected repository's name, default branch, visibility, and web URL.",
            inputSchema: objectSchema(properties: [:], required: []),
            annotations: annotations(readOnly: true)
        ),
        PluginToolDescriptor(
            name: .listPullRequests,
            description: "List open pull requests or merge requests in the connected repository.",
            inputSchema: objectSchema(properties: [:], required: []),
            annotations: annotations(readOnly: true)
        ),
        PluginToolDescriptor(
            name: .getPullRequest,
            description: "Get one pull request or merge request by number, including its description and CI checks.",
            inputSchema: objectSchema(
                properties: [
                    "number": integerProperty("The pull request or merge request number."),
                    "include_checks": booleanProperty("Whether to include CI checks. Defaults to true.")
                ],
                required: ["number"]
            ),
            annotations: annotations(readOnly: true)
        ),
        PluginToolDescriptor(
            name: .listChecks,
            description: "List CI checks for a pull request or merge request by number.",
            inputSchema: objectSchema(
                properties: [
                    "number": integerProperty("The pull request or merge request number.")
                ],
                required: ["number"]
            ),
            annotations: annotations(readOnly: true)
        ),
        PluginToolDescriptor(
            name: .commentOnPullRequest,
            description: "Post a conversation comment on a pull request or merge request. This changes the remote repository and should only be used when the user asks for it.",
            inputSchema: objectSchema(
                properties: [
                    "number": integerProperty("The pull request or merge request number."),
                    "body": stringProperty("The comment text to post.")
                ],
                required: ["number", "body"]
            ),
            annotations: annotations(readOnly: false)
        ),
        PluginToolDescriptor(
            name: .createPullRequest,
            description: "Create a pull request or merge request from an existing source branch to a target branch. This changes the remote repository and should only be used when the user asks for it.",
            inputSchema: objectSchema(
                properties: [
                    "title": stringProperty("The title of the new pull request."),
                    "source_branch": stringProperty("The branch containing the changes. It must already exist on the code host."),
                    "target_branch": stringProperty("The branch to merge into, usually the default branch."),
                    "body": stringProperty("Optional description for the new pull request."),
                    "draft": booleanProperty("Whether to create it as a draft.")
                ],
                required: ["title", "source_branch", "target_branch"]
            ),
            annotations: annotations(readOnly: false)
        )
    ]

    public static func descriptor(for name: PluginToolName) -> PluginToolDescriptor? {
        all.first { $0.name == name }
    }

    private static func objectSchema(
        properties: [String: JSONValue],
        required: [String]
    ) -> JSONValue {
        .object([
            "type": .string("object"),
            "properties": .object(properties),
            "required": .array(required.map { .string($0) }),
            "additionalProperties": .bool(false)
        ])
    }

    private static func stringProperty(_ description: String) -> JSONValue {
        .object([
            "type": .string("string"),
            "description": .string(description)
        ])
    }

    private static func integerProperty(_ description: String) -> JSONValue {
        .object([
            "type": .string("integer"),
            "description": .string(description)
        ])
    }

    private static func booleanProperty(_ description: String) -> JSONValue {
        .object([
            "type": .string("boolean"),
            "description": .string(description)
        ])
    }

    private static func annotations(readOnly: Bool) -> JSONValue {
        .object([
            "readOnlyHint": .bool(readOnly),
            "destructiveHint": .bool(false),
            "idempotentHint": .bool(readOnly),
            "openWorldHint": .bool(true)
        ])
    }
}

// MARK: - Bridge wire format

public struct PluginToolBridgeRequest: Codable, Hashable, Sendable {
    public var auth: String
    public var tool: String
    public var arguments: JSONValue

    public init(auth: String, tool: String, arguments: JSONValue = .object([:])) {
        self.auth = auth
        self.tool = tool
        self.arguments = arguments
    }
}

public struct PluginToolBridgeResponse: Codable, Hashable, Sendable {
    public var ok: Bool
    public var result: JSONValue?
    public var error: String?

    public init(ok: Bool, result: JSONValue? = nil, error: String? = nil) {
        self.ok = ok
        self.result = result
        self.error = error
    }
}

// MARK: - Executor

public enum PluginToolError: Error, LocalizedError, Sendable {
    case unknownTool(String)
    case missingArgument(String)
    case invalidArgument(String)
    case pullRequestNotFound(Int)

    public var errorDescription: String? {
        switch self {
        case .unknownTool(let name):
            return "Unknown plugin tool “\(name)”."
        case .missingArgument(let name):
            return "The “\(name)” argument is required."
        case .invalidArgument(let name):
            return "The “\(name)” argument has an invalid value."
        case .pullRequestNotFound(let number):
            return "No open pull request or merge request #\(number) was found."
        }
    }
}

public struct PluginToolExecutor: Sendable {
    private let client: CodeHostClient
    private let remote: RepositoryRemote

    public init(client: CodeHostClient, remote: RepositoryRemote) {
        self.client = client
        self.remote = remote
    }

    public func execute(tool rawName: String, arguments: JSONValue) async throws -> JSONValue {
        guard let tool = PluginToolName(rawValue: rawName) else {
            throw PluginToolError.unknownTool(rawName)
        }
        let arguments = arguments.objectValue ?? [:]

        switch tool {
        case .getRepository:
            let repository = try await client.repository(for: remote)
            return repositoryValue(repository)

        case .listPullRequests:
            let pullRequests = try await client.pullRequests(for: remote)
            return .object([
                "repository": .string(remote.fullName),
                "pull_requests": .array(pullRequests.map { pullRequestValue($0, includeBody: false) })
            ])

        case .getPullRequest:
            let number = try requiredInt("number", in: arguments)
            let pullRequest = try await findPullRequest(number)
            let includeChecks = optionalBool("include_checks", in: arguments) ?? true
            var value = pullRequestValue(pullRequest).objectValue ?? [:]
            if includeChecks {
                do {
                    let checks = try await client.checks(for: pullRequest, in: remote)
                    value["checks"] = .array(checks.map(checkValue))
                } catch {
                    value["checks"] = .array([])
                    value["checks_error"] = .string(error.localizedDescription)
                }
            }
            return .object(value)

        case .listChecks:
            let number = try requiredInt("number", in: arguments)
            let pullRequest = try await findPullRequest(number)
            let checks = try await client.checks(for: pullRequest, in: remote)
            return .object([
                "repository": .string(remote.fullName),
                "number": .number(Double(pullRequest.number)),
                "title": .string(pullRequest.title),
                "checks": .array(checks.map(checkValue))
            ])

        case .commentOnPullRequest:
            let number = try requiredInt("number", in: arguments)
            let body = try requiredString("body", in: arguments)
            try await client.comment(on: number, in: remote, body: body)
            return .object([
                "ok": .bool(true),
                "number": .number(Double(number)),
                "message": .string("Comment posted to #\(number).")
            ])

        case .createPullRequest:
            let title = try requiredString("title", in: arguments)
            let source = try requiredString("source_branch", in: arguments)
            let target = try requiredString("target_branch", in: arguments)
            let body = optionalString("body", in: arguments) ?? ""
            let draft = optionalBool("draft", in: arguments) ?? false
            let created = try await client.createPullRequest(
                PluginNewPullRequest(
                    title: title,
                    body: body,
                    sourceBranch: source,
                    targetBranch: target,
                    isDraft: draft
                ),
                in: remote
            )
            return .object([
                "created": .bool(true),
                "pull_request": pullRequestValue(created)
            ])
        }
    }

    private func findPullRequest(_ number: Int) async throws -> PluginPullRequest {
        let pullRequests = try await client.pullRequests(for: remote)
        guard let pullRequest = pullRequests.first(where: { $0.number == number }) else {
            throw PluginToolError.pullRequestNotFound(number)
        }
        return pullRequest
    }

    private func repositoryValue(_ repository: PluginRepository) -> JSONValue {
        var value: [String: JSONValue] = [
            "full_name": .string(repository.fullName),
            "default_branch": .string(repository.defaultBranch),
            "private": .bool(repository.isPrivate)
        ]
        if let webURL = repository.webURL {
            value["web_url"] = .string(webURL.absoluteString)
        }
        return .object(value)
    }

    private func pullRequestValue(
        _ pullRequest: PluginPullRequest,
        includeBody: Bool = true
    ) -> JSONValue {
        var value: [String: JSONValue] = [
            "number": .number(Double(pullRequest.number)),
            "title": .string(pullRequest.title),
            "state": .string(pullRequest.state.rawValue),
            "draft": .bool(pullRequest.isDraft),
            "author": .string(pullRequest.author),
            "source_branch": .string(pullRequest.sourceBranch),
            "target_branch": .string(pullRequest.targetBranch)
        ]
        if includeBody {
            value["body"] = .string(String(pullRequest.body.prefix(12_000)))
        }
        if let headSHA = pullRequest.headSHA {
            value["head_sha"] = .string(headSHA)
        }
        if let webURL = pullRequest.webURL {
            value["web_url"] = .string(webURL.absoluteString)
        }
        if let updatedAt = pullRequest.updatedAt {
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime]
            value["updated_at"] = .string(formatter.string(from: updatedAt))
        }
        return .object(value)
    }

    private func checkValue(_ check: PluginCheck) -> JSONValue {
        var value: [String: JSONValue] = [
            "name": .string(check.name),
            "state": .string(check.state.rawValue)
        ]
        if let description = check.description {
            value["description"] = .string(description)
        }
        if let detailsURL = check.detailsURL {
            value["details_url"] = .string(detailsURL.absoluteString)
        }
        return .object(value)
    }

    private func requiredInt(_ key: String, in arguments: [String: JSONValue]) throws -> Int {
        guard let value = arguments[key] else {
            throw PluginToolError.missingArgument(key)
        }
        if let number = value.numberValue,
           number.rounded() == number,
           number >= 1,
           number <= Double(Int.max) {
            return Int(number)
        }
        if let string = value.stringValue,
           let number = Int(string),
           number >= 1 {
            return number
        }
        throw PluginToolError.invalidArgument(key)
    }

    private func requiredString(_ key: String, in arguments: [String: JSONValue]) throws -> String {
        guard let value = arguments[key] else {
            throw PluginToolError.missingArgument(key)
        }
        guard let string = value.stringValue?.trimmingCharacters(in: .whitespacesAndNewlines),
              !string.isEmpty else {
            throw PluginToolError.invalidArgument(key)
        }
        return string
    }

    private func optionalString(_ key: String, in arguments: [String: JSONValue]) -> String? {
        arguments[key]?.stringValue
    }

    private func optionalBool(_ key: String, in arguments: [String: JSONValue]) -> Bool? {
        arguments[key]?.boolValue
    }
}
