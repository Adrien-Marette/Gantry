import AppKit
import SwiftUI
import GantryCore

/// A session-level review of the files Claude changed, with notes that can be
/// sent back to Claude and a commit flow that touches only those files.
struct ReviewChangesSheet: View {
    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss

    var session: ChatSession
    var project: Project
    var activity: SessionActivity?

    @State private var review: SessionReview
    @State private var selectedFileID: String?
    @State private var notes: [String: String] = [:]
    @State private var overallNote = ""
    @State private var showingCommit = false
    @State private var errorMessage: String?
    @State private var committedMessage: String?
    @State private var isGitRepository = false

    init(session: ChatSession, project: Project, activity: SessionActivity?) {
        self.session = session
        self.project = project
        self.activity = activity
        _review = State(initialValue: SessionReview.build(
            session: session,
            projectPath: project.path
        ))
    }

    private var commitPlan: GitCommitPlan {
        GitCommitService.plan(files: review.files, projectPath: project.path)
    }

    private var selectedFile: ReviewedFile? {
        review.files.first { $0.id == selectedFileID } ?? review.files.first
    }

    private var canSendNotes: Bool {
        activity?.isRunning != true
            && app.claudeAvailability.isReady
            && review.reviewMessage(notes: notes, overallNote: overallNote) != nil
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Hairline()

            if review.isEmpty {
                emptyState
            } else {
                HStack(spacing: 0) {
                    fileList
                    Hairline(axis: .vertical)
                    detail
                }
            }

            Hairline()
            footer
        }
        .frame(width: 880, height: 640)
        .background(CanvasBackground())
        .onAppear {
            isGitRepository = GitContext.read(from: project.url).isRepository
            repairSelection()
        }
        .sheet(isPresented: $showingCommit) {
            CommitChangesSheet(
                files: review.files,
                project: project,
                onCommitted: { output in
                    committedMessage = output
                        .components(separatedBy: .newlines)
                        .first(where: { !$0.trimmingCharacters(in: .whitespaces).isEmpty })
                }
            )
        }
    }

    // MARK: - Header and footer

    private var header: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text("Review changes")
                    .font(Typo.sectionTitle)
                    .foregroundStyle(Palette.ink)
                HStack(spacing: 6) {
                    Text(review.summaryLine)
                    Text("·")
                        .foregroundStyle(Palette.faintInk)
                    Text(project.name)
                    if review.fileCount > 0 {
                        Text("·")
                            .foregroundStyle(Palette.faintInk)
                        Text("From Claude's file edits")
                    }
                }
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

    private var footer: some View {
        HStack(spacing: 10) {
            if let committedMessage {
                Label(committedMessage, systemImage: "checkmark.seal.fill")
                    .font(Typo.caption)
                    .foregroundStyle(Palette.success)
                    .lineLimit(1)
                    .truncationMode(.tail)
            } else if let errorMessage {
                Text(errorMessage)
                    .font(Typo.caption)
                    .foregroundStyle(Palette.danger)
                    .lineLimit(2)
            } else if activity?.isRunning == true {
                Text("Claude is working; notes can be sent when this turn ends.")
                    .font(Typo.caption)
                    .foregroundStyle(Palette.tertiaryInk)
            } else if review.isEmpty {
                Text("Notes appear when Claude edits a file.")
                    .font(Typo.caption)
                    .foregroundStyle(Palette.tertiaryInk)
            }

            Spacer(minLength: 8)

            TextField("Overall note for Claude", text: $overallNote, axis: .vertical)
                .textFieldStyle(.plain)
                .font(Typo.caption)
                .foregroundStyle(Palette.ink)
                .lineLimit(1...3)
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
                .background(FieldBackground(radius: 8))
                .frame(minWidth: 160, maxWidth: 300)
                .layoutPriority(1)
                .accessibilityLabel("Overall note for Claude")

            CopyButton(text: review.plainText(), showsLabel: true)

            Button("Send notes") {
                sendNotes()
            }
            .buttonStyle(.glassProminent)
            .tint(Palette.accent)
            .disabled(!canSendNotes)
            .help(sendNotesHelp)

            if isGitRepository {
                Button("Commit…") {
                    showingCommit = true
                }
                .buttonStyle(.glass)
                .disabled(review.isEmpty || commitPlan.isEmpty)
                .help(commitPlan.isEmpty
                    ? "No reviewed files are inside this project."
                    : "Commit only these files. Gantry never pushes.")
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    private var sendNotesHelp: String {
        if activity?.isRunning == true {
            return "Wait for the current turn to finish before sending notes."
        }
        if !app.claudeAvailability.isReady {
            return "Claude Code isn't available yet."
        }
        if review.reviewMessage(notes: notes, overallNote: overallNote) == nil {
            return "Write a note on a file, or an overall note, first."
        }
        return "Send these notes to Claude as the next message."
    }

    // MARK: - File list

    private var fileList: some View {
        ScrollView {
            LazyVStack(spacing: 2) {
                ForEach(review.files) { file in
                    fileRow(file)
                }
            }
            .padding(8)
        }
        .frame(width: 280)
        .scrollIndicators(.never)
    }

    private func fileRow(_ file: ReviewedFile) -> some View {
        let isSelected = selectedFile?.id == file.id
        let hasNote = !(notes[file.id] ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .isEmpty

        return Button {
            selectedFileID = file.id
        } label: {
            HStack(spacing: 8) {
                RoundedRectangle(cornerRadius: 1, style: .continuous)
                    .fill(isSelected ? Palette.accent : Color.clear)
                    .frame(width: 2, height: 30)

                Image(systemName: file.wasCreated ? "doc.badge.plus" : "doc.text")
                    .font(.system(size: 12, weight: .regular))
                    .foregroundStyle(isSelected ? Palette.ink : Palette.tertiaryInk)
                    .frame(width: 16)

                VStack(alignment: .leading, spacing: 3) {
                    Text(file.displayPath)
                        .font(Typo.monoSmall)
                        .foregroundStyle(Palette.ink)
                        .lineLimit(1)
                        .truncationMode(.middle)

                    HStack(spacing: 6) {
                        if file.wasCreated {
                            Text("New")
                                .font(Typo.micro)
                                .foregroundStyle(Palette.success)
                        }
                        if file.addedLines > 0 {
                            Text("+\(file.addedLines)")
                                .font(Typo.micro)
                                .foregroundStyle(Palette.diffAdditionText)
                        }
                        if file.removedLines > 0 {
                            Text("−\(file.removedLines)")
                                .font(Typo.micro)
                                .foregroundStyle(Palette.diffDeletionText)
                        }
                        if hasNote {
                            Image(systemName: "text.bubble.fill")
                                .font(.system(size: 9))
                                .foregroundStyle(Palette.accent)
                                .accessibilityLabel("Has a note")
                        }
                    }
                }

                Spacer(minLength: 0)
            }
            .padding(.vertical, 6)
            .padding(.trailing, 8)
            .background(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(isSelected ? Palette.sidebarSelection : Color.clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(file.displayPath), \(file.changeSummary)")
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }

    // MARK: - Detail

    @ViewBuilder
    private var detail: some View {
        if let file = selectedFile {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    fileHeader(file)

                    ForEach(Array(file.changes.enumerated()), id: \.element.id) { index, change in
                        changeCard(
                            change,
                            index: index,
                            total: file.changes.count
                        )
                    }

                    noteEditor(for: file)
                }
                .padding(20)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .scrollIndicators(.automatic)
        }
    }

    private func fileHeader(_ file: ReviewedFile) -> some View {
        HStack(alignment: .top, spacing: 10) {
            VStack(alignment: .leading, spacing: 4) {
                Text(file.displayPath)
                    .font(Typo.bodyMedium)
                    .foregroundStyle(Palette.ink)
                    .textSelection(.enabled)
                Text("\(file.changeSummary) · \(file.toolNames.joined(separator: ", "))")
                    .font(Typo.micro)
                    .foregroundStyle(Palette.tertiaryInk)
            }

            Spacer()

            CopyButton(text: review.plainText(for: file), showsLabel: true)

            IconButton(
                systemName: "folder",
                help: "Reveal in Finder",
                frame: 26
            ) {
                NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: file.path)])
            }
        }
    }

    private func changeCard(
        _ change: ReviewedChange,
        index: Int,
        total: Int
    ) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 6) {
                Text(changeTitle(change, index: index, total: total))
                    .font(Typo.micro)
                    .foregroundStyle(Palette.secondaryInk)
                if change.toolName == "Write", !change.isCreation {
                    Text("· replaces the file")
                        .font(Typo.micro)
                        .foregroundStyle(Palette.tertiaryInk)
                }
                Spacer()
                Text("+\(change.addedLines) −\(change.removedLines)")
                    .font(Typo.micro)
                    .monospacedDigit()
                    .foregroundStyle(Palette.tertiaryInk)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 7)
            .background(Palette.codeHeader)

            Hairline()

            if change.toolName == "Write", !change.isCreation, change.oldText == nil {
                Text("The previous content of this file is not in the session transcript, so only the written content is shown.")
                    .font(Typo.micro)
                    .foregroundStyle(Palette.tertiaryInk)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
            }

            DiffLinesView(
                oldText: change.oldText,
                newText: change.newText,
                maxLines: 400
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

    private func changeTitle(_ change: ReviewedChange, index: Int, total: Int) -> String {
        if change.isCreation { return "New file" }
        if change.toolName == "Write" { return "Wrote file" }
        if total > 1 { return "\(change.toolName) · change \(index + 1)" }
        return change.toolName
    }

    private func noteEditor(for file: ReviewedFile) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Note for Claude")
                .font(Typo.micro)
                .foregroundStyle(Palette.tertiaryInk)

            TextField(
                "Ask for a change, or explain what should stay",
                text: noteBinding(for: file),
                axis: .vertical
            )
            .textFieldStyle(.plain)
            .font(Typo.caption)
            .foregroundStyle(Palette.ink)
            .lineLimit(2...6)
            .padding(10)
            .background(FieldBackground(radius: 8))
            .accessibilityLabel("Note for Claude about \(file.displayPath)")
        }
    }

    private func noteBinding(for file: ReviewedFile) -> Binding<String> {
        Binding(
            get: { notes[file.id] ?? "" },
            set: { notes[file.id] = $0 }
        )
    }

    // MARK: - Empty state

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "doc.text.magnifyingglass")
                .font(.system(size: 24, weight: .regular))
                .foregroundStyle(Palette.tertiaryInk)
            Text("No file changes to review")
                .font(Typo.bodyMedium)
                .foregroundStyle(Palette.ink)
            Text("When Claude edits files in this session, the changes appear here with a place to leave notes for Claude.")
                .font(Typo.caption)
                .foregroundStyle(Palette.tertiaryInk)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 360)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Actions

    private func repairSelection() {
        guard let selectedFileID else {
            self.selectedFileID = review.files.first?.id
            return
        }
        if !review.files.contains(where: { $0.id == selectedFileID }) {
            self.selectedFileID = review.files.first?.id
        }
    }

    private func sendNotes() {
        guard let message = review.reviewMessage(
            notes: notes,
            overallNote: overallNote
        ) else { return }

        errorMessage = nil
        committedMessage = nil
        if app.send(message, in: session.id) {
            dismiss()
        } else {
            errorMessage = "Could not send the notes. Check that Claude Code is ready and no turn is running."
        }
    }
}

/// Confirms and runs a pathspec commit for exactly the reviewed files.
private struct CommitChangesSheet: View {
    @Environment(\.dismiss) private var dismiss

    var files: [ReviewedFile]
    var project: Project
    var onCommitted: (String) -> Void

    @State private var message = ""
    @State private var isCommitting = false
    @State private var errorMessage: String?
    @State private var resultMessage: String?

    private var plan: GitCommitPlan {
        GitCommitService.plan(files: files, projectPath: project.path)
    }

    private var canCommit: Bool {
        !message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !plan.isEmpty
            && !isCommitting
    }

    /// Paths that commonly hold credentials. This is a warning, not a block:
    /// the person may have a legitimate reason, but they should look twice.
    private var sensitivePaths: [String] {
        plan.paths.filter { path in
            let name = URL(fileURLWithPath: path).lastPathComponent.lowercased()
            if name == ".env" || name.hasPrefix(".env.") { return true }
            if name == "id_rsa" || name == "id_ed25519" || name == "credentials" { return true }
            return [".pem", ".key", ".p12", ".pfx"].contains { name.hasSuffix($0) }
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Hairline()

            if let resultMessage {
                successState(resultMessage)
            } else {
                form
            }

            Hairline()
            footer
        }
        .frame(width: 560, height: resultMessage == nil ? 540 : 340)
        .background(CanvasBackground())
        .interactiveDismissDisabled(isCommitting)
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text("Commit changes")
                    .font(Typo.sectionTitle)
                    .foregroundStyle(Palette.ink)
                Text("\(plan.paths.count) file\(plan.paths.count == 1 ? "" : "s") · \(project.name)")
                    .font(Typo.caption)
                    .foregroundStyle(Palette.tertiaryInk)
            }
            Spacer()
            IconButton(systemName: "xmark", help: "Close", size: 12, frame: 28) {
                dismiss()
            }
            .disabled(isCommitting)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
    }

    private var form: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 8) {
                    SectionLabel(title: "Files")
                    VStack(spacing: 0) {
                        ForEach(Array(planFileRows.enumerated()), id: \.offset) { index, row in
                            HStack(spacing: 8) {
                                Image(systemName: "doc.text")
                                    .font(.system(size: 11))
                                    .foregroundStyle(Palette.tertiaryInk)
                                Text(row.displayPath)
                                    .font(Typo.monoSmall)
                                    .foregroundStyle(Palette.secondaryInk)
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                                Spacer()
                                if row.wasCreated {
                                    Text("New")
                                        .font(Typo.micro)
                                        .foregroundStyle(Palette.success)
                                }
                                Text("+\(row.addedLines) −\(row.removedLines)")
                                    .font(Typo.micro)
                                    .monospacedDigit()
                                    .foregroundStyle(Palette.tertiaryInk)
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            if index < planFileRows.count - 1 {
                                Hairline()
                            }
                        }
                    }
                    .surfaceCard(radius: Radius.card)
                }

                if !plan.excludedDisplayPaths.isEmpty {
                    Text("Excluded from the commit: \(plan.excludedDisplayPaths.joined(separator: ", "))")
                        .font(Typo.micro)
                        .foregroundStyle(Palette.warning)
                        .fixedSize(horizontal: false, vertical: true)
                }

                if !sensitivePaths.isEmpty {
                    Label(
                        "These files often contain secrets: \(sensitivePaths.joined(separator: ", ")). Make sure they belong in this commit.",
                        systemImage: "exclamationmark.shield.fill"
                    )
                    .font(Typo.micro)
                    .foregroundStyle(Palette.warning)
                    .fixedSize(horizontal: false, vertical: true)
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text("Commit message")
                        .font(Typo.micro)
                        .foregroundStyle(Palette.tertiaryInk)
                    TextField(
                        "feat(scope): describe the change",
                        text: $message,
                        axis: .vertical
                    )
                    .textFieldStyle(.plain)
                    .font(Typo.caption)
                    .foregroundStyle(Palette.ink)
                    .lineLimit(2...4)
                    .padding(10)
                    .background(FieldBackground(radius: 8))
                    .accessibilityLabel("Commit message")
                }

                Text("Only these files are committed, using their current contents on disk. Your Git signing configuration is used, hooks run normally, and Gantry never pushes.")
                    .font(Typo.micro)
                    .foregroundStyle(Palette.tertiaryInk)
                    .fixedSize(horizontal: false, vertical: true)

                if let errorMessage {
                    Text(errorMessage)
                        .font(Typo.caption)
                        .foregroundStyle(Palette.danger)
                        .textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(20)
        }
    }

    private func successState(_ output: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Committed", systemImage: "checkmark.seal.fill")
                .font(Typo.headline)
                .foregroundStyle(Palette.success)
            Text(output)
                .font(Typo.monoSmall)
                .foregroundStyle(Palette.secondaryInk)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
            Text("Gantry did not push. Push from your Git client when you're ready.")
                .font(Typo.micro)
                .foregroundStyle(Palette.tertiaryInk)
        }
        .padding(20)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var footer: some View {
        HStack(spacing: 10) {
            Spacer()
            if resultMessage != nil {
                Button("Done") { dismiss() }
                    .buttonStyle(.glassProminent)
                    .tint(Palette.accent)
            } else {
                Button("Cancel") { dismiss() }
                    .buttonStyle(.glass)
                    .disabled(isCommitting)
                Button {
                    commit()
                } label: {
                    HStack(spacing: 6) {
                        if isCommitting {
                            ProgressView()
                                .controlSize(.mini)
                        }
                        Text(isCommitting ? "Committing…" : "Commit \(plan.paths.count) file\(plan.paths.count == 1 ? "" : "s")")
                    }
                }
                .buttonStyle(.glassProminent)
                .tint(Palette.accent)
                .disabled(!canCommit)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    private var planFileRows: [ReviewedFile] {
        files.filter { plan.includedFileIDs.contains($0.id) }
    }

    private func commit() {
        isCommitting = true
        errorMessage = nil
        let commitMessage = message
        let files = files

        Task {
            do {
                let output = try await GitCommitService().commit(
                    message: commitMessage,
                    files: files,
                    in: project.url
                )
                resultMessage = output
                onCommitted(output)
            } catch {
                errorMessage = error.localizedDescription
            }
            isCommitting = false
        }
    }
}
