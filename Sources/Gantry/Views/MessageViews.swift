import AppKit
import SwiftUI
import GantryCore

// MARK: - Markdown

struct MarkdownTextView: View {
    let text: String
    @State private var blocks: [MarkdownBlock]

    init(_ text: String) {
        self.text = text
        _blocks = State(initialValue: MarkdownBlockCache.blocks(for: text))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(Array(blocks.enumerated()), id: \.offset) { _, block in
                markdownBlock(block)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .onChange(of: text) { _, newValue in
            blocks = MarkdownBlockCache.blocks(for: newValue)
        }
    }

    @ViewBuilder
    private func markdownBlock(_ block: MarkdownBlock) -> some View {
        switch block {
        case .paragraph(let text):
            MarkdownInlineText(text)

        case .heading(let level, let text):
            MarkdownInlineText(
                text,
                font: level == 1
                    ? .system(size: 21, weight: .semibold)
                    : (level == 2 ? .system(size: 17.5, weight: .semibold) : .system(size: 15.5, weight: .semibold)),
                color: Palette.ink
            )
            .padding(.top, level <= 2 ? 7 : 3)

        case .code(let language, let code, _):
            CodeBlockView(language: language, code: code)

        case .list(let ordered, let items):
            VStack(alignment: .leading, spacing: 5.5) {
                ForEach(Array(items.enumerated()), id: \.offset) { index, item in
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        listMarker(item: item, ordered: ordered, index: index)
                            .frame(width: 17, alignment: .trailing)
                        MarkdownInlineText(item.text)
                    }
                    .padding(.leading, CGFloat(min(item.depth, 4)) * 16)
                }
            }

        case .quote(let text):
            HStack(alignment: .top, spacing: 11) {
                Capsule(style: .continuous)
                    .fill(Palette.accent.opacity(0.48))
                    .frame(width: 2.5)
                MarkdownInlineText(text, color: Palette.secondaryInk)
                    .italic()
            }
            .padding(.vertical, 2)

        case .table(let headers, let alignments, let rows):
            MarkdownTable(headers: headers, alignments: alignments, rows: rows)

        case .divider:
            Hairline()
                .padding(.vertical, 4)
        }
    }

    @ViewBuilder
    private func listMarker(item: MarkdownListItem, ordered: Bool, index: Int) -> some View {
        if let checked = item.checked {
            Image(systemName: checked ? "checkmark.square.fill" : "square")
                .font(.system(size: 11, weight: .regular))
                .foregroundStyle(checked ? Palette.accent : Palette.tertiaryInk)
                .alignmentGuide(.firstTextBaseline) { $0[.bottom] - 2 }
        } else if ordered {
            Text("\(index + 1).")
                .font(.system(size: 12, weight: .medium, design: .monospaced))
                .foregroundStyle(Palette.tertiaryInk)
        } else {
            Circle()
                .fill(Palette.tertiaryInk)
                .frame(width: 3.5, height: 3.5)
                .alignmentGuide(.firstTextBaseline) { $0[.bottom] + 2 }
        }
    }
}

struct MarkdownInlineText: View {
    let text: String
    var font: Font = Typo.body
    var color: Color = Palette.ink

    init(_ text: String, font: Font = Typo.body, color: Color = Palette.ink) {
        self.text = text
        self.font = font
        self.color = color
    }

    var body: some View {
        Text(InlineMarkdown.attributed(text))
            .font(font)
            .foregroundStyle(color)
            .lineSpacing(4)
            .textSelection(.enabled)
            .tint(Palette.accent)
            .fixedSize(horizontal: false, vertical: true)
    }
}

private struct MarkdownTable: View {
    var headers: [String]
    var alignments: [MarkdownAlignment]
    var rows: [[String]]

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            Grid(alignment: .leading, horizontalSpacing: 22, verticalSpacing: 0) {
                GridRow {
                    ForEach(headers.indices, id: \.self) { index in
                        Text(InlineMarkdown.attributed(headers[index]))
                            .font(Typo.captionMedium)
                            .foregroundStyle(Palette.secondaryInk)
                            .frame(minWidth: 74, alignment: alignment(at: index))
                            .padding(.vertical, 7)
                    }
                }

                Divider()
                    .gridCellColumns(max(1, headers.count))

                ForEach(Array(rows.enumerated()), id: \.offset) { rowIndex, row in
                    GridRow {
                        ForEach(headers.indices, id: \.self) { index in
                            Text(InlineMarkdown.attributed(index < row.count ? row[index] : ""))
                                .font(Typo.caption)
                                .foregroundStyle(Palette.ink)
                                .frame(minWidth: 74, alignment: alignment(at: index))
                                .padding(.vertical, 6)
                                .textSelection(.enabled)
                        }
                    }
                    if rowIndex < rows.count - 1 {
                        Divider()
                            .gridCellColumns(max(1, headers.count))
                            .opacity(0.65)
                    }
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 3)
        }
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Palette.surface.opacity(0.45))
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .strokeBorder(Palette.line, lineWidth: 0.7)
                )
        )
    }

    private func alignment(at index: Int) -> Alignment {
        let value = alignments.indices.contains(index) ? alignments[index] : .none
        switch value {
        case .leading: return .leading
        case .center: return .center
        case .trailing: return .trailing
        case .none: return .leading
        }
    }
}

// MARK: - Code

struct CodeBlockView: View {
    var language: String?
    var code: String
    var showsHeader: Bool = true

    @State private var isHovering = false

    private var highlighted: AttributedString {
        CodeSyntax.highlighted(code, language: language)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if showsHeader {
                HStack(spacing: 8) {
                    Text((language?.isEmpty == false ? language! : "code").uppercased())
                        .font(.system(size: 9, weight: .semibold, design: .rounded))
                        .tracking(0.6)
                        .foregroundStyle(Palette.tertiaryInk)
                    Spacer()
                    CopyButton(text: code, showsLabel: true, compact: true)
                }
                .padding(.leading, 12)
                .padding(.trailing, 7)
                .padding(.vertical, 5)
                .background(Palette.codeHeader)

                Hairline()
            }

            ScrollView(.horizontal, showsIndicators: false) {
                Text(highlighted)
                    .font(.system(size: 12, weight: .regular, design: .monospaced))
                    .foregroundStyle(Palette.codePlain)
                    .lineSpacing(3)
                    .textSelection(.enabled)
                    .padding(.horizontal, 13)
                    .padding(.vertical, 11)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .background(Palette.codeSurface)
        .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .strokeBorder(Palette.line.opacity(isHovering ? 1 : 0.6), lineWidth: 0.7)
        )
        .onHover { isHovering = $0 }
    }
}

struct EditsDetailView: View {
    var edits: [EditDiff]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(Array(edits.enumerated()), id: \.offset) { index, edit in
                if edits.count > 1 {
                    Text("Change \(index + 1) · \(edit.path)")
                        .font(Typo.micro)
                        .foregroundStyle(Palette.tertiaryInk)
                        .padding(.leading, 2)
                }
                VStack(alignment: .leading, spacing: 0) {
                    HStack(spacing: 7) {
                        Image(systemName: "doc.text")
                            .font(.system(size: 9.5))
                            .foregroundStyle(Palette.tertiaryInk)
                        Text(edit.path)
                            .font(Typo.monoSmall)
                            .foregroundStyle(Palette.secondaryInk)
                            .lineLimit(1)
                        Spacer()
                        CopyButton(text: edit.newText, showsLabel: false, compact: true)
                    }
                    .padding(.horizontal, 11)
                    .padding(.vertical, 6)
                    .background(Palette.codeHeader)

                    Hairline()

                    DiffLinesView(
                        oldText: edit.oldText,
                        newText: edit.newText
                    )
                    .padding(.vertical, 7)
                }
                .background(Palette.codeSurface)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .strokeBorder(Palette.line, lineWidth: 0.7)
                )
            }
        }
    }
}

private struct DiffLinesView: View {
    var oldText: String?
    var newText: String

    private let maxLines = 140

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let oldText, !oldText.isEmpty {
                diffSection(prefix: "−", text: oldText, color: Palette.diffDeletion, textColor: Palette.diffDeletionText)
            }
            if !newText.isEmpty {
                diffSection(prefix: "+", text: newText, color: Palette.diffAddition, textColor: Palette.diffAdditionText)
            }
        }
    }

    private func diffSection(prefix: String, text: String, color: Color, textColor: Color) -> some View {
        let lines = text.components(separatedBy: "\n")
        let visible = Array(lines.prefix(maxLines))
        return VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(visible.enumerated()), id: \.offset) { _, line in
                HStack(alignment: .top, spacing: 7) {
                    Text(prefix)
                        .font(.system(size: 10.5, weight: .medium, design: .monospaced))
                        .foregroundStyle(textColor)
                        .frame(width: 9, alignment: .trailing)
                    Text(line.isEmpty ? " " : line)
                        .font(.system(size: 11.5, design: .monospaced))
                        .foregroundStyle(textColor)
                        .textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.horizontal, 11)
                .padding(.vertical, 1)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(color)
            }
            if lines.count > maxLines {
                Text("\(lines.count - maxLines) more lines…")
                    .font(Typo.micro)
                    .foregroundStyle(Palette.tertiaryInk)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 5)
            }
        }
    }
}

struct TerminalOutputView: View {
    var text: String
    var isError: Bool = false
    @State private var expanded = false

    private let collapsedLineLimit = 16
    private let hardLineLimit = 1_500

    var body: some View {
        let lines = text.components(separatedBy: "\n")
        let allVisible = Array(lines.prefix(hardLineLimit))
        let visible = expanded ? allVisible : Array(allVisible.prefix(collapsedLineLimit))

        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text(isError ? "ERROR" : "OUTPUT")
                    .font(.system(size: 9, weight: .semibold, design: .rounded))
                    .tracking(0.6)
                    .foregroundStyle(isError ? Palette.danger : Palette.tertiaryInk)
                Spacer()
                CopyButton(text: text, showsLabel: false, compact: true)
            }
            .padding(.horizontal, 11)
            .padding(.vertical, 5)
            .background(Palette.codeHeader)

            Hairline()

            VStack(alignment: .leading, spacing: 0) {
                Text(visible.joined(separator: "\n"))
                    .font(.system(size: 11.5, design: .monospaced))
                    .foregroundStyle(isError ? Palette.diffDeletionText : Palette.codePlain)
                    .lineSpacing(2)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 11)
                    .padding(.vertical, 8)
                    .frame(maxWidth: .infinity, alignment: .leading)

                if lines.count > collapsedLineLimit {
                    Button {
                        withAnimation(.smooth(duration: 0.2)) { expanded.toggle() }
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: expanded ? "chevron.up" : "chevron.down")
                                .font(.system(size: 8, weight: .semibold))
                            Text(expanded ? "Show less" : "Show \(min(lines.count, hardLineLimit) - collapsedLineLimit) more lines")
                                .font(Typo.micro)
                        }
                        .foregroundStyle(Palette.tertiaryInk)
                        .padding(.horizontal, 11)
                        .padding(.bottom, 7)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .background(Palette.codeSurface)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(isError ? Palette.danger.opacity(0.30) : Palette.line, lineWidth: 0.7)
        )
    }
}

// MARK: - Assistant & user turns

struct UserTurnView: View {
    var turn: ConversationTurn
    @State private var isHovering = false

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Spacer(minLength: 90)

            VStack(alignment: .trailing, spacing: 5) {
                Text(turn.textContent)
                    .font(.system(size: 14.5))
                    .foregroundStyle(Palette.ink)
                    .lineSpacing(3.5)
                    .textSelection(.enabled)
                    .multilineTextAlignment(.leading)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 11)
                    .background(
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .fill(Palette.userBubble)
                            .overlay(
                                LinearGradient(
                                    colors: [
                                        Palette.accent.opacity(0.055),
                                        Color.clear
                                    ],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 18, style: .continuous)
                                    .strokeBorder(Palette.accent.opacity(0.20), lineWidth: 0.8)
                            )
                            .shadow(color: Palette.shadow.opacity(0.10), radius: 8, y: 3)
                    )
                    .frame(maxWidth: 620, alignment: .trailing)

                HStack(spacing: 6) {
                    if isHovering {
                        CopyButton(text: turn.textContent, showsLabel: true, compact: true)
                    }
                    Text(turn.createdAt.formatted(date: .omitted, time: .shortened))
                        .font(.system(size: 9.5))
                        .foregroundStyle(Palette.faintInk)
                }
                .frame(height: 15)
            }
            .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .onHover { isHovering = $0 }
    }
}

struct AssistantTurnView: View {
    var turn: ConversationTurn
    var activity: SessionActivity?
    var isLatest: Bool
    var projectPath: String
    var onRetry: () -> Void = {}

    @State private var isHovering = false

    private var isLive: Bool {
        isLatest && turn.isStreaming
    }

    private var reasoningText: String {
        turn.blocks
            .filter { $0.kind == .thinking }
            .map(\.text)
            .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            .joined(separator: "\n\n")
    }

    private var visibleBlocks: [MessageBlock] {
        turn.blocks.filter { $0.kind != .thinking }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 11) {
            header

            if !reasoningText.isEmpty {
                ReasoningDisclosure(text: reasoningText)
            }

            ForEach(visibleBlocks) { block in
                switch block.kind {
                case .text:
                    MarkdownTextView(block.text)
                case .tool:
                    if let tool = block.tool {
                        ToolRowView(tool: tool, projectPath: projectPath)
                    }
                case .thinking:
                    EmptyView()
                }
            }

            if isLive {
                LiveAssistantSection(activity: activity)
            }

            if let error = turn.errorText {
                AssistantErrorCard(message: error, onRetry: onRetry)
            }

            if !turn.isStreaming {
                AssistantTurnFooter(turn: turn, showCopy: isHovering)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .onHover { isHovering = $0 }
    }

    private var header: some View {
        HStack(spacing: 7) {
            BrandMark(size: 20, castsShadow: false)
            Text("Claude")
                .font(.system(size: 11.5, weight: .semibold))
                .foregroundStyle(Palette.secondaryInk)
            if isLive {
                ActivityDots(color: Palette.accent, size: 2.5)
            }
            Text(turn.createdAt.formatted(date: .omitted, time: .shortened))
                .font(.system(size: 9.5))
                .foregroundStyle(Palette.faintInk)
                .opacity(isHovering ? 1 : 0)
            Spacer()
        }
        .frame(height: 21)
    }
}

struct ReasoningDisclosure: View {
    var text: String
    @State private var expanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button {
                withAnimation(.smooth(duration: 0.2)) { expanded.toggle() }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "brain")
                        .font(.system(size: 10.5, weight: .regular))
                        .foregroundStyle(Palette.tertiaryInk)
                    Text("Reasoning")
                        .font(Typo.micro)
                        .foregroundStyle(Palette.tertiaryInk)
                    Image(systemName: expanded ? "chevron.down" : "chevron.right")
                        .font(.system(size: 7, weight: .semibold))
                        .foregroundStyle(Palette.faintInk)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(
                    Capsule(style: .continuous)
                        .fill(Palette.ink.opacity(0.035))
                )
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if expanded {
                ScrollView {
                    Text(text)
                        .font(.system(size: 12.5))
                        .foregroundStyle(Palette.secondaryInk)
                        .lineSpacing(3)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxHeight: 280)
                .padding(.leading, 2)
            }
        }
    }
}

/// Reads activity properties inside its own body, so streaming preview ticks
/// invalidate this small subtree instead of the whole assistant turn.
private struct LiveAssistantSection: View {
    var activity: SessionActivity?

    var body: some View {
        if let activity,
           !(activity.hasPendingPermission && activity.preview.isEmpty) {
            LiveAssistantPreview(
                preview: activity.preview,
                fallbackStatus: activity.statusText
            )
        }
    }
}

struct LiveAssistantPreview: View {
    var preview: StreamPreview
    var fallbackStatus: String?
    private var hasContent: Bool {
        !preview.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || !preview.thinking.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || preview.toolName != nil
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if !preview.thinking.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "brain")
                        .font(.system(size: 10.5))
                        .foregroundStyle(Palette.tertiaryInk)
                        .padding(.top, 3)
                    VStack(alignment: .leading, spacing: 3) {
                        HStack(spacing: 6) {
                            Text("Reasoning")
                                .font(Typo.micro)
                                .foregroundStyle(Palette.tertiaryInk)
                            ActivityDots(color: Palette.tertiaryInk, size: 2.2)
                        }
                        Text(preview.thinking)
                            .font(.system(size: 12.5))
                            .foregroundStyle(Palette.tertiaryInk)
                            .lineSpacing(3)
                            .lineLimit(4)
                            .textSelection(.enabled)
                    }
                }
                .transition(.opacity)
            }

            if !preview.text.isEmpty {
                Text("\(Text(preview.text).font(.system(size: 14.5)).foregroundColor(Palette.ink))\(Text("▍").font(.system(size: 13, weight: .regular, design: .monospaced)).foregroundColor(Palette.accent.opacity(0.75)))")
                    .lineSpacing(4)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else if let toolName = preview.toolName {
                HStack(spacing: 7) {
                    ActivityDots(color: Palette.accent, size: 2.5)
                    Text("Preparing \(toolName)…")
                        .font(Typo.caption)
                        .foregroundStyle(Palette.tertiaryInk)
                }
                .padding(.vertical, 2)
            } else if !hasContent {
                HStack(spacing: 8) {
                    ActivityDots(color: Palette.tertiaryInk, size: 2.5)
                    Text(fallbackStatus ?? "Thinking")
                        .font(Typo.caption)
                        .foregroundStyle(Palette.tertiaryInk)
                }
                .padding(.vertical, 2)
            }
        }
    }
}

struct AssistantTurnFooter: View {
    var turn: ConversationTurn
    var showCopy: Bool

    private var metadata: String? {
        var parts: [String] = []
        if let duration = Format.duration(milliseconds: turn.usage?.durationMS) {
            parts.append(duration)
        }
        if let tokens = turn.usage?.totalTokens, tokens > 0 {
            parts.append("\(Format.tokens(tokens)) tokens")
        }
        if let cost = turn.usage.map({ Format.cost($0.costUSD) }) ?? nil {
            parts.append(cost)
        }
        if turn.stopReason == "Stopped" {
            parts.append("Stopped")
        } else if turn.stopReason == "max_turns" {
            parts.append("Turn limit")
        }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    var body: some View {
        HStack(spacing: 8) {
            if showCopy, !turn.textContent.isEmpty {
                CopyButton(text: turn.textContent, showsLabel: true, compact: true)
            }
            if let metadata {
                Text(metadata)
                    .font(.system(size: 9.5))
                    .foregroundStyle(Palette.faintInk)
                    .help("Usage for this turn")
            }
            Spacer()
        }
        .frame(height: 17)
        .padding(.top, 1)
    }
}

struct AssistantErrorCard: View {
    var message: String
    var onRetry: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 9) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 12))
                    .foregroundStyle(Palette.warning)
                    .padding(.top, 2)
                VStack(alignment: .leading, spacing: 3) {
                    Text("This turn didn't finish")
                        .font(Typo.captionMedium)
                        .foregroundStyle(Palette.ink)
                    Text(message)
                        .font(Typo.caption)
                        .foregroundStyle(Palette.secondaryInk)
                        .textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            HStack {
                Button {
                    onRetry()
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: 9.5, weight: .medium))
                        Text("Try again")
                            .font(Typo.micro)
                    }
                    .padding(.horizontal, 9)
                    .padding(.vertical, 5)
                    .background(
                        Capsule(style: .continuous)
                            .fill(Palette.ink.opacity(0.055))
                            .overlay(Capsule(style: .continuous).strokeBorder(Palette.line, lineWidth: 0.7))
                    )
                }
                .buttonStyle(.plain)
                Spacer()
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Palette.warning.opacity(0.07))
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(Palette.warning.opacity(0.22), lineWidth: 0.8)
                )
        )
    }
}

// MARK: - Tool rows

struct ToolRowView: View {
    var tool: ToolActivity
    var projectPath: String
    @State private var expanded = false
    @State private var isHovering = false

    private var presentation: ToolPresentation {
        ToolPresentation.make(for: tool, projectPath: projectPath)
    }

    private var isExpandable: Bool {
        switch presentation.detail {
        case .none: return false
        case .command(_, let output): return true || output != nil
        case .code(_, _, let code, let output):
            return !code.isEmpty || output != nil || tool.status == .failed
        case .edits(_, let output): return output != nil || true
        case .output(let output): return !output.isEmpty
        case .todos(let todos): return !todos.isEmpty
        case .json(let json): return !json.isEmpty
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Button {
                guard isExpandable else { return }
                withAnimation(.smooth(duration: 0.20)) { expanded.toggle() }
            } label: {
                header
            }
            .buttonStyle(.plain)
            .disabled(!isExpandable)

            if expanded {
                ToolDetailView(presentation: presentation)
                    .padding(.leading, 30)
                    .padding(.top, 2)
                    .padding(.trailing, 2)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .onChange(of: tool.status) { _, status in
            if status == .failed { expanded = true }
        }
    }

    private var header: some View {
        HStack(spacing: 8) {
            ZStack {
                RoundedRectangle(cornerRadius: 6.5, style: .continuous)
                    .fill(presentation.tint.opacity(0.10))
                Image(systemName: presentation.icon)
                    .font(.system(size: 10.5, weight: .medium))
                    .foregroundStyle(presentation.tint)
            }
            .frame(width: 23, height: 23)

            HStack(spacing: 5) {
                Text(presentation.title)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Palette.ink)
                    .lineLimit(1)
                Text(presentation.subtitle)
                    .font(.system(size: 11.5))
                    .foregroundStyle(Palette.tertiaryInk)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            Spacer(minLength: 6)

            statusView

            if isExpandable {
                Image(systemName: "chevron.right")
                    .font(.system(size: 7.5, weight: .semibold))
                    .foregroundStyle(Palette.faintInk)
                    .rotationEffect(.degrees(expanded ? 90 : 0))
            }
        }
        .padding(.horizontal, 7)
        .padding(.vertical, 5)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(isHovering || expanded ? Palette.ink.opacity(0.035) : Color.clear)
        )
        .contentShape(Rectangle())
        .onHover { isHovering = $0 }
    }

    @ViewBuilder
    private var statusView: some View {
        switch tool.status {
        case .running:
            LoadingDotRing(size: 11, color: Palette.tertiaryInk)
        case .awaitingPermission:
            HStack(spacing: 4) {
                Image(systemName: "lock.fill")
                    .font(.system(size: 8.5, weight: .semibold))
                Text("Needs approval")
                    .font(Typo.micro)
            }
            .foregroundStyle(Palette.accent)
        case .completed:
            Image(systemName: "checkmark")
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(Palette.success.opacity(0.8))
        case .failed:
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 9.5))
                .foregroundStyle(Palette.danger)
        case .denied:
            Image(systemName: "hand.raised.fill")
                .font(.system(size: 9))
                .foregroundStyle(Palette.danger)
        case .interrupted:
            Image(systemName: "stop.fill")
                .font(.system(size: 8.5))
                .foregroundStyle(Palette.tertiaryInk)
        }
    }
}

struct ToolDetailView: View {
    var presentation: ToolPresentation

    var body: some View {
        switch presentation.detail {
        case .command(let command, let output):
            VStack(alignment: .leading, spacing: 7) {
                VStack(alignment: .leading, spacing: 0) {
                    HStack(alignment: .top, spacing: 8) {
                        Text("$")
                            .font(.system(size: 11.5, weight: .semibold, design: .monospaced))
                            .foregroundStyle(Palette.accent)
                        Text(command)
                            .font(.system(size: 11.5, design: .monospaced))
                            .foregroundStyle(Palette.codePlain)
                            .textSelection(.enabled)
                            .fixedSize(horizontal: false, vertical: true)
                        Spacer(minLength: 6)
                        CopyButton(text: command, showsLabel: false, compact: true)
                    }
                    .padding(.horizontal, 11)
                    .padding(.vertical, 8)
                }
                .background(Palette.codeSurface)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .strokeBorder(Palette.line, lineWidth: 0.7)
                )

                if let output, !output.isEmpty {
                    TerminalOutputView(text: output)
                }
            }

        case .code(let path, let language, let code, let output):
            VStack(alignment: .leading, spacing: 7) {
                if let path {
                    HStack(spacing: 6) {
                        Image(systemName: "doc.text")
                            .font(.system(size: 9.5))
                            .foregroundStyle(Palette.tertiaryInk)
                        Text(path)
                            .font(Typo.monoSmall)
                            .foregroundStyle(Palette.secondaryInk)
                            .lineLimit(1)
                    }
                    .padding(.leading, 2)
                }
                if !code.isEmpty {
                    CodeBlockView(language: language, code: code)
                }
                if let output, !output.isEmpty {
                    TerminalOutputView(text: output, isError: true)
                }
            }

        case .edits(let edits, let output):
            VStack(alignment: .leading, spacing: 7) {
                EditsDetailView(edits: edits)
                if let output, !output.isEmpty {
                    TerminalOutputView(text: output, isError: true)
                }
            }

        case .output(let output):
            TerminalOutputView(text: output)

        case .todos(let todos):
            VStack(alignment: .leading, spacing: 6) {
                ForEach(Array(todos.enumerated()), id: \.offset) { _, todo in
                    Text(todo)
                        .font(Typo.caption)
                        .foregroundStyle(
                            todo.hasPrefix("✓") ? Palette.tertiaryInk : Palette.secondaryInk
                        )
                }
            }
            .padding(11)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Palette.surface.opacity(0.5))
                    .overlay(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .strokeBorder(Palette.line, lineWidth: 0.7)
                    )
            )

        case .json(let json):
            CodeBlockView(language: "json", code: json)

        case .none:
            EmptyView()
        }
    }
}

// MARK: - Render caches

private final class MarkdownBlocksBox {
    let blocks: [MarkdownBlock]

    init(_ blocks: [MarkdownBlock]) {
        self.blocks = blocks
    }
}

private enum MarkdownBlockCache {
    static let cache: NSCache<NSString, MarkdownBlocksBox> = {
        let cache = NSCache<NSString, MarkdownBlocksBox>()
        cache.countLimit = 500
        cache.totalCostLimit = 24 * 1_024 * 1_024
        return cache
    }()

    static func blocks(for text: String) -> [MarkdownBlock] {
        let key = text as NSString
        if let cached = cache.object(forKey: key) {
            return cached.blocks
        }
        let blocks = MarkdownParser.parse(text)
        cache.setObject(MarkdownBlocksBox(blocks), forKey: key, cost: text.utf8.count)
        return blocks
    }
}
