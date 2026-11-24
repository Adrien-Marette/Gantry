import Foundation

// MARK: - JSON

/// A small, lossless-enough JSON value used for tool inputs and protocol payloads.
/// Keeping this generic avoids inventing a bespoke model for every Claude Code tool.
public enum JSONValue: Codable, Hashable, Sendable {
    case null
    case bool(Bool)
    case number(Double)
    case string(String)
    case array([JSONValue])
    case object([String: JSONValue])

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .null
        } else if let value = try? container.decode(Bool.self) {
            self = .bool(value)
        } else if let value = try? container.decode(Double.self) {
            self = .number(value)
        } else if let value = try? container.decode(String.self) {
            self = .string(value)
        } else if let value = try? container.decode([JSONValue].self) {
            self = .array(value)
        } else if let value = try? container.decode([String: JSONValue].self) {
            self = .object(value)
        } else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Unsupported JSON value")
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .null: try container.encodeNil()
        case .bool(let value): try container.encode(value)
        case .number(let value): try container.encode(value)
        case .string(let value): try container.encode(value)
        case .array(let value): try container.encode(value)
        case .object(let value): try container.encode(value)
        }
    }

    public init(any value: Any) {
        switch value {
        case is NSNull:
            self = .null
        case let value as Bool:
            self = .bool(value)
        case let value as Int:
            self = .number(Double(value))
        case let value as Double:
            self = .number(value)
        case let value as NSNumber:
            self = .number(value.doubleValue)
        case let value as String:
            self = .string(value)
        case let value as [Any]:
            self = .array(value.map(JSONValue.init(any:)))
        case let value as [String: Any]:
            self = .object(value.mapValues(JSONValue.init(any:)))
        default:
            self = .null
        }
    }

    public var objectValue: [String: JSONValue]? {
        if case .object(let value) = self { return value }
        return nil
    }

    public var arrayValue: [JSONValue]? {
        if case .array(let value) = self { return value }
        return nil
    }

    public var stringValue: String? {
        if case .string(let value) = self { return value }
        return nil
    }

    public var numberValue: Double? {
        if case .number(let value) = self { return value }
        return nil
    }

    public var boolValue: Bool? {
        if case .bool(let value) = self { return value }
        return nil
    }

    public subscript(key: String) -> JSONValue? {
        objectValue?[key]
    }

    public subscript(index: Int) -> JSONValue? {
        guard let array = arrayValue, array.indices.contains(index) else { return nil }
        return array[index]
    }

    public var anyValue: Any {
        switch self {
        case .null: return NSNull()
        case .bool(let value): return value
        case .number(let value): return value
        case .string(let value): return value
        case .array(let value): return value.map(\.anyValue)
        case .object(let value): return value.mapValues(\.anyValue)
        }
    }

    public var prettyJSON: String {
        guard JSONSerialization.isValidJSONObject(anyValue),
              let data = try? JSONSerialization.data(
                withJSONObject: anyValue,
                options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
              ),
              let string = String(data: data, encoding: .utf8) else {
            return displayString
        }
        return string
    }

    public var displayString: String {
        switch self {
        case .null: return ""
        case .bool(let value): return value ? "true" : "false"
        case .number(let value):
            if value.rounded() == value, abs(value) < 1e15 {
                return String(Int(value))
            }
            return String(value)
        case .string(let value): return value
        case .array, .object: return prettyJSON
        }
    }
}

// MARK: - Preferences

public enum AppearanceMode: String, CaseIterable, Codable, Identifiable, Sendable {
    case system
    case light
    case dark

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .system: return "System"
        case .light: return "Light"
        case .dark: return "Dark"
        }
    }
}

public enum ModelChoice: String, CaseIterable, Codable, Identifiable, Sendable {
    case automatic
    case fable
    case opus
    case sonnet
    case haiku

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .automatic: return "Automatic"
        case .fable: return "Fable"
        case .opus: return "Opus"
        case .sonnet: return "Sonnet"
        case .haiku: return "Haiku"
        }
    }

    public var detail: String {
        switch self {
        case .automatic: return "Use Claude Code's default model"
        case .fable: return "The most capable Claude"
        case .opus: return "Deep reasoning for hard problems"
        case .sonnet: return "Balanced speed and intelligence"
        case .haiku: return "Fast and lightweight"
        }
    }

    public var cliValue: String? {
        self == .automatic ? nil : rawValue
    }
}

public enum PermissionMode: String, CaseIterable, Codable, Identifiable, Sendable {
    case ask
    case autoEdits
    case plan
    case auto

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .ask: return "Ask first"
        case .autoEdits: return "Auto-edit"
        case .plan: return "Plan"
        case .auto: return "Auto"
        }
    }

    public var detail: String {
        switch self {
        case .ask: return "Approve commands and file changes yourself"
        case .autoEdits: return "Apply file edits automatically; still ask before commands"
        case .plan: return "Explore and propose a plan without changing files"
        case .auto: return "Let Claude Code's safety classifier decide"
        }
    }

    public var cliValue: String {
        switch self {
        case .ask: return "manual"
        case .autoEdits: return "acceptEdits"
        case .plan: return "plan"
        case .auto: return "auto"
        }
    }

    public var symbol: String {
        switch self {
        case .ask: return "hand.raised"
        case .autoEdits: return "square.and.pencil"
        case .plan: return "map"
        case .auto: return "wand.and.stars"
        }
    }
}

// MARK: - Conversation

public enum MessageRole: String, Codable, Hashable, Sendable {
    case user
    case assistant
}

public enum ToolStatus: String, Codable, Hashable, Sendable {
    case running
    case awaitingPermission
    case completed
    case failed
    case denied
    case interrupted
}

public struct ToolActivity: Codable, Hashable, Identifiable, Sendable {
    public var id: String
    public var name: String
    public var displayName: String?
    public var input: JSONValue
    public var status: ToolStatus
    public var resultText: String?
    public var structuredResult: JSONValue?
    public var isError: Bool
    public var startedAt: Date
    public var completedAt: Date?

    public init(
        id: String,
        name: String,
        displayName: String? = nil,
        input: JSONValue = .object([:]),
        status: ToolStatus = .running,
        resultText: String? = nil,
        structuredResult: JSONValue? = nil,
        isError: Bool = false,
        startedAt: Date = .now,
        completedAt: Date? = nil
    ) {
        self.id = id
        self.name = name
        self.displayName = displayName
        self.input = input
        self.status = status
        self.resultText = resultText
        self.structuredResult = structuredResult
        self.isError = isError
        self.startedAt = startedAt
        self.completedAt = completedAt
    }

    public var filePath: String? {
        input["file_path"]?.stringValue
            ?? input["notebook_path"]?.stringValue
            ?? input["path"]?.stringValue
    }

    public var command: String? {
        input["command"]?.stringValue
    }

    public var isFileMutation: Bool {
        let mutatingTools = ["Edit", "Write", "MultiEdit", "NotebookEdit"]
        return mutatingTools.contains(name)
    }

    public var duration: TimeInterval? {
        guard let completedAt else { return nil }
        return completedAt.timeIntervalSince(startedAt)
    }
}

public struct MessageBlock: Codable, Hashable, Identifiable, Sendable {
    public enum Kind: String, Codable, Hashable, Sendable {
        case text
        case thinking
        case tool
    }

    public var id: UUID
    public var kind: Kind
    public var text: String
    public var tool: ToolActivity?

    public init(id: UUID = UUID(), kind: Kind, text: String = "", tool: ToolActivity? = nil) {
        self.id = id
        self.kind = kind
        self.text = text
        self.tool = tool
    }

    public static func makeText(_ text: String) -> MessageBlock {
        MessageBlock(kind: .text, text: text)
    }

    public static func makeThinking(_ text: String) -> MessageBlock {
        MessageBlock(kind: .thinking, text: text)
    }

    public static func makeTool(_ tool: ToolActivity) -> MessageBlock {
        MessageBlock(kind: .tool, tool: tool)
    }
}

public struct TurnUsage: Codable, Hashable, Sendable {
    public var inputTokens: Int
    public var outputTokens: Int
    public var cacheReadTokens: Int
    public var cacheCreationTokens: Int
    public var costUSD: Double
    public var durationMS: Int?
    public var modelName: String?

    public init(
        inputTokens: Int = 0,
        outputTokens: Int = 0,
        cacheReadTokens: Int = 0,
        cacheCreationTokens: Int = 0,
        costUSD: Double = 0,
        durationMS: Int? = nil,
        modelName: String? = nil
    ) {
        self.inputTokens = inputTokens
        self.outputTokens = outputTokens
        self.cacheReadTokens = cacheReadTokens
        self.cacheCreationTokens = cacheCreationTokens
        self.costUSD = costUSD
        self.durationMS = durationMS
        self.modelName = modelName
    }

    public var totalTokens: Int {
        inputTokens + outputTokens + cacheReadTokens + cacheCreationTokens
    }
}

public struct ConversationTurn: Codable, Hashable, Identifiable, Sendable {
    public var id: UUID
    public var role: MessageRole
    public var createdAt: Date
    public var blocks: [MessageBlock]
    public var isStreaming: Bool
    public var errorText: String?
    public var stopReason: String?
    public var usage: TurnUsage?

    public init(
        id: UUID = UUID(),
        role: MessageRole,
        createdAt: Date = .now,
        blocks: [MessageBlock] = [],
        isStreaming: Bool = false,
        errorText: String? = nil,
        stopReason: String? = nil,
        usage: TurnUsage? = nil
    ) {
        self.id = id
        self.role = role
        self.createdAt = createdAt
        self.blocks = blocks
        self.isStreaming = isStreaming
        self.errorText = errorText
        self.stopReason = stopReason
        self.usage = usage
    }

    public var textContent: String {
        blocks.compactMap { block in
            block.kind == .text ? block.text : nil
        }.joined(separator: "\n\n")
    }

    public var hasVisibleContent: Bool {
        blocks.contains { block in
            switch block.kind {
            case .text, .thinking: return !block.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            case .tool: return true
            }
        }
    }

    public var tools: [ToolActivity] {
        blocks.compactMap(\.tool)
    }
}

public struct ChatSession: Codable, Hashable, Identifiable, Sendable {
    public var id: UUID
    public var claudeSessionID: UUID
    public var title: String
    public var hasCustomTitle: Bool
    public var createdAt: Date
    public var updatedAt: Date
    public var turns: [ConversationTurn]
    public var model: ModelChoice
    public var permissionMode: PermissionMode
    public var claudeStarted: Bool
    public var actualModelName: String?
    public var totalCostUSD: Double
    public var providerID: UUID?
    /// Last cumulative per-model usage reported by Claude Code. Used to price
    /// the next turn from the difference rather than from its assumptions.
    public var modelUsage: [String: ModelTokenUsage]?
    /// Prompt tokens in the latest request, including cache reads and writes.
    /// Optional so state written before the context bar decodes unchanged.
    public var contextTokens: Int?
    /// Model that reported `contextTokens`, used to pick a context-window size.
    public var contextModelName: String?
    /// Claude Code's own cumulative cost, kept separately from Gantry's
    /// model-priced estimate so fallback deltas stay on the same scale.
    public var claudeReportedCostUSD: Double?

    public init(
        id: UUID = UUID(),
        claudeSessionID: UUID? = nil,
        title: String = "New session",
        hasCustomTitle: Bool = false,
        createdAt: Date = .now,
        updatedAt: Date = .now,
        turns: [ConversationTurn] = [],
        model: ModelChoice = .automatic,
        permissionMode: PermissionMode = .ask,
        claudeStarted: Bool = false,
        actualModelName: String? = nil,
        totalCostUSD: Double = 0,
        providerID: UUID? = nil,
        modelUsage: [String: ModelTokenUsage]? = nil,
        contextTokens: Int? = nil,
        contextModelName: String? = nil,
        claudeReportedCostUSD: Double? = nil
    ) {
        self.id = id
        self.claudeSessionID = claudeSessionID ?? id
        self.title = title
        self.hasCustomTitle = hasCustomTitle
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.turns = turns
        self.model = model
        self.permissionMode = permissionMode
        self.claudeStarted = claudeStarted
        self.actualModelName = actualModelName
        self.totalCostUSD = totalCostUSD
        self.providerID = providerID
        self.modelUsage = modelUsage
        self.contextTokens = contextTokens
        self.contextModelName = contextModelName
        self.claudeReportedCostUSD = claudeReportedCostUSD
    }

    public var firstUserPrompt: String? {
        turns.first(where: { $0.role == .user })?.textContent
    }

    public var isEmpty: Bool {
        turns.isEmpty
    }

    public var displayModelName: String {
        actualModelName ?? model.title
    }

    public var tools: [ToolActivity] {
        turns.flatMap(\.tools)
    }

    public var changedFilePaths: [String] {
        var seen = Set<String>()
        return tools.compactMap { tool in
            guard tool.isFileMutation, let path = tool.filePath else { return nil }
            return seen.insert(path).inserted ? path : nil
        }
    }

    public var totalTokens: Int {
        turns.compactMap(\.usage).reduce(0) { $0 + $1.totalTokens }
    }
}

public struct Project: Codable, Hashable, Identifiable, Sendable {
    public var id: UUID
    public var path: String
    public var name: String
    public var createdAt: Date
    public var lastOpenedAt: Date
    public var sessions: [ChatSession]
    /// Optional so state written before code-host plugins decodes unchanged.
    public var pluginID: UUID?
    /// Optional so state written before mod authoring decodes unchanged.
    /// When set to this project's folder, its chats launch with `--plugin-dir`.
    public var devModPath: String?

    public init(
        id: UUID = UUID(),
        path: String,
        name: String,
        createdAt: Date = .now,
        lastOpenedAt: Date = .now,
        sessions: [ChatSession] = [],
        pluginID: UUID? = nil,
        devModPath: String? = nil
    ) {
        self.id = id
        self.path = path
        self.name = name
        self.createdAt = createdAt
        self.lastOpenedAt = lastOpenedAt
        self.sessions = sessions
        self.pluginID = pluginID
        self.devModPath = devModPath
    }

    public var url: URL {
        URL(fileURLWithPath: path, isDirectory: true)
    }

    public var sortedSessions: [ChatSession] {
        sessions.sorted { $0.updatedAt > $1.updatedAt }
    }
}

// MARK: - Persistence

/// A saved marketplace repository. `source` is `ClaudeMarketplace.stableKey`
/// when known so a rename does not orphan the favorite.
public struct FavoriteMarketplace: Codable, Hashable, Identifiable, Sendable {
    public var name: String
    public var source: String?

    public var id: String { source ?? "name:\(name)" }

    public init(name: String, source: String? = nil) {
        self.name = name
        self.source = source
    }
}

public struct AppSettings: Codable, Hashable, Sendable {
    public var defaultModel: ModelChoice
    public var defaultPermissionMode: PermissionMode
    public var claudePathOverride: String?
    public var showsInspector: Bool
    public var sidebarWidth: Double
    /// Optional so state written before the appearance control continues to decode.
    public var appearance: AppearanceMode?
    /// Optional so state written before code-host plugins decodes unchanged.
    public var plugins: [PluginConnection]?
    /// Optional so state written by Gantry 0.1.0 continues to decode.
    public var providers: [AIProvider]?
    public var defaultProviderID: UUID?
    /// Optional so state written before extension management decodes unchanged.
    public var favoriteMarketplaces: [FavoriteMarketplace]?
    /// Last folder used by the Create Mod wizard.
    public var modsDirectory: String?

    public init(
        defaultModel: ModelChoice = .automatic,
        defaultPermissionMode: PermissionMode = .ask,
        claudePathOverride: String? = nil,
        showsInspector: Bool = true,
        sidebarWidth: Double = 274,
        appearance: AppearanceMode? = nil,
        plugins: [PluginConnection]? = nil,
        providers: [AIProvider]? = nil,
        defaultProviderID: UUID? = nil,
        favoriteMarketplaces: [FavoriteMarketplace]? = nil,
        modsDirectory: String? = nil
    ) {
        self.defaultModel = defaultModel
        self.defaultPermissionMode = defaultPermissionMode
        self.claudePathOverride = claudePathOverride
        self.showsInspector = showsInspector
        self.sidebarWidth = sidebarWidth
        self.appearance = appearance
        self.plugins = plugins
        self.providers = providers
        self.defaultProviderID = defaultProviderID
        self.favoriteMarketplaces = favoriteMarketplaces
        self.modsDirectory = modsDirectory
    }
}

public struct AppSnapshot: Codable, Sendable {
    public var version: Int
    public var projects: [Project]
    public var selectedProjectID: UUID?
    public var selectedSessionID: UUID?
    public var settings: AppSettings

    public init(
        version: Int = 2,
        projects: [Project] = [],
        selectedProjectID: UUID? = nil,
        selectedSessionID: UUID? = nil,
        settings: AppSettings = AppSettings()
    ) {
        self.version = version
        self.projects = projects
        self.selectedProjectID = selectedProjectID
        self.selectedSessionID = selectedSessionID
        self.settings = settings
    }
}
