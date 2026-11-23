import Foundation

/// The structured questions carried by an `AskUserQuestion` permission
/// request. Claude Code asks through `can_use_tool`; answering is an `allow`
/// whose `updatedInput` adds an `answers` map keyed by question text.
public struct ClaudeQuestionnaire: Hashable, Sendable {
    public var title: String?
    public var questions: [ClaudeQuestion]

    public init(title: String? = nil, questions: [ClaudeQuestion]) {
        self.title = title
        self.questions = questions
    }

    /// Parses the tool input of an `AskUserQuestion` request. Returns `nil`
    /// when the payload is not a usable questionnaire, so callers can fall
    /// back to the regular permission card.
    public static func parse(input: JSONValue) -> ClaudeQuestionnaire? {
        guard let object = input.objectValue,
              let rawQuestions = object["questions"]?.arrayValue else { return nil }
        let questions = rawQuestions.compactMap(question(from:))
        guard !questions.isEmpty else { return nil }
        return ClaudeQuestionnaire(
            title: nonEmpty(object["title"]?.stringValue),
            questions: questions
        )
    }

    /// Joins selected option labels the way Claude Code's dialog does: labels
    /// that contain a comma or quote are JSON-quoted so the comma-separated
    /// answer can be split again.
    public static func joinedSelection(_ labels: [String]) -> String {
        labels.map(quotedLabel).joined(separator: ", ")
    }

    private static func quotedLabel(_ label: String) -> String {
        guard label.contains(",") || label.contains("\"") else { return label }
        guard let data = try? JSONSerialization.data(
            withJSONObject: [label],
            options: [.withoutEscapingSlashes]
        ), let array = String(data: data, encoding: .utf8) else {
            return label
        }
        return String(array.dropFirst().dropLast())
    }

    private static func question(from value: JSONValue) -> ClaudeQuestion? {
        guard let object = value.objectValue,
              let rawQuestion = object["question"]?.stringValue,
              let text = nonEmpty(rawQuestion) else { return nil }

        let kind = ClaudeQuestion.Kind(wireValue: object["kind"]?.stringValue)
        let options = (object["options"]?.arrayValue ?? []).compactMap { value -> ClaudeQuestion.Option? in
            guard let option = value.objectValue,
                  let label = nonEmpty(option["label"]?.stringValue) else { return nil }
            return ClaudeQuestion.Option(
                label: label,
                description: nonEmpty(option["description"]?.stringValue),
                preview: preview(from: option["preview"])
            )
        }

        return ClaudeQuestion(
            question: text,
            answerKey: rawQuestion,
            header: nonEmpty(object["header"]?.stringValue),
            kind: kind,
            options: options,
            multiSelect: kind == .choice && object["multiSelect"]?.boolValue == true,
            placeholder: nonEmpty(object["placeholder"]?.stringValue),
            minimum: object["min"]?.numberValue,
            maximum: object["max"]?.numberValue
        )
    }

    private static func preview(from value: JSONValue?) -> String? {
        guard let value else { return nil }
        if let string = nonEmpty(value.stringValue) { return string }
        guard let object = value.objectValue else { return nil }
        return nonEmpty(object["markdown"]?.stringValue)
            ?? nonEmpty(object["text"]?.stringValue)
            ?? nonEmpty(object["content"]?.stringValue)
    }

    private static func nonEmpty(_ string: String?) -> String? {
        guard let trimmed = string?.trimmingCharacters(in: .whitespacesAndNewlines),
              !trimmed.isEmpty else { return nil }
        return trimmed
    }
}

public struct ClaudeQuestion: Hashable, Sendable, Identifiable {
    public enum Kind: String, Hashable, Sendable {
        case choice
        case text
        case number

        init(wireValue: String?) {
            switch wireValue {
            case "text": self = .text
            case "number": self = .number
            default: self = .choice
            }
        }
    }

    public struct Option: Hashable, Sendable, Identifiable {
        public var label: String
        public var description: String?
        public var preview: String?

        public var id: String { label }

        public init(label: String, description: String? = nil, preview: String? = nil) {
            self.label = label
            self.description = description
            self.preview = preview
        }
    }

    /// The display text, with surrounding whitespace removed.
    public var question: String
    /// The exact text Claude Code sent. The answers map is keyed by this, not
    /// the trimmed display text.
    public var answerKey: String
    public var header: String?
    public var kind: Kind
    public var options: [Option]
    public var multiSelect: Bool
    public var placeholder: String?
    public var minimum: Double?
    public var maximum: Double?

    public var id: String { question }

    public init(
        question: String,
        answerKey: String? = nil,
        header: String? = nil,
        kind: Kind = .choice,
        options: [Option] = [],
        multiSelect: Bool = false,
        placeholder: String? = nil,
        minimum: Double? = nil,
        maximum: Double? = nil
    ) {
        self.question = question
        self.answerKey = answerKey ?? question
        self.header = header
        self.kind = kind
        self.options = options
        self.multiSelect = multiSelect
        self.placeholder = placeholder
        self.minimum = minimum
        self.maximum = maximum
    }
}

/// The in-progress answer to one question. Choice answers can use options,
/// free text, or both conceptually, but typed text wins so a user can always
/// override a selection.
public struct ClaudeQuestionAnswer: Hashable, Sendable {
    public var selectedOptions: Set<String>
    public var customText: String
    public var numberText: String

    public init(
        selectedOptions: Set<String> = [],
        customText: String = "",
        numberText: String = ""
    ) {
        self.selectedOptions = selectedOptions
        self.customText = customText
        self.numberText = numberText
    }

    public func hasInput(for question: ClaudeQuestion) -> Bool {
        switch question.kind {
        case .choice:
            return !selectedOptions.isEmpty || !trimmed(customText).isEmpty
        case .text:
            return !trimmed(customText).isEmpty
        case .number:
            return !trimmed(numberText).isEmpty
        }
    }

    /// The wire value for this question, or `nil` when it is unanswered or
    /// invalid.
    public func resolvedValue(for question: ClaudeQuestion) -> String? {
        switch question.kind {
        case .choice:
            let other = trimmed(customText)
            if !other.isEmpty { return other }
            let labels = question.options.map(\.label).filter(selectedOptions.contains)
            guard !labels.isEmpty else { return nil }
            return question.multiSelect ? ClaudeQuestionnaire.joinedSelection(labels) : labels.first
        case .text:
            let text = trimmed(customText)
            return text.isEmpty ? nil : text
        case .number:
            guard let value = numericValue else { return nil }
            if let minimum = question.minimum, value < minimum { return nil }
            if let maximum = question.maximum, value > maximum { return nil }
            return trimmed(numberText)
        }
    }

    /// A short explanation when the field has input but cannot be submitted.
    public func validationMessage(for question: ClaudeQuestion) -> String? {
        guard question.kind == .number, hasInput(for: question) else { return nil }
        guard let value = numericValue else { return "Enter a number." }
        if let minimum = question.minimum, value < minimum {
            return "Enter \(Self.format(minimum)) or more."
        }
        if let maximum = question.maximum, value > maximum {
            return "Enter \(Self.format(maximum)) or less."
        }
        return nil
    }

    private static let decimalNumberPattern =
        #"^[+-]?(?:\d+(?:\.\d*)?|\.\d+)(?:[eE][+-]?\d+)?$"#

    private var numericValue: Double? {
        let text = trimmed(numberText)
        guard text.range(of: Self.decimalNumberPattern, options: .regularExpression) != nil,
              let value = Double(text),
              value.isFinite else { return nil }
        return value
    }

    private func trimmed(_ string: String) -> String {
        string.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func format(_ value: Double) -> String {
        if value.rounded() == value, abs(value) < 1e15 {
            return String(Int(value))
        }
        return String(value)
    }
}

public extension ClaudePermissionRequest {
    /// The questionnaire carried by an `AskUserQuestion` request.
    var questionnaire: ClaudeQuestionnaire? {
        guard toolName == "AskUserQuestion" else { return nil }
        return ClaudeQuestionnaire.parse(input: input)
    }
}
