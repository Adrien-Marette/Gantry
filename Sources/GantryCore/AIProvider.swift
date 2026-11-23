import Foundation

public enum ProviderPreset: String, Codable, Hashable, Sendable, CaseIterable {
    case claudeCode
    case anthropic
    case deepSeek
    case custom

    public var title: String {
        switch self {
        case .claudeCode: return "Claude Code"
        case .anthropic: return "Anthropic API"
        case .deepSeek: return "DeepSeek"
        case .custom: return "Custom provider"
        }
    }

    public var defaultBaseURL: String {
        switch self {
        case .claudeCode, .custom: return ""
        case .anthropic: return "https://api.anthropic.com"
        case .deepSeek: return "https://api.deepseek.com/anthropic"
        }
    }

    public var defaultAuthMode: ProviderAuthMode {
        switch self {
        case .claudeCode: return .inherit
        case .anthropic: return .apiKey
        case .deepSeek, .custom: return .authToken
        }
    }

    /// Provider-specific environment defaults. These are editable after creation.
    public var suggestedModels: (main: String, opus: String, sonnet: String, haiku: String, subagent: String) {
        switch self {
        case .anthropic:
            return (
                "claude-sonnet-5-5",
                "claude-opus-5-5",
                "claude-sonnet-5-5",
                "claude-haiku-5-5",
                "claude-haiku-5-5"
            )
        case .claudeCode, .deepSeek, .custom:
            return ("", "", "", "", "")
        }
    }
}

public enum ProviderAuthMode: String, Codable, Hashable, Sendable, CaseIterable {
    case inherit
    case authToken
    case apiKey

    public var title: String {
        switch self {
        case .inherit: return "Use Claude Code login"
        case .authToken: return "Authorization token"
        case .apiKey: return "API key"
        }
    }

    public var detail: String {
        switch self {
        case .inherit:
            return "Use the credentials and settings already configured in Claude Code."
        case .authToken:
            return "Send the key as a bearer token. Recommended for Anthropic-compatible gateways."
        case .apiKey:
            return "Send the key as an Anthropic API key. Best for api.anthropic.com."
        }
    }

    public var environmentVariable: String? {
        switch self {
        case .inherit: return nil
        case .authToken: return "ANTHROPIC_AUTH_TOKEN"
        case .apiKey: return "ANTHROPIC_API_KEY"
        }
    }
}

/// A named provider configuration. The API key itself is never stored here;
/// it lives in the macOS Keychain (Apple Passwords) under `keychainServer` +
/// `keychainAccount`.
public struct AIProvider: Codable, Hashable, Identifiable, Sendable {
    public static let claudeCodeID = UUID(uuidString: "C1A0D000-0000-4000-8000-000000000001")!

    public var id: UUID
    public var name: String
    public var preset: ProviderPreset
    public var baseURL: String
    public var authMode: ProviderAuthMode
    public var mainModel: String
    public var opusModel: String
    public var sonnetModel: String
    public var haikuModel: String
    public var subagentModel: String
    public var extraEnvironment: [String: String]
    public var keychainServer: String
    public var keychainAccount: String
    public var isBuiltIn: Bool

    public init(
        id: UUID = UUID(),
        name: String,
        preset: ProviderPreset,
        baseURL: String = "",
        authMode: ProviderAuthMode = .authToken,
        mainModel: String = "",
        opusModel: String = "",
        sonnetModel: String = "",
        haikuModel: String = "",
        subagentModel: String = "",
        extraEnvironment: [String: String] = [:],
        keychainServer: String = "",
        keychainAccount: String = "",
        isBuiltIn: Bool = false
    ) {
        self.id = id
        self.name = name
        self.preset = preset
        self.baseURL = baseURL
        self.authMode = authMode
        self.mainModel = mainModel
        self.opusModel = opusModel
        self.sonnetModel = sonnetModel
        self.haikuModel = haikuModel
        self.subagentModel = subagentModel
        self.extraEnvironment = extraEnvironment
        self.keychainServer = keychainServer
        self.keychainAccount = keychainAccount
        self.isBuiltIn = isBuiltIn
    }

    public static let claudeCodeDefault = AIProvider(
        id: claudeCodeID,
        name: "Claude Code",
        preset: .claudeCode,
        authMode: .inherit,
        isBuiltIn: true
    )

    public static func make(
        preset: ProviderPreset,
        name: String,
        baseURL: String? = nil,
        id: UUID = UUID()
    ) -> AIProvider {
        let models = preset.suggestedModels
        let resolvedBaseURL = baseURL ?? preset.defaultBaseURL
        let server = Self.host(from: resolvedBaseURL)
            ?? (preset == .anthropic ? "api.anthropic.com" : (preset == .deepSeek ? "api.deepseek.com" : "Gantry.local"))
        return AIProvider(
            id: id,
            name: name,
            preset: preset,
            baseURL: resolvedBaseURL,
            authMode: preset.defaultAuthMode,
            mainModel: models.main,
            opusModel: models.opus,
            sonnetModel: models.sonnet,
            haikuModel: models.haiku,
            subagentModel: models.subagent,
            keychainServer: server,
            keychainAccount: "Gantry · \(name)"
        )
    }

    public var requiresAPIKey: Bool {
        authMode != .inherit
    }

    public var keychainLabel: String {
        "Gantry — \(name)"
    }

    public var displayBaseURL: String {
        baseURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? "Claude Code's current setup"
            : baseURL
    }

    /// Values that should be removed from the inherited process environment
    /// before applying this profile. This prevents a key intended for one
    /// provider from being sent to another provider's endpoint.
    public var environmentKeysToClear: [String] {
        switch authMode {
        case .inherit: return []
        case .authToken: return ["ANTHROPIC_API_KEY"]
        case .apiKey: return ["ANTHROPIC_AUTH_TOKEN"]
        }
    }

    public func environment(apiKey: String?) -> [String: String] {
        var environment = extraEnvironment
        let trimmedBaseURL = baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedBaseURL.isEmpty {
            environment["ANTHROPIC_BASE_URL"] = trimmedBaseURL
        }
        assignIfPresent(mainModel, key: "ANTHROPIC_MODEL", to: &environment)
        assignIfPresent(opusModel, key: "ANTHROPIC_DEFAULT_OPUS_MODEL", to: &environment)
        assignIfPresent(sonnetModel, key: "ANTHROPIC_DEFAULT_SONNET_MODEL", to: &environment)
        assignIfPresent(haikuModel, key: "ANTHROPIC_DEFAULT_HAIKU_MODEL", to: &environment)
        assignIfPresent(subagentModel, key: "CLAUDE_CODE_SUBAGENT_MODEL", to: &environment)
        if let apiKey, let variable = authMode.environmentVariable, !apiKey.isEmpty {
            environment[variable] = apiKey
        }
        return environment
    }

    public static func host(from baseURL: String) -> String? {
        let trimmed = baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              let url = URL(string: trimmed),
              let host = url.host,
              !host.isEmpty else {
            return nil
        }
        return host
    }

    private func assignIfPresent(_ value: String, key: String, to dictionary: inout [String: String]) {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty {
            dictionary[key] = trimmed
        }
    }
}
