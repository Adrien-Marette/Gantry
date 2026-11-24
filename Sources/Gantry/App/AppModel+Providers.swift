import Foundation
import GantryCore

extension AppModel {
    var defaultProvider: AIProvider {
        providers.first(where: { $0.id == defaultProviderID })
            ?? providers.first
            ?? .claudeCodeDefault
    }

    func provider(withID providerID: UUID) -> AIProvider? {
        providers.first(where: { $0.id == providerID })
    }

    func provider(for session: ChatSession) -> AIProvider {
        if let providerID = session.providerID,
           let provider = provider(withID: providerID) {
            return provider
        }
        return defaultProvider
    }

    func providerID(for session: ChatSession) -> UUID {
        provider(for: session).id
    }

    func uniqueProviderName(basedOn base: String, excluding: UUID? = nil) -> String {
        let trimmed = base.trimmingCharacters(in: .whitespacesAndNewlines)
        let root = trimmed.isEmpty ? "Provider" : trimmed
        let existing = Set(
            providers
                .filter { $0.id != excluding }
                .map { $0.name.lowercased() }
        )
        guard existing.contains(root.lowercased()) else { return root }
        var counter = 2
        while existing.contains("\(root) \(counter)".lowercased()) {
            counter += 1
        }
        return "\(root) \(counter)"
    }

    func setProvider(_ providerID: UUID, for sessionID: UUID) {
        guard let provider = provider(withID: providerID),
              activities[sessionID]?.isRunning != true,
              let location = locateSession(sessionID) else { return }
        guard projects[location.projectIndex].sessions[location.sessionIndex].providerID != providerID else {
            return
        }
        projects[location.projectIndex].sessions[location.sessionIndex].providerID = provider.id
        projects[location.projectIndex].sessions[location.sessionIndex].actualModelName = nil
        projects[location.projectIndex].sessions[location.sessionIndex].updatedAt = .now
        recycleRuntime(for: sessionID)
        scheduleSave()
    }

    func setDefaultProvider(_ providerID: UUID) {
        guard provider(withID: providerID) != nil else { return }
        defaultProviderID = providerID
        scheduleSave()
    }

    /// Performs the Keychain operation (if any), then commits the provider and
    /// refreshes any idle Claude Code processes that use it.
    func persistProvider(
        _ provider: AIProvider,
        apiKey: String?,
        removeExistingKey: Bool
    ) async throws {
        let normalized = try normalize(provider)
        let key = apiKey?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let shouldRemove = removeExistingKey && key.isEmpty

        if !key.isEmpty {
            let provider = normalized
            do {
                try await Task.detached(priority: .userInitiated) {
                    try ProviderKeychain.store(key, for: provider)
                }.value
            } catch {
                throw ProviderManagementError.keychain(
                    provider.name,
                    (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
                )
            }
        } else if shouldRemove {
            let provider = normalized
            do {
                try await Task.detached(priority: .userInitiated) {
                    try ProviderKeychain.deleteKey(for: provider)
                }.value
            } catch {
                throw ProviderManagementError.keychain(
                    provider.name,
                    (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
                )
            }
        }

        if let index = providers.firstIndex(where: { $0.id == normalized.id }) {
            providers[index] = normalized
        } else {
            providers.append(normalized)
        }
        providerKeyRevision &+= 1
        if self.provider(withID: defaultProviderID) == nil {
            defaultProviderID = AIProvider.claudeCodeID
        }
        scheduleSave()
        refreshSessions(using: normalized.id)
    }

    /// Removes a provider, its Keychain item, and any per-session reference.
    func deleteProvider(_ provider: AIProvider) async throws {
        guard !provider.isBuiltIn, provider.id != AIProvider.claudeCodeID else {
            throw ProviderManagementError.builtInProvider
        }
        do {
            try await Task.detached(priority: .userInitiated) {
                try ProviderKeychain.deleteKey(for: provider)
            }.value
        } catch {
            throw ProviderManagementError.keychain(
                provider.name,
                (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            )
        }

        providers.removeAll { $0.id == provider.id }
        providerKeyRevision &+= 1
        if defaultProviderID == provider.id {
            defaultProviderID = AIProvider.claudeCodeID
        }
        let replacementID = self.provider(withID: defaultProviderID)?.id ?? AIProvider.claudeCodeID

        for projectIndex in projects.indices {
            for sessionIndex in projects[projectIndex].sessions.indices {
                guard projects[projectIndex].sessions[sessionIndex].providerID == provider.id else {
                    continue
                }
                let sessionID = projects[projectIndex].sessions[sessionIndex].id
                projects[projectIndex].sessions[sessionIndex].providerID = replacementID
                projects[projectIndex].sessions[sessionIndex].actualModelName = nil
                if activities[sessionID]?.isRunning == true {
                    staleProviderSessions.insert(sessionID)
                } else {
                    recycleRuntime(for: sessionID)
                }
            }
        }
        scheduleSave()
    }

    /// Returns the API key for a provider. This runs off the main thread because
    /// Keychain may need to prompt the user.
    func apiKey(for provider: AIProvider) async throws -> String? {
        guard provider.requiresAPIKey else { return nil }
        let provider = provider
        do {
            let key = try await Task.detached(priority: .userInitiated) {
                try ProviderKeychain.secret(for: provider)
            }.value
            guard let key, !key.isEmpty else {
                throw ProviderRuntimeError.missingAPIKey(provider.name)
            }
            return key
        } catch let error as ProviderRuntimeError {
            throw error
        } catch {
            throw ProviderRuntimeError.keychain(
                provider.name,
                (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            )
        }
    }

    /// Called after a turn when a provider was edited or deleted while its
    /// process was still working. Recycles the process only once it is idle.
    func refreshProviderRuntimeIfNeeded(sessionID: UUID) {
        guard staleProviderSessions.remove(sessionID) != nil else { return }
        recycleRuntime(for: sessionID)
    }

    func recycleRuntime(for sessionID: UUID) {
        runtimeStarts.removeValue(forKey: sessionID)?.cancel()
        runtimeTasks[sessionID]?.cancel()
        runtimeTasks.removeValue(forKey: sessionID)
        runtimes.removeValue(forKey: sessionID)?.terminate()
        stopPluginToolBridge(for: sessionID)
    }

    private func refreshSessions(using providerID: UUID) {
        for project in projects {
            for session in project.sessions where session.providerID == providerID {
                if activities[session.id]?.isRunning == true {
                    staleProviderSessions.insert(session.id)
                } else {
                    recycleRuntime(for: session.id)
                }
            }
        }
    }

    private func normalize(_ provider: AIProvider) throws -> AIProvider {
        guard provider.id != AIProvider.claudeCodeID, !provider.isBuiltIn else {
            throw ProviderManagementError.builtInProvider
        }
        var provider = provider
        provider.name = provider.name.trimmingCharacters(in: .whitespacesAndNewlines)
        provider.baseURL = provider.baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        provider.mainModel = provider.mainModel.trimmingCharacters(in: .whitespacesAndNewlines)
        provider.opusModel = provider.opusModel.trimmingCharacters(in: .whitespacesAndNewlines)
        provider.sonnetModel = provider.sonnetModel.trimmingCharacters(in: .whitespacesAndNewlines)
        provider.haikuModel = provider.haikuModel.trimmingCharacters(in: .whitespacesAndNewlines)
        provider.subagentModel = provider.subagentModel.trimmingCharacters(in: .whitespacesAndNewlines)
        provider.extraEnvironment = provider.extraEnvironment.reduce(into: [:]) { result, entry in
            let key = entry.key.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !key.isEmpty else { return }
            result[key] = entry.value
        }

        guard !provider.name.isEmpty else {
            throw ProviderManagementError.nameRequired
        }
        if providers.contains(where: {
            $0.id != provider.id && $0.name.caseInsensitiveCompare(provider.name) == .orderedSame
        }) {
            throw ProviderManagementError.duplicateName(provider.name)
        }

        if !provider.baseURL.isEmpty {
            guard let url = URL(string: provider.baseURL),
                  let scheme = url.scheme?.lowercased(),
                  scheme == "http" || scheme == "https",
                  let host = url.host,
                  !host.isEmpty else {
                throw ProviderManagementError.invalidBaseURL
            }
        }

        if provider.keychainServer.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            provider.keychainServer = AIProvider.host(from: provider.baseURL) ?? "Gantry.local"
        }
        if provider.keychainAccount.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            provider.keychainAccount = "Gantry · \(provider.name)"
        }
        return provider
    }
}

enum ProviderManagementError: Error, LocalizedError {
    case nameRequired
    case duplicateName(String)
    case invalidBaseURL
    case builtInProvider
    case keychain(String, String)

    var errorDescription: String? {
        switch self {
        case .nameRequired:
            return "Give this provider a name."
        case .duplicateName(let name):
            return "A provider named “\(name)” already exists."
        case .invalidBaseURL:
            return "Enter a valid http or https base URL."
        case .builtInProvider:
            return "The built-in Claude Code provider can't be modified."
        case .keychain(let name, let message):
            return "Couldn't update the API key for \(name). \(message)"
        }
    }
}

enum ProviderRuntimeError: Error, LocalizedError {
    case missingAPIKey(String)
    case keychain(String, String)

    var errorDescription: String? {
        switch self {
        case .missingAPIKey(let name):
            return "“\(name)” has no API key. Add one in Settings → Providers."
        case .keychain(let name, let message):
            return "Couldn't read the API key for “\(name)”. \(message)"
        }
    }
}
