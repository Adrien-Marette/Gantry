import Foundation
import GantryCore

extension AppModel {
    // MARK: - Navigation

    func showExtensions() {
        commandPalettePresented = false
        mainDestination = .extensions
    }

    func hideExtensions() {
        mainDestination = .workspace
    }

    // MARK: - Favorites

    static func normalizedFavoriteMarketplaces(
        _ favorites: [FavoriteMarketplace]?
    ) -> [FavoriteMarketplace]? {
        guard let favorites else { return nil }
        var seen = Set<String>()
        var normalized: [FavoriteMarketplace] = []
        for favorite in favorites {
            var favorite = favorite
            favorite.name = favorite.name.trimmingCharacters(in: .whitespacesAndNewlines)
            favorite.source = favorite.source?
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .nilIfEmpty
            guard !favorite.name.isEmpty || favorite.source != nil else { continue }
            guard seen.insert(favorite.id).inserted else { continue }
            normalized.append(favorite)
        }
        return normalized.isEmpty ? nil : normalized
    }

    func isFavoriteMarketplace(name: String, sourceKey: String?) -> Bool {
        (settings.favoriteMarketplaces ?? []).contains {
            $0.matches(name: name, sourceKey: sourceKey)
        }
    }

    func isFavoriteMarketplace(_ marketplace: ClaudeMarketplace) -> Bool {
        isFavoriteMarketplace(name: marketplace.name, sourceKey: marketplace.stableKey)
    }

    func setFavoriteMarketplace(name: String, sourceKey: String?, favorite: Bool) {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedSource = sourceKey?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .nilIfEmpty
        guard !trimmedName.isEmpty || trimmedSource != nil else { return }

        var favorites = settings.favoriteMarketplaces ?? []
        favorites.removeAll { $0.matches(name: trimmedName, sourceKey: trimmedSource) }
        if favorite {
            favorites.append(FavoriteMarketplace(name: trimmedName, source: trimmedSource))
        }
        settings.favoriteMarketplaces = Self.normalizedFavoriteMarketplaces(favorites)
        scheduleSave()
    }

    func toggleFavoriteMarketplace(name: String, sourceKey: String?) {
        setFavoriteMarketplace(
            name: name,
            sourceKey: sourceKey,
            favorite: !isFavoriteMarketplace(name: name, sourceKey: sourceKey)
        )
    }

    func removeFavoriteMarketplace(name: String, sourceKey: String?) {
        setFavoriteMarketplace(name: name, sourceKey: sourceKey, favorite: false)
    }

    // MARK: - Mods folder

    func resolveModsDirectory() -> URL {
        // Preserve the stored path exactly, including leading or trailing
        // spaces in a folder name; only an empty setting uses the default.
        if let stored = settings.modsDirectory,
           !stored.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return URL(fileURLWithPath: stored, isDirectory: true)
        }
        let home = FileManager.default.homeDirectoryForCurrentUser
        let developer = home.appendingPathComponent("Developer", isDirectory: true)
        if FileManager.default.fileExists(atPath: developer.path) {
            return developer.appendingPathComponent("Gantry Mods", isDirectory: true)
        }
        return home
            .appendingPathComponent("Documents", isDirectory: true)
            .appendingPathComponent("Gantry Mods", isDirectory: true)
    }

    func setModsDirectory(_ url: URL) {
        let standardized = url.standardizedFileURL
        guard settings.modsDirectory != standardized.path else { return }
        settings.modsDirectory = standardized.path
        scheduleSave()
    }

    // MARK: - Runtime application

    /// Recycles idle Claude processes and marks running ones stale so the next
    /// turn starts with the current plugin set.
    func pluginEnvironmentDidChange() {
        for project in projects {
            for session in project.sessions {
                if activities[session.id]?.isRunning == true {
                    staleRuntimeSessions.insert(session.id)
                } else {
                    recycleRuntime(for: session.id)
                }
            }
        }
        scheduleSave()
    }

    // MARK: - Opening a created mod

    /// Adds the mod folder as a project and, when the folder is the project
    /// itself, loads it for that project's chats with `--plugin-dir`.
    @discardableResult
    func openModInGantry(at url: URL) -> UUID? {
        let standardized = url.resolvingSymlinksInPath().standardizedFileURL
        guard let sessionID = addProject(at: standardized) else { return nil }
        guard let location = locateSession(sessionID) else { return sessionID }

        let projectPath = projects[location.projectIndex].url
            .resolvingSymlinksInPath()
            .standardizedFileURL
            .path
        guard standardized.path == projectPath else { return sessionID }

        projects[location.projectIndex].devModPath = standardized.path
        recycleRuntime(for: sessionID)
        scheduleSave()
        return sessionID
    }
}
