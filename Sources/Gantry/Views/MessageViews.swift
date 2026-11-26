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
            ForEach(Array(Self.items(from: blocks).enumerated()), id: \.offset) { _, item in
                switch item {
                case .paragraphs(let paragraphs):
                    MarkdownParagraphRun(paragraphs: paragraphs)
                case .block(let block):
                    markdownBlock(block)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .onChange(of: text) { _, newValue in
            blocks = MarkdownBlockCache.blocks(for: newValue)
        }
    }

    /// Consecutive paragraphs share one Text so a drag selection can span
    /// paragraph breaks; other block kinds keep their dedicated views.
    private enum Item {
        case paragraphs([String])
        case block(MarkdownBlock)
    }

    private static func items(from blocks: [MarkdownBlock]) -> [Item] {
        var items: [Item] = []
        var run: [String] = []
        func flushRun() {
            if !run.isEmpty {
                items.append(.paragraphs(run))
                run.removeAll(keepingCapacity: true)
            }
        }
        for block in blocks {
            if case .paragraph(let text) = block {
                run.append(text)
            } else {
                flushRun()
                items.append(.block(block))
            }
        }
        flushRun()
        return items
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
                    ? .system(size: 20, weight: .semibold)
                    : (level == 2 ? .system(size: 16, weight: .semibold) : .system(size: 14, weight: .semibold)),
                color: Palette.ink
            )
            .padding(.top, level <= 2 ? 8 : 4)

        case .code(let language, let code, _):
            CodeBlockView(language: language, code: code)

        case .list(let ordered, let items):
            VStack(alignment: .leading, spacing: 6) {
                ForEach(Array(items.enumerated()), id: \.offset) { index, item in
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        listMarker(item: item, ordered: ordered, index: index)
                            .frame(width: 18, alignment: .trailing)
                        MarkdownInlineText(item.text)
                    }
                    .padding(.leading, CGFloat(min(item.depth, 4)) * 16)
                }
            }

        case .quote(let text):
            HStack(alignment: .top, spacing: 12) {
                Rectangle()
                    .fill(Palette.lineStrong)
                    .frame(width: 2)
                MarkdownInlineText(text, color: Palette.secondaryInk)
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
                .font(.system(size: 12, weight: .regular, design: .monospaced))
                .foregroundStyle(Palette.tertiaryInk)
                .monospacedDigit()
        } else {
            Circle()
                .fill(Palette.tertiaryInk)
                .frame(width: 3.5, height: 3.5)
                .alignmentGuide(.firstTextBaseline) { $0[.bottom] + 2 }
        }
    }
}

/// One Text for consecutive paragraphs so selection can cross paragraph
/// breaks. SwiftUI ignores paragraph spacing, so a 4 pt blank line keeps the
/// gap near the old 10 pt rhythm; upgrade when a TextKit renderer lands.
private struct MarkdownParagraphRun: View {
    var paragraphs: [String]

    private var merged: AttributedString {
        var result = AttributedString()
        for (index, paragraph) in paragraphs.enumerated() {
            if index > 0 {
                var separator = AttributedString("\n\n")
                separator[AttributeScopes.SwiftUIAttributes.FontAttribute.self] = .system(size: 4)
                result += separator
            }
            result += InlineMarkdown.attributed(paragraph)
        }
        return result
    }

    var body: some View {
        Text(merged)
            .font(Typo.body)
            .foregroundStyle(Palette.ink)
            .lineSpacing(4)
            .textSelection(.enabled)
            .tint(Palette.accent)
            .fixedSize(horizontal: false, vertical: true)
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
            Grid(alignment: .leading, horizontalSpacing: 24, verticalSpacing: 0) {
                GridRow {
                    ForEach(headers.indices, id: \.self) { index in
                        Text(InlineMarkdown.attributed(headers[index]))
                            .font(Typo.captionMedium)
                            .monospacedDigit()
                            .foregroundStyle(Palette.secondaryInk)
                            .frame(minWidth: 80, alignment: alignment(at: index))
                            .padding(.vertical, 8)
                    }
                }

                Divider()
                    .gridCellColumns(max(1, headers.count))

                ForEach(Array(rows.enumerated()), id: \.offset) { rowIndex, row in
                    GridRow {
                        ForEach(headers.indices, id: \.self) { index in
                            Text(InlineMarkdown.attributed(index < row.count ? row[index] : ""))
                                .font(Typo.caption)
                                .monospacedDigit()
                                .foregroundStyle(Palette.ink)
                                .frame(minWidth: 80, alignment: alignment(at: index))
                                .padding(.vertical, 6)
                                .textSelection(.enabled)
                        }
                    }
                    if rowIndex < rows.count - 1 {
                        Divider()
                            .gridCellColumns(max(1, headers.count))
                            .opacity(0.6)
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 4)
        }
        .background(
            RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
                .fill(Palette.surface)
                .overlay(
                    RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
                        .strokeBorder(Palette.line, lineWidth: 1)
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

    private var highlighted: AttributedString {
        CodeSyntax.highlighted(code, language: language)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if showsHeader {
                HStack(spacing: 8) {
                    Text(language?.isEmpty == false ? language! : "code")
                        .font(.system(size: 10, weight: .medium, design: .monospaced))
                        .foregroundStyle(Palette.tertiaryInk)
                    Spacer()
                    CopyButton(text: code, showsLabel: true, compact: true)
                }
                .padding(.leading, 16)
                .padding(.trailing, 8)
                .padding(.vertical, 6)
                .background(Palette.codeHeader)

                Hairline()
            }

            ScrollView(.horizontal, showsIndicators: false) {
                Text(highlighted)
                    .font(.system(size: 12, weight: .regular, design: .monospaced))
                    .foregroundStyle(Palette.codePlain)
                    .lineSpacing(3)
                    .textSelection(.enabled)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .background(Palette.codeSurface)
        .clipShape(RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
                .strokeBorder(Palette.line, lineWidth: 1)
        )
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
                    HStack(spacing: 8) {
                        Image(systemName: "doc.text")
                            .font(.system(size: 10))
                            .foregroundStyle(Palette.tertiaryInk)
                        Text(edit.path)
                            .font(Typo.monoSmall)
                            .foregroundStyle(Palette.secondaryInk)
                            .lineLimit(1)
                        Spacer()
                        CopyButton(text: edit.newText, showsLabel: false, compact: true)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 6)
                    .background(Palette.codeHeader)

                    Hairline()

                    DiffLinesView(
                        oldText: edit.oldText,
                        newText: edit.newText
                    )
                    .padding(.vertical, 8)
                }
                .background(Palette.codeSurface)
                .clipShape(RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
                        .strokeBorder(Palette.line, lineWidth: 1)
                )
            }
        }
    }
}

struct DiffLinesView: View {
    var oldText: String?
    var newText: String
    var maxLines: Int = 140

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
                HStack(alignment: .top, spacing: 8) {
                    Text(prefix)
                        .font(.system(size: 11, weight: .regular, design: .monospaced))
                        .foregroundStyle(textColor)
                        .frame(width: 10, alignment: .trailing)
                    Text(line.isEmpty ? " " : line)
                        .font(.system(size: 12, weight: .regular, design: .monospaced))
                        .foregroundStyle(textColor)
                        .textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 1)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(color)
            }
            if lines.count > maxLines {
                Text("\(lines.count - maxLines) more lines")
                    .font(Typo.micro)
                    .foregroundStyle(Palette.tertiaryInk)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 6)
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
                Text(isError ? "Error" : "Output")
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .foregroundStyle(isError ? Palette.danger : Palette.tertiaryInk)
                Spacer()
                CopyButton(text: text, showsLabel: false, compact: true)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 6)
            .background(Palette.codeHeader)

            Hairline()

            VStack(alignment: .leading, spacing: 0) {
                Text(visible.joined(separator: "\n"))
                    .font(.system(size: 12, weight: .regular, design: .monospaced))
                    .foregroundStyle(isError ? Palette.diffDeletionText : Palette.codePlain)
                    .lineSpacing(2)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .frame(maxWidth: .infinity, alignment: .leading)

                if lines.count > collapsedLineLimit {
                    Button {
                        withAnimation(.easeOut(duration: 0.2)) { expanded.toggle() }
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: expanded ? "chevron.up" : "chevron.down")
                                .font(.system(size: 10, weight: .medium))
                            Text(expanded ? "Show less" : "Show \(min(lines.count, hardLineLimit) - collapsedLineLimit) more lines")
                                .font(Typo.micro)
                        }
                        .foregroundStyle(Palette.tertiaryInk)
                        .padding(.horizontal, 16)
                        .padding(.bottom, 8)
                    }
                    .buttonStyle(.plain)
                }

                if expanded, lines.count > hardLineLimit {
                    Text("Showing the first \(hardLineLimit) of \(lines.count) lines.")
                        .font(Typo.micro)
                        .foregroundStyle(Palette.tertiaryInk)
                        .padding(.horizontal, 16)
                        .padding(.bottom, 8)
                }
            }
        }
        .background(Palette.codeSurface)
        .clipShape(RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
                .strokeBorder(isError ? Palette.danger.opacity(0.3) : Palette.line, lineWidth: 1)
        )
    }
}

// MARK: - Assistant & user turns

struct UserTurnView: View {
    var turn: ConversationTurn
    @State private var isHovering = false

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Spacer(minLength: 96)

            VStack(alignment: .trailing, spacing: 6) {
                let imagePaths = PromptAttachmentComposer.imagePaths(in: turn.textContent)
                if !imagePaths.isEmpty {
                    HStack(spacing: 6) {
                        ForEach(imagePaths, id: \.self) { ImageThumbnail(path: $0, size: 120) }
                    }
                }
                Text(turn.textContent)
                    .font(.system(size: 14))
                    .foregroundStyle(Palette.ink)
                    .lineSpacing(4)
                    .textSelection(.enabled)
                    .multilineTextAlignment(.leading)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    .background(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .fill(Palette.surfaceRaised)
                            .overlay(
                                RoundedRectangle(cornerRadius: 16, style: .continuous)
                                    .strokeBorder(Palette.line, lineWidth: 1)
                            )
                    )
                    .frame(maxWidth: 620, alignment: .trailing)

                HStack(spacing: 8) {
                    if isHovering {
                        CopyButton(text: turn.textContent, showsLabel: true, compact: true)
                    }
                    Text(turn.createdAt.formatted(date: .omitted, time: .shortened))
                        .font(.system(size: 11).monospacedDigit())
                        .foregroundStyle(Palette.tertiaryInk)
                }
                .frame(height: 16)
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
        .overlay(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: 1, style: .continuous)
                .fill(Palette.accent)
                .frame(width: 2, height: 24)
                .offset(x: -12, y: 1)
                .opacity(isLive ? 1 : 0)
        }
        .onHover { isHovering = $0 }
    }

    private var header: some View {
        HStack(spacing: 8) {
            BrandMark(size: 20)
            Text("Claude")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Palette.secondaryInk)
            if isLive {
                LiveIndicator(color: Palette.accent, size: 12)
            }
            Text(turn.createdAt.formatted(date: .omitted, time: .shortened))
                .font(.system(size: 11).monospacedDigit())
                .foregroundStyle(Palette.tertiaryInk)
                .opacity(isHovering ? 1 : 0)
            Spacer()
        }
        .frame(height: 24)
    }
}

struct ReasoningDisclosure: View {
    var text: String
    @State private var expanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button {
                withAnimation(.easeOut(duration: 0.2)) { expanded.toggle() }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "brain")
                        .font(.system(size: 11, weight: .regular))
                        .foregroundStyle(Palette.tertiaryInk)
                    Text("Reasoning")
                        .font(Typo.micro)
                        .foregroundStyle(Palette.tertiaryInk)
                    Image(systemName: expanded ? "chevron.down" : "chevron.right")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(Palette.tertiaryInk)
                }
                .padding(.vertical, 2)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if expanded {
                ScrollView {
                    Text(text)
                        .font(.system(size: 12))
                        .foregroundStyle(Palette.secondaryInk)
                        .lineSpacing(4)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxHeight: 280)
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
                        .font(.system(size: 11))
                        .foregroundStyle(Palette.tertiaryInk)
                        .padding(.top, 3)
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 6) {
                            Text("Reasoning")
                                .font(Typo.micro)
                                .foregroundStyle(Palette.tertiaryInk)
                            LiveIndicator(color: Palette.tertiaryInk, size: 12)
                        }
                        Text(preview.thinking)
                            .font(.system(size: 12))
                            .foregroundStyle(Palette.tertiaryInk)
                            .lineSpacing(4)
                            .lineLimit(4)
                    }
                }
                .transition(.opacity)
            }

            if !preview.text.isEmpty {
                Text("\(Text(preview.text).font(.system(size: 14)).foregroundColor(Palette.ink))\(Text("▍").font(.system(size: 13, weight: .regular, design: .monospaced)).foregroundColor(Palette.accent.opacity(0.75)))")
                    .lineSpacing(4)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else if let toolName = preview.toolName {
                HStack(spacing: 8) {
                    LiveIndicator(color: Palette.accent, size: 12)
                    Text("Preparing \(toolName)")
                        .font(Typo.caption)
                        .foregroundStyle(Palette.tertiaryInk)
                }
                .padding(.vertical, 2)
            } else if !hasContent {
                HStack(spacing: 8) {
                    LiveIndicator(color: Palette.tertiaryInk, size: 12)
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
                    .font(.system(size: 11, weight: .regular, design: .monospaced))
                    .foregroundStyle(Palette.tertiaryInk)
                    .help("Usage for this turn")
            }
            Spacer()
        }
        .frame(height: 20)
        .padding(.top, 2)
    }
}

struct AssistantErrorCard: View {
    var message: String
    var onRetry: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 12))
                    .foregroundStyle(Palette.warning)
                    .padding(.top, 1)
                VStack(alignment: .leading, spacing: 4) {
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
                            .font(.system(size: 10, weight: .medium))
                        Text("Try again")
                            .font(Typo.micro)
                    }
                }
                .buttonStyle(.glass)
                Spacer()
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
                .fill(Palette.surface)
                .overlay(
                    RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
                        .strokeBorder(Palette.warning.opacity(0.3), lineWidth: 1)
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
                withAnimation(.easeOut(duration: 0.2)) { expanded.toggle() }
            } label: {
                header
            }
            .buttonStyle(.plain)
            .disabled(!isExpandable)

            if expanded {
                ToolDetailView(presentation: presentation)
                    .padding(.leading, 32)
                    .padding(.top, 4)
                    .transition(.opacity)
            }
        }
        .onChange(of: tool.status) { _, status in
            if status == .failed { expanded = true }
        }
    }

    private var header: some View {
        HStack(spacing: 8) {
            ZStack {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(Palette.ink.opacity(0.04))
                Image(systemName: presentation.icon)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Palette.secondaryInk)
            }
            .frame(width: 24, height: 24)

            HStack(spacing: 6) {
                Text(presentation.title)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Palette.ink)
                    .lineLimit(1)
                Text(presentation.subtitle)
                    .font(.system(size: 12))
                    .foregroundStyle(Palette.tertiaryInk)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            Spacer(minLength: 8)

            statusView

            if isExpandable {
                Image(systemName: "chevron.right")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(Palette.tertiaryInk)
                    .rotationEffect(.degrees(expanded ? 90 : 0))
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: Radius.control, style: .continuous)
                .fill(isHovering || expanded ? Palette.ink.opacity(0.04) : Color.clear)
        )
        .contentShape(Rectangle())
        .onHover { isHovering = $0 }
    }

    @ViewBuilder
    private var statusView: some View {
        switch tool.status {
        case .running:
            Spinner(size: 12)
        case .awaitingPermission:
            HStack(spacing: 4) {
                Image(systemName: "lock.fill")
                    .font(.system(size: 10, weight: .medium))
                Text("Needs approval")
                    .font(Typo.micro)
            }
            .foregroundStyle(Palette.accent)
        case .completed:
            Image(systemName: "checkmark")
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(Palette.success)
        case .failed:
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 10))
                .foregroundStyle(Palette.danger)
        case .denied:
            Image(systemName: "hand.raised.fill")
                .font(.system(size: 10))
                .foregroundStyle(Palette.danger)
        case .interrupted:
            Image(systemName: "stop.fill")
                .font(.system(size: 10))
                .foregroundStyle(Palette.tertiaryInk)
        }
    }
}

struct ToolDetailView: View {
    var presentation: ToolPresentation

    var body: some View {
        switch presentation.detail {
        case .command(let command, let output):
            VStack(alignment: .leading, spacing: 8) {
                VStack(alignment: .leading, spacing: 0) {
                    HStack(alignment: .top, spacing: 8) {
                        Text("$")
                            .font(.system(size: 12, weight: .regular, design: .monospaced))
                            .foregroundStyle(Palette.tertiaryInk)
                        Text(command)
                            .font(.system(size: 12, weight: .regular, design: .monospaced))
                            .foregroundStyle(Palette.codePlain)
                            .textSelection(.enabled)
                            .fixedSize(horizontal: false, vertical: true)
                        Spacer(minLength: 8)
                        CopyButton(text: command, showsLabel: false, compact: true)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                }
                .background(Palette.codeSurface)
                .clipShape(RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
                        .strokeBorder(Palette.line, lineWidth: 1)
                )

                if let output, !output.isEmpty {
                    TerminalOutputView(text: output)
                }
            }

        case .code(let path, let language, let code, let output):
            VStack(alignment: .leading, spacing: 8) {
                if let path {
                    HStack(spacing: 6) {
                        Image(systemName: "doc.text")
                            .font(.system(size: 10))
                            .foregroundStyle(Palette.tertiaryInk)
                        Text(path)
                            .font(Typo.monoSmall)
                            .foregroundStyle(Palette.secondaryInk)
                            .lineLimit(1)
                    }
                }
                if !code.isEmpty {
                    CodeBlockView(language: language, code: code)
                }
                if let output, !output.isEmpty {
                    TerminalOutputView(text: output, isError: true)
                }
            }

        case .edits(let edits, let output):
            VStack(alignment: .leading, spacing: 8) {
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
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
                    .fill(Palette.surface)
                    .overlay(
                        RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
                            .strokeBorder(Palette.line, lineWidth: 1)
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
