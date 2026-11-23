import Foundation

// MARK: - Plugin descriptions

public enum PluginKind: String, CaseIterable, Codable, Identifiable, Sendable {
    case github
    case gitlab
    case gitea

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .github: return "GitHub"
        case .gitlab: return "GitLab"
        case .gitea: return "Gitea"
        }
    }

    public var symbol: String {
        switch self {
        case .github: return "chevron.left.forwardslash.chevron.right"
        case .gitlab: return "arrow.triangle.branch"
        case .gitea: return "server.rack"
        }
    }

    public var defaultServerURL: String {
        switch self {
        case .github: return "https://github.com"
        case .gitlab: return "https://gitlab.com"
        case .gitea: return "https://gitea.com"
        }
    }

    public var pullRequestTerm: String {
        self == .gitlab ? "merge request" : "pull request"
    }

    public var pullRequestTermPlural: String {
        self == .gitlab ? "merge requests" : "pull requests"
    }

    public var tokenScopeHint: String {
        switch self {
        case .github:
            return "Classic token with repo scope, or a fine-grained token with contents, pull requests, issues, checks, and metadata access."
        case .gitlab:
            return "Personal access token with the api scope for merge requests, comments, and pipelines."
        case .gitea:
            return "Access token with repository and issue read/write access."
        }
    }

    public var capabilities: [PluginCapability] {
        PluginCapability.allCases
    }

    /// Adds a default scheme to a user-entered server address and removes a
    /// trailing slash. The returned URL is the web root of the instance.
    public static func normalizedServerURL(_ raw: String) -> URL? {
        var trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        if !trimmed.contains("://") {
            trimmed = "https://\(trimmed)"
        }
        guard var components = URLComponents(string: trimmed),
              let scheme = components.scheme?.lowercased(),
              scheme == "https" || scheme == "http",
              let host = components.host,
              !host.isEmpty,
              components.user == nil,
              components.password == nil else {
            return nil
        }
        components.scheme = scheme
        components.host = host.lowercased()
        components.query = nil
        components.fragment = nil
        var path = components.path
        while path.count > 1, path.hasSuffix("/") {
            path.removeLast()
        }
        if path == "/" { path = "" }
        components.path = path
        return components.url
    }

    /// The REST API root for this instance. GitHub.com uses api.github.com;
    /// self-hosted instances use their documented API suffixes.
    public func apiBaseURL(for serverURL: URL) -> URL? {
        var basePath = serverURL.path
        while basePath.count > 1, basePath.hasSuffix("/") {
            basePath.removeLast()
        }
        if basePath == "/" { basePath = "" }

        let suffix: String
        switch self {
        case .github:
            if serverURL.host?.lowercased() == "github.com", basePath.isEmpty {
                return URL(string: "https://api.github.com")
            }
            suffix = "/api/v3"
        case .gitlab:
            suffix = "/api/v4"
        case .gitea:
            suffix = "/api/v1"
        }

        var components = URLComponents(url: serverURL, resolvingAgainstBaseURL: false)
        if !basePath.lowercased().hasSuffix(suffix) {
            basePath += suffix
        }
        components?.path = basePath
        components?.query = nil
        components?.fragment = nil
        return components?.url
    }

    public func tokenPageURL(serverURL: URL) -> URL? {
        let path: String
        switch self {
        case .github: path = "/settings/tokens"
        case .gitlab: path = "/-/user_settings/personal_access_tokens"
        case .gitea: path = "/user/settings/applications"
        }
        var components = URLComponents(url: serverURL, resolvingAgainstBaseURL: false)
        var basePath = components?.path ?? ""
        while basePath.count > 1, basePath.hasSuffix("/") {
            basePath.removeLast()
        }
        if basePath == "/" { basePath = "" }
        components?.path = basePath + path
        components?.query = nil
        components?.fragment = nil
        return components?.url
    }
}

public enum PluginCapability: String, CaseIterable, Codable, Identifiable, Sendable {
    case pullRequests
    case comments
    case checks

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .pullRequests: return "Pull requests"
        case .comments: return "Comments"
        case .checks: return "Checks"
        }
    }
}

// MARK: - Connections

/// A connected code-host account. The access token itself is never stored in
/// this value or in Gantry's state file; it lives in the macOS Keychain under
/// `keychainServer` + `keychainAccount`.
public struct PluginConnection: Codable, Hashable, Identifiable, Sendable {
    public var id: UUID
    public var kind: PluginKind
    public var name: String
    public var serverURL: String
    public var accountName: String
    public var keychainServer: String
    public var keychainAccount: String
    public var createdAt: Date
    public var lastVerifiedAt: Date?

    public init(
        id: UUID = UUID(),
        kind: PluginKind,
        name: String,
        serverURL: String,
        accountName: String = "",
        keychainServer: String = "",
        keychainAccount: String = "",
        createdAt: Date = .now,
        lastVerifiedAt: Date? = nil
    ) {
        self.id = id
        self.kind = kind
        self.name = name
        self.serverURL = serverURL
        self.accountName = accountName
        self.keychainServer = keychainServer
        self.keychainAccount = keychainAccount
        self.createdAt = createdAt
        self.lastVerifiedAt = lastVerifiedAt
    }

    public var serverHost: String {
        URL(string: serverURL)?.host?.lowercased() ?? serverURL.lowercased()
    }

    public var serverBaseURL: URL? {
        URL(string: serverURL)
    }

    public var apiBaseURL: URL? {
        guard let serverBaseURL else { return nil }
        return kind.apiBaseURL(for: serverBaseURL)
    }

    public var keychainLabel: String {
        "Gantry — \(kind.title) · \(accountName.isEmpty ? name : accountName)"
    }

    public var capabilities: [PluginCapability] {
        kind.capabilities
    }

    public func tokenPageURL() -> URL? {
        guard let serverBaseURL else { return nil }
        return kind.tokenPageURL(serverURL: serverBaseURL)
    }

    public func webURL(for remote: RepositoryRemote) -> URL? {
        guard let serverBaseURL else { return nil }
        var base = serverBaseURL.absoluteString
        while base.hasSuffix("/") { base.removeLast() }
        return URL(string: "\(base)/\(remote.path)")
    }

    public func matches(host: String) -> Bool {
        serverHost == host.lowercased()
    }
}

// MARK: - Git remotes

public struct RepositoryRemote: Hashable, Sendable {
    public var host: String
    /// The repository path as written by the remote, without a leading slash
    /// or `.git` suffix. GitLab groups can contain multiple path components.
    public var path: String

    public init(host: String, path: String) {
        self.host = host.lowercased()
        self.path = path
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
    }

    public var fullName: String { path }

    public var owner: String {
        String(path.split(separator: "/", omittingEmptySubsequences: true).first ?? "")
    }

    public var repositoryName: String {
        String(path.split(separator: "/", omittingEmptySubsequences: true).last ?? "")
    }

    /// Parses HTTPS, SSH, git, and scp-style remotes. Returns nil for local
    /// paths and URLs that do not contain an owner/repository path.
    public static func parse(_ raw: String) -> RepositoryRemote? {
        var value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return nil }
        while value.hasSuffix("/") { value.removeLast() }
        if value.lowercased().hasSuffix(".git") {
            value.removeLast(4)
        }

        if value.contains("://") {
            guard let url = URL(string: value),
                  let host = url.host,
                  !host.isEmpty else { return nil }
            return make(host: host, path: url.path)
        }

        // scp-style remotes: git@github.com:owner/repo
        guard let colon = value.firstIndex(of: ":") else { return nil }
        let before = String(value[..<colon])
        guard !before.contains("/"), !before.isEmpty else { return nil }
        let hostPart = before.split(separator: "@").last.map(String.init) ?? before
        let pathPart = String(value[value.index(after: colon)...])
        return make(host: hostPart, path: pathPart)
    }

    private static func make(host: String, path: String) -> RepositoryRemote? {
        var normalizedPath = path.trimmingCharacters(in: .whitespacesAndNewlines)
        while normalizedPath.hasPrefix("/") { normalizedPath.removeFirst() }
        while normalizedPath.hasSuffix("/") { normalizedPath.removeLast() }
        if normalizedPath.lowercased().hasSuffix(".git") {
            normalizedPath.removeLast(4)
        }
        let components = normalizedPath.split(separator: "/", omittingEmptySubsequences: true)
        guard components.count >= 2 else { return nil }
        return RepositoryRemote(host: host, path: components.joined(separator: "/"))
    }
}

public enum GitRepositoryReader {
    public static func originRemote(at projectURL: URL) -> RepositoryRemote? {
        guard let raw = remoteURL(at: projectURL, remoteName: "origin") else { return nil }
        return RepositoryRemote.parse(raw)
    }

    public static func remoteURL(
        at projectURL: URL,
        remoteName: String = "origin"
    ) -> String? {
        guard let gitDirectory = gitDirectory(for: projectURL) else { return nil }
        let configURL = gitDirectory.appendingPathComponent("config")
        guard let config = try? String(contentsOf: configURL, encoding: .utf8) else {
            return nil
        }

        var currentRemote: String?
        var foundURL: String?
        for rawLine in config.components(separatedBy: .newlines) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            guard !line.isEmpty, !line.hasPrefix("#"), !line.hasPrefix(";") else {
                continue
            }

            if line.hasPrefix("[") && line.hasSuffix("]") {
                let body = line.dropFirst().dropLast()
                    .trimmingCharacters(in: .whitespaces)
                if body.lowercased().hasPrefix("remote") {
                    if let first = body.firstIndex(of: "\""),
                       let last = body.lastIndex(of: "\""),
                       first < last {
                        currentRemote = String(body[body.index(after: first)..<last])
                    } else {
                        currentRemote = nil
                    }
                } else {
                    currentRemote = nil
                }
                continue
            }

            guard currentRemote == remoteName,
                  let equals = line.firstIndex(of: "=") else { continue }
            let key = line[..<equals]
                .trimmingCharacters(in: .whitespaces)
                .lowercased()
            guard key == "url" else { continue }
            var value = line[line.index(after: equals)...]
                .trimmingCharacters(in: .whitespaces)
            if value.hasPrefix("\""), value.hasSuffix("\""), value.count >= 2 {
                value.removeFirst()
                value.removeLast()
            }
            if !value.isEmpty {
                foundURL = value
                break
            }
        }
        return foundURL
    }

    private static func gitDirectory(for projectURL: URL) -> URL? {
        let dotGit = projectURL.appendingPathComponent(".git")
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: dotGit.path, isDirectory: &isDirectory) else {
            return nil
        }
        if isDirectory.boolValue {
            return dotGit
        }
        guard let contents = try? String(contentsOf: dotGit, encoding: .utf8),
              let line = contents.components(separatedBy: .newlines)
                .first(where: { $0.hasPrefix("gitdir:") }) else {
            return nil
        }
        let rawPath = line.dropFirst("gitdir:".count)
            .trimmingCharacters(in: .whitespaces)
        guard !rawPath.isEmpty else { return nil }
        let path = rawPath.hasPrefix("/")
            ? rawPath
            : projectURL.appendingPathComponent(rawPath).standardizedFileURL.path
        return URL(fileURLWithPath: path, isDirectory: true)
    }
}

// MARK: - Remote API models

public struct PluginAccount: Hashable, Sendable {
    public var login: String
    public var displayName: String?
    public var avatarURL: URL?

    public init(login: String, displayName: String? = nil, avatarURL: URL? = nil) {
        self.login = login
        self.displayName = displayName
        self.avatarURL = avatarURL
    }
}

public struct PluginRepository: Hashable, Sendable {
    public var fullName: String
    public var defaultBranch: String
    public var webURL: URL?
    public var isPrivate: Bool

    public init(fullName: String, defaultBranch: String, webURL: URL? = nil, isPrivate: Bool = false) {
        self.fullName = fullName
        self.defaultBranch = defaultBranch
        self.webURL = webURL
        self.isPrivate = isPrivate
    }
}

public enum PluginPullRequestState: String, Hashable, Sendable {
    case open
    case closed
    case merged
}

public struct PluginPullRequest: Identifiable, Hashable, Sendable {
    public var id: Int
    public var number: Int
    public var title: String
    public var state: PluginPullRequestState
    public var isDraft: Bool
    public var author: String
    public var sourceBranch: String
    public var targetBranch: String
    public var headSHA: String?
    public var webURL: URL?
    public var updatedAt: Date?
    public var body: String

    public init(
        id: Int,
        number: Int,
        title: String,
        state: PluginPullRequestState = .open,
        isDraft: Bool = false,
        author: String,
        sourceBranch: String,
        targetBranch: String,
        headSHA: String? = nil,
        webURL: URL? = nil,
        updatedAt: Date? = nil,
        body: String = ""
    ) {
        self.id = id
        self.number = number
        self.title = title
        self.state = state
        self.isDraft = isDraft
        self.author = author
        self.sourceBranch = sourceBranch
        self.targetBranch = targetBranch
        self.headSHA = headSHA
        self.webURL = webURL
        self.updatedAt = updatedAt
        self.body = body
    }
}

public enum PluginCheckState: String, Hashable, Sendable {
    case pending
    case success
    case failure
    case neutral
    case skipped
    case cancelled
    case unknown

    public var title: String {
        switch self {
        case .pending: return "Pending"
        case .success: return "Passed"
        case .failure: return "Failed"
        case .neutral: return "Neutral"
        case .skipped: return "Skipped"
        case .cancelled: return "Cancelled"
        case .unknown: return "Unknown"
        }
    }

    public var isFailure: Bool { self == .failure }
}

public struct PluginCheck: Identifiable, Hashable, Sendable {
    public var id: String
    public var name: String
    public var state: PluginCheckState
    public var description: String?
    public var detailsURL: URL?

    public init(
        id: String,
        name: String,
        state: PluginCheckState,
        description: String? = nil,
        detailsURL: URL? = nil
    ) {
        self.id = id
        self.name = name
        self.state = state
        self.description = description
        self.detailsURL = detailsURL
    }
}

public struct PluginNewPullRequest: Hashable, Sendable {
    public var title: String
    public var body: String
    public var sourceBranch: String
    public var targetBranch: String
    public var isDraft: Bool

    public init(
        title: String,
        body: String,
        sourceBranch: String,
        targetBranch: String,
        isDraft: Bool = false
    ) {
        self.title = title
        self.body = body
        self.sourceBranch = sourceBranch
        self.targetBranch = targetBranch
        self.isDraft = isDraft
    }
}
