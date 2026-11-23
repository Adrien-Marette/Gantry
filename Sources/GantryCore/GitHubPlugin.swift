import Foundation

struct GitHubBackend: CodeHostBackend {
    private let http: PluginHTTPClient

    init(connection: PluginConnection, token: String, transport: any PluginHTTPTransport) {
        self.http = PluginHTTPClient(connection: connection, token: token, transport: transport)
    }

    func verify() async throws -> PluginAccount {
        let data = try await http.data(path: "user")
        let user = try http.decode(GitHubUserDTO.self, from: data)
        return PluginAccount(
            login: user.login,
            displayName: user.name?.trimmedNonEmpty,
            avatarURL: user.avatarURL
        )
    }

    func repository(for remote: RepositoryRemote) async throws -> PluginRepository {
        let (owner, name) = try PluginPaths.requireOwnerAndName(remote)
        let path = "repos/\(PluginPaths.segment(owner))/\(PluginPaths.segment(name))"
        let data = try await http.data(path: path)
        let repository = try http.decode(GitHubRepositoryDTO.self, from: data)
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
                URLQueryItem(name: "per_page", value: "50"),
                URLQueryItem(name: "sort", value: "updated"),
                URLQueryItem(name: "direction", value: "desc")
            ]
        )
        let requests = try http.decode([GitHubPullRequestDTO].self, from: data)
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
        let base = "repos/\(PluginPaths.segment(owner))/\(PluginPaths.segment(name))/commits/\(PluginPaths.segment(sha))"

        var checks: [PluginCheck] = []
        var firstError: Error?
        let acceptChecks = ["Accept": "application/vnd.github+json"]

        do {
            let runsData = try await http.data(
                path: "\(base)/check-runs",
                query: [URLQueryItem(name: "per_page", value: "50")],
                additionalHeaders: acceptChecks
            )
            let runs = try http.decode(GitHubCheckRunsDTO.self, from: runsData)
            checks.append(contentsOf: runs.checkRuns.map(\.pluginValue))
        } catch {
            if !isNotFound(error) {
                firstError = error
            }
        }

        do {
            let statusData = try await http.data(path: "\(base)/status")
            let status = try http.decode(GitHubCombinedStatusDTO.self, from: statusData)
            checks.append(contentsOf: status.statuses.enumerated().map { index, item in
                item.pluginValue(index: index)
            })
        } catch {
            if firstError == nil, !isNotFound(error) {
                firstError = error
            }
        }

        if checks.isEmpty, let firstError {
            throw firstError
        }
        return checks
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
        let data = try await http.data(
            method: "POST",
            path: path,
            body: [
                "title": request.title,
                "body": request.body,
                "head": request.sourceBranch,
                "base": request.targetBranch,
                "draft": request.isDraft
            ]
        )
        let dto = try http.decode(GitHubPullRequestDTO.self, from: data)
        return dto.pluginValue
    }

    private func isNotFound(_ error: Error) -> Bool {
        guard let pluginError = error as? PluginAPIError,
              case .notFound = pluginError else { return false }
        return true
    }
}

// MARK: - GitHub payloads

private struct GitHubUserDTO: Decodable {
    let login: String
    let name: String?
    let avatarURL: URL?

    enum CodingKeys: String, CodingKey {
        case login
        case name
        case avatarURL = "avatar_url"
    }
}

private struct GitHubRepositoryDTO: Decodable {
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

private struct GitHubBranchDTO: Decodable {
    let ref: String
    let sha: String?
}

private struct GitHubPullRequestDTO: Decodable {
    let number: Int
    let title: String
    let state: String
    let draft: Bool?
    let htmlURL: URL?
    let updatedAt: String?
    let user: GitHubUserDTO?
    let head: GitHubBranchDTO
    let base: GitHubBranchDTO
    let body: String?
    let mergedAt: String?

    enum CodingKeys: String, CodingKey {
        case number, title, state, draft, user, head, base, body
        case htmlURL = "html_url"
        case updatedAt = "updated_at"
        case mergedAt = "merged_at"
    }

    var pluginValue: PluginPullRequest {
        let state: PluginPullRequestState = mergedAt != nil
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

private struct GitHubCheckRunsDTO: Decodable {
    let checkRuns: [GitHubCheckRunDTO]

    enum CodingKeys: String, CodingKey {
        case checkRuns = "check_runs"
    }
}

private struct GitHubCheckRunDTO: Decodable {
    let id: Int
    let name: String
    let status: String?
    let conclusion: String?
    let detailsURL: URL?
    let output: GitHubCheckOutputDTO?

    enum CodingKeys: String, CodingKey {
        case id, name, status, conclusion, output
        case detailsURL = "details_url"
    }

    var pluginValue: PluginCheck {
        PluginCheck(
            id: "check-\(id)",
            name: name,
            state: Self.state(status: status, conclusion: conclusion),
            description: output?.title?.trimmedNonEmpty ?? conclusion,
            detailsURL: detailsURL
        )
    }

    private static func state(status: String?, conclusion: String?) -> PluginCheckState {
        guard status?.lowercased() == "completed" else { return .pending }
        switch conclusion?.lowercased() {
        case "success": return .success
        case "failure", "timed_out", "action_required": return .failure
        case "neutral": return .neutral
        case "skipped": return .skipped
        case "cancelled": return .cancelled
        default: return .unknown
        }
    }
}

private struct GitHubCheckOutputDTO: Decodable {
    let title: String?
}

private struct GitHubCombinedStatusDTO: Decodable {
    let statuses: [GitHubStatusDTO]
}

private struct GitHubStatusDTO: Decodable {
    let context: String
    let state: String
    let description: String?
    let targetURL: URL?

    enum CodingKeys: String, CodingKey {
        case context, state, description
        case targetURL = "target_url"
    }

    func pluginValue(index: Int) -> PluginCheck {
        PluginCheck(
            id: "status-\(index)-\(context)",
            name: context,
            state: Self.state(state),
            description: description?.trimmedNonEmpty,
            detailsURL: targetURL
        )
    }

    private static func state(_ raw: String) -> PluginCheckState {
        switch raw.lowercased() {
        case "success": return .success
        case "failure", "error": return .failure
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
