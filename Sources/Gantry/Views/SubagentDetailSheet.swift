import SwiftUI
import GantryCore

/// Details for one Task/Agent call. The tool is resolved from the live session
/// so a running sub-agent's status and report appear as they arrive.
struct SubagentDetailSheet: View {
    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss

    var sessionID: UUID
    var toolID: String

    private var tool: ToolActivity? {
        app.session(withID: sessionID)?.tools.first { $0.id == toolID }
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Hairline()

            if let tool {
                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        summary(tool)
                        promptSection(tool)
                        reportSection(tool)
                    }
                    .padding(20)
                }
                .scrollIndicators(.never)
            } else {
                Text("This sub-agent is no longer part of the session.")
                    .font(Typo.caption)
                    .foregroundStyle(Palette.secondaryInk)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(width: 720, height: 600)
        .background(CanvasBackground())
    }

    private var header: some View {
        HStack(spacing: 10) {
            Image(systemName: "point.3.connected.trianglepath.dotted")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(Palette.info)

            VStack(alignment: .leading, spacing: 2) {
                Text(tool?.subagentTypeTitle ?? "Sub-agent")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Palette.ink)
                Text(tool?.subagentDescription ?? "Delegated work")
                    .font(Typo.micro)
                    .foregroundStyle(Palette.tertiaryInk)
                    .lineLimit(1)
            }

            Spacer()

            if let tool {
                SubagentStatusView(tool: tool, showsLabel: true)
            }

            IconButton(systemName: "xmark", help: "Close", size: 11, frame: 28) {
                dismiss()
            }
        }
        .padding(.leading, 20)
        .padding(.trailing, 12)
        .frame(height: 60)
    }

    private func summary(_ tool: ToolActivity) -> some View {
        HStack(spacing: 8) {
            detailMetric(
                label: "Status",
                value: statusText(tool)
            )
            detailMetric(
                label: "Duration",
                value: tool.duration.flatMap {
                    Format.duration(milliseconds: Int($0 * 1_000))
                } ?? "—"
            )
            detailMetric(
                label: "Started",
                value: tool.startedAt.formatted(.dateTime.hour().minute())
            )
        }
    }

    private func detailMetric(label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(label)
                .font(Typo.micro)
                .foregroundStyle(Palette.tertiaryInk)
            Text(value)
                .font(Typo.captionMedium)
                .foregroundStyle(Palette.ink)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .surfaceCard(radius: Radius.card)
    }

    private func promptSection(_ tool: ToolActivity) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                SectionLabel(title: "Prompt")
                Spacer()
                if let prompt = promptText(tool) {
                    CopyButton(text: prompt, showsLabel: false, compact: true)
                }
            }
            if let prompt = promptText(tool) {
                MarkdownTextView(prompt)
                    .textSelection(.enabled)
                    .padding(16)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .surfaceCard(radius: Radius.card)
            } else {
                Text("This call did not include a prompt.")
                    .font(Typo.caption)
                    .foregroundStyle(Palette.tertiaryInk)
            }
        }
    }

    private func reportSection(_ tool: ToolActivity) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                SectionLabel(title: "Report")
                Spacer()
                if let report = reportText(tool) {
                    CopyButton(text: report, showsLabel: false, compact: true)
                }
            }

            if let report = reportText(tool) {
                MarkdownTextView(report)
                    .textSelection(.enabled)
                    .padding(16)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .surfaceCard(radius: Radius.card)
            } else {
                Text(emptyReportText(tool))
                    .font(Typo.caption)
                    .foregroundStyle(Palette.tertiaryInk)
                    .padding(16)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .surfaceCard(radius: Radius.card)
            }
        }
    }

    private func promptText(_ tool: ToolActivity) -> String? {
        guard let prompt = tool.input["prompt"]?.stringValue,
              !prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else { return nil }
        return prompt
    }

    private func reportText(_ tool: ToolActivity) -> String? {
        if tool.isBackgroundSubagent {
            switch tool.status {
            case .running, .awaitingPermission, .completed:
                return nil
            case .failed, .denied, .interrupted:
                break
            }
        }
        guard let text = tool.resultText,
              !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else { return nil }
        return text
    }

    private func emptyReportText(_ tool: ToolActivity) -> String {
        switch tool.status {
        case .running, .awaitingPermission, .completed:
            if tool.isBackgroundSubagent {
                return "This is a background task. Claude Code reports its final result later, and Gantry cannot capture it yet."
            }
            return tool.status == .completed ? "No report was returned." : "Still running…"
        case .denied:
            return "The sub-agent was not allowed to run."
        case .failed:
            return "The sub-agent failed without returning a report."
        case .interrupted:
            return "The sub-agent was interrupted before returning a report."
        }
    }

    private func statusText(_ tool: ToolActivity) -> String {
        if tool.isBackgroundSubagent, tool.status == .completed {
            return "Background"
        }
        switch tool.status {
        case .running: return "Running"
        case .awaitingPermission: return "Waiting for approval"
        case .completed: return "Completed"
        case .failed: return "Failed"
        case .denied: return "Denied"
        case .interrupted: return "Interrupted"
        }
    }
}

/// Shared status indicator for sub-agent rows and the detail sheet.
struct SubagentStatusView: View {
    var tool: ToolActivity
    var showsLabel = false

    var body: some View {
        HStack(spacing: 5) {
            switch tool.status {
            case .running:
                Spinner(size: 11)
            case .awaitingPermission:
                Image(systemName: "lock.fill")
                    .font(.system(size: 10, weight: .medium))
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

            if showsLabel {
                Text(label)
                    .font(Typo.micro)
                    .foregroundStyle(labelColor)
            }
        }
        .accessibilityLabel("Sub-agent status: \(label)")
    }

    private var label: String {
        if tool.isBackgroundSubagent, tool.status == .completed { return "Background" }
        switch tool.status {
        case .running: return "Running"
        case .awaitingPermission: return "Waiting for approval"
        case .completed: return "Completed"
        case .failed: return "Failed"
        case .denied: return "Denied"
        case .interrupted: return "Interrupted"
        }
    }

    private var labelColor: Color {
        switch tool.status {
        case .running, .awaitingPermission: return Palette.accent
        case .completed: return Palette.secondaryInk
        case .failed, .denied: return Palette.danger
        case .interrupted: return Palette.tertiaryInk
        }
    }
}
