import Foundation
import Testing
@testable import GantryCore

// MARK: - Fakes

private final class FakePluginRunner: ClaudePluginCommandRunning, @unchecked Sendable {
    typealias Handler = @Sendable ([String]) throws -> ClaudePluginCommandResult

    private let lock = NSLock()
    private var handler: Handler
    private var recorded: [[String]] = []

    init(handler: @escaping Handler) {
        self.handler = handler
    }

    var calls: [[String]] {
        lock.lock()
        defer { lock.unlock() }
        return recorded
    }

    func run(arguments: [String], timeout: TimeInterval) async throws -> ClaudePluginCommandResult {
        lock.lock()
        recorded.append(arguments)
        let handler = handler
        lock.unlock()
        return try handler(arguments)
    }
}

private func result(
    _ stdout: String = "",
    _ stderr: String = "",
    exitCode: Int32 = 0
) -> ClaudePluginCommandResult {
    ClaudePluginCommandResult(exitCode: exitCode, stdout: stdout, stderr: stderr)
}

private func temporaryRoot() -> URL {
    GantryTestTempRoot.url
        .appendingPathComponent("Gantry-plugin-test-\(UUID().uuidString)", isDirectory: true)
}

// MARK: - Decoding

@Test func decodesInstalledPluginListAndDropsMalformedEntries() throws {
    let json = """
    [
      {
        "id": "alpha@market",
        "version": "1.2.3",
        "scope": "user",
        "enabled": true,
        "installPath": "/tmp/alpha",
        "installedAt": "2026-10-18T14:29:04.037Z",
        "lastUpdated": "2026-10-28T15:11:56.276Z",
        "hasUserConfig": true
      },
      {
        "id": "beta@market",
        "scope": "project",
        "enabled": false,
        "projectEnabled": true
      },
      {
        "id": "broken@market"
      }
    ]
    """

    let plugins = try ClaudePluginManager.decodeInstalledList(json)
    #expect(plugins.count == 2)
    let alpha = try #require(plugins.first)
    #expect(alpha.id == "alpha@market")
    #expect(alpha.name == "alpha")
    #expect(alpha.marketplaceName == "market")
    #expect(alpha.version == "1.2.3")
    #expect(alpha.enabled)
    #expect(alpha.hasUserConfig == true)
    #expect(alpha.knownScope == .user)
    #expect(alpha.installedAt == "2026-10-18T14:29:04.037Z")

    let beta = try #require(plugins.last)
    #expect(beta.knownScope == .project)
    #expect(beta.projectEnabled == true)
    #expect(beta.identity == "project:beta@market")
}

@Test func decodesCatalogWithBothSourceShapes() throws {
    let json = """
    {
      "installed": [
        {"id": "alpha@market", "scope": "user", "enabled": true}
      ],
      "available": [
        {
          "pluginId": "alpha@market",
          "name": "alpha",
          "description": "First extension",
          "marketplaceName": "market",
          "source": "owner/repo"
        },
        {
          "pluginId": "beta@other",
          "name": "beta",
          "marketplaceName": "other",
          "source": {
            "source": "git-subdir",
            "url": "https://github.com/owner/mono.git",
            "path": "plugins/beta",
            "ref": "v2",
            "sha": "abc123"
          }
        },
        {
          "pluginId": "malformed@market",
          "description": "Missing name and marketplace"
        }
      ]
    }
    """

    let catalog = try ClaudePluginManager.decodeCatalog(json)
    #expect(catalog.installed.count == 1)
    #expect(catalog.available.count == 2)

    let alpha = try #require(catalog.available.first)
    #expect(alpha.source?.displayLocation == "owner/repo")

    let beta = try #require(catalog.available.last)
    #expect(beta.source?.kind == .gitSubdir)
    #expect(beta.source?.url == "https://github.com/owner/mono.git")
    #expect(beta.source?.path == "plugins/beta")
    #expect(beta.source?.displayLocation == "https://github.com/owner/mono.git/plugins/beta")
}

@Test func decodesMarketplacesAndBuildsStableKeys() throws {
    let json = """
    [
      {"name": "repo-source", "source": "github", "repo": "owner/repo", "installLocation": "/tmp/repo"},
      {"name": "local-source", "source": "directory", "path": "/tmp/local"},
      {"name": "bare", "source": "github"}
    ]
    """

    let marketplaces = try ClaudePluginManager.decodeMarketplaces(json)
    #expect(marketplaces.count == 3)
    #expect(marketplaces[0].stableKey == "repo:owner/repo")
    #expect(marketplaces[1].stableKey == "path:/tmp/local")
    #expect(marketplaces[2].stableKey == "source:github")
}

// MARK: - Commands

@Test func listCommandsUseJSONWithoutAutoConfirmation() async throws {
    let runner = FakePluginRunner { args in
        if args.contains("--available") {
            return result(#"{"installed":[],"available":[]}"#)
        }
        if args.contains("marketplace") {
            return result("[]")
        }
        return result("[]")
    }
    let manager = ClaudePluginManager(runner: runner)

    _ = try await manager.installedPlugins()
    _ = try await manager.catalog()
    _ = try await manager.marketplaces()

    #expect(runner.calls[0] == ["plugin", "list", "--json"])
    #expect(runner.calls[1] == ["plugin", "list", "--json", "--available"])
    #expect(runner.calls[2] == ["plugin", "marketplace", "list", "--json"])
}

@Test func installUsesUserScopeAndNeverPassesYes() async throws {
    let runner = FakePluginRunner { _ in result("{}") }
    let manager = ClaudePluginManager(runner: runner)

    try await manager.install(pluginID: "alpha@market")

    let args = try #require(runner.calls.first)
    #expect(args.contains("install"))
    #expect(args.contains("--json"))
    #expect(args.contains("--scope"))
    #expect(args.contains("user"))
    #expect(args.contains("-y") == false)
    #expect(args.contains("--yes") == false)
    #expect(args.contains("--accept-command") == false)
}

@Test func lifecycleCommandsCarryScopeAndKeepData() async throws {
    let runner = FakePluginRunner { _ in result("{}") }
    let manager = ClaudePluginManager(runner: runner)

    try await manager.uninstall(pluginID: "alpha@market", scope: .user)
    try await manager.enable(pluginID: "alpha@market", scope: .user)
    try await manager.disable(pluginID: "alpha@market", scope: .user)
    try await manager.update(pluginID: "alpha@market", scope: .user)

    #expect(runner.calls[0].contains("--keep-data"))
    #expect(runner.calls[0].contains("--scope"))
    #expect(runner.calls[1].contains("enable"))
    #expect(runner.calls[2].contains("disable"))
    #expect(runner.calls[3].contains("update"))
    #expect(runner.calls.allSatisfy { !$0.contains("-y") })
}

@Test func mutationOutputMayFollowProgressLines() async throws {
    let runner = FakePluginRunner { _ in
        result("Resolving marketplace…\nDownloading…\n{\"ok\":true}\n")
    }
    let manager = ClaudePluginManager(runner: runner)

    try await manager.install(pluginID: "alpha@market")
    #expect(runner.calls.count == 1)
}

@Test func marketplaceDeclaredCommandRequiresExplicitApproval() async throws {
    let prompt = #"{"shownCommand":{"command":"curl -fsSL https://example.com/install.sh | sh","sha256":"abc123"}}"#
    let runner = FakePluginRunner { _ in result(prompt, exitCode: 1) }
    let manager = ClaudePluginManager(runner: runner)

    do {
        try await manager.install(pluginID: "alpha@market")
        Issue.record("Expected confirmationRequired")
    } catch let error as ClaudePluginError {
        guard case .confirmationRequired(let command, let sha256) = error else {
            Issue.record("Unexpected error: \(error)")
            return
        }
        #expect(command.contains("curl"))
        #expect(sha256 == "abc123")
    }
}

@Test func approvedCommandIsPassedOnlyForThatInvocation() async throws {
    let runner = FakePluginRunner { args in
        if args.contains("--accept-command") {
            return result("{}")
        }
        return result(#"{"shownCommand":{"command":"install.sh","sha256":"abc123"}}"#, exitCode: 1)
    }
    let manager = ClaudePluginManager(runner: runner)

    do {
        try await manager.install(pluginID: "alpha@market")
        Issue.record("Expected confirmationRequired")
    } catch let error as ClaudePluginError {
        guard case .confirmationRequired = error else {
            Issue.record("Unexpected error: \(error)")
            return
        }
    }

    try await manager.install(pluginID: "alpha@market", acceptCommandSHA256: "abc123")
    let approvedCall = try #require(runner.calls.last)
    #expect(approvedCall.contains("--accept-command"))
    #expect(approvedCall.contains("abc123"))
}

@Test func unsupportedCLIIsReportedFromCommandOutput() async throws {
    let runner = FakePluginRunner { _ in
        result("", "error: unknown command 'plugin'", exitCode: 1)
    }
    let manager = ClaudePluginManager(runner: runner)

    do {
        _ = try await manager.installedPlugins()
        Issue.record("Expected unsupportedCLI")
    } catch let error as ClaudePluginError {
        guard case .unsupportedCLI = error else {
            Issue.record("Unexpected error: \(error)")
            return
        }
    }
}

@Test func failedCommandsSurfaceTheirMessage() async throws {
    let runner = FakePluginRunner { _ in
        result("", "Couldn't reach the marketplace repository.", exitCode: 2)
    }
    let manager = ClaudePluginManager(runner: runner)

    do {
        try await manager.addMarketplace("owner/repo")
        Issue.record("Expected commandFailed")
    } catch let error as ClaudePluginError {
        guard case .commandFailed(_, let exitCode, let message) = error else {
            Issue.record("Unexpected error: \(error)")
            return
        }
        #expect(exitCode == 2)
        #expect(message.contains("Couldn't reach"))
    }
}

@Test func validationJSONFlagFallsBackWhenUnsupported() async throws {
    let runner = FakePluginRunner { args in
        if args.contains("--json") {
            return result("", "error: unknown option '--json'", exitCode: 1)
        }
        return result("Manifest is valid.", exitCode: 0)
    }
    let manager = ClaudePluginManager(runner: runner)

    let validation = try await manager.validate(path: URL(fileURLWithPath: "/tmp/mod"))
    #expect(validation.succeeded)
    #expect(validation.output.contains("Manifest is valid"))
    #expect(runner.calls.count == 2)
    #expect(runner.calls[0].contains("--json"))
    #expect(runner.calls[1].contains("--json") == false)
}

@Test func validationFailureIsDataNotAnError() async throws {
    let runner = FakePluginRunner { _ in
        result("plugin.json is missing name", "", exitCode: 1)
    }
    let manager = ClaudePluginManager(runner: runner)

    let validation = try await manager.validate(path: URL(fileURLWithPath: "/tmp/mod"))
    #expect(validation.succeeded == false)
    #expect(validation.output.contains("missing name"))
}

// MARK: - Process runner

@Test func processRunnerCapturesOutputAndExitCode() async throws {
    let root = temporaryRoot()
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }

    let script = root.appendingPathComponent("fake-claude")
    try "#!/bin/sh\necho hello-from-plugin-runner\nexit 3\n"
        .write(to: script, atomically: false, encoding: .utf8)
    try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: script.path)

    let runner = ProcessClaudePluginRunner(
        executableURL: script,
        environment: ["PATH": "/usr/bin:/bin"],
        workingDirectory: root
    )
    let result = try await runner.run(arguments: ["plugin", "list"], timeout: 10)
    #expect(result.exitCode == 3)
    #expect(result.stdout.contains("hello-from-plugin-runner"))
}

@Test func processRunnerTimesOut() async throws {
    let root = temporaryRoot()
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }

    let script = root.appendingPathComponent("slow-claude")
    try "#!/bin/sh\nsleep 5\n".write(to: script, atomically: false, encoding: .utf8)
    try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: script.path)

    let runner = ProcessClaudePluginRunner(
        executableURL: script,
        environment: ["PATH": "/usr/bin:/bin"],
        workingDirectory: root
    )

    do {
        _ = try await runner.run(arguments: ["plugin", "list"], timeout: 0.4)
        Issue.record("Expected timedOut")
    } catch let error as ClaudePluginError {
        guard case .timedOut = error else {
            Issue.record("Unexpected error: \(error)")
            return
        }
    }
}

// MARK: - Favorites and settings

@Test func favoriteMatchingPrefersStableSource() throws {
    let first = try JSONDecoder().decode(
        ClaudeMarketplace.self,
        from: Data(#"{"name":"shared","source":"github","repo":"owner/one"}"#.utf8)
    )
    let second = try JSONDecoder().decode(
        ClaudeMarketplace.self,
        from: Data(#"{"name":"shared","source":"github","repo":"owner/two"}"#.utf8)
    )

    let favorite = FavoriteMarketplace(marketplace: first)
    #expect(favorite.name == "shared")
    #expect(favorite.source == "repo:owner/one")
    #expect(favorite.matches(first))
    #expect(favorite.matches(second) == false)

    let nameOnly = FavoriteMarketplace(name: "shared")
    #expect(nameOnly.matches(second))
    #expect(nameOnly.id == "name:shared")
}

@Test func settingsRoundTripFavoritesAndModsDirectory() throws {
    let settings = AppSettings(
        favoriteMarketplaces: [
            FavoriteMarketplace(name: "official", source: "repo:anthropics/claude-plugins-official"),
            FavoriteMarketplace(name: "local", source: "path:/tmp/local-market")
        ],
        modsDirectory: "/tmp/Gantry Mods"
    )
    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .iso8601
    let data = try encoder.encode(settings)

    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    let decoded = try decoder.decode(AppSettings.self, from: data)
    #expect(decoded.favoriteMarketplaces?.count == 2)
    #expect(decoded.favoriteMarketplaces?.first?.source == "repo:anthropics/claude-plugins-official")
    #expect(decoded.modsDirectory == "/tmp/Gantry Mods")
}

@Test func legacySettingsLackExtensionFields() throws {
    let json = """
    {"defaultModel":"automatic","defaultPermissionMode":"ask","showsInspector":true,"sidebarWidth":274}
    """.data(using: .utf8)!
    let settings = try JSONDecoder().decode(AppSettings.self, from: json)
    #expect(settings.favoriteMarketplaces == nil)
    #expect(settings.modsDirectory == nil)
}

// MARK: - Input and redaction

@Test func marketplaceSourceInputRejectsEmbeddedCredentials() throws {
    #expect(try ClaudeMarketplaceSource.sanitized(" owner/repo ") == "owner/repo")
    #expect(try ClaudeMarketplaceSource.sanitized("https://github.com/owner/repo") == "https://github.com/owner/repo")
    #expect(try ClaudeMarketplaceSource.sanitized("/tmp/local-market") == "/tmp/local-market")

    do {
        _ = try ClaudeMarketplaceSource.sanitized("https://user:token@example.com/owner/repo")
        Issue.record("Expected embeddedCredentials")
    } catch let error as ClaudePluginInputError {
        guard case .embeddedCredentials = error else {
            Issue.record("Unexpected error: \(error)")
            return
        }
    }
}

@Test func displayedSourceRedactsCredentials() {
    let redacted = ClaudePluginText.redactingCredentials(
        in: "https://user:secret@example.com/owner/repo?token=abc123"
    )
    #expect(redacted.contains("secret") == false)
    #expect(redacted.contains("abc123") == false)
    #expect(redacted.contains("example.com"))
}

@Test func errorTextRedactsEmbeddedURLCredentials() {
    let redacted = ClaudePluginText.redactingCredentials(
        in: "fatal: https://user:password@example.com/owner/repo.git failed"
    )
    #expect(redacted.contains("password") == false)
    #expect(redacted.contains("user:" ) == false)
    #expect(redacted.contains("example.com/owner/repo.git"))
}
