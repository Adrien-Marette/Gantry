import Foundation
import Testing
@testable import GantryCore

@Test func parsesAskUserQuestionInput() throws {
    let input: JSONValue = .object([
        "title": .string("Before I build"),
        "questions": .array([
            .object([
                "question": .string("Which library should we use?"),
                "header": .string("Library"),
                "multiSelect": .bool(true),
                "options": .array([
                    .object([
                        "label": .string("Swift Testing"),
                        "description": .string("Modern and concise"),
                        "preview": .object(["markdown": .string("**swift-testing**")])
                    ]),
                    .object(["label": .string("XCTest")])
                ])
            ]),
            .object([
                "question": .string("How many files?"),
                "kind": .string("number"),
                "min": .number(1),
                "max": .number(10)
            ]),
            .object([
                "question": .string("Anything else?"),
                "kind": .string("text"),
                "placeholder": .string("Notes")
            ])
        ])
    ])

    let questionnaire = try #require(ClaudeQuestionnaire.parse(input: input))
    #expect(questionnaire.title == "Before I build")
    #expect(questionnaire.questions.count == 3)

    let first = questionnaire.questions[0]
    #expect(first.header == "Library")
    #expect(first.kind == .choice)
    #expect(first.multiSelect)
    #expect(first.options.map(\.label) == ["Swift Testing", "XCTest"])
    #expect(first.options.first?.description == "Modern and concise")
    #expect(first.options.first?.preview == "**swift-testing**")

    let second = questionnaire.questions[1]
    #expect(second.kind == .number)
    #expect(second.minimum == 1)
    #expect(second.maximum == 10)
    #expect(second.multiSelect == false)

    let third = questionnaire.questions[2]
    #expect(third.kind == .text)
    #expect(third.placeholder == "Notes")
}

@Test func rejectsQuestionnaireWithoutUsableQuestions() {
    #expect(ClaudeQuestionnaire.parse(input: .object([:])) == nil)
    #expect(ClaudeQuestionnaire.parse(input: .object(["questions": .array([])])) == nil)
    #expect(ClaudeQuestionnaire.parse(input: .object([
        "questions": .array([.object(["header": .string("Missing text")])])
    ])) == nil)
}

@Test func parsesAskUserQuestionPermissionRequest() throws {
    let line = """
    {"type":"control_request","request_id":"req_q","request":{"subtype":"can_use_tool","tool_name":"AskUserQuestion","input":{"questions":[{"question":"Ship it?","header":"Ship","options":[{"label":"Yes"},{"label":"No"}]}]},"tool_use_id":"tool_q"}}
    """
    let events = ClaudeStreamParser.parse(line: line)
    guard case .permissionRequest(let request) = events.first else {
        Issue.record("Expected a permission request")
        return
    }
    #expect(request.toolName == "AskUserQuestion")
    let questionnaire = try #require(request.questionnaire)
    #expect(questionnaire.questions.count == 1)
    #expect(questionnaire.questions.first?.question == "Ship it?")
    #expect(request.questionnaire != nil)
}

@Test func onlyAskUserQuestionRequestsCarryQuestionnaires() {
    let request = ClaudePermissionRequest(
        requestID: "req_1",
        toolName: "Bash",
        input: .object(["questions": .array([])])
    )
    #expect(request.questionnaire == nil)
}

@Test func singleChoiceAnswerUsesOptionLabel() {
    let question = ClaudeQuestion(
        question: "Pick one",
        options: [.init(label: "A"), .init(label: "B")]
    )
    var answer = ClaudeQuestionAnswer()
    answer.selectedOptions = ["B"]
    #expect(answer.hasInput(for: question))
    #expect(answer.resolvedValue(for: question) == "B")
    #expect(answer.validationMessage(for: question) == nil)
}

@Test func freeTextOverridesChoiceSelection() {
    let question = ClaudeQuestion(
        question: "Pick one",
        options: [.init(label: "A")]
    )
    let answer = ClaudeQuestionAnswer(selectedOptions: ["A"], customText: "  Something else  ")
    #expect(answer.resolvedValue(for: question) == "Something else")
}

@Test func multiSelectAnswerJoinsInOptionOrderAndQuotesCommas() {
    let question = ClaudeQuestion(
        question: "Features",
        options: [
            .init(label: "Plain"),
            .init(label: "A, B"),
            .init(label: "A,B"),
            .init(label: "Quote \"x\"")
        ],
        multiSelect: true
    )
    let answer = ClaudeQuestionAnswer(selectedOptions: ["Quote \"x\"", "A, B", "A,B", "Plain"])
    #expect(
        answer.resolvedValue(for: question)
            == "Plain, \"A, B\", \"A,B\", \"Quote \\\"x\\\"\""
    )
}

@Test func textAnswerTrimsWhitespace() {
    let question = ClaudeQuestion(question: "Notes", kind: .text)
    #expect(ClaudeQuestionAnswer(customText: "   ").resolvedValue(for: question) == nil)
    #expect(ClaudeQuestionAnswer(customText: "  Keep this  ").resolvedValue(for: question) == "Keep this")
}

@Test func numberAnswerValidatesRange() {
    let question = ClaudeQuestion(question: "Count", kind: .number, minimum: 1, maximum: 10)
    #expect(ClaudeQuestionAnswer(numberText: "5").resolvedValue(for: question) == "5")
    #expect(ClaudeQuestionAnswer(numberText: "0").resolvedValue(for: question) == nil)
    #expect(ClaudeQuestionAnswer(numberText: "11").resolvedValue(for: question) == nil)
    #expect(ClaudeQuestionAnswer(numberText: "nope").resolvedValue(for: question) == nil)
    #expect(ClaudeQuestionAnswer(numberText: "nan").resolvedValue(for: question) == nil)
    #expect(ClaudeQuestionAnswer(numberText: "inf").resolvedValue(for: question) == nil)
    #expect(ClaudeQuestionAnswer(numberText: "0x10").resolvedValue(for: question) == nil)
    #expect(ClaudeQuestionAnswer(numberText: "nope").validationMessage(for: question) == "Enter a number.")
    #expect(ClaudeQuestionAnswer(numberText: "nan").validationMessage(for: question) == "Enter a number.")
    #expect(ClaudeQuestionAnswer(numberText: "0").validationMessage(for: question) == "Enter 1 or more.")
    #expect(ClaudeQuestionAnswer(numberText: "11").validationMessage(for: question) == "Enter 10 or less.")

    let open = ClaudeQuestion(question: "Count", kind: .number)
    #expect(ClaudeQuestionAnswer(numberText: "1e3").resolvedValue(for: open) == "1e3")
}

@Test func answerKeyPreservesTheQuestionClaudeSent() throws {
    let input: JSONValue = .object([
        "questions": .array([
            .object(["question": .string("Pick one \n")])
        ])
    ])
    let questionnaire = try #require(ClaudeQuestionnaire.parse(input: input))
    let question = try #require(questionnaire.questions.first)
    #expect(question.question == "Pick one")
    #expect(question.answerKey == "Pick one \n")
}

@Test func answerReplyCarriesAnswersInUpdatedInput() throws {
    let input: JSONValue = .object([
        "questions": .array([
            .object([
                "question": .string("Pick one"),
                "options": .array([
                    .object(["label": .string("A")]),
                    .object(["label": .string("B")])
                ])
            ])
        ])
    ])
    let request = ClaudePermissionRequest(
        requestID: "req_q",
        toolName: "AskUserQuestion",
        input: input,
        toolUseID: "tool_q"
    )

    let data = try ClaudeWire.permissionResponse(
        requestID: request.requestID,
        reply: .answer(request, answers: ["Pick one": "B"])
    )
    let json = try #require(
        try JSONSerialization.jsonObject(with: data) as? [String: Any]
    )
    let response = try #require(json["response"] as? [String: Any])
    #expect(response["request_id"] as? String == "req_q")
    #expect(response["subtype"] as? String == "success")

    let payload = try #require(response["response"] as? [String: Any])
    #expect(payload["behavior"] as? String == "allow")
    #expect(payload["toolUseID"] as? String == "tool_q")
    #expect(payload["updatedPermissions"] == nil)

    let updatedInput = try #require(payload["updatedInput"] as? [String: Any])
    let answers = try #require(updatedInput["answers"] as? [String: String])
    #expect(answers == ["Pick one": "B"])
    let questions = try #require(updatedInput["questions"] as? [[String: Any]])
    #expect(questions.count == 1)
    #expect(questions.first?["question"] as? String == "Pick one")
}
