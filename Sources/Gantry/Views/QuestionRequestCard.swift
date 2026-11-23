import SwiftUI
import GantryCore

/// The answer sheet for Claude Code's `AskUserQuestion` tool. It replaces the
/// generic permission card whenever the pending tool call carries questions.
struct QuestionRequestCard: View {
    var request: ClaudePermissionRequest
    var questionnaire: ClaudeQuestionnaire
    var queuedCount: Int
    var glassNamespace: Namespace.ID?
    var onSubmit: ([String: String]) -> Void
    var onDecline: () -> Void

    @State private var answers: [Int: ClaudeQuestionAnswer] = [:]
    @State private var currentIndex = 0
    @FocusState private var focusedField: Field?
    @Namespace private var ownGlassNamespace

    private enum Field: Hashable {
        case other(Int)
        case text(Int)
        case number(Int)
    }

    private var resolvedAnswers: [String: String] {
        var result: [String: String] = [:]
        for (index, question) in questionnaire.questions.enumerated() {
            guard let value = answers[index]?.resolvedValue(for: question) else { continue }
            result[question.answerKey] = value
        }
        return result
    }

    private var hasInvalidAnswer: Bool {
        questionnaire.questions.enumerated().contains { index, question in
            hasInvalidAnswer(at: index, question: question)
        }
    }

    private func hasInvalidAnswer(at index: Int, question: ClaudeQuestion) -> Bool {
        guard let answer = answers[index], answer.hasInput(for: question) else { return false }
        return answer.resolvedValue(for: question) == nil
    }

    private var canSubmit: Bool {
        !resolvedAnswers.isEmpty && !hasInvalidAnswer
    }

    private var answeredCount: Int {
        questionnaire.questions.enumerated().count { index, question in
            answers[index]?.resolvedValue(for: question) != nil
        }
    }

    private var currentQuestion: ClaudeQuestion {
        questionnaire.questions[min(currentIndex, questionnaire.questions.count - 1)]
    }

    private var isLastQuestion: Bool {
        currentIndex >= questionnaire.questions.count - 1
    }

    private var usesHeaderChips: Bool {
        questionnaire.questions.allSatisfy { $0.header != nil }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            if questionnaire.questions.count > 1 {
                navigator
            }
            questionBlock(currentQuestion, index: currentIndex)
            footer
        }
        .padding(16)
        .glassPanel(radius: 20)
        .glassEffectID("question", in: glassNamespace ?? ownGlassNamespace)
    }

    // MARK: - Header

    private var header: some View {
        HStack(alignment: .top, spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Palette.info.opacity(0.12))
                Image(systemName: "bubble.left.and.bubble.right.fill")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(Palette.info)
            }
            .frame(width: 32, height: 32)

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 8) {
                    Text("Claude has a question")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(Palette.ink)
                    Text(request.displayName ?? "AskUserQuestion")
                        .font(.system(size: 11, weight: .regular, design: .monospaced))
                        .foregroundStyle(Palette.tertiaryInk)
                }

                Text(questionnaire.title ?? "Answer below and Claude will keep going.")
                    .font(Typo.micro)
                    .foregroundStyle(Palette.tertiaryInk)
                    .lineLimit(2)
            }

            Spacer(minLength: 4)

            if queuedCount > 0 {
                Text("\(queuedCount) more")
                    .font(Typo.micro)
                    .monospacedDigit()
                    .foregroundStyle(Palette.tertiaryInk)
            }
        }
    }

    // MARK: - Questions

    private var navigator: some View {
        HStack(spacing: 6) {
            ForEach(questionnaire.questions.indices, id: \.self) { index in
                stepChip(index: index)
            }
            Spacer(minLength: 8)
            Text("\(currentIndex + 1) of \(questionnaire.questions.count)")
                .font(Typo.micro)
                .monospacedDigit()
                .foregroundStyle(Palette.tertiaryInk)
        }
    }

    private func stepChip(index: Int) -> some View {
        let question = questionnaire.questions[index]
        let isCurrent = index == currentIndex
        let isAnswered = answers[index]?.resolvedValue(for: question) != nil
        let label = usesHeaderChips ? (question.header ?? "\(index + 1)") : "\(index + 1)"
        return Button {
            goTo(index)
        } label: {
            HStack(spacing: 4) {
                if isAnswered {
                    Image(systemName: "checkmark")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(Palette.accent)
                }
                Text(label)
                    .font(Typo.micro)
                    .foregroundStyle(isCurrent ? Palette.ink : Palette.secondaryInk)
                    .lineLimit(1)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(isCurrent ? Palette.ink.opacity(0.06) : Palette.ink.opacity(0.025))
                    .overlay(
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .strokeBorder(
                                isCurrent ? Palette.accent : Palette.line,
                                lineWidth: 1
                            )
                    )
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("Question \(index + 1) of \(questionnaire.questions.count)")
        .accessibilityLabel(accessibilityLabel(for: question, index: index))
        .accessibilityAddTraits(isCurrent ? .isSelected : [])
    }

    private func accessibilityLabel(for question: ClaudeQuestion, index: Int) -> String {
        let name = question.header ?? question.question
        return "Question \(index + 1) of \(questionnaire.questions.count): \(name)"
    }

    @ViewBuilder
    private func questionBlock(_ question: ClaudeQuestion, index: Int) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                if let header = question.header {
                    Text(header)
                        .font(Typo.micro)
                        .foregroundStyle(Palette.secondaryInk)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(
                            RoundedRectangle(cornerRadius: 5, style: .continuous)
                                .fill(Palette.ink.opacity(0.05))
                        )
                }
                Text(question.question)
                    .font(Typo.bodyMedium)
                    .foregroundStyle(Palette.ink)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
            }

            switch question.kind {
            case .choice:
                VStack(spacing: 6) {
                    ForEach(question.options) { option in
                        optionRow(option, question: question, index: index)
                    }
                    otherRow(question, index: index)
                }
            case .text:
                textField(question, index: index)
            case .number:
                numberField(question, index: index)
                if let hint = rangeHint(for: question) {
                    Text(hint)
                        .font(Typo.micro)
                        .foregroundStyle(Palette.tertiaryInk)
                }
            }

            if let message = answers[index]?.validationMessage(for: question) {
                Text(message)
                    .font(Typo.micro)
                    .foregroundStyle(Palette.danger)
            }
        }
    }

    private func optionRow(
        _ option: ClaudeQuestion.Option,
        question: ClaudeQuestion,
        index: Int
    ) -> some View {
        let selected = answers[index]?.selectedOptions.contains(option.label) == true
        return Button {
            toggle(option, in: question, index: index)
        } label: {
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: selectionIcon(multiSelect: question.multiSelect, selected: selected))
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(selected ? Palette.accent : Palette.tertiaryInk)
                    .padding(.top, 1)

                VStack(alignment: .leading, spacing: 2) {
                    Text(option.label)
                        .font(Typo.captionMedium)
                        .foregroundStyle(Palette.ink)
                        .fixedSize(horizontal: false, vertical: true)
                    if let description = option.description, !description.isEmpty {
                        Text(description)
                            .font(Typo.micro)
                            .foregroundStyle(Palette.tertiaryInk)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                Spacer(minLength: 0)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(optionBackground(selected: selected))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(option.label)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private func otherRow(_ question: ClaudeQuestion, index: Int) -> some View {
        let field = Field.other(index)
        let text = customTextBinding(for: index)
        let active = !text.wrappedValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        return HStack(spacing: 8) {
            Image(systemName: "pencil.line")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(active ? Palette.accent : Palette.tertiaryInk)
            TextField("Other…", text: text)
                .textFieldStyle(.plain)
                .font(Typo.captionMedium)
                .foregroundStyle(Palette.ink)
                .focused($focusedField, equals: field)
                .onSubmit { advanceOrSubmit() }
                .accessibilityLabel("Other answer for \(question.question)")
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(optionBackground(selected: active, focused: focusedField == field))
    }

    private func textField(_ question: ClaudeQuestion, index: Int) -> some View {
        let field = Field.text(index)
        return TextField(question.placeholder ?? "Type your answer", text: customTextBinding(for: index), axis: .vertical)
            .textFieldStyle(.plain)
            .font(Typo.captionMedium)
            .foregroundStyle(Palette.ink)
            .lineLimit(1...4)
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(optionBackground(selected: false, focused: focusedField == field))
            .focused($focusedField, equals: field)
            .accessibilityLabel(question.question)
    }

    private func numberField(_ question: ClaudeQuestion, index: Int) -> some View {
        let field = Field.number(index)
        return TextField(question.placeholder ?? "Type a number", text: numberBinding(for: index))
            .textFieldStyle(.plain)
            .font(Typo.captionMedium.monospacedDigit())
            .foregroundStyle(Palette.ink)
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(optionBackground(selected: false, focused: focusedField == field))
            .focused($focusedField, equals: field)
            .onSubmit { advanceOrSubmit() }
            .accessibilityLabel(question.question)
    }

    // MARK: - Footer

    private var footer: some View {
        HStack(spacing: 8) {
            Button("Decline") {
                focusedField = nil
                onDecline()
            }
            .buttonStyle(.glass)
            .controlSize(.small)

            Spacer()

            if questionnaire.questions.count > 1 {
                Text("\(answeredCount) of \(questionnaire.questions.count) answered")
                    .font(Typo.micro)
                    .monospacedDigit()
                    .foregroundStyle(Palette.tertiaryInk)
            }

            if currentIndex > 0 {
                Button {
                    goTo(currentIndex - 1)
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 10, weight: .medium))
                        Text("Back")
                            .font(Typo.captionMedium)
                    }
                }
                .buttonStyle(.glass)
                .controlSize(.small)
                .help("Previous question")
            }

            if isLastQuestion {
                Button {
                    submitIfPossible()
                } label: {
                    HStack(spacing: 6) {
                        Text("Send answer")
                            .font(Typo.captionMedium)
                        Image(systemName: "arrow.right")
                            .font(.system(size: 10, weight: .medium))
                    }
                }
                .buttonStyle(.glassProminent)
                .tint(Palette.accent)
                .controlSize(.small)
                .disabled(!canSubmit)
            } else {
                Button {
                    goTo(currentIndex + 1)
                } label: {
                    HStack(spacing: 4) {
                        Text("Next")
                            .font(Typo.captionMedium)
                        Image(systemName: "chevron.right")
                            .font(.system(size: 10, weight: .medium))
                    }
                }
                .buttonStyle(.glass)
                .controlSize(.small)
                .help("Next question")
            }
        }
    }

    // MARK: - State

    private func selectionIcon(multiSelect: Bool, selected: Bool) -> String {
        if multiSelect {
            return selected ? "checkmark.square.fill" : "square"
        }
        return selected ? "checkmark.circle.fill" : "circle"
    }

    private func optionBackground(selected: Bool, focused: Bool = false) -> some View {
        RoundedRectangle(cornerRadius: Radius.control, style: .continuous)
            .fill(selected ? Palette.ink.opacity(0.05) : Palette.ink.opacity(0.025))
            .overlay(
                RoundedRectangle(cornerRadius: Radius.control, style: .continuous)
                    .strokeBorder(
                        focused ? Palette.accent : (selected ? Palette.accent.opacity(0.45) : Palette.line),
                        lineWidth: 1
                    )
            )
    }

    private func toggle(_ option: ClaudeQuestion.Option, in question: ClaudeQuestion, index: Int) {
        var answer = answers[index] ?? ClaudeQuestionAnswer()
        if question.multiSelect {
            if answer.selectedOptions.contains(option.label) {
                answer.selectedOptions.remove(option.label)
            } else {
                answer.selectedOptions.insert(option.label)
            }
        } else if answer.selectedOptions.contains(option.label) {
            answer.selectedOptions = []
        } else {
            answer.selectedOptions = [option.label]
        }
        answer.customText = ""
        answers[index] = answer
    }

    private func customTextBinding(for index: Int) -> Binding<String> {
        Binding(
            get: { answers[index]?.customText ?? "" },
            set: { value in
                var answer = answers[index] ?? ClaudeQuestionAnswer()
                answer.customText = value
                answer.selectedOptions = []
                answers[index] = answer
            }
        )
    }

    private func numberBinding(for index: Int) -> Binding<String> {
        Binding(
            get: { answers[index]?.numberText ?? "" },
            set: { value in
                var answer = answers[index] ?? ClaudeQuestionAnswer()
                answer.numberText = value
                answers[index] = answer
            }
        )
    }

    /// Return in a single-line field moves through the sheet. Only the last
    /// question submits, matching the Send answer button.
    private func advanceOrSubmit() {
        if isLastQuestion {
            submitIfPossible()
        } else {
            goTo(currentIndex + 1)
        }
    }

    private func submitIfPossible() {
        guard canSubmit else { return }
        focusedField = nil
        onSubmit(resolvedAnswers)
    }

    private func goTo(_ index: Int) {
        guard questionnaire.questions.indices.contains(index), index != currentIndex else { return }
        focusedField = nil
        currentIndex = index
    }

    private func rangeHint(for question: ClaudeQuestion) -> String? {
        switch (question.minimum, question.maximum) {
        case let (minimum?, maximum?):
            return "Between \(formatNumber(minimum)) and \(formatNumber(maximum))"
        case let (minimum?, nil):
            return "\(formatNumber(minimum)) or more"
        case let (nil, maximum?):
            return "\(formatNumber(maximum)) or less"
        default:
            return nil
        }
    }

    private func formatNumber(_ value: Double) -> String {
        if value.rounded() == value, abs(value) < 1e15 {
            return String(Int(value))
        }
        return String(value)
    }
}
