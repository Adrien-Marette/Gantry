import Foundation
import GantryCore

extension AppModel {
    func plugin(withID pluginID: UUID) -> PluginConnection? {
        plugins.first { $0.id == pluginID }
    }

    func matchingPlugins(for remote: RepositoryRemote) -> [PluginConnection] {
        plugins.filter { $0.matches(host: remote.host) }
    }

    func resolvedPlugin(for project: Project, remote: RepositoryRemote?) -> PluginConnection? {
        guard let remote else { return nil }
        let candidates = matchingPlugins(for: remote)
        if let chosenID = project.pluginID,
           let chosen = candidates.first(where: { $0.id == chosenID }) {
            return chosen
        }
        return candidates.first
    }

    func pluginID(for project: Project, remote: RepositoryRemote?) -> UUID? {
        resolvedPlugin(for: project, remote: remote)?.id
    }

    func setPluginConnection(_ pluginID: UUID?, for projectID: UUID) {
        guard pluginID == nil || plugin(withID: pluginID!) != nil,
              let projectIndex = projects.firstIndex(where: { $0.id == projectID }) else {
            return
        }
        guard projects[projectIndex].pluginID != pluginID else { return }
        projects[projectIndex].pluginID = pluginID
        scheduleSave()
        invalidateRuntimes(projectID: projectID)
    }

    /// Verifies the token against the code host, then stores it in the Keychain
    /// and adds the connection. The token is never written to app state.
    @discardableResult
    func connectPlugin(
        kind: PluginKind,
        serverURL rawServerURL: String,
        displayName rawName: String,
        token rawToken: String
    ) async throws -> PluginConnection {
        guard let serverURL = PluginKind.normalizedServerURL(rawServerURL),
              let host = serverURL.host,
              !host.isEmpty else {
            throw PluginManagementError.invalidServerURL
        }
        let token = rawToken.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !token.isEmpty else {
            throw PluginManagementError.tokenRequired
        }

        let id = UUID()
        let customName = rawName.trimmingCharacters(in: .whitespacesAndNewlines)
        let keychainAccount =
            "Gantry Plugins · \(kind.title) · pending · \(id.uuidString.prefix(8))"
        let candidate = PluginConnection(
            id: id,
            kind: kind,
            name: customName.isEmpty ? kind.title : customName,
            serverURL: serverURL.absoluteString,
            accountName: "",
            keychainServer: host,
            keychainAccount: keychainAccount
        )

        let account: PluginAccount
        do {
            account = try await CodeHostClient(connection: candidate, token: token).verify()
        } catch {
            throw PluginManagementError.verification(
                error.localizedDescription
            )
        }

        let login = account.login.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !login.isEmpty else {
            throw PluginManagementError.verification(
                "The code host didn't return an account name."
            )
        }
        if plugins.contains(where: {
            $0.kind == kind &&
                $0.serverHost == host.lowercased() &&
                $0.accountName.caseInsensitiveCompare(login) == .orderedSame
        }) {
            throw PluginManagementError.alreadyConnected(kind.title, login)
        }

        var connection = candidate
        if customName.isEmpty {
            let displayName = account.displayName?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            connection.name = displayName.isEmpty ? login : displayName
        }
        connection.accountName = login
        connection.keychainAccount =
            "Gantry Plugins · \(kind.title) · \(login) · \(id.uuidString.prefix(8))"
        connection.lastVerifiedAt = .now

        do {
            try await Task.detached(priority: .userInitiated) {
                try PluginKeychain.store(token, for: connection)
            }.value
        } catch {
            throw PluginManagementError.keychain(
                "Couldn't save the \(kind.title) access token. \(error.localizedDescription)"
            )
        }

        plugins.append(connection)
        scheduleSave()
        invalidateRuntimes()
        return connection
    }

    func deletePlugin(_ plugin: PluginConnection) async throws {
        guard plugins.contains(where: { $0.id == plugin.id }) else { return }
        do {
            try await Task.detached(priority: .userInitiated) {
                try PluginKeychain.deleteKey(for: plugin)
            }.value
        } catch {
            throw PluginManagementError.keychain(
                "Couldn't remove the \(plugin.kind.title) access token. \(error.localizedDescription)"
            )
        }

        plugins.removeAll { $0.id == plugin.id }
        for projectIndex in projects.indices where projects[projectIndex].pluginID == plugin.id {
            projects[projectIndex].pluginID = nil
        }
        scheduleSave()
        invalidateRuntimes()
    }

    func pluginToken(for plugin: PluginConnection) async throws -> String {
        let token: String?
        do {
            token = try await Task.detached(priority: .userInitiated) {
                try PluginKeychain.secret(for: plugin)
            }.value
        } catch {
            throw PluginManagementError.keychain(
                "Couldn't read the \(plugin.kind.title) access token. \(error.localizedDescription)"
            )
        }
        guard let token, !token.isEmpty else {
            throw PluginManagementError.missingToken(plugin.name)
        }
        return token
    }

    func pluginClient(for plugin: PluginConnection) async throws -> CodeHostClient {
        let token = try await pluginToken(for: plugin)
        return CodeHostClient(connection: plugin, token: token)
    }
}

enum PluginManagementError: Error, LocalizedError {
    case invalidServerURL
    case tokenRequired
    case alreadyConnected(String, String)
    case verification(String)
    case keychain(String)
    case missingToken(String)

    var errorDescription: String? {
        switch self {
        case .invalidServerURL:
            return "Enter a valid server URL, for example https://github.com."
        case .tokenRequired:
            return "Enter an access token first."
        case .alreadyConnected(let kind, let login):
            return "The \(kind) account “\(login)” is already connected."
        case .verification(let message):
            return "Couldn't connect to the code host. \(message)"
        case .keychain(let message):
            return message
        case .missingToken(let name):
            return "“\(name)” has no token in the Keychain. Remove and reconnect the plugin."
        }
    }
}
