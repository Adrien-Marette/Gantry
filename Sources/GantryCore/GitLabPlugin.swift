import Foundation

struct GitLabBackend: CodeHostBackend {
    private let http: PluginHTTPClient

    init(connection: PluginConnection, token: String, transport: any PluginHTTPTransport) {
        self.http = PluginHTTPClient(connection: connection, token: token, transport: transport)
    }

    func verify() async throws -> PluginAccount {
        let data = try await http.data(path: "user")
        let user = try http.decode(GitLabUserDTO.self, from: data)
        return PluginAccount(
            login: user.username,
            displayName: user.name?.trimmedNonEmpty,
            avatarURL: user.avatarURL
        )
    }

    func repository(for remote: RepositoryRemote) async throws -> PluginRepository {
        let project = PluginPaths.gitLabProject(remote.path)
        let data = try await http.data(path: "projects/\(project)")
        let repository = try http.decode(GitLabProjectDTO.self, from: data)
        return PluginRepository(
            fullName: repository.pathWithNamespace ?? remote.path,
            defaultBranch: repository.defaultBranch ?? "main",
            webURL: repository.webURL,
            isPrivate: repository.visibility?.lowercased() == "private"
        )
    }

    func pullRequests(for remote: RepositoryRemote) async throws -> [PluginPullRequest] {
        let project = PluginPaths.gitLabProject(remote.path)
        let data = try await http.data(
            path: "projects/\(project)/merge_requests",
            query: [
                URLQueryItem(name: "state", value: "opened"),
                URLQueryItem(name: "per_page", value: "50"),
                URLQueryItem(name: "order_by", value: "updated_at"),
                URLQueryItem(name: "sort", value: "desc")
            ]
        )
        let requests = try http.decode([GitLabMergeRequestDTO].self, from: data)
        return requests.map(\.pluginValue)
    }

    func checks(
        for pullRequest: PluginPullRequest,
        in remote: RepositoryRemote
    ) async throws -> [PluginCheck] {
        let project = PluginPaths.gitLabProject(remote.path)
        let detailData = try await http.data(
            path: "projects/\(project)/merge_requests/\(pullRequest.number)"
        )
        let detail = try http.decode(GitLabMergeRequestDetailDTO.self, from: detailData)
        guard let pipeline = detail.headPipeline else { return [] }

        let jobsData = try await http.data(
            path: "projects/\(project)/pipelines/\(pipeline.id)/jobs",
            query: [URLQueryItem(name: "per_page", value: "50")]
        )
        let jobs = try http.decode([GitLabJobDTO].self, from: jobsData)
        if jobs.isEmpty {
            return [
                PluginCheck(
                    id: "pipeline-\(pipeline.id)",
                    name: "Pipeline",
                    state: PipelineState.state(pipeline.status),
                    description: pipeline.status?.capitalized,
                    detailsURL: pipeline.webURL
                )
            ]
        }
        return jobs.map(\.pluginValue)
    }

    func comment(
        on pullRequestNumber: Int,
        in remote: RepositoryRemote,
        body: String
    ) async throws {
        let project = PluginPaths.gitLabProject(remote.path)
        let path = "projects/\(project)/merge_requests/\(pullRequestNumber)/notes"
        _ = try await http.data(method: "POST", path: path, body: ["body": body])
    }

    func createPullRequest(
        _ request: PluginNewPullRequest,
        in remote: RepositoryRemote
    ) async throws -> PluginPullRequest {
        let project = PluginPaths.gitLabProject(remote.path)
        let path = "projects/\(project)/merge_requests"
        var title = request.title
        if request.isDraft, !title.lowercased().hasPrefix("draft:") {
            title = "Draft: \(title)"
        }
        let data = try await http.data(
            method: "POST",
            path: path,
            body: [
                "title": title,
                "description": request.body,
                "source_branch": request.sourceBranch,
                "target_branch": request.targetBranch
            ]
        )
        let dto = try http.decode(GitLabMergeRequestDTO.self, from: data)
        return dto.pluginValue
    }
}

// MARK: - GitLab payloads

private struct GitLabUserDTO: Decodable {
    let username: String
    let name: String?
    let avatarURL: URL?

    enum CodingKeys: String, CodingKey {
        case username, name
        case avatarURL = "avatar_url"
    }
}

private struct GitLabProjectDTO: Decodable {
    let pathWithNamespace: String?
    let defaultBranch: String?
    let webURL: URL?
    let visibility: String?

    enum CodingKeys: String, CodingKey {
        case pathWithNamespace = "path_with_namespace"
        case defaultBranch = "default_branch"
        case webURL = "web_url"
        case visibility
    }
}

private struct GitLabPipelineDTO: Decodable {
    let id: Int
    let status: String?
    let webURL: URL?

    enum CodingKeys: String, CodingKey {
        case id, status
        case webURL = "web_url"
    }
}

private struct GitLabMergeRequestDTO: Decodable {
    let iid: Int
    let title: String
    let state: String
    let draft: Bool?
    let workInProgress: Bool?
    let webURL: URL?
    let updatedAt: String?
    let author: GitLabUserDTO?
    let sourceBranch: String
    let targetBranch: String
    let sha: String?
    let description: String?

    enum CodingKeys: String, CodingKey {
        case iid, title, state, draft, author, sha, description
        case workInProgress = "work_in_progress"
        case webURL = "web_url"
        case updatedAt = "updated_at"
        case sourceBranch = "source_branch"
        case targetBranch = "target_branch"
    }

    var pluginValue: PluginPullRequest {
        let titleIsDraft = title.lowercased().hasPrefix("draft:") || title.lowercased().hasPrefix("wip:")
        return PluginPullRequest(
            id: iid,
            number: iid,
            title: title,
            state: PluginState.pullRequest(state),
            isDraft: draft ?? workInProgress ?? titleIsDraft,
            author: author?.username ?? "unknown",
            sourceBranch: sourceBranch,
            targetBranch: targetBranch,
            headSHA: sha,
            webURL: webURL,
            updatedAt: PluginDates.parse(updatedAt),
            body: description ?? ""
        )
    }
}

private struct GitLabMergeRequestDetailDTO: Decodable {
    let headPipeline: GitLabPipelineDTO?

    enum CodingKeys: String, CodingKey {
        case headPipeline = "head_pipeline"
    }
}

private struct GitLabJobDTO: Decodable {
    let id: Int
    let name: String
    let status: String?
    let webURL: URL?
    let allowFailure: Bool?

    enum CodingKeys: String, CodingKey {
        case id, name, status
        case webURL = "web_url"
        case allowFailure = "allow_failure"
    }

    var pluginValue: PluginCheck {
        var state = PipelineState.state(status)
        if state == .failure, allowFailure == true {
            state = .neutral
        }
        return PluginCheck(
            id: "job-\(id)",
            name: name,
            state: state,
            description: status?.capitalized,
            detailsURL: webURL
        )
    }
}

private enum PipelineState {
    static func state(_ raw: String?) -> PluginCheckState {
        switch raw?.lowercased() {
        case "success": return .success
        case "failed", "failure": return .failure
        case "canceled", "cancelling": return .cancelled
        case "skipped": return .skipped
        case "manual": return .neutral
        case "created", "waiting_for_resource", "preparing", "pending", "running", "scheduled":
            return .pending
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
