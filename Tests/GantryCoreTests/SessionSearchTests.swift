import Foundation
import Testing
@testable import GantryCore

private func date(_ seconds: TimeInterval) -> Date {
    Date(timeIntervalSince1970: seconds)
}

private func bashTool(id: String, command: String) -> ToolActivity {
    ToolActivity(
        id: id,
        name: "Bash",
        input: .object(["command": .string(command)]),
        status: .completed
    )
}

@Test func searchesTitlesPromptsAnswersAndToolsInRankOrder() throws {
    let userTurn = ConversationTurn(
        role: .user,
        createdAt: date(100),
        blocks: [.makeText("How do I deploy the service?")]
    )
    let assistantTurn = ConversationTurn(
        role: .assistant,
        createdAt: date(200),
        blocks: [.makeText("Run the deploy script.")]
    )
    let toolTurn = ConversationTurn(
        role: .assistant,
        createdAt: date(300),
        blocks: [.makeTool(bashTool(id: "t1", command: "deploy --prod"))]
    )
    let session = ChatSession(
        title: "Deploy pipeline notes",
        createdAt: date(50),
        updatedAt: date(350),
        turns: [userTurn, assistantTurn, toolTurn]
    )
    let project = Project(path: "/tmp/project", name: "Project", sessions: [session])

    let hits = SessionSearch.search(query: "deploy", projects: [project])

    #expect(hits.map(\.kind) == [.title, .user, .assistant, .tool])
    #expect(hits[0].turnID == nil)
    #expect(hits[0].snippet.contains("deploy"))
    #expect(hits[1].turnID == userTurn.id)
    #expect(hits[2].turnID == assistantTurn.id)
    #expect(hits[3].turnID == toolTurn.id)
    #expect(hits.allSatisfy { $0.snippet.lowercased().contains("deploy") })
}

@Test func returnsOneBestHitPerTurn() {
    let turn = ConversationTurn(
        role: .assistant,
        createdAt: date(100),
        blocks: [
            .makeText("Deploy it with the script."),
            .makeTool(bashTool(id: "t1", command: "deploy --prod"))
        ]
    )
    let session = ChatSession(title: "Release", turns: [turn])
    let project = Project(path: "/tmp/project", name: "Project", sessions: [session])

    let hits = SessionSearch.search(query: "deploy", projects: [project])

    #expect(hits.count == 1)
    #expect(hits[0].kind == .assistant)
    #expect(hits[0].turnID == turn.id)
}

@Test func searchIsCaseAndDiacriticInsensitive() {
    let turn = ConversationTurn(
        role: .user,
        createdAt: date(100),
        blocks: [.makeText("Résumé review for the Café launch")]
    )
    let session = ChatSession(title: "Résumé review", turns: [turn])
    let project = Project(path: "/tmp/project", name: "Project", sessions: [session])

    let titleHits = SessionSearch.search(query: "resume", projects: [project])
    #expect(titleHits.contains { $0.kind == .title })

    let textHits = SessionSearch.search(query: "cafe", projects: [project])
    #expect(textHits.contains { $0.kind == .user })
    #expect(textHits.first?.snippet.contains("Café") == true)
}

@Test func snippetsCollapseWhitespaceAndContainTheMatch() throws {
    let text = "first line\nsecond line\nfind the deployment target here\nlast line"
    let snippet = try #require(SessionSearch.matchingSnippet(in: text, query: "deployment"))
    #expect(snippet.contains("deployment"))
    #expect(!snippet.contains("\n"))
}

@Test func searchesToolFilePaths() {
    let tool = ToolActivity(
        id: "t1",
        name: "Read",
        input: .object(["file_path": .string("/tmp/Sources/PromptAttachments.swift")]),
        status: .completed
    )
    let turn = ConversationTurn(role: .assistant, blocks: [.makeTool(tool)])
    let session = ChatSession(title: "Reading", turns: [turn])
    let project = Project(path: "/tmp/project", name: "Project", sessions: [session])

    let hits = SessionSearch.search(query: "promptattachments", projects: [project])
    #expect(hits.count == 1)
    #expect(hits[0].kind == .tool)
    #expect(hits[0].snippet.contains("PromptAttachments.swift"))
}

@Test func emptyQueryAndLimitBehavePredictably() {
    let session = ChatSession(
        title: "Deploy",
        turns: [ConversationTurn(role: .user, blocks: [.makeText("deploy")])]
    )
    let project = Project(path: "/tmp/project", name: "Project", sessions: [session])

    #expect(SessionSearch.search(query: "  ", projects: [project]).isEmpty)

    let hits = SessionSearch.search(query: "deploy", projects: [project], limit: 1)
    #expect(hits.count == 1)
    #expect(hits[0].kind == .title)
}

@Test func titleSearchNormalizesRepeatedWhitespace() {
    let session = ChatSession(title: "Release  notes")
    let project = Project(path: "/tmp/project", name: "Project", sessions: [session])

    let hits = SessionSearch.search(query: "Release  notes", projects: [project])

    #expect(hits.map(\.kind) == [.title])
    #expect(hits.map(\.sessionTitle) == ["Release  notes"])
}

@Test func searchNormalizesRepeatedWhitespace() {
    let turn = ConversationTurn(
        role: .user,
        blocks: [.makeText("Open /tmp/a  b.swift now")]
    )
    let session = ChatSession(title: "Files", turns: [turn])
    let project = Project(path: "/tmp/project", name: "Project", sessions: [session])

    let hits = SessionSearch.search(query: "a  b", projects: [project])

    #expect(hits.contains { $0.kind == .user })
    #expect(SessionSearch.normalizedQuery("  a  b  ") == "a b")
}
