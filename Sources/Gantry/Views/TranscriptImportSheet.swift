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
    @State private var remembersChoice = false

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
        .frame(width: 980, height: 640)
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
                    .frame(width: 300)
                Divider()
                preview
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }

    private var list: some View {
        List(selection: $previewID) {
            Section("\(sessions.count) conversations") {
                ForEach(sessions) { session in
                    row(session).tag(session.id)
                }
            }
        }
        .listStyle(.sidebar)
    }

    private func row(_ session: ChatSession) -> some View {
        HStack(spacing: 8) {
            Toggle("", isOn: Binding(
                get: { checked.contains(session.id) },
                set: { isOn in
                    if isOn { checked.insert(session.id) } else { checked.remove(session.id) }
                }
            ))
            .toggleStyle(.checkbox)
            .labelsHidden()
            .accessibilityLabel("Import \(session.title)")

            VStack(alignment: .leading, spacing: 2) {
                Text(session.title)
                    .lineLimit(1)
                Text("\(Format.relativeTime(session.updatedAt)) · \(session.turns.count) messages")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
    }

    /// Reuses the chat's own turn views so the preview looks like the conversation will.
    @ViewBuilder
    private var preview: some View {
        if let session = sessions.first(where: { $0.id == previewID }) {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(session.turns) { turn in
                        if turn.role == .user {
                            UserTurnView(turn: turn)
                                .padding(.top, turn.id == session.turns.first?.id ? 0 : 32)
                        } else {
                            AssistantTurnView(
                                turn: turn,
                                activity: nil,
                                isLatest: false,
                                projectPath: app.projects.first { $0.id == projectID }?.path ?? ""
                            )
                            .padding(.top, 16)
                        }
                    }
                }
                .padding(24)
            }
            .id(session.id)
            .background(Palette.canvas)
        } else {
            Text("Select a conversation to preview it.")
                .font(Typo.caption)
                .foregroundStyle(Palette.tertiaryInk)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
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
            Toggle("Remember my choice", isOn: $remembersChoice)
                .toggleStyle(.checkbox)
                .font(Typo.caption)
                .help("Import automatically next time, or never ask again if you choose Not Now")
            Button("Not Now") {
                if remembersChoice { app.setTranscriptImportPreference(.never) }
                dismiss()
            }
                .keyboardShortcut(.cancelAction)
            Button(checked.isEmpty ? "Import" : "Import \(checked.count)") {
                if remembersChoice { app.setTranscriptImportPreference(.always) }
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
