import Foundation

struct GiteaBackend: CodeHostBackend {
    private let http: PluginHTTPClient

    init(connection: PluginConnection, token: String, transport: any PluginHTTPTransport) {
        self.http = PluginHTTPClient(connection: connection, token: token, transport: transport)
    }

    func verify() async throws -> PluginAccount {
        let data = try await http.data(path: "user")
        let user = try http.decode(GiteaUserDTO.self, from: data)
        return PluginAccount(
            login: user.login,
            displayName: user.fullName?.trimmedNonEmpty,
            avatarURL: user.avatarURL
        )
    }

    func repository(for remote: RepositoryRemote) async throws -> PluginRepository {
        let (owner, name) = try PluginPaths.requireOwnerAndName(remote)
        let path = "repos/\(PluginPaths.segment(owner))/\(PluginPaths.segment(name))"
        let data = try await http.data(path: path)
        let repository = try http.decode(GiteaRepositoryDTO.self, from: data)
        return PluginRepository(
            fullName: repository.fullName ?? "\(owner)/\(name)",
            defaultBranch: repository.defaultBranch ?? "main",
            webURL: repository.htmlURL,
            isPrivate: repository.isPrivate ?? false
        )
    }

    func pullRequests(for remote: RepositoryRemote) async throws -> [PluginPullRequest] {
        let (owner, name) = try PluginPaths.requireOwnerAndName(remote)
        let path = "repos/\(PluginPaths.segment(owner))/\(PluginPaths.segment(name))/pulls"
        let data = try await http.data(
            path: path,
            query: [
                URLQueryItem(name: "state", value: "open"),
                URLQueryItem(name: "limit", value: "50"),
                URLQueryItem(name: "sort", value: "recentupdate")
            ]
        )
        let requests = try http.decode([GiteaPullRequestDTO].self, from: data)
        return requests.map(\.pluginValue)
    }

    func checks(
        for pullRequest: PluginPullRequest,
        in remote: RepositoryRemote
    ) async throws -> [PluginCheck] {
        guard let sha = pullRequest.headSHA, !sha.isEmpty else {
            throw PluginAPIError.missingCommit
        }
        let (owner, name) = try PluginPaths.requireOwnerAndName(remote)
        let path = "repos/\(PluginPaths.segment(owner))/\(PluginPaths.segment(name))/commits/\(PluginPaths.segment(sha))/statuses"
        let data = try await http.data(path: path)
        let statuses = try http.decode([GiteaCommitStatusDTO].self, from: data)
        return statuses.enumerated().map { index, status in
            status.pluginValue(index: index)
        }
    }

    func comment(
        on pullRequestNumber: Int,
        in remote: RepositoryRemote,
        body: String
    ) async throws {
        let (owner, name) = try PluginPaths.requireOwnerAndName(remote)
        let path = "repos/\(PluginPaths.segment(owner))/\(PluginPaths.segment(name))/issues/\(pullRequestNumber)/comments"
        _ = try await http.data(method: "POST", path: path, body: ["body": body])
    }

    func createPullRequest(
        _ request: PluginNewPullRequest,
        in remote: RepositoryRemote
    ) async throws -> PluginPullRequest {
        let (owner, name) = try PluginPaths.requireOwnerAndName(remote)
        let path = "repos/\(PluginPaths.segment(owner))/\(PluginPaths.segment(name))/pulls"
        let title = request.isDraft && !request.title.lowercased().hasPrefix("wip:")
            ? "WIP: \(request.title)"
            : request.title
        let data = try await http.data(
            method: "POST",
            path: path,
            body: [
                "title": title,
                "body": request.body,
                "head": request.sourceBranch,
                "base": request.targetBranch
            ]
        )
        let dto = try http.decode(GiteaPullRequestDTO.self, from: data)
        return dto.pluginValue
    }
}

// MARK: - Gitea payloads

private struct GiteaUserDTO: Decodable {
    let login: String
    let fullName: String?
    let avatarURL: URL?

    enum CodingKeys: String, CodingKey {
        case login
        case fullName = "full_name"
        case avatarURL = "avatar_url"
    }
}

private struct GiteaRepositoryDTO: Decodable {
    let fullName: String?
    let defaultBranch: String?
    let htmlURL: URL?
    let isPrivate: Bool?

    enum CodingKeys: String, CodingKey {
        case fullName = "full_name"
        case defaultBranch = "default_branch"
        case htmlURL = "html_url"
        case isPrivate = "private"
    }
}

private struct GiteaBranchDTO: Decodable {
    let ref: String
    let sha: String?
}

private struct GiteaPullRequestDTO: Decodable {
    let number: Int
    let title: String
    let state: String
    let draft: Bool?
    let merged: Bool?
    let htmlURL: URL?
    let updatedAt: String?
    let user: GiteaUserDTO?
    let head: GiteaBranchDTO
    let base: GiteaBranchDTO
    let body: String?

    enum CodingKeys: String, CodingKey {
        case number, title, state, draft, merged, user, head, base, body
        case htmlURL = "html_url"
        case updatedAt = "updated_at"
    }

    var pluginValue: PluginPullRequest {
        let state: PluginPullRequestState = merged == true
            ? .merged
            : PluginState.pullRequest(self.state)
        return PluginPullRequest(
            id: number,
            number: number,
            title: title,
            state: state,
            isDraft: draft ?? false,
            author: user?.login ?? "unknown",
            sourceBranch: head.ref,
            targetBranch: base.ref,
            headSHA: head.sha,
            webURL: htmlURL,
            updatedAt: PluginDates.parse(updatedAt),
            body: body ?? ""
        )
    }
}

private struct GiteaCommitStatusDTO: Decodable {
    let id: Int?
    let context: String
    let status: String
    let description: String?
    let targetURL: URL?

    enum CodingKeys: String, CodingKey {
        case id, context, status, description
        case targetURL = "target_url"
    }

    func pluginValue(index: Int) -> PluginCheck {
        PluginCheck(
            id: id.map { "gitea-\($0)" } ?? "gitea-\(index)-\(context)",
            name: context.isEmpty ? "Commit status" : context,
            state: Self.state(status),
            description: description?.trimmedNonEmpty ?? status.capitalized,
            detailsURL: targetURL
        )
    }

    private static func state(_ raw: String) -> PluginCheckState {
        switch raw.lowercased() {
        case "success": return .success
        case "failure", "error": return .failure
        case "warning": return .neutral
        case "pending": return .pending
        default: return .unknown
        }
    }
}

private extension String {
    var trimmedNonEmpty: String? {
        let value = trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }
}
