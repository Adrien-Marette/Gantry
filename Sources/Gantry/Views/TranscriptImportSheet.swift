import SwiftUI
import GantryCore

/// Lists a project's Claude Code conversations that Gantry has not imported,
/// with a read-only preview so the person can pick the ones worth keeping.
struct TranscriptImportSheet: View {
    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss

    let projectID: UUID
    var offersRemember = false

    @State private var sessions: [ChatSession] = []
    @State private var isLoading = true
    @State private var checked: Set<UUID> = []
    @State private var previewID: UUID?
    @State private var remembersChoice = false
    @State private var hoveredID: UUID?

    private var projectName: String {
        app.projects.first { $0.id == projectID }?.name ?? "Project"
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            content
            footer
        }
        .frame(width: 980, height: 640)
        // The whole window is one Liquid Glass surface; content sits on a flat card inside it.
        .glassEffect(.regular, in: Rectangle())
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
                Text("Import conversations")
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
                preview
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }

    /// Styled like the main sidebar: Liquid Glass with an accent rail on the previewed row.
    private var list: some View {
        ZStack {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 2) {
                    SectionLabel(title: "\(sessions.count) conversations")
                        .padding(.horizontal, 10)
                        .padding(.bottom, 6)
                    ForEach(sessions) { session in
                        row(session)
                    }
                }
                .padding(10)
            }
            .scrollIndicators(.never)
        }
    }

    private func row(_ session: ChatSession) -> some View {
        let isSelected = previewID == session.id
        let isHovering = hoveredID == session.id
        return HStack(spacing: 8) {
            RoundedRectangle(cornerRadius: 1, style: .continuous)
                .fill(Palette.accent)
                .frame(width: 2, height: 28)
                .opacity(isSelected ? 1 : 0)

            Toggle("", isOn: Binding(
                get: { checked.contains(session.id) },
                set: { isOn in
                    if isOn { checked.insert(session.id) } else { checked.remove(session.id) }
                }
            ))
            .toggleStyle(.checkbox)
            .labelsHidden()
            .tint(Palette.accent)
            .accessibilityLabel("Import \(session.title)")

            Button {
                previewID = session.id
            } label: {
                VStack(alignment: .leading, spacing: 2) {
                    Text(session.title)
                        .font(.system(size: 13, weight: isSelected ? .medium : .regular))
                        .foregroundStyle(isSelected ? Palette.ink : Palette.secondaryInk)
                        .lineLimit(1)
                    Text("\(Format.relativeTime(session.updatedAt)) · \(session.turns.count) messages")
                        .font(.system(size: 10, weight: .medium).monospacedDigit())
                        .foregroundStyle(Palette.tertiaryInk)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Preview \(session.title)")
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(isSelected ? Palette.sidebarSelection : (isHovering ? Palette.sidebarHover : Color.clear))
        )
        .onHover { hoveredID = $0 ? session.id : nil }
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
            .surfaceCard(radius: Radius.panel)
            .padding([.top, .trailing, .bottom], 4)
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
            if offersRemember {
                Toggle("Remember my choice", isOn: $remembersChoice)
                    .toggleStyle(.checkbox)
                    .font(Typo.caption)
                    .help("Import automatically next time, or never ask again if you choose Not Now")
            }
            Button("Not Now") {
                if remembersChoice { app.setTranscriptImportPreference(.never) }
                dismiss()
            }
                .keyboardShortcut(.cancelAction)
                .buttonStyle(.glass)
            Button(checked.isEmpty ? "Import" : "Import \(checked.count)") {
                if remembersChoice { app.setTranscriptImportPreference(.always) }
                app.importSessions(sessions.filter { checked.contains($0.id) }, into: projectID)
                dismiss()
            }
            .keyboardShortcut(.defaultAction)
            .buttonStyle(.glassProminent)
            .tint(Palette.accent)
            .disabled(checked.isEmpty)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
    }
}
