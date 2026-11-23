import Foundation
import Observation
import GantryCore

@MainActor
@Observable
final class ExtensionsModel {
    enum LoadState: Equatable {
        case idle
        case loading
        case loaded
        case failed(String)
    }

    var installedPlugins: [ClaudeInstalledPlugin] = []
    var availablePlugins: [ClaudeAvailablePlugin] = []
    var marketplaces: [ClaudeMarketplace] = []
    var loadState: LoadState = .idle
    var isRefreshing = false
    var errorMessage: String?
    var browseError: String?
    var busyKey: String?
    var lastLoadedAt: Date?

    @ObservationIgnored private let app: AppModel
    @ObservationIgnored private var manager: ClaudePluginManager?
    @ObservationIgnored private var managerPath: String?

    init(app: AppModel) {
        self.app = app
    }

    // MARK: - Loading

    func start() async {
        guard loadState == .idle else { return }
        await reload()
    }

    func reload() async {
        guard !isRefreshing else { return }
        isRefreshing = true
        if loadState != .loaded {
            loadState = .loading
        }
        browseError = nil
        defer { isRefreshing = false }

        guard let manager = makeManager() else {
            loadState = .failed(cliMessage)
            return
        }

        var installedLoaded = false
        do {
            let catalog = try await manager.catalog()
            installedPlugins = catalog.installed
            availablePlugins = catalog.available
            installedLoaded = true
        } catch {
            browseError = userMessage(error)
            do {
                installedPlugins = try await manager.installedPlugins()
                installedLoaded = true
            } catch {
                // Keep any previous state; the marketplace load below decides
                // whether the page is usable at all.
            }
        }

        do {
            marketplaces = try await manager.marketplaces()
        } catch {
            if installedLoaded {
                if browseError == nil {
                    browseError = userMessage(error)
                }
            } else {
                loadState = .failed(userMessage(error))
                return
            }
        }

        if installedLoaded {
            loadState = .loaded
            lastLoadedAt = .now
        } else {
            loadState = .failed(browseError ?? "Couldn't load extensions.")
        }
    }

    // MARK: - Derived values

    func installedEntry(for pluginID: String) -> ClaudeInstalledPlugin? {
        installedPlugins.first { $0.id == pluginID }
    }

    func marketplace(named name: String) -> ClaudeMarketplace? {
        marketplaces.first { $0.name == name }
    }

    func isFavorite(_ marketplace: ClaudeMarketplace) -> Bool {
        app.isFavoriteMarketplace(marketplace)
    }

    func availableCount(for marketplace: ClaudeMarketplace) -> Int {
        availablePlugins.filter { $0.marketplaceName == marketplace.name }.count
    }

    func isUserScope(_ plugin: ClaudeInstalledPlugin) -> Bool {
        plugin.knownScope == .user
    }

    func isBusy(_ key: String) -> Bool {
        busyKey == key
    }

    var isMutating: Bool {
        busyKey != nil
    }

    func userMessage(_ error: Error) -> String {
        (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
    }

    func clearError() {
        errorMessage = nil
    }

    // MARK: - Plugin actions

    func install(
        pluginID: String,
        acceptCommandSHA256: String? = nil
    ) async throws {
        try await performAction(
            key: "install:\(pluginID)",
            reloadAfter: true,
            applyToRuntimes: true
        ) { manager in
            try await manager.install(
                pluginID: pluginID,
                acceptCommandSHA256: acceptCommandSHA256
            )
        }
    }

    func uninstall(_ plugin: ClaudeInstalledPlugin) async throws {
        guard isUserScope(plugin) else {
            throw ExtensionsModelError.readOnlyScope
        }
        try await performAction(
            key: "uninstall:\(plugin.identity)",
            reloadAfter: true,
            applyToRuntimes: true
        ) { manager in
            try await manager.uninstall(pluginID: plugin.id, scope: .user)
        }
    }

    func setEnabled(_ plugin: ClaudeInstalledPlugin, enabled: Bool) async throws {
        guard isUserScope(plugin) else {
            throw ExtensionsModelError.readOnlyScope
        }
        try await performAction(
            key: "toggle:\(plugin.identity)",
            reloadAfter: true,
            applyToRuntimes: true
        ) { manager in
            if enabled {
                try await manager.enable(pluginID: plugin.id, scope: .user)
            } else {
                try await manager.disable(pluginID: plugin.id, scope: .user)
            }
        }
    }

    func update(
        _ plugin: ClaudeInstalledPlugin,
        acceptCommandSHA256: String? = nil
    ) async throws {
        guard isUserScope(plugin) else {
            throw ExtensionsModelError.readOnlyScope
        }
        try await update(
            pluginID: plugin.id,
            acceptCommandSHA256: acceptCommandSHA256
        )
    }

    func update(
        pluginID: String,
        acceptCommandSHA256: String? = nil
    ) async throws {
        try await performAction(
            key: "update:\(pluginID)",
            reloadAfter: true,
            applyToRuntimes: true
        ) { manager in
            try await manager.update(
                pluginID: pluginID,
                scope: .user,
                acceptCommandSHA256: acceptCommandSHA256
            )
        }
    }

    // MARK: - Marketplace actions

    @discardableResult
    func addMarketplace(source: String, favorite: Bool) async throws -> ClaudeMarketplace? {
        let sanitized = try ClaudeMarketplaceSource.sanitized(source)
        let previousKeys = Set(marketplaces.map(\.stableKey))

        do {
            try await performAction(
                key: "marketplace-add",
                reloadAfter: true,
                applyToRuntimes: false
            ) { manager in
                try await manager.addMarketplace(sanitized)
            }
        } catch {
            // Adding an already-configured source is not a failure for the UI;
            // refresh and offer the existing marketplace as the target.
            if let existing = marketplace(matchingInput: sanitized),
               isAlreadyConfigured(error) {
                if favorite {
                    app.setFavoriteMarketplace(
                        name: existing.name,
                        sourceKey: existing.stableKey,
                        favorite: true
                    )
                }
                return existing
            }
            throw error
        }

        let added = marketplaces.first { !previousKeys.contains($0.stableKey) }
            ?? marketplace(matchingInput: sanitized)
        if favorite, let added {
            app.setFavoriteMarketplace(
                name: added.name,
                sourceKey: added.stableKey,
                favorite: true
            )
        }
        return added
    }

    func removeMarketplace(_ marketplace: ClaudeMarketplace) async throws {
        try await performAction(
            key: "marketplace:\(marketplace.name)",
            reloadAfter: true,
            applyToRuntimes: false
        ) { manager in
            try await manager.removeMarketplace(name: marketplace.name)
        }
        app.removeFavoriteMarketplace(name: marketplace.name, sourceKey: marketplace.stableKey)
    }

    func refreshMarketplaces(name: String? = nil) async throws {
        let key = name.map { "marketplace:\($0)" } ?? "marketplace-refresh"
        try await performAction(
            key: key,
            reloadAfter: true,
            applyToRuntimes: false
        ) { manager in
            try await manager.refreshMarketplaces(name: name)
        }
    }

    // MARK: - Authoring

    func validate(path: URL) async throws -> ClaudePluginValidationResult {
        guard busyKey == nil else { throw ExtensionsModelError.busy }
        guard let manager = makeManager() else {
            throw ClaudePluginError.cliUnavailable(cliMessage)
        }
        busyKey = "validate"
        defer { busyKey = nil }
        return try await manager.validate(path: path)
    }

    func test(path: URL) async throws -> ClaudePluginValidationResult {
        guard busyKey == nil else { throw ExtensionsModelError.busy }
        guard let manager = makeManager() else {
            throw ClaudePluginError.cliUnavailable(cliMessage)
        }
        busyKey = "test"
        defer { busyKey = nil }
        return try await manager.test(path: path)
    }

    // MARK: - Helpers

    private func performAction(
        key: String,
        reloadAfter: Bool,
        applyToRuntimes: Bool,
        operation: (ClaudePluginManager) async throws -> Void
    ) async throws {
        guard busyKey == nil else { throw ExtensionsModelError.busy }
        guard let manager = makeManager() else {
            throw ClaudePluginError.cliUnavailable(cliMessage)
        }

        busyKey = key
        defer { busyKey = nil }

        do {
            try await operation(manager)
            if reloadAfter {
                await reload()
            }
            if applyToRuntimes {
                app.pluginEnvironmentDidChange()
            }
        } catch {
            if reloadAfter {
                await reload()
            }
            if applyToRuntimes {
                app.pluginEnvironmentDidChange()
            }
            throw error
        }
    }

    private func makeManager() -> ClaudePluginManager? {
        guard let path = app.claudeAvailability.path else { return nil }
        if manager == nil || managerPath != path {
            manager = ClaudePluginManager(
                runner: ProcessClaudePluginRunner(
                    executableURL: URL(fileURLWithPath: path)
                )
            )
            managerPath = path
        }
        return manager
    }

    private var cliMessage: String {
        switch app.claudeAvailability {
        case .checking:
            return "Looking for Claude Code…"
        case .ready:
            return "Claude Code is unavailable."
        case .missing:
            return "Claude Code wasn't found. Install it or choose its executable in Settings → Claude Code."
        case .failed(let message):
            return message
        }
    }

    private func marketplace(matchingInput input: String) -> ClaudeMarketplace? {
        let normalized = input.trimmingCharacters(in: .whitespacesAndNewlines)
        return marketplaces.first { marketplace in
            marketplace.displayLocation.caseInsensitiveCompare(normalized) == .orderedSame
                || marketplace.repo?.caseInsensitiveCompare(normalized) == .orderedSame
                || marketplace.path?.caseInsensitiveCompare(normalized) == .orderedSame
                || marketplace.name.caseInsensitiveCompare(normalized) == .orderedSame
        }
    }

    private func isAlreadyConfigured(_ error: Error) -> Bool {
        let message = userMessage(error).lowercased()
        return message.contains("already")
            || message.contains("exists")
            || message.contains("configured")
    }
}

enum ExtensionsModelError: Error, LocalizedError {
    case busy
    case readOnlyScope

    var errorDescription: String? {
        switch self {
        case .busy:
            return "Another extension action is still running. Wait for it to finish."
        case .readOnlyScope:
            return "This plugin is managed in a project. Change it from that project's folder."
        }
    }
}
