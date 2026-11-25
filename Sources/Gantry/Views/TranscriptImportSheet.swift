import SwiftUI
import GantryCore

/// Lists a project's Claude Code conversations that Gantry has not imported,
/// with a read-only preview so the person can pick the ones worth keeping.
struct TranscriptImportSheet: View {
    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss

    let projectID: UUID

    @State private var sessions: [ChatSession] = []
    @State private var isLoading = true
    @State private var checked: Set<UUID> = []
    @State private var previewID: UUID?

    private var projectName: String {
        app.projects.first { $0.id == projectID }?.name ?? "Project"
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Hairline()
            content
            Hairline()
            footer
        }
        .frame(width: 860, height: 600)
        .background(CanvasBackground())
        .task {
            sessions = await app.loadImportableSessions(for: projectID)
            checked = Set(sessions.map(\.id))
            previewID = sessions.first?.id
            isLoading = false
        }
    }

    private var header: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Import Claude Code conversations")
                    .font(Typo.sectionTitle)
                    .foregroundStyle(Palette.ink)
                Text(projectName)
                    .font(Typo.caption)
                    .foregroundStyle(Palette.tertiaryInk)
            }
            Spacer()
            IconButton(systemName: "xmark", help: "Close", size: 12, frame: 28) {
                dismiss()
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
    }

    @ViewBuilder
    private var content: some View {
        if isLoading {
            VStack(spacing: 8) {
                Spinner(size: 18)
                Text("Reading conversations…")
                    .font(Typo.caption)
                    .foregroundStyle(Palette.tertiaryInk)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if sessions.isEmpty {
            VStack(spacing: 8) {
                Image(systemName: "tray")
                    .font(.system(size: 24))
                    .foregroundStyle(Palette.tertiaryInk)
                Text("Nothing to import")
                    .font(Typo.bodyMedium)
                    .foregroundStyle(Palette.ink)
                Text("Every Claude Code conversation for this project is already in Gantry.")
                    .font(Typo.caption)
                    .foregroundStyle(Palette.tertiaryInk)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            HStack(spacing: 0) {
                list
                    .frame(width: 340)
                Hairline(axis: .vertical)
                preview
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }

    private var list: some View {
        ScrollView {
            LazyVStack(spacing: 2) {
                ForEach(sessions) { session in
                    row(session)
                }
            }
            .padding(8)
        }
        .scrollIndicators(.never)
    }

    private func row(_ session: ChatSession) -> some View {
        let isPreviewed = previewID == session.id
        return HStack(spacing: 10) {
            Toggle("", isOn: Binding(
                get: { checked.contains(session.id) },
                set: { isOn in
                    if isOn { checked.insert(session.id) } else { checked.remove(session.id) }
                }
            ))
            .toggleStyle(.checkbox)
            .labelsHidden()
            .accessibilityLabel("Import \(session.title)")

            Button {
                previewID = session.id
            } label: {
                VStack(alignment: .leading, spacing: 3) {
                    Text(session.title)
                        .font(Typo.bodyMedium)
                        .foregroundStyle(Palette.ink)
                        .lineLimit(1)
                    Text("\(Format.relativeTime(session.updatedAt)) · \(session.turns.count) messages")
                        .font(Typo.micro)
                        .foregroundStyle(Palette.tertiaryInk)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Preview \(session.title)")
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(isPreviewed ? Palette.sidebarSelection : Color.clear)
        )
    }

    @ViewBuilder
    private var preview: some View {
        if let session = sessions.first(where: { $0.id == previewID }) {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 14) {
                    ForEach(session.turns) { turn in
                        previewTurn(turn)
                    }
                }
                .padding(20)
            }
            .id(session.id)
        } else {
            Text("Select a conversation to preview it.")
                .font(Typo.caption)
                .foregroundStyle(Palette.tertiaryInk)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func previewTurn(_ turn: ConversationTurn) -> some View {
        let text = turn.textContent
        let tools = turn.tools.map(\.name)
        return VStack(alignment: .leading, spacing: 4) {
            Text(turn.role == .user ? "You" : "Claude")
                .font(Typo.micro)
                .foregroundStyle(turn.role == .user ? Palette.accent : Palette.tertiaryInk)
            if !text.isEmpty {
                // shortcut: plain text capped at 1,200 characters, enough to judge relevance.
                Text(text.count > 1200 ? String(text.prefix(1200)) + "…" : text)
                    .font(Typo.caption)
                    .foregroundStyle(Palette.ink)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if !tools.isEmpty {
                Text("Tools: " + tools.joined(separator: ", "))
                    .font(Typo.monoSmall)
                    .foregroundStyle(Palette.tertiaryInk)
                    .lineLimit(2)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .surfaceCard()
    }

    private var footer: some View {
        HStack(spacing: 12) {
            if !sessions.isEmpty {
                Button(checked.count == sessions.count ? "Select None" : "Select All") {
                    checked = checked.count == sessions.count ? [] : Set(sessions.map(\.id))
                }
                .buttonStyle(.plain)
                .font(Typo.caption)
                .foregroundStyle(Palette.accent)
            }
            Spacer()
            Button("Cancel") { dismiss() }
                .keyboardShortcut(.cancelAction)
            Button(checked.isEmpty ? "Import" : "Import \(checked.count)") {
                app.importSessions(sessions.filter { checked.contains($0.id) }, into: projectID)
                dismiss()
            }
            .keyboardShortcut(.defaultAction)
            .buttonStyle(.glassProminent)
            .disabled(checked.isEmpty)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
    }
}
