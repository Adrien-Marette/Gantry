import SwiftUI
import GantryCore

/// The floating menu above the composer that appears while the draft is a
/// slash command. It lists built-in, user/project, plugin, and mod commands
/// reported by Claude Code for this session.
struct SlashCommandMenu: View {
    var commands: [ClaudeSlashCommand]
    var selectedIndex: Int
    var isLoading: Bool
    var errorMessage: String?
    var query: String = ""
    var catalogCount: Int = 0
    /// Incremented only by keyboard navigation. Hovering a row changes the
    /// highlight but must not move the list under the pointer.
    var scrollRevision: Int = 0
    var onSelect: (ClaudeSlashCommand) -> Void
    var onHighlight: (ClaudeSlashCommand) -> Void
    var onRetry: () -> Void

    static let maxVisibleRows = 6
    static let rowHeight: CGFloat = 40

    static func height(rowCount: Int) -> CGFloat {
        // Header 32 + hairlines 2 + list padding 8 + footer 32.
        let chromeHeight: CGFloat = 74
        let rows = CGFloat(max(1, min(rowCount, maxVisibleRows)))
        return chromeHeight + rows * rowHeight
    }

    private var displayedRows: Int {
        commands.isEmpty ? 1 : min(commands.count, Self.maxVisibleRows)
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Hairline()
            content
            Hairline()
            footer
        }
        .frame(height: Self.height(rowCount: displayedRows))
        .glassPanel(radius: 16)
    }

    private var header: some View {
        HStack(spacing: 8) {
            Image(systemName: "chevron.left.forwardslash.chevron.right")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(Palette.tertiaryInk)
            Text("Commands")
                .font(Typo.captionMedium)
                .foregroundStyle(Palette.secondaryInk)
            Spacer(minLength: 8)
            if !commands.isEmpty {
                Text("\(commands.count)")
                    .font(Typo.micro)
                    .monospacedDigit()
                    .foregroundStyle(Palette.tertiaryInk)
            }
        }
        .padding(.horizontal, 12)
        .frame(height: 32)
    }

    @ViewBuilder
    private var content: some View {
        if commands.isEmpty {
            statusRow
        } else {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 1) {
                        ForEach(Array(commands.enumerated()), id: \.element.id) { index, command in
                            SlashCommandRow(
                                command: command,
                                isSelected: index == selectedIndex,
                                onHover: { onHighlight(command) },
                                action: { onSelect(command) }
                            )
                            .id(command.id)
                        }
                    }
                    .padding(.horizontal, 6)
                    .padding(.vertical, 4)
                }
                .scrollIndicators(.never)
                .frame(height: CGFloat(displayedRows) * Self.rowHeight + 8)
                .onChange(of: scrollRevision) { _, _ in
                    guard !commands.isEmpty else { return }
                    let clamped = min(max(selectedIndex, 0), commands.count - 1)
                    withAnimation(.easeOut(duration: 0.12)) {
                        proxy.scrollTo(commands[clamped].id, anchor: .center)
                    }
                }
                .onAppear {
                    guard !commands.isEmpty else { return }
                    let clamped = min(max(selectedIndex, 0), commands.count - 1)
                    proxy.scrollTo(commands[clamped].id, anchor: .center)
                }
            }
        }
    }

    private var statusRow: some View {
        HStack(spacing: 9) {
            if isLoading {
                Spinner(size: 12)
            } else {
                Image(systemName: statusIcon)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(errorMessage == nil ? Palette.tertiaryInk : Palette.warning)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(statusTitle)
                    .font(Typo.captionMedium)
                    .foregroundStyle(Palette.secondaryInk)
                Text(statusDetail)
                    .font(Typo.micro)
                    .foregroundStyle(Palette.tertiaryInk)
                    .lineLimit(1)
            }

            Spacer(minLength: 6)

            if errorMessage != nil {
                Button("Retry", action: onRetry)
                    .buttonStyle(.plain)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Palette.accent)
                    .padding(.horizontal, 4)
                    .padding(.vertical, 2)
            }
        }
        .padding(.horizontal, 12)
        .frame(height: Self.rowHeight + 8)
    }

    private var isNoMatch: Bool {
        commands.isEmpty && catalogCount > 0 && !isLoading && errorMessage == nil
    }

    private var statusIcon: String {
        if errorMessage != nil { return "exclamationmark.triangle.fill" }
        return isNoMatch ? "magnifyingglass" : "terminal"
    }

    private var statusTitle: String {
        if isLoading { return "Loading commands…" }
        if errorMessage != nil { return "Commands unavailable" }
        return isNoMatch ? "No matching commands" : "No commands"
    }

    private var statusDetail: String {
        if isLoading {
            return "Asking Claude Code what this project can run."
        }
        if let errorMessage { return errorMessage }
        if isNoMatch { return "Nothing matches /\(query)." }
        return "Claude Code didn't report any commands for this project."
    }

    private var footer: some View {
        HStack(spacing: 10) {
            HStack(spacing: 4) {
                KeyHint(text: "↑↓")
                Text("navigate")
                    .font(Typo.micro)
                    .foregroundStyle(Palette.tertiaryInk)
            }
            HStack(spacing: 4) {
                KeyHint(text: "↵")
                Text("select")
                    .font(Typo.micro)
                    .foregroundStyle(Palette.tertiaryInk)
            }
            HStack(spacing: 4) {
                KeyHint(text: "esc")
                Text("dismiss")
                    .font(Typo.micro)
                    .foregroundStyle(Palette.tertiaryInk)
            }
            Spacer(minLength: 4)
            if isLoading, !commands.isEmpty {
                Spinner(size: 12)
            }
        }
        .padding(.horizontal, 12)
        .frame(height: 32)
    }
}

private struct SlashCommandRow: View {
    var command: ClaudeSlashCommand
    var isSelected: Bool
    var onHover: () -> Void
    var action: () -> Void

    private var symbol: String {
        if command.sourceLabel != nil { return "puzzlepiece.extension" }
        return command.isBuiltin ? "terminal" : "doc.text"
    }

    private var fallbackDescription: String {
        if let source = command.sourceLabel { return "From \(source)" }
        return command.isBuiltin ? "Built-in command" : "Custom command"
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: symbol)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(isSelected ? Palette.ink : Palette.secondaryInk)
                    .frame(width: 18, height: 18)

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(command.invocation)
                            .font(.system(size: 12, weight: .medium, design: .monospaced))
                            .foregroundStyle(Palette.ink)
                            .lineLimit(1)
                        if let hint = command.argumentHint {
                            Text(hint)
                                .font(.system(size: 10, weight: .regular, design: .monospaced))
                                .foregroundStyle(Palette.tertiaryInk)
                                .lineLimit(1)
                                .truncationMode(.tail)
                        }
                    }
                    Text(command.description ?? fallbackDescription)
                        .font(Typo.micro)
                        .foregroundStyle(Palette.tertiaryInk)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }

                Spacer(minLength: 6)

                if let source = command.sourceLabel {
                    Text(source)
                        .font(Typo.micro)
                        .foregroundStyle(Palette.tertiaryInk)
                        .lineLimit(1)
                } else if command.isBuiltin {
                    Text("built-in")
                        .font(Typo.micro)
                        .foregroundStyle(Palette.tertiaryInk)
                }
            }
            .padding(.horizontal, 8)
            .frame(height: 38)
            .background(
                RoundedRectangle(cornerRadius: Radius.control, style: .continuous)
                    .fill(isSelected ? Palette.ink.opacity(0.06) : Color.clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            if hovering { onHover() }
        }
        .help(command.description ?? fallbackDescription)
        .accessibilityLabel("Command \(command.invocation)")
        .accessibilityHint("Inserts this command in the message field")
    }
}
