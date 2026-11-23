import Darwin
import Foundation
import Testing
@testable import GantryCore

// MARK: - Test transport

private final class RecordingPluginTransport: PluginHTTPTransport, @unchecked Sendable {
    private let lock = NSLock()
    private var recorded: [URLRequest] = []
    private let handler: @Sendable (URLRequest) async throws -> (Int, Data)

    init(handler: @escaping @Sendable (URLRequest) async throws -> (Int, Data)) {
        self.handler = handler
    }

    var requests: [URLRequest] {
        lock.lock()
        defer { lock.unlock() }
        return recorded
    }

    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        lock.lock()
        recorded.append(request)
        lock.unlock()

        let (status, data) = try await handler(request)
        guard let url = request.url,
              let response = HTTPURLResponse(
                url: url,
                statusCode: status,
                httpVersion: "HTTP/1.1",
                headerFields: nil
              ) else {
            throw PluginAPIError.network("Test transport couldn't create a response.")
        }
        return (data, response)
    }
}

private func connection(
    kind: PluginKind,
    serverURL: String,
    account: String = "tester"
) -> PluginConnection {
    let host = URL(string: serverURL)?.host ?? "example.com"
    return PluginConnection(
        kind: kind,
        name: "Test \(kind.title)",
        serverURL: serverURL,
        accountName: account,
        keychainServer: host,
        keychainAccount: "Gantry Plugins Test · \(account)"
    )
}

private func jsonData(_ string: String) -> Data {
    Data(string.utf8)
}

// MARK: - Local model and remote parsing

@Test func repositoryRemoteParsing() {
    #expect(
        RepositoryRemote.parse("git@github.com:acme/app.git")
            == RepositoryRemote(host: "github.com", path: "acme/app")
    )
    #expect(
        RepositoryRemote.parse("https://github.com/acme/app.git")
            == RepositoryRemote(host: "github.com", path: "acme/app")
    )
    #expect(
        RepositoryRemote.parse("ssh://git@gitlab.com/group/sub/repo.git")
            == RepositoryRemote(host: "gitlab.com", path: "group/sub/repo")
    )
    #expect(
        RepositoryRemote.parse("https://gitea.example.com/team/app/")
            == RepositoryRemote(host: "gitea.example.com", path: "team/app")
    )
    #expect(RepositoryRemote.parse("/Users/me/Projects/app") == nil)
    #expect(RepositoryRemote.parse("https://github.com/only-owner") == nil)
}

@Test func pluginAPIRoots() {
    let github = connection(kind: .github, serverURL: "https://github.com")
    #expect(github.apiBaseURL?.absoluteString == "https://api.github.com")

    let enterprise = connection(kind: .github, serverURL: "https://github.example.com")
    #expect(enterprise.apiBaseURL?.absoluteString == "https://github.example.com/api/v3")

    let gitlab = connection(kind: .gitlab, serverURL: "https://gitlab.com")
    #expect(gitlab.apiBaseURL?.absoluteString == "https://gitlab.com/api/v4")

    let gitea = connection(kind: .gitea, serverURL: "https://gitea.example.com")
    #expect(gitea.apiBaseURL?.absoluteString == "https://gitea.example.com/api/v1")

    #expect(
        PluginKind.normalizedServerURL("gitea.example.com")?.absoluteString
            == "https://gitea.example.com"
    )
    #expect(
        PluginKind.normalizedServerURL("https://GitHub.example.com/")?.absoluteString
            == "https://github.example.com"
    )
    #expect(
        PluginKind.gitlab.tokenPageURL(serverURL: URL(string: "https://gitlab.example.com")!)?
            .absoluteString
            == "https://gitlab.example.com/-/user_settings/personal_access_tokens"
    )
}

@Test func readsOriginRemoteFromGitConfig() throws {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("Gantry-remote-\(UUID().uuidString)", isDirectory: true)
    let gitDirectory = root.appendingPathComponent(".git", isDirectory: true)
    try FileManager.default.createDirectory(at: gitDirectory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }

    let config = """
    [core]
        repositoryformatversion = 0
        bare = false
    [remote "origin"]
        url = git@github.com:acme/app.git
        fetch = +refs/heads/*:refs/remotes/origin/*
    """
    try config.write(
        to: gitDirectory.appendingPathComponent("config"),
        atomically: true,
        encoding: .utf8
    )

    let remote = try #require(GitRepositoryReader.originRemote(at: root))
    #expect(remote.host == "github.com")
    #expect(remote.fullName == "acme/app")
    #expect(GitRepositoryReader.remoteURL(at: root) == "git@github.com:acme/app.git")
}

@Test func legacyProjectDecodesWithoutPluginID() throws {
    let id = UUID()
    let json = """
    {
      "id": "\(id.uuidString)",
      "path": "/tmp/project",
      "name": "Old project",
      "createdAt": "2026-01-01T00:00:00Z",
      "lastOpenedAt": "2026-01-01T00:00:00Z",
      "sessions": []
    }
    """.data(using: .utf8)!
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    let project = try decoder.decode(Project.self, from: json)
    #expect(project.pluginID == nil)
    #expect(project.name == "Old project")
}

// MARK: - GitHub

@Test func gitHubVerifiesAccountAndBuildsRequest() async throws {
    let transport = RecordingPluginTransport { _ in
        (200, jsonData(#"{"login":"octocat","name":"The Octocat","avatar_url":"https://avatars.example.com/u/1"}"#))
    }
    let plugin = connection(kind: .github, serverURL: "https://github.com")
    let client = CodeHostClient(connection: plugin, token: "token-123", transport: transport)

    let account = try await client.verify()
    #expect(account.login == "octocat")
    #expect(account.displayName == "The Octocat")

    let request = try #require(transport.requests.first)
    #expect(request.url?.absoluteString == "https://api.github.com/user")
    #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer token-123")
    #expect(request.value(forHTTPHeaderField: "X-GitHub-Api-Version") == "2022-11-28")
    #expect(request.url?.absoluteString.contains("token-123") == false)
}

@Test func gitHubMapsOpenPullRequests() async throws {
    let transport = RecordingPluginTransport { _ in
        (200, jsonData("""
        [
          {
            "number": 7,
            "title": "Improve plugin support",
            "state": "open",
            "draft": false,
            "html_url": "https://github.com/acme/app/pull/7",
            "updated_at": "2026-11-20T10:00:00Z",
            "user": {"login": "alice"},
            "head": {"ref": "feature/plugins", "sha": "abc123"},
            "base": {"ref": "main"},
            "body": "Adds plugins."
          }
        ]
        """))
    }
    let plugin = connection(kind: .github, serverURL: "https://github.com")
    let client = CodeHostClient(connection: plugin, token: "token-123", transport: transport)
    let remote = RepositoryRemote(host: "github.com", path: "acme/app")

    let requests = try await client.pullRequests(for: remote)
    #expect(requests.count == 1)
    let pullRequest = try #require(requests.first)
    #expect(pullRequest.number == 7)
    #expect(pullRequest.state == .open)
    #expect(pullRequest.author == "alice")
    #expect(pullRequest.sourceBranch == "feature/plugins")
    #expect(pullRequest.targetBranch == "main")
    #expect(pullRequest.headSHA == "abc123")
    #expect(pullRequest.webURL?.absoluteString == "https://github.com/acme/app/pull/7")

    let request = try #require(transport.requests.first)
    #expect(request.url?.path == "/repos/acme/app/pulls")
    let query = try #require(request.url.flatMap { URLComponents(url: $0, resolvingAgainstBaseURL: false)?.queryItems })
    #expect(query.contains { $0.name == "state" && $0.value == "open" })
}

@Test func gitHubMapsCheckRunsAndStatuses() async throws {
    let transport = RecordingPluginTransport { request in
        let path = request.url?.path ?? ""
        if path.hasSuffix("/check-runs") {
            return (200, jsonData("""
            {
              "total_count": 1,
              "check_runs": [
                {
                  "id": 11,
                  "name": "build",
                  "status": "completed",
                  "conclusion": "success",
                  "details_url": "https://github.com/acme/app/runs/11",
                  "output": {"title": "Build passed"}
                }
              ]
            }
            """))
        }
        if path.hasSuffix("/status") {
            return (200, jsonData("""
            {
              "state": "failure",
              "statuses": [
                {
                  "context": "ci/test",
                  "state": "failure",
                  "description": "Tests failed",
                  "target_url": "https://github.com/acme/app/runs/12"
                }
              ]
            }
            """))
        }
        return (404, jsonData(#"{"message":"not found"}"#))
    }
    let plugin = connection(kind: .github, serverURL: "https://github.com")
    let client = CodeHostClient(connection: plugin, token: "token-123", transport: transport)
    let remote = RepositoryRemote(host: "github.com", path: "acme/app")
    let pullRequest = PluginPullRequest(
        id: 7,
        number: 7,
        title: "Improve plugin support",
        author: "alice",
        sourceBranch: "feature/plugins",
        targetBranch: "main",
        headSHA: "abc123"
    )

    let checks = try await client.checks(for: pullRequest, in: remote)
    #expect(checks.count == 2)
    #expect(checks[0].name == "build")
    #expect(checks[0].state == .success)
    #expect(checks[1].name == "ci/test")
    #expect(checks[1].state == .failure)
    #expect(transport.requests.first?.url?.path == "/repos/acme/app/commits/abc123/check-runs")
}

// MARK: - GitLab

@Test func gitLabMapsMergeRequests() async throws {
    let transport = RecordingPluginTransport { _ in
        (200, jsonData("""
        [
          {
            "iid": 3,
            "title": "Draft: Improve docs",
            "state": "opened",
            "draft": true,
            "web_url": "https://gitlab.com/group/sub/repo/-/merge_requests/3",
            "updated_at": "2026-11-20T10:30:00Z",
            "author": {"username": "alice"},
            "source_branch": "docs",
            "target_branch": "main",
            "sha": "sha3",
            "description": "Docs changes"
          }
        ]
        """))
    }
    let plugin = connection(kind: .gitlab, serverURL: "https://gitlab.com")
    let client = CodeHostClient(connection: plugin, token: "gl-token", transport: transport)
    let remote = RepositoryRemote(host: "gitlab.com", path: "group/sub/repo")

    let requests = try await client.pullRequests(for: remote)
    let pullRequest = try #require(requests.first)
    #expect(pullRequest.number == 3)
    #expect(pullRequest.title == "Draft: Improve docs")
    #expect(pullRequest.isDraft)
    #expect(pullRequest.state == .open)
    #expect(pullRequest.author == "alice")
    #expect(pullRequest.sourceBranch == "docs")
    #expect(pullRequest.targetBranch == "main")
    #expect(pullRequest.headSHA == "sha3")

    let request = try #require(transport.requests.first)
    let url = try #require(request.url?.absoluteString)
    #expect(url.contains("/api/v4/projects/group%2Fsub%2Frepo/merge_requests"))
    #expect(request.value(forHTTPHeaderField: "PRIVATE-TOKEN") == "gl-token")
    #expect(url.contains("gl-token") == false)
}

@Test func gitLabMapsPipelineJobsAndPostsComment() async throws {
    let transport = RecordingPluginTransport { request in
        let path = request.url?.path ?? ""
        if request.httpMethod == "POST" {
            return (201, jsonData("{}"))
        }
        if path.hasSuffix("/merge_requests/3") {
            return (200, jsonData("""
            {"head_pipeline":{"id":42,"status":"failed","web_url":"https://gitlab.com/group/sub/repo/-/pipelines/42"}}
            """))
        }
        if path.contains("/pipelines/42/jobs") {
            return (200, jsonData("""
            [
              {"id":10,"name":"rspec","status":"failed","web_url":"https://gitlab.com/job/10","allow_failure":false},
              {"id":11,"name":"lint","status":"success","web_url":"https://gitlab.com/job/11","allow_failure":false},
              {"id":12,"name":"optional","status":"failed","web_url":"https://gitlab.com/job/12","allow_failure":true}
            ]
            """))
        }
        return (404, jsonData(#"{"message":"not found"}"#))
    }
    let plugin = connection(kind: .gitlab, serverURL: "https://gitlab.com")
    let client = CodeHostClient(connection: plugin, token: "gl-token", transport: transport)
    let remote = RepositoryRemote(host: "gitlab.com", path: "group/sub/repo")
    let pullRequest = PluginPullRequest(
        id: 3,
        number: 3,
        title: "Docs",
        author: "alice",
        sourceBranch: "docs",
        targetBranch: "main",
        headSHA: "sha3"
    )

    let checks = try await client.checks(for: pullRequest, in: remote)
    #expect(checks.count == 3)
    #expect(checks.map(\.state) == [.failure, .success, .neutral])

    try await client.comment(on: 3, in: remote, body: "Looks good")
    let commentRequest = try #require(transport.requests.last)
    #expect(commentRequest.httpMethod == "POST")
    #expect(commentRequest.url?.path.contains("merge_requests/3/notes") == true)
    let body = try #require(commentRequest.httpBody)
    let object = try #require(
        JSONSerialization.jsonObject(with: body) as? [String: Any]
    )
    #expect(object["body"] as? String == "Looks good")
}

// MARK: - Gitea

@Test func giteaListsPullRequestsAndReadsStatuses() async throws {
    let transport = RecordingPluginTransport { request in
        let path = request.url?.path ?? ""
        if path.hasSuffix("/pulls") {
            return (200, jsonData("""
            [
              {
                "number": 5,
                "title": "Gitea fix",
                "state": "open",
                "draft": false,
                "html_url": "https://gitea.example.com/team/app/pulls/5",
                "updated_at": "2026-11-20T11:00:00Z",
                "user": {"login": "bob"},
                "head": {"ref": "fix", "sha": "def456"},
                "base": {"ref": "main"},
                "body": "Gitea changes"
              }
            ]
            """))
        }
        if path.hasSuffix("/statuses") {
            return (200, jsonData("""
            [
              {"id":1,"context":"ci/build","status":"success","description":"ok","target_url":"https://gitea.example.com/status/1"},
              {"id":2,"context":"ci/test","status":"failure","description":"failed","target_url":"https://gitea.example.com/status/2"}
            ]
            """))
        }
        return (404, jsonData(#"{"message":"not found"}"#))
    }
    let plugin = connection(kind: .gitea, serverURL: "https://gitea.example.com")
    let client = CodeHostClient(connection: plugin, token: "gitea-token", transport: transport)
    let remote = RepositoryRemote(host: "gitea.example.com", path: "team/app")

    let requests = try await client.pullRequests(for: remote)
    let pullRequest = try #require(requests.first)
    #expect(pullRequest.number == 5)
    #expect(pullRequest.author == "bob")
    #expect(pullRequest.headSHA == "def456")

    let checks = try await client.checks(for: pullRequest, in: remote)
    #expect(checks.count == 2)
    #expect(checks.map(\.name) == ["ci/build", "ci/test"])
    #expect(checks.map(\.state) == [.success, .failure])

    let firstRequest = try #require(transport.requests.first)
    #expect(firstRequest.url?.path == "/api/v1/repos/team/app/pulls")
    #expect(firstRequest.value(forHTTPHeaderField: "Authorization") == "token gitea-token")
}

// MARK: - Keychain

@Test func pluginKeychainRoundTrip() throws {
    guard ProcessInfo.processInfo.environment["Gantry_RUN_KEYCHAIN_TESTS"] == "1" else {
        return
    }
    let unique = UUID().uuidString
    let plugin = PluginConnection(
        kind: .gitea,
        name: "Gantry Plugin Keychain Test",
        serverURL: "https://Gantry-plugin-test.example.com",
        accountName: "tester",
        keychainServer: "Gantry-plugin-test-\(unique).example.com",
        keychainAccount: "Gantry Plugins Test · \(unique)"
    )
    defer { try? PluginKeychain.deleteKey(for: plugin) }

    try PluginKeychain.store("first-plugin-token", for: plugin)
    #expect(try PluginKeychain.secret(for: plugin) == "first-plugin-token")
    #expect(PluginKeychain.hasKey(for: plugin))

    try PluginKeychain.store("second-plugin-token", for: plugin)
    #expect(try PluginKeychain.secret(for: plugin) == "second-plugin-token")

    try PluginKeychain.deleteKey(for: plugin)
    #expect(try PluginKeychain.secret(for: plugin) == nil)
    #expect(!PluginKeychain.hasKey(for: plugin))
}

// MARK: - MCP tools

@Test func pluginToolCatalogIsConsistent() {
    let tools = PluginToolCatalog.all
    #expect(tools.count == 6)
    #expect(Set(tools.map(\.name)).count == tools.count)
    for tool in tools {
        let schema = tool.inputSchema.objectValue
        #expect(schema?["type"]?.stringValue == "object")
        #expect(schema?["properties"] != nil)
        let annotations = tool.annotations.objectValue
        #expect(annotations?["readOnlyHint"]?.boolValue == !tool.name.isWrite)
    }
}

@Test func pluginToolExecutorReadsRepositoryAndChecks() async throws {
    let transport = RecordingPluginTransport { request in
        let path = request.url?.path ?? ""
        if path.hasSuffix("/pulls") {
            return (200, jsonData("""
            [
              {
                "number": 5,
                "title": "Gitea fix",
                "state": "open",
                "draft": false,
                "html_url": "https://gitea.example.com/team/app/pulls/5",
                "updated_at": "2026-11-20T11:00:00Z",
                "user": {"login": "bob"},
                "head": {"ref": "fix", "sha": "def456"},
                "base": {"ref": "main"},
                "body": "Gitea changes"
              }
            ]
            """))
        }
        if path.hasSuffix("/statuses") {
            return (200, jsonData("""
            [
              {"id":1,"context":"ci/build","status":"success","description":"ok","target_url":"https://gitea.example.com/status/1"},
              {"id":2,"context":"ci/test","status":"failure","description":"failed","target_url":"https://gitea.example.com/status/2"}
            ]
            """))
        }
        if path.hasSuffix("/repos/team/app") {
            return (200, jsonData("""
            {"full_name":"team/app","default_branch":"main","html_url":"https://gitea.example.com/team/app","private":false}
            """))
        }
        return (404, jsonData(#"{"message":"not found"}"#))
    }
    let plugin = connection(kind: .gitea, serverURL: "https://gitea.example.com")
    let client = CodeHostClient(connection: plugin, token: "gitea-token", transport: transport)
    let remote = RepositoryRemote(host: "gitea.example.com", path: "team/app")
    let executor = PluginToolExecutor(client: client, remote: remote)

    let repository = try await executor.execute(tool: "get_repository", arguments: .object([:]))
    #expect(repository.objectValue?["full_name"]?.stringValue == "team/app")

    let listed = try await executor.execute(tool: "list_pull_requests", arguments: .object([:]))
    let pullRequests = try #require(listed.objectValue?["pull_requests"]?.arrayValue)
    #expect(pullRequests.count == 1)
    #expect(pullRequests[0].objectValue?["number"]?.numberValue == 5)

    let detail = try await executor.execute(
        tool: "get_pull_request",
        arguments: .object(["number": .number(5)])
    )
    #expect(detail.objectValue?["title"]?.stringValue == "Gitea fix")
    #expect(detail.objectValue?["checks"]?.arrayValue?.count == 2)
}

@Test func pluginToolExecutorPostsComment() async throws {
    let transport = RecordingPluginTransport { request in
        if request.httpMethod == "POST" {
            return (201, jsonData("{}"))
        }
        return (404, jsonData(#"{"message":"not found"}"#))
    }
    let plugin = connection(kind: .gitea, serverURL: "https://gitea.example.com")
    let client = CodeHostClient(connection: plugin, token: "gitea-token", transport: transport)
    let remote = RepositoryRemote(host: "gitea.example.com", path: "team/app")
    let executor = PluginToolExecutor(client: client, remote: remote)

    let result = try await executor.execute(
        tool: "comment_on_pull_request",
        arguments: .object([
            "number": .number(5),
            "body": .string("Looks good to me")
        ])
    )
    #expect(result.objectValue?["ok"]?.boolValue == true)
    #expect(result.objectValue?["number"]?.numberValue == 5)

    let request = try #require(transport.requests.first)
    #expect(request.httpMethod == "POST")
    #expect(request.url?.path.contains("/issues/5/comments") == true)
    let body = try #require(request.httpBody)
    let object = try #require(JSONSerialization.jsonObject(with: body) as? [String: Any])
    #expect(object["body"] as? String == "Looks good to me")
}

@Test func pluginToolExecutorRejectsUnknownTool() async throws {
    let plugin = connection(kind: .gitea, serverURL: "https://gitea.example.com")
    let transport = RecordingPluginTransport { _ in
        (500, Data())
    }
    let client = CodeHostClient(connection: plugin, token: "gitea-token", transport: transport)
    let executor = PluginToolExecutor(
        client: client,
        remote: RepositoryRemote(host: "gitea.example.com", path: "team/app")
    )

    do {
        _ = try await executor.execute(tool: "delete_everything", arguments: .object([:]))
        Issue.record("Expected an unknown tool error")
    } catch let error as PluginToolError {
        guard case .unknownTool = error else {
            Issue.record("Unexpected error: \(error)")
            return
        }
    }
}

@Test func pluginToolBridgeRoundTripAndAuth() throws {
    let bridge = try PluginToolBridge { request in
        .object([
            "tool": .string(request.tool),
            "arguments": request.arguments
        ])
    }
    defer { bridge.stop() }

    let request = PluginToolBridgeRequest(
        auth: bridge.authToken,
        tool: "list_pull_requests",
        arguments: .object(["page": .number(1)])
    )
    let response = try sendBridgeRequest(request, socketPath: bridge.socketPath)
    #expect(response.ok)
    #expect(response.result?.objectValue?["tool"]?.stringValue == "list_pull_requests")
    #expect(response.result?.objectValue?["arguments"]?.objectValue?["page"]?.numberValue == 1)

    let unauthorized = PluginToolBridgeRequest(
        auth: "wrong-token",
        tool: "list_pull_requests"
    )
    let rejected = try sendBridgeRequest(unauthorized, socketPath: bridge.socketPath)
    #expect(!rejected.ok)
    #expect(rejected.error?.contains("authorized") == true)
}

private func sendBridgeRequest(
    _ request: PluginToolBridgeRequest,
    socketPath: String
) throws -> PluginToolBridgeResponse {
    guard socketPath.utf8.count < 104 else {
        throw PluginToolBridgeError.incompleteRequest
    }
    let fileDescriptor = socket(AF_UNIX, SOCK_STREAM, 0)
    guard fileDescriptor >= 0 else {
        throw PluginToolBridgeError.socket(errno)
    }
    defer { close(fileDescriptor) }

    var noSigPipe: Int32 = 1
    _ = setsockopt(
        fileDescriptor,
        SOL_SOCKET,
        SO_NOSIGPIPE,
        &noSigPipe,
        socklen_t(MemoryLayout<Int32>.size)
    )
    var timeout = timeval(tv_sec: 10, tv_usec: 0)
    _ = setsockopt(
        fileDescriptor,
        SOL_SOCKET,
        SO_RCVTIMEO,
        &timeout,
        socklen_t(MemoryLayout<timeval>.size)
    )

    var address = sockaddr_un()
    let addressLength = socklen_t(MemoryLayout<sa_family_t>.size + socketPath.utf8.count + 1)
    address.sun_len = UInt8(min(addressLength, 255))
    address.sun_family = sa_family_t(AF_UNIX)
    socketPath.withCString { path in
        _ = strlcpy(
            &address.sun_path.0,
            path,
            MemoryLayout.size(ofValue: address.sun_path)
        )
    }
    let connectResult = withUnsafePointer(to: &address) { pointer in
        pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { socketAddress in
            connect(fileDescriptor, socketAddress, addressLength)
        }
    }
    guard connectResult == 0 else {
        throw PluginToolBridgeError.bind(errno)
    }

    var data = try JSONEncoder().encode(request)
    data.append(0x0A)
    data.withUnsafeBytes { bytes in
        guard let base = bytes.baseAddress else { return }
        _ = Darwin.write(fileDescriptor, base, bytes.count)
    }

    var responseData = Data()
    var buffer = [UInt8](repeating: 0, count: 4_096)
    while !responseData.contains(0x0A) {
        let count = buffer.withUnsafeMutableBytes { bytes -> Int in
            guard let base = bytes.baseAddress else { return 0 }
            return Darwin.read(fileDescriptor, base, bytes.count)
        }
        if count > 0 {
            buffer.withUnsafeBytes { bytes in
                if let base = bytes.baseAddress {
                    responseData.append(
                        base.assumingMemoryBound(to: UInt8.self),
                        count: count
                    )
                }
            }
        } else {
            break
        }
    }
    guard let newline = responseData.firstIndex(of: 0x0A) else {
        throw PluginToolBridgeError.incompleteRequest
    }
    return try JSONDecoder().decode(
        PluginToolBridgeResponse.self,
        from: responseData.prefix(upTo: newline)
    )
}
