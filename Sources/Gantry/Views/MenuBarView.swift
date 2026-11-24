import AppKit
import SwiftUI
import GantryCore

/// The menu bar label. It stays at idle when nothing is happening, shows a
/// spinner state while Claude works, and surfaces the number of requests that
/// need the person.
struct MenuBarStatusLabel: View {
    var app: AppModel
    var onReady: () -> Void = {}

    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Group {
            if app.pendingPermissionCount > 0 {
                Label("\(app.pendingPermissionCount)", systemImage: "exclamationmark.bubble.fill")
            } else if app.runningSessionCount > 0 {
                Label("\(app.runningSessionCount)", systemImage: "hourglass")
            } else if app.finishedSessionCount > 0 {
                Label("\(app.finishedSessionCount)", systemImage: "checkmark.circle.fill")
            } else {
                Image(systemName: "sparkles")
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .gantryShowMainWindow)) { _ in
            openMainWindow(openWindow)
        }
        .task {
            onReady()
        }
        .accessibilityLabel(accessibilityLabel)
    }

    private var accessibilityLabel: String {
        "Gantry, \(app.pendingPermissionCount) waiting, "
            + "\(app.runningSessionCount) running, "
            + "\(app.finishedSessionCount) finished"
    }
}

/// The menu bar popover. It lists pending permissions and questions, running
/// sessions, and recently finished sessions, and offers the same allow, deny,
/// and answer paths as the main window.
struct MenuBarView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.openWindow) private var openWindow
    @Environment(\.openSettings) private var openSettings
    @Environment(\.dismiss) private var dismiss

    private var pending: [PendingPermissionItem] {
        app.pendingPermissionItems
    }

    private var active: [SessionActivityItem] {
        app.activeSessionItems
    }

    private var finished: [SessionActivityItem] {
        app.finishedSessionItems
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Hairline()
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    if pending.isEmpty, active.isEmpty, finished.isEmpty {
                        idleState
                    }
                    if !pending.isEmpty {
                        pendingSection
                    }
                    if !active.isEmpty {
                        activeSection
                    }
                    if !finished.isEmpty {
                        finishedSection
                    }
                }
                .padding(12)
            }
            .frame(minHeight: 90, maxHeight: 460)
            Hairline()
            footer
        }
        .frame(width: 360)
    }

    // MARK: - Header and footer

    private var header: some View {
        HStack(spacing: 8) {
            GantryLockup(compact: true)
            Spacer()
            statusBadge
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    @ViewBuilder
    private var statusBadge: some View {
        if pending.count > 0 {
            QuietBadge(
                text: pending.count == 1 ? "Needs you" : "\(pending.count) need you",
                color: Palette.warning
            )
        } else if active.count > 0 {
            QuietBadge(
                text: active.count == 1 ? "Working" : "\(active.count) working",
                color: Palette.accent
            )
        } else if finished.count > 0 {
            QuietBadge(
                text: finished.count == 1 ? "Finished" : "\(finished.count) finished",
                color: Palette.success
            )
        } else {
            QuietBadge(text: "Idle", color: Palette.tertiaryInk)
        }
    }

    private var footer: some View {
        HStack(spacing: 8) {
            Button("Open Gantry") {
                showMainWindow()
            }
            .buttonStyle(.borderedProminent)
            .tint(Palette.accent)
            .controlSize(.small)

            Spacer()

            Button("Settings…") {
                NSApp.unhide(nil)
                NSApp.activate(ignoringOtherApps: true)
                openSettings()
                dismiss()
            }
            .buttonStyle(.bordered)
            .controlSize(.small)

            Button("Quit Gantry") {
                NSApp.terminate(nil)
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    // MARK: - Sections

    private var pendingSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionHeader("Needs you", count: pending.count, tint: Palette.warning)
            ForEach(pending) { item in
                MenuBarRequestCard(
                    item: item,
                    onPermission: { action in
                        app.respond(
                            to: item.request,
                            action: action,
                            sessionID: item.session.id
                        )
                    },
                    onAnswer: { answers in
                        app.answer(
                            item.request,
                            with: answers,
                            sessionID: item.session.id
                        )
                    },
                    onDeclineQuestion: {
                        app.declineQuestion(item.request, sessionID: item.session.id)
                    },
                    onOpen: {
                        show(sessionID: item.session.id)
                    }
                )
            }
        }
    }

    private var activeSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionHeader("Working", count: active.count, tint: Palette.accent)
            activityGroup(active, finished: false)
        }
    }

    private var finishedSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionHeader("Finished", count: finished.count, tint: Palette.success)
            activityGroup(finished, finished: true)
        }
    }

    private func activityGroup(
        _ items: [SessionActivityItem],
        finished: Bool
    ) -> some View {
        VStack(spacing: 0) {
            ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                activityRow(item, finished: finished)
                if index < items.count - 1 {
                    Hairline()
                }
            }
        }
        .background(
            RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
                .fill(Palette.ink.opacity(0.04))
                .overlay(
                    RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
                        .strokeBorder(Palette.line, lineWidth: 1)
                )
        )
        .clipShape(RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
    }

    private func activityRow(
        _ item: SessionActivityItem,
        finished: Bool
    ) -> some View {
        Button {
            show(sessionID: item.session.id)
        } label: {
            HStack(spacing: 8) {
                if finished {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(Palette.success)
                        .frame(width: 12)
                } else {
                    LiveIndicator(color: Palette.accent, size: 10)
                        .frame(width: 12)
                }

                VStack(alignment: .leading, spacing: 1) {
                    Text(item.session.title.isEmpty ? "New session" : item.session.title)
                        .font(Typo.captionMedium)
                        .foregroundStyle(Palette.ink)
                        .lineLimit(1)
                    Text(statusText(for: item, finished: finished))
                        .font(Typo.micro)
                        .foregroundStyle(Palette.tertiaryInk)
                        .lineLimit(1)
                }

                Spacer(minLength: 8)

                Text(item.project.name)
                    .font(Typo.micro)
                    .foregroundStyle(Palette.tertiaryInk)
                    .lineLimit(1)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("Show this session in Gantry")
    }

    private func statusText(for item: SessionActivityItem, finished: Bool) -> String {
        if finished {
            return "Finished \(Format.relativeTime(item.session.updatedAt))"
        }
        if item.activity.isStopping { return "Stopping" }
        return item.activity.statusText ?? "Working"
    }

    private var idleState: some View {
        VStack(spacing: 6) {
            Image(systemName: "sparkles")
                .font(.system(size: 18, weight: .regular))
                .foregroundStyle(Palette.tertiaryInk)
            Text("All quiet")
                .font(Typo.captionMedium)
                .foregroundStyle(Palette.ink)
            Text("Close the window any time. Gantry keeps working and shows up here.")
                .font(Typo.micro)
                .foregroundStyle(Palette.tertiaryInk)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 280)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 14)
    }

    private func sectionHeader(_ title: String, count: Int, tint: Color) -> some View {
        HStack(spacing: 6) {
            Text(title)
                .font(Typo.micro)
                .foregroundStyle(tint)
            Text("\(count)")
                .font(Typo.micro)
                .monospacedDigit()
                .foregroundStyle(Palette.tertiaryInk)
            Spacer()
        }
    }

    // MARK: - Actions

    private func showMainWindow() {
        if let sessionID = app.selectedSessionID {
            app.activities[sessionID]?.unread = false
        }
        openMainWindow(openWindow)
        dismiss()
    }

    private func show(sessionID: UUID) {
        app.select(sessionID: sessionID)
        showMainWindow()
    }
}

// MARK: - Request card

private struct MenuBarRequestCard: View {
    var item: PendingPermissionItem
    var onPermission: (PermissionAction) -> Void
    var onAnswer: ([String: String]) -> Void
    var onDeclineQuestion: () -> Void
    var onOpen: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            header

            if let questionnaire = item.request.questionnaire {
                MenuBarQuestionForm(
                    questionnaire: questionnaire,
                    onSubmit: onAnswer,
                    onDecline: onDeclineQuestion
                )
            } else {
                permissionContent
            }
        }
        .padding(11)
        .background(
            RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
                .fill(Palette.ink.opacity(0.04))
                .overlay(
                    RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
                        .strokeBorder(Palette.line, lineWidth: 1)
                )
        )
    }

    private var header: some View {
        HStack(spacing: 6) {
            Image(systemName: "folder")
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(Palette.tertiaryInk)

            Button(action: onOpen) {
                Text(item.session.title.isEmpty ? "New session" : item.session.title)
                    .font(Typo.captionMedium)
                    .foregroundStyle(Palette.ink)
                    .lineLimit(1)
            }
            .buttonStyle(.plain)
            .help("Show this session in Gantry")

            Spacer(minLength: 8)

            Text(item.project.name)
                .font(Typo.micro)
                .foregroundStyle(Palette.tertiaryInk)
                .lineLimit(1)
        }
    }

    private var permissionContent: some View {
        let presentation = PermissionPresentation.make(
            from: item.request,
            projectPath: item.project.path
        )
        return VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: presentation.icon)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(presentation.tint)
                Text(presentation.title)
                    .font(Typo.caption)
                    .foregroundStyle(Palette.ink)
                Spacer(minLength: 6)
                Text(item.request.displayName ?? Format.prettyToolName(item.request.toolName))
                    .font(Typo.micro)
                    .foregroundStyle(Palette.tertiaryInk)
                    .lineLimit(1)
            }

            if let path = presentation.pathPreview {
                Text(path)
                    .font(Typo.monoSmall)
                    .foregroundStyle(Palette.secondaryInk)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            if let command = presentation.commandPreview, !command.isEmpty {
                Text(command)
                    .font(Typo.monoSmall)
                    .foregroundStyle(Palette.codePlain)
                    .textSelection(.enabled)
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack(spacing: 6) {
                Button("Deny") {
                    onPermission(.deny)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)

                Spacer(minLength: 4)

                if item.request.alwaysAllowSuggestion != nil {
                    Button(item.request.alwaysAllowLabel) {
                        onPermission(.allowAlways)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .lineLimit(1)
                    .help(item.request.alwaysAllowLabel)
                }

                Button("Allow once") {
                    onPermission(.allowOnce)
                }
                .buttonStyle(.borderedProminent)
                .tint(Palette.accent)
                .controlSize(.small)
            }
        }
    }
}

// MARK: - Question form

private struct MenuBarQuestionForm: View {
    var questionnaire: ClaudeQuestionnaire
    var onSubmit: ([String: String]) -> Void
    var onDecline: () -> Void

    @State private var answers: [String: ClaudeQuestionAnswer] = [:]

    private var resolvedAnswers: [String: String] {
        var result: [String: String] = [:]
        for question in questionnaire.questions {
            guard let value = answers[question.answerKey]?.resolvedValue(for: question) else {
                continue
            }
            result[question.answerKey] = value
        }
        return result
    }

    private var hasInvalidAnswer: Bool {
        questionnaire.questions.contains { question in
            guard let answer = answers[question.answerKey],
                  answer.hasInput(for: question) else {
                return false
            }
            return answer.resolvedValue(for: question) == nil
        }
    }

    private var canSubmit: Bool {
        !resolvedAnswers.isEmpty && !hasInvalidAnswer
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let title = questionnaire.title, !title.isEmpty {
                Text(title)
                    .font(Typo.micro)
                    .foregroundStyle(Palette.tertiaryInk)
                    .lineLimit(2)
            }

            ForEach(Array(questionnaire.questions.enumerated()), id: \.offset) { _, question in
                questionBlock(question)
            }

            HStack(spacing: 6) {
                Button("Decline") {
                    onDecline()
                }
                .buttonStyle(.bordered)
                .controlSize(.small)

                Spacer()

                Button("Send answer") {
                    onSubmit(resolvedAnswers)
                }
                .buttonStyle(.borderedProminent)
                .tint(Palette.accent)
                .controlSize(.small)
                .disabled(!canSubmit)
            }
        }
    }

    private func questionBlock(_ question: ClaudeQuestion) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            if let header = question.header, !header.isEmpty {
                Text(header)
                    .font(Typo.micro)
                    .foregroundStyle(Palette.tertiaryInk)
            }

            Text(question.question)
                .font(Typo.caption)
                .foregroundStyle(Palette.ink)
                .fixedSize(horizontal: false, vertical: true)

            if question.kind == .choice {
                ForEach(question.options) { option in
                    optionRow(option, question: question)
                }
                TextField("Other answer", text: customTextBinding(question))
                    .textFieldStyle(.roundedBorder)
                    .controlSize(.small)
                    .font(Typo.caption)
                    .onSubmit { submitIfPossible() }
            } else if question.kind == .text {
                TextField(
                    question.placeholder ?? "Type an answer",
                    text: customTextBinding(question)
                )
                .textFieldStyle(.roundedBorder)
                .controlSize(.small)
                .font(Typo.caption)
                .onSubmit { submitIfPossible() }
            } else {
                TextField(
                    question.placeholder ?? "Enter a number",
                    text: numberBinding(question)
                )
                .textFieldStyle(.roundedBorder)
                .controlSize(.small)
                .font(Typo.caption)
                .onSubmit { submitIfPossible() }
                if let hint = rangeHint(question) {
                    Text(hint)
                        .font(Typo.micro)
                        .foregroundStyle(Palette.tertiaryInk)
                }
            }
        }
    }

    private func optionRow(
        _ option: ClaudeQuestion.Option,
        question: ClaudeQuestion
    ) -> some View {
        let isSelected = answers[question.answerKey]?.selectedOptions.contains(option.label) == true
        return Button {
            select(option, in: question)
        } label: {
            HStack(spacing: 6) {
                Image(systemName: selectionSymbol(for: question, selected: isSelected))
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(isSelected ? Palette.accent : Palette.tertiaryInk)
                Text(option.label)
                    .font(Typo.caption)
                    .foregroundStyle(Palette.ink)
                    .lineLimit(2)
                Spacer(minLength: 0)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(option.description ?? option.label)
    }

    private func selectionSymbol(for question: ClaudeQuestion, selected: Bool) -> String {
        if question.multiSelect {
            return selected ? "checkmark.square.fill" : "square"
        }
        return selected ? "largecircle.fill.circle" : "circle"
    }

    private func select(_ option: ClaudeQuestion.Option, in question: ClaudeQuestion) {
        var answer = answers[question.answerKey] ?? ClaudeQuestionAnswer()
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
        answers[question.answerKey] = answer
    }

    private func customTextBinding(_ question: ClaudeQuestion) -> Binding<String> {
        Binding(
            get: { answers[question.answerKey]?.customText ?? "" },
            set: { value in
                var answer = answers[question.answerKey] ?? ClaudeQuestionAnswer()
                answer.customText = value
                if question.kind == .choice {
                    answer.selectedOptions = []
                }
                answers[question.answerKey] = answer
            }
        )
    }

    private func numberBinding(_ question: ClaudeQuestion) -> Binding<String> {
        Binding(
            get: { answers[question.answerKey]?.numberText ?? "" },
            set: { value in
                var answer = answers[question.answerKey] ?? ClaudeQuestionAnswer()
                answer.numberText = value
                answers[question.answerKey] = answer
            }
        )
    }

    private func submitIfPossible() {
        guard canSubmit else { return }
        onSubmit(resolvedAnswers)
    }

    private func rangeHint(_ question: ClaudeQuestion) -> String? {
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

// MARK: - Window helpers

@MainActor
private func openMainWindow(_ openWindow: OpenWindowAction) {
    NSApp.unhide(nil)
    NSApp.activate(ignoringOtherApps: true)
    openWindow(id: "main")
    DispatchQueue.main.async {
        guard let window = NSApp.windows.first(where: { $0.title == "Gantry" }) else {
            return
        }
        if window.isMiniaturized {
            window.deminiaturize(nil)
        }
        window.makeKeyAndOrderFront(nil)
    }
}
