import Foundation
import Testing
@testable import GantryCore

@Test func providerEnvironmentMapsModelsAndSecret() {
    let provider = AIProvider(
        name: "Test Gateway",
        preset: .custom,
        baseURL: "https://gateway.example.com/anthropic",
        authMode: .authToken,
        mainModel: "gateway-main",
        opusModel: "gateway-large",
        sonnetModel: "gateway-medium",
        haikuModel: "gateway-small",
        subagentModel: "gateway-subagent",
        extraEnvironment: ["CLAUDE_CODE_AUTO_COMPACT_WINDOW": "786432"]
    )
    let environment = provider.environment(apiKey: "secret-value")
    #expect(environment["ANTHROPIC_BASE_URL"] == "https://gateway.example.com/anthropic")
    #expect(environment["ANTHROPIC_MODEL"] == "gateway-main")
    #expect(environment["ANTHROPIC_DEFAULT_OPUS_MODEL"] == "gateway-large")
    #expect(environment["ANTHROPIC_DEFAULT_SONNET_MODEL"] == "gateway-medium")
    #expect(environment["ANTHROPIC_DEFAULT_HAIKU_MODEL"] == "gateway-small")
    #expect(environment["CLAUDE_CODE_SUBAGENT_MODEL"] == "gateway-subagent")
    #expect(environment["CLAUDE_CODE_AUTO_COMPACT_WINDOW"] == "786432")
    #expect(environment["ANTHROPIC_AUTH_TOKEN"] == "secret-value")
    #expect(environment["ANTHROPIC_API_KEY"] == nil)
    #expect(provider.environmentKeysToClear == ["ANTHROPIC_API_KEY"])
    #expect(provider.requiresAPIKey)
}

@Test func providerEnvironmentForAPIKeyMode() {
    let provider = AIProvider(
        name: "Official",
        preset: .anthropic,
        baseURL: "https://api.anthropic.com",
        authMode: .apiKey
    )
    let environment = provider.environment(apiKey: "anthropic-key")
    #expect(environment["ANTHROPIC_API_KEY"] == "anthropic-key")
    #expect(environment["ANTHROPIC_AUTH_TOKEN"] == nil)
    #expect(provider.environmentKeysToClear == ["ANTHROPIC_AUTH_TOKEN"])
}

@Test func builtInProviderUsesClaudeCodeSettings() {
    let provider = AIProvider.claudeCodeDefault
    #expect(provider.isBuiltIn)
    #expect(provider.preset == .claudeCode)
    #expect(provider.authMode == .inherit)
    #expect(!provider.requiresAPIKey)
    #expect(provider.environmentKeysToClear.isEmpty)
    #expect(provider.environment(apiKey: "ignored").isEmpty)
}

@Test func anthropicPresetHasEditableModelDefaults() {
    let provider = AIProvider.make(preset: .anthropic, name: "Anthropic API")
    #expect(provider.baseURL == "https://api.anthropic.com")
    #expect(provider.authMode == .apiKey)
    #expect(provider.mainModel == "claude-sonnet-5-5")
    #expect(provider.keychainServer == "api.anthropic.com")
    #expect(provider.keychainAccount == "Gantry · Anthropic API")
}

@Test func legacySettingsDecodeWithoutProviders() throws {
    let json = """
    {"defaultModel":"automatic","defaultPermissionMode":"ask","showsInspector":true,"sidebarWidth":274}
    """.data(using: .utf8)!
    let settings = try JSONDecoder().decode(AppSettings.self, from: json)
    #expect(settings.providers == nil)
    #expect(settings.defaultProviderID == nil)
    #expect(settings.appearance == nil)
    #expect(settings.plugins == nil)
    #expect(settings.favoriteMarketplaces == nil)
    #expect(settings.modsDirectory == nil)
    #expect(settings.defaultModel == .automatic)
}

@Test func legacySessionDecodesWithoutProviderID() throws {
    let id = UUID()
    let json = """
    {
      "id": "\(id.uuidString)",
      "claudeSessionID": "\(id.uuidString)",
      "title": "Old session",
      "hasCustomTitle": false,
      "createdAt": "2026-01-01T00:00:00Z",
      "updatedAt": "2026-01-01T00:00:00Z",
      "turns": [],
      "model": "automatic",
      "permissionMode": "ask",
      "claudeStarted": false,
      "totalCostUSD": 0
    }
    """.data(using: .utf8)!
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    let session = try decoder.decode(ChatSession.self, from: json)
    #expect(session.providerID == nil)
    #expect(session.modelUsage == nil)
    #expect(session.claudeReportedCostUSD == nil)
    #expect(session.contextTokens == nil)
    #expect(session.contextModelName == nil)
    #expect(session.title == "Old session")
}

@Test func runtimeReceivesProviderEnvironment() async throws {
    let root = GantryTestTempRoot.url
        .appendingPathComponent("Gantry-provider-env-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    let executable = root.appendingPathComponent("fake-claude")
    let capture = root.appendingPathComponent("environment.txt")
    let script = """
    #!/bin/sh
    {
      printf 'BASE=%s\\n' "$ANTHROPIC_BASE_URL"
      printf 'AUTH=%s\\n' "$ANTHROPIC_AUTH_TOKEN"
      printf 'APIKEY=%s\\n' "$ANTHROPIC_API_KEY"
      printf 'MODEL=%s\\n' "$ANTHROPIC_MODEL"
    } > "$Gantry_TEST_ENV_CAPTURE"
    sleep 1
    """
    try script.write(to: executable, atomically: false, encoding: .utf8)
    try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: executable.path)
    setenv("Gantry_TEST_ENV_CAPTURE", capture.path, 1)
    defer {
        unsetenv("Gantry_TEST_ENV_CAPTURE")
        try? FileManager.default.removeItem(at: root)
    }

    let configuration = ClaudeLaunchConfiguration(
        executableURL: executable,
        workingDirectory: root,
        claudeSessionID: UUID(),
        resume: false,
        model: .automatic,
        permissionMode: .ask,
        environmentOverrides: [
            "ANTHROPIC_BASE_URL": "https://provider.example.com",
            "ANTHROPIC_AUTH_TOKEN": "test-token",
            "ANTHROPIC_MODEL": "provider-model"
        ],
        removedEnvironmentKeys: ["ANTHROPIC_API_KEY"]
    )
    let runtime = try ClaudeRuntime(configuration: configuration)
    defer { runtime.terminate() }

    var contents: String?
    for _ in 0..<40 {
        if FileManager.default.fileExists(atPath: capture.path),
           let value = try? String(contentsOf: capture, encoding: .utf8),
           value.contains("AUTH=") {
            contents = value
            break
        }
        try await Task.sleep(for: .milliseconds(50))
    }
    let captured = try #require(contents)
    #expect(captured.contains("BASE=https://provider.example.com"))
    #expect(captured.contains("AUTH=test-token"))
    #expect(captured.contains("APIKEY=\n"))
    #expect(captured.contains("MODEL=provider-model"))
}

@Test func keychainRoundTrip() throws {
    guard ProcessInfo.processInfo.environment["Gantry_RUN_KEYCHAIN_TESTS"] == "1" else {
        return
    }
    let unique = UUID().uuidString
    let provider = AIProvider(
        name: "Gantry Keychain Test",
        preset: .custom,
        baseURL: "https://Gantry-keychain-test.example.com",
        authMode: .authToken,
        keychainServer: "Gantry-keychain-test-\(unique).example.com",
        keychainAccount: "Gantry · Test · \(unique)"
    )
    defer { try? ProviderKeychain.deleteKey(for: provider) }

    try ProviderKeychain.store("first-test-value", for: provider)
    #expect(try ProviderKeychain.secret(for: provider) == "first-test-value")
    #expect(ProviderKeychain.hasKey(for: provider))

    try ProviderKeychain.store("second-test-value", for: provider)
    #expect(try ProviderKeychain.secret(for: provider) == "second-test-value")

    try ProviderKeychain.deleteKey(for: provider)
    #expect(try ProviderKeychain.secret(for: provider) == nil)
    #expect(!ProviderKeychain.hasKey(for: provider))
}
