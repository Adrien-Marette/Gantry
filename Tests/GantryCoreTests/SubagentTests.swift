import Testing
@testable import GantryCore

@Test func subagentToolsFilterTaskAndAgent() {
    let task = ToolActivity(
        id: "tool_task",
        name: "Task",
        input: .object([
            "subagent_type": .string("general-purpose"),
            "description": .string("Do the thing"),
            "prompt": .string("A long prompt")
        ]),
        status: .running
    )
    let agent = ToolActivity(
        id: "tool_agent",
        name: "Agent",
        input: .object(["prompt": .string("Plan the work")]),
        status: .completed
    )
    let bash = ToolActivity(id: "tool_bash", name: "Bash", status: .completed)
    let session = ChatSession(turns: [
        ConversationTurn(role: .assistant, blocks: [
            .makeTool(task),
            .makeTool(bash),
            .makeTool(agent)
        ])
    ])

    #expect(session.subagentTools.map(\.id) == ["tool_task", "tool_agent"])
    #expect(task.subagentTypeTitle == "General Purpose")
    #expect(task.subagentDescription == "Do the thing")
    #expect(agent.subagentType == nil)
    #expect(agent.subagentTypeTitle == "Sub-agent")
    #expect(agent.subagentDescription == "Plan the work")
    #expect(!task.isBackgroundSubagent)
}

@Test func detectsBackgroundSubagentResults() {
    let background = ToolActivity(
        id: "tool_bg",
        name: "Agent",
        input: .object(["run_in_background": .bool(true)]),
        status: .completed
    )
    #expect(background.isBackgroundSubagent)

    let reported = ToolActivity(
        id: "tool_bg2",
        name: "Agent",
        status: .completed,
        resultText: "task-abc123"
    )
    #expect(reported.isBackgroundSubagent)
}
