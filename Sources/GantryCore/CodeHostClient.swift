import Foundation

/// A small, provider-independent client for the actions Gantry's code-host
/// plugins expose. It never logs requests or tokens.
public struct CodeHostClient: Sendable {
    private let backend: any CodeHostBackend

    public init(connection: PluginConnection, token: String) {
        self.init(
            connection: connection,
            token: token,
            transport: URLSessionPluginTransport()
        )
    }

    init(
        connection: PluginConnection,
        token: String,
        transport: any PluginHTTPTransport
    ) {
        switch connection.kind {
        case .github:
            backend = GitHubBackend(connection: connection, token: token, transport: transport)
        case .gitlab:
            backend = GitLabBackend(connection: connection, token: token, transport: transport)
        case .gitea:
            backend = GiteaBackend(connection: connection, token: token, transport: transport)
        }
    }

    public func verify() async throws -> PluginAccount {
        try await backend.verify()
    }

    public func repository(for remote: RepositoryRemote) async throws -> PluginRepository {
        try await backend.repository(for: remote)
    }

    public func pullRequests(for remote: RepositoryRemote) async throws -> [PluginPullRequest] {
        try await backend.pullRequests(for: remote)
    }

    public func checks(
        for pullRequest: PluginPullRequest,
        in remote: RepositoryRemote
    ) async throws -> [PluginCheck] {
        try await backend.checks(for: pullRequest, in: remote)
    }

    public func comment(
        on pullRequestNumber: Int,
        in remote: RepositoryRemote,
        body: String
    ) async throws {
        try await backend.comment(on: pullRequestNumber, in: remote, body: body)
    }

    @discardableResult
    public func createPullRequest(
        _ request: PluginNewPullRequest,
        in remote: RepositoryRemote
    ) async throws -> PluginPullRequest {
        try await backend.createPullRequest(request, in: remote)
    }
}

// MARK: - Errors

public enum PluginAPIError: Error, LocalizedError, Sendable {
    case invalidServerURL
    case invalidRepository(String)
    case missingCommit
    case unauthorized(String)
    case forbidden(String)
    case notFound(String)
    case rateLimited
    case invalidRequest(String)
    case server(String)
    case network(String)
    case decoding

    public var errorDescription: String? {
        switch self {
        case .invalidServerURL:
            return "The plugin's server URL isn't valid. Check it in Settings → Plugins."
        case .invalidRepository(let path):
            return "The git remote path “\(path)” isn't supported by this plugin."
        case .missingCommit:
            return "This pull request doesn't report a head commit yet."
        case .unauthorized:
            return "The access token was rejected. Update the plugin token in Settings → Plugins."
        case .forbidden(let detail):
            return detail.isEmpty
                ? "The connected account doesn't have permission for this action."
                : "The connected account doesn't have permission for this action. \(detail)"
        case .notFound(let detail):
            return detail.isEmpty
                ? "The repository or pull request couldn't be found."
                : "The repository or pull request couldn't be found. \(detail)"
        case .rateLimited:
            return "The code host's rate limit was reached. Try again later."
        case .invalidRequest(let detail):
            return detail.isEmpty
                ? "The code host rejected the request."
                : "The code host rejected the request. \(detail)"
        case .server(let detail):
            return detail.isEmpty
                ? "The code host returned an error."
                : "The code host returned an error. \(detail)"
        case .network(let detail):
            return "Couldn't reach the code host. \(detail)"
        case .decoding:
            return "The code host's response couldn't be read."
        }
    }
}

// MARK: - Backend protocol

protocol CodeHostBackend: Sendable {
    func verify() async throws -> PluginAccount
    func repository(for remote: RepositoryRemote) async throws -> PluginRepository
    func pullRequests(for remote: RepositoryRemote) async throws -> [PluginPullRequest]
    func checks(for pullRequest: PluginPullRequest, in remote: RepositoryRemote) async throws -> [PluginCheck]
    func comment(on pullRequestNumber: Int, in remote: RepositoryRemote, body: String) async throws
    func createPullRequest(_ request: PluginNewPullRequest, in remote: RepositoryRemote) async throws -> PluginPullRequest
}

// MARK: - HTTP

protocol PluginHTTPTransport: Sendable {
    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse)
}

struct URLSessionPluginTransport: PluginHTTPTransport {
    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw PluginAPIError.network("The code host didn't return an HTTP response.")
        }
        return (data, http)
    }
}

struct PluginHTTPClient: Sendable {
    let connection: PluginConnection
    let token: String
    let transport: any PluginHTTPTransport

    func data(
        method: String = "GET",
        path: String,
        query: [URLQueryItem] = [],
        body: [String: Any]? = nil,
        additionalHeaders: [String: String] = [:]
    ) async throws -> Data {
        guard let base = connection.apiBaseURL else {
            throw PluginAPIError.invalidServerURL
        }
        let normalizedPath = path.hasPrefix("/") ? path : "/\(path)"
        guard var components = URLComponents(string: base.absoluteString + normalizedPath) else {
            throw PluginAPIError.invalidServerURL
        }
        if !query.isEmpty {
            components.queryItems = query
        }
        guard let url = components.url else {
            throw PluginAPIError.invalidServerURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = method
        request.timeoutInterval = 30
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("Gantry", forHTTPHeaderField: "User-Agent")
        switch connection.kind {
        case .github:
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            request.setValue("2022-11-28", forHTTPHeaderField: "X-GitHub-Api-Version")
        case .gitlab:
            request.setValue(token, forHTTPHeaderField: "PRIVATE-TOKEN")
        case .gitea:
            request.setValue("token \(token)", forHTTPHeaderField: "Authorization")
        }
        if let body {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
        }
        for (key, value) in additionalHeaders {
            request.setValue(value, forHTTPHeaderField: key)
        }

        let data: Data
        let response: HTTPURLResponse
        do {
            (data, response) = try await transport.data(for: request)
        } catch let error as PluginAPIError {
            throw error
        } catch {
            throw PluginAPIError.network(error.localizedDescription)
        }

        guard (200..<300).contains(response.statusCode) else {
            throw Self.error(status: response.statusCode, data: data)
        }
        return data
    }

    func decode<T: Decodable>(_ type: T.Type, from data: Data) throws -> T {
        do {
            return try JSONDecoder().decode(T.self, from: data)
        } catch {
            throw PluginAPIError.decoding
        }
    }

    private static func error(status: Int, data: Data) -> PluginAPIError {
        let detail = message(from: data)
        switch status {
        case 401:
            return .unauthorized(detail)
        case 403:
            return .forbidden(detail)
        case 404:
            return .notFound(detail)
        case 422, 400:
            return .invalidRequest(detail)
        case 429:
            return .rateLimited
        default:
            return .server("HTTP \(status). \(detail)".trimmingCharacters(in: .whitespaces))
        }
    }

    private static func message(from data: Data) -> String {
        guard !data.isEmpty,
              let object = try? JSONSerialization.jsonObject(with: data),
              let dictionary = object as? [String: Any] else {
            return ""
        }
        if let message = dictionary["message"] as? String, !message.isEmpty {
            return String(message.prefix(400))
        }
        if let error = dictionary["error"] as? String, !error.isEmpty {
            return String(error.prefix(400))
        }
        if let errors = dictionary["errors"] as? [String], !errors.isEmpty {
            return String(errors.joined(separator: ", ").prefix(400))
        }
        return ""
    }
}

// MARK: - Shared helpers

enum PluginPaths {
    static func segment(_ value: String) -> String {
        var allowed = CharacterSet.urlPathAllowed
        allowed.remove(charactersIn: "/?#")
        return value.addingPercentEncoding(withAllowedCharacters: allowed) ?? value
    }

    /// GitLab identifies projects by a URL-encoded full path.
    static func gitLabProject(_ path: String) -> String {
        segment(path)
    }

    static func requireOwnerAndName(_ remote: RepositoryRemote) throws -> (owner: String, name: String) {
        let parts = remote.path.split(separator: "/", omittingEmptySubsequences: true)
        guard parts.count == 2 else {
            throw PluginAPIError.invalidRepository(remote.path)
        }
        return (String(parts[0]), String(parts[1]))
    }
}

enum PluginDates {
    static func parse(_ value: String?) -> Date? {
        guard let value, !value.isEmpty else { return nil }
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = fractional.date(from: value) {
            return date
        }
        let plain = ISO8601DateFormatter()
        plain.formatOptions = [.withInternetDateTime]
        return plain.date(from: value)
    }
}

enum PluginState {
    static func pullRequest(_ raw: String) -> PluginPullRequestState {
        switch raw.lowercased() {
        case "open", "opened": return .open
        case "merged": return .merged
        default: return .closed
        }
    }
}
