import AppKit
import Observation
import SwiftUI
import GantryCore

@MainActor
@Observable
final class RepositoryPluginModel {
    enum Mode: Equatable {
        case pullRequests
        case newPullRequest
    }

    @ObservationIgnored private let app: AppModel
    @ObservationIgnored private let project: Project

    var remote: RepositoryRemote?
    var availablePlugins: [PluginConnection] = []
    var selectedPluginID: UUID?
    var repository: PluginRepository?
    var pullRequests: [PluginPullRequest] = []
    var selectedNumber: Int?
    var checks: [PluginCheck] = []
    var currentBranch: String?

    var mode: Mode = .pullRequests
    var isLoading = false
    var isLoadingChecks = false
    var isWorking = false
    var hasLoaded = false
    var errorMessage: String?
    var checksError: String?
    var actionMessage: String?

    var comment = ""
    var newTitle = ""
    var newBody = ""
    var newSourceBranch = ""
    var newTargetBranch = ""
    var newDraft = false

    @ObservationIgnored private var loadRequestID = UUID()
    @ObservationIgnored private var checksRequestID = UUID()

    init(app: AppModel, project: Project) {
        self.app = app
        self.project = project
    }

    var selectedPlugin: PluginConnection? {
        guard let selectedPluginID else { return nil }
        return availablePlugins.first { $0.id == selectedPluginID }
    }

    var selectedPullRequest: PluginPullRequest? {
        guard let selectedNumber else { return nil }
        return pullRequests.first { $0.number == selectedNumber }
    }

    var repositoryWebURL: URL? {
        repository?.webURL ?? selectedPlugin.flatMap { plugin in
            remote.flatMap { plugin.webURL(for: $0) }
        }
    }

    var pullRequestTerm: String {
        selectedPlugin?.kind.pullRequestTerm ?? "pull request"
    }

    var pullRequestTermPlural: String {
        selectedPlugin?.kind.pullRequestTermPlural ?? "pull requests"
    }

    func start() async {
        guard !hasLoaded else { return }
        currentBranch = GitContext.read(from: project.url).branch
        remote = GitRepositoryReader.originRemote(at: project.url)
        refreshPluginChoices()
        hasLoaded = true
        if remote != nil, selectedPlugin != nil {
            await load()
        }
    }

    func refreshPluginChoices() {
        guard let remote else {
            availablePlugins = []
            selectedPluginID = nil
            return
        }
        availablePlugins = app.matchingPlugins(for: remote)
        if let selectedPluginID,
           availablePlugins.contains(where: { $0.id == selectedPluginID }) {
            return
        }
        selectedPluginID = app.resolvedPlugin(for: project, remote: remote)?.id
            ?? availablePlugins.first?.id
    }

    func switchPlugin(to pluginID: UUID) {
        guard pluginID != selectedPluginID,
              availablePlugins.contains(where: { $0.id == pluginID }) else { return }
        app.setPluginConnection(pluginID, for: project.id)
        selectedPluginID = pluginID
        loadRequestID = UUID()
        checksRequestID = UUID()
        isLoading = false
        isLoadingChecks = false
        repository = nil
        pullRequests = []
        selectedNumber = nil
        checks = []
        comment = ""
        actionMessage = nil
        errorMessage = nil
        checksError = nil
        mode = .pullRequests
        Task { await load() }
    }

    func load() async {
        refreshPluginChoices()
        guard let remote, let plugin = selectedPlugin else { return }
        let requestID = UUID()
        loadRequestID = requestID
        isLoading = true
        errorMessage = nil
        defer {
            if loadRequestID == requestID {
                isLoading = false
            }
        }

        do {
            let client = try await app.pluginClient(for: plugin)
            async let repositoryTask = client.repository(for: remote)
            async let requestsTask = client.pullRequests(for: remote)
            let (repository, requests) = try await (repositoryTask, requestsTask)
            guard loadRequestID == requestID else { return }

            self.repository = repository
            self.pullRequests = requests

            if let selectedNumber,
               requests.contains(where: { $0.number == selectedNumber }) {
                // Keep the user's current selection.
            } else {
                selectedNumber = requests.first?.number
            }
            checks = []
            checksError = nil
            if selectedNumber != nil {
                await loadChecks()
            }
        } catch {
            guard loadRequestID == requestID else { return }
            errorMessage = error.localizedDescription
        }
    }

    func select(_ pullRequest: PluginPullRequest) {
        guard selectedNumber != pullRequest.number else { return }
        selectedNumber = pullRequest.number
        checks = []
        checksError = nil
        comment = ""
        actionMessage = nil
        Task { await loadChecks() }
    }

    func loadChecks() async {
        guard let number = selectedNumber,
              let pullRequest = pullRequests.first(where: { $0.number == number }),
              let remote,
              let plugin = selectedPlugin else {
            return
        }
        let requestID = UUID()
        let pluginID = plugin.id
        checksRequestID = requestID
        isLoadingChecks = true
        checksError = nil
        defer {
            if checksRequestID == requestID {
                isLoadingChecks = false
            }
        }

        do {
            let client = try await app.pluginClient(for: plugin)
            let result = try await client.checks(for: pullRequest, in: remote)
            guard checksRequestID == requestID,
                  selectedNumber == number,
                  selectedPluginID == pluginID else { return }
            checks = result
        } catch {
            guard checksRequestID == requestID,
                  selectedNumber == number,
                  selectedPluginID == pluginID else { return }
            checksError = error.localizedDescription
        }
    }

    func postComment() async {
        guard let number = selectedNumber,
              let remote,
              let plugin = selectedPlugin else { return }
        let body = comment.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !body.isEmpty else { return }

        isWorking = true
        errorMessage = nil
        actionMessage = nil
        defer { isWorking = false }
        do {
            let client = try await app.pluginClient(for: plugin)
            try await client.comment(on: number, in: remote, body: body)
            comment = ""
            actionMessage = "Comment posted to #\(number)."
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func beginNewPullRequest() {
        guard let repository else { return }
        mode = .newPullRequest
        errorMessage = nil
        actionMessage = nil
        newTitle = ""
        newBody = ""
        newSourceBranch = currentBranch ?? ""
        newTargetBranch = repository.defaultBranch
        newDraft = false
    }

    func cancelNewPullRequest() {
        mode = .pullRequests
        errorMessage = nil
    }

    func createPullRequest() async {
        guard let remote, let plugin = selectedPlugin else { return }
        let title = newTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        let source = newSourceBranch.trimmingCharacters(in: .whitespacesAndNewlines)
        let target = newTargetBranch.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty, !source.isEmpty, !target.isEmpty else {
            errorMessage = "Add a title and both branch names."
            return
        }
        guard source != target else {
            errorMessage = "Choose a source branch that differs from the target branch."
            return
        }

        isWorking = true
        errorMessage = nil
        actionMessage = nil
        defer { isWorking = false }
        do {
            let client = try await app.pluginClient(for: plugin)
            let created = try await client.createPullRequest(
                PluginNewPullRequest(
                    title: title,
                    body: newBody,
                    sourceBranch: source,
                    targetBranch: target,
                    isDraft: newDraft
                ),
                in: remote
            )
            pullRequests.removeAll { $0.id == created.id }
            pullRequests.insert(created, at: 0)
            selectedNumber = created.number
            checks = []
            mode = .pullRequests
            actionMessage = "\(pullRequestTerm.capitalized) #\(created.number) created."
            await loadChecks()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

// MARK: - Sheet

struct RepositoryPluginSheet: View {
    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openSettings) private var openSettings

    @State private var model: RepositoryPluginModel

    init(app: AppModel, project: Project) {
        _model = State(initialValue: RepositoryPluginModel(app: app, project: project))
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Hairline()

            if !model.hasLoaded {
                loadingState
            } else if model.remote == nil {
                emptyState(
                    icon: "network.slash",
                    title: "No git remote",
                    message: "This project has no origin remote. Add one in a terminal, then reopen this panel.",
                    actionTitle: nil,
                    action: nil
                )
            } else if model.availablePlugins.isEmpty {
                emptyState(
                    icon: "puzzlepiece",
                    title: "Connect a code host",
                    message: "No code host is connected for \(model.remote?.host ?? "this host"). Add one in Settings → Code Hosts to browse \(kindWord) and checks.",
                    actionTitle: "Open Code Hosts",
                    action: openPluginsSettings
                )
            } else if model.mode == .newPullRequest {
                newPullRequestForm
            } else {
                repositoryContent
            }
        }
        .frame(width: 880, height: 620)
        .background(Palette.canvasGradient)
        .task { await model.start() }
    }

    private var header: some View {
        HStack(spacing: 11) {
            ZStack {
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(headerTint.opacity(0.11))
                Image(systemName: headerSymbol)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(headerTint)
            }
            .frame(width: 34, height: 34)

            VStack(alignment: .leading, spacing: 2) {
                Text(model.remote?.fullName ?? "Repository")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Palette.ink)
                    .lineLimit(1)
                Text(headerSubtitle)
                    .font(Typo.micro)
                    .foregroundStyle(Palette.tertiaryInk)
                    .lineLimit(1)
            }

            Spacer(minLength: 10)

            if model.availablePlugins.count > 1 {
                Picker("Account", selection: Binding(
                    get: { model.selectedPluginID ?? model.availablePlugins.first?.id ?? UUID() },
                    set: { model.switchPlugin(to: $0) }
                )) {
                    ForEach(model.availablePlugins) { plugin in
                        Text("\(plugin.name) · @\(plugin.accountName)")
                            .tag(plugin.id)
                    }
                }
                .labelsHidden()
                .frame(maxWidth: 220)
                .help("Choose which connected account to use")
            }

            if model.hasLoaded, model.remote != nil {
                IconButton(
                    systemName: "arrow.clockwise",
                    help: "Refresh repository",
                    size: 11,
                    frame: 26
                ) {
                    Task { await model.load() }
                }
                .disabled(model.isLoading)
            }

            if let url = model.repositoryWebURL {
                IconButton(
                    systemName: "arrow.up.right.square",
                    help: "Open on \(model.selectedPlugin?.kind.title ?? "code host")",
                    size: 11,
                    frame: 26
                ) {
                    NSWorkspace.shared.open(url)
                }
            }

            IconButton(systemName: "xmark", help: "Close", size: 10, frame: 26) {
                dismiss()
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
        .background(Palette.canvasTop.opacity(0.30))
    }

    private var headerSymbol: String {
        if let plugin = model.selectedPlugin {
            return PluginPresentation.symbol(for: plugin.kind)
        }
        return "arrow.triangle.branch"
    }

    private var headerTint: Color {
        if let plugin = model.selectedPlugin {
            return PluginPresentation.tint(for: plugin.kind)
        }
        return Palette.secondaryInk
    }

    private var headerSubtitle: String {
        guard let remote = model.remote else {
            return "Repository integrations"
        }
        if let plugin = model.selectedPlugin {
            let account = plugin.accountName.isEmpty ? plugin.name : "@\(plugin.accountName)"
            return "\(plugin.kind.title) · \(account) · \(remote.host)"
        }
        return remote.host
    }

    private var kindWord: String {
        model.selectedPlugin?.kind.pullRequestTermPlural ?? "pull requests"
    }

    private var loadingState: some View {
        VStack(spacing: 12) {
            ProgressView()
                .controlSize(.small)
            Text("Looking at the repository…")
                .font(Typo.caption)
                .foregroundStyle(Palette.tertiaryInk)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func emptyState(
        icon: String,
        title: String,
        message: String,
        actionTitle: String?,
        action: (() -> Void)?
    ) -> some View {
        VStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 27, weight: .light))
                .foregroundStyle(Palette.tertiaryInk)
            Text(title)
                .font(Typo.headline)
                .foregroundStyle(Palette.ink)
            Text(message)
                .font(Typo.caption)
                .foregroundStyle(Palette.secondaryInk)
                .multilineTextAlignment(.center)
                .lineSpacing(2)
                .frame(maxWidth: 420)
            if let actionTitle, let action {
                Button(actionTitle, action: action)
                    .font(Typo.captionMedium)
                    .padding(.top, 4)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(30)
    }

    // MARK: Repository content

    private var repositoryContent: some View {
        VStack(spacing: 0) {
            if let errorMessage = model.errorMessage {
                InlineNotice(
                    icon: "exclamationmark.circle.fill",
                    title: "Something needs attention",
                    message: errorMessage,
                    tint: Palette.danger,
                    actionTitle: "Settings",
                    action: openPluginsSettings,
                    onDismiss: { model.errorMessage = nil }
                )
                .padding(.horizontal, 16)
                .padding(.top, 12)
                .padding(.bottom, 4)
            }

            HStack(spacing: 0) {
                pullRequestList
                    .frame(width: 322)

                Hairline(axis: .vertical)

                pullRequestDetail
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }

    private var pullRequestList: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                SectionLabel(title: "Open \(model.pullRequestTermPlural)")
                if !model.pullRequests.isEmpty {
                    Text("\(model.pullRequests.count)")
                        .font(Typo.micro)
                        .foregroundStyle(Palette.tertiaryInk)
                }
                Spacer()
                Button {
                    model.beginNewPullRequest()
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(Palette.accent)
                        .frame(width: 22, height: 22)
                        .background(Circle().fill(Palette.accent.opacity(0.09)))
                }
                .buttonStyle(.plain)
                .help("New \(model.pullRequestTerm)")
                .disabled(model.repository == nil)
            }
            .padding(.horizontal, 16)
            .frame(height: 48)

            if model.isLoading, model.pullRequests.isEmpty {
                VStack(spacing: 9) {
                    ProgressView().controlSize(.small)
                    Text("Loading \(model.pullRequestTermPlural)…")
                        .font(Typo.micro)
                        .foregroundStyle(Palette.tertiaryInk)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if model.pullRequests.isEmpty {
                VStack(spacing: 7) {
                    Image(systemName: "arrow.triangle.branch")
                        .font(.system(size: 20, weight: .light))
                        .foregroundStyle(Palette.tertiaryInk)
                    Text("No open \(model.pullRequestTermPlural)")
                        .font(Typo.captionMedium)
                        .foregroundStyle(Palette.secondaryInk)
                    Text("Create one from your current branch.")
                        .font(Typo.micro)
                        .foregroundStyle(Palette.tertiaryInk)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 1) {
                        ForEach(model.pullRequests) { pullRequest in
                            pullRequestRow(pullRequest)
                        }
                    }
                    .padding(.horizontal, 7)
                    .padding(.vertical, 6)
                }
                .scrollIndicators(.never)
            }
        }
        .background(Palette.surfaceSubtle.opacity(0.34))
    }

    private func pullRequestRow(_ pullRequest: PluginPullRequest) -> some View {
        let selected = pullRequest.number == model.selectedNumber
        return Button {
            model.select(pullRequest)
        } label: {
            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 6) {
                    Text("#\(pullRequest.number)")
                        .font(.system(size: 10.5, weight: .semibold, design: .monospaced))
                        .foregroundStyle(Palette.faintInk)
                    Text(pullRequest.title)
                        .font(Typo.captionMedium)
                        .foregroundStyle(Palette.ink)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                    Spacer(minLength: 0)
                }

                HStack(spacing: 5) {
                    Image(systemName: "arrow.triangle.branch")
                        .font(.system(size: 8.5))
                    Text("\(pullRequest.sourceBranch) → \(pullRequest.targetBranch)")
                        .font(.system(size: 9.5, design: .monospaced))
                        .lineLimit(1)
                    if pullRequest.isDraft {
                        Text("Draft")
                            .font(.system(size: 8.5, weight: .semibold))
                            .foregroundStyle(Palette.tertiaryInk)
                            .padding(.horizontal, 4)
                            .padding(.vertical, 1)
                            .background(Capsule().fill(Palette.ink.opacity(0.05)))
                    }
                }
                .foregroundStyle(Palette.tertiaryInk)

                HStack(spacing: 5) {
                    Text("@\(pullRequest.author)")
                    if let updatedAt = pullRequest.updatedAt {
                        Text("·")
                        Text(Format.relativeTime(updatedAt))
                    }
                }
                .font(Typo.micro)
                .foregroundStyle(Palette.faintInk)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 9)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(selected ? Palette.accent.opacity(0.10) : Color.clear)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .strokeBorder(selected ? Palette.accent.opacity(0.18) : Color.clear, lineWidth: 0.8)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var pullRequestDetail: some View {
        if let pullRequest = model.selectedPullRequest {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    pullRequestHeader(pullRequest)
                    checksSection
                    commentSection(pullRequest)
                }
                .padding(20)
            }
            .scrollIndicators(.never)
        } else {
            VStack(spacing: 8) {
                Image(systemName: "text.bubble")
                    .font(.system(size: 22, weight: .light))
                    .foregroundStyle(Palette.tertiaryInk)
                Text("Select a \(model.pullRequestTerm)")
                    .font(Typo.captionMedium)
                    .foregroundStyle(Palette.secondaryInk)
                if let repository = model.repository {
                    Text("\(repository.fullName) · default branch \(repository.defaultBranch)")
                        .font(Typo.micro)
                        .foregroundStyle(Palette.tertiaryInk)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func pullRequestHeader(_ pullRequest: PluginPullRequest) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(alignment: .top, spacing: 9) {
                Text(pullRequest.title)
                    .font(.system(size: 19, weight: .semibold))
                    .foregroundStyle(Palette.ink)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 4)
                if pullRequest.isDraft {
                    pill("Draft", color: Palette.tertiaryInk)
                }
                pill(pullRequest.state.rawValue.capitalized, color: stateColor(pullRequest.state))
            }

            HStack(spacing: 6) {
                Image(systemName: "person.crop.circle")
                    .font(.system(size: 9))
                Text("@\(pullRequest.author)")
                Text("·")
                Text("\(pullRequest.sourceBranch) → \(pullRequest.targetBranch)")
                    .font(.system(size: 10.5, design: .monospaced))
                if let updatedAt = pullRequest.updatedAt {
                    Text("·")
                    Text("updated \(Format.relativeTime(updatedAt))")
                }
                Spacer(minLength: 0)
                if let url = pullRequest.webURL {
                    Button {
                        NSWorkspace.shared.open(url)
                    } label: {
                        Label("Open", systemImage: "arrow.up.right.square")
                            .font(Typo.micro)
                            .foregroundStyle(Palette.accent)
                    }
                    .buttonStyle(.plain)
                }
            }
            .font(Typo.micro)
            .foregroundStyle(Palette.tertiaryInk)
            .lineLimit(1)

            if !pullRequest.body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Text(pullRequest.body)
                    .font(Typo.caption)
                    .foregroundStyle(Palette.secondaryInk)
                    .lineLimit(5)
                    .padding(11)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .surfaceCard(radius: 10)
            }
        }
    }

    private var checksSection: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(spacing: 8) {
                SectionLabel(title: "Checks")
                if let summary = PluginPresentation.checkSummary(model.checks) {
                    Text(summary.text)
                        .font(Typo.micro)
                        .foregroundStyle(summary.tint)
                }
                Spacer()
                Button {
                    Task { await model.loadChecks() }
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 9.5, weight: .semibold))
                        .foregroundStyle(Palette.tertiaryInk)
                }
                .buttonStyle(.plain)
                .help("Refresh checks")
                .disabled(model.isLoadingChecks)
            }

            if model.isLoadingChecks {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text("Loading checks…")
                        .font(Typo.micro)
                        .foregroundStyle(Palette.tertiaryInk)
                }
                .padding(.vertical, 8)
            } else if let checksError = model.checksError {
                InlineNotice(
                    icon: "exclamationmark.circle.fill",
                    title: "Couldn't load checks",
                    message: checksError,
                    tint: Palette.danger,
                    actionTitle: nil,
                    action: nil,
                    onDismiss: nil
                )
            } else if model.checks.isEmpty {
                Text("No checks reported for this commit.")
                    .font(Typo.micro)
                    .foregroundStyle(Palette.tertiaryInk)
                    .padding(11)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .surfaceCard(radius: 10)
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(model.checks.enumerated()), id: \.element.id) { index, check in
                        checkRow(check)
                        if index < model.checks.count - 1 {
                            settingsDivider
                        }
                    }
                }
                .surfaceCard(radius: 10)
            }
        }
    }

    private func checkRow(_ check: PluginCheck) -> some View {
        HStack(spacing: 9) {
            Image(systemName: PluginPresentation.checkSymbol(for: check.state))
                .font(.system(size: 11))
                .foregroundStyle(PluginPresentation.checkTint(for: check.state))
                .frame(width: 14)
            VStack(alignment: .leading, spacing: 1) {
                Text(check.name)
                    .font(Typo.captionMedium)
                    .foregroundStyle(Palette.ink)
                    .lineLimit(1)
                if let description = check.description, !description.isEmpty {
                    Text(description)
                        .font(Typo.micro)
                        .foregroundStyle(Palette.tertiaryInk)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 4)
            Text(check.state.title)
                .font(Typo.micro)
                .foregroundStyle(PluginPresentation.checkTint(for: check.state))
            if let url = check.detailsURL {
                Button {
                    NSWorkspace.shared.open(url)
                } label: {
                    Image(systemName: "arrow.up.right.square")
                        .font(.system(size: 9.5, weight: .medium))
                        .foregroundStyle(Palette.tertiaryInk)
                }
                .buttonStyle(.plain)
                .help("Open check details")
            }
        }
        .padding(.horizontal, 11)
        .padding(.vertical, 8)
    }

    private func commentSection(_ pullRequest: PluginPullRequest) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            SectionLabel(title: "Add a comment")
            ZStack(alignment: .topLeading) {
                TextEditor(text: Binding(
                    get: { model.comment },
                    set: { model.comment = $0 }
                ))
                .font(Typo.body)
                .foregroundStyle(Palette.ink)
                .scrollContentBackground(.hidden)
                .frame(minHeight: 72, maxHeight: 120)
                .padding(7)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Palette.surfaceSubtle)
                        .overlay(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .strokeBorder(Palette.line, lineWidth: 0.7)
                        )
                )

                if model.comment.isEmpty {
                    Text("Write a comment on #\(pullRequest.number)…")
                        .font(Typo.body)
                        .foregroundStyle(Palette.faintInk)
                        .padding(.horizontal, 12)
                        .padding(.top, 15)
                        .allowsHitTesting(false)
                }
            }

            HStack(spacing: 8) {
                if let actionMessage = model.actionMessage {
                    Label(actionMessage, systemImage: "checkmark.circle")
                        .font(Typo.micro)
                        .foregroundStyle(Palette.success)
                        .transition(.opacity)
                }
                Spacer()
                Button {
                    Task { await model.postComment() }
                } label: {
                    HStack(spacing: 5) {
                        if model.isWorking {
                            ProgressView().controlSize(.small)
                        }
                        Text("Post Comment")
                            .font(Typo.captionMedium)
                    }
                    .foregroundStyle(Palette.onAccent)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 7)
                    .background(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(Palette.accent)
                    )
                }
                .buttonStyle(.plain)
                .disabled(model.isWorking || model.comment.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
    }

    // MARK: New pull request

    private var newPullRequestForm: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack(spacing: 8) {
                    Button {
                        model.cancelNewPullRequest()
                    } label: {
                        Label("Back", systemImage: "chevron.left")
                            .font(Typo.micro)
                            .foregroundStyle(Palette.tertiaryInk)
                    }
                    .buttonStyle(.plain)
                    Spacer()
                }

                VStack(alignment: .leading, spacing: 3) {
                    Text("New \(model.pullRequestTerm)")
                        .font(Typo.sectionTitle)
                        .foregroundStyle(Palette.ink)
                    Text("Create a \(model.pullRequestTerm) from a branch that already exists on \(model.selectedPlugin?.serverHost ?? "the code host").")
                        .font(Typo.micro)
                        .foregroundStyle(Palette.tertiaryInk)
                }

                formField("Title", hint: nil) {
                    TextField("What changed?", text: Binding(
                        get: { model.newTitle },
                        set: { model.newTitle = $0 }
                    ))
                    .textFieldStyle(.plain)
                    .font(Typo.body)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
                    .background(formFieldBackground)
                }

                HStack(alignment: .top, spacing: 12) {
                    formField("Source branch", hint: "The branch with your changes.") {
                        TextField("feature/my-change", text: Binding(
                            get: { model.newSourceBranch },
                            set: { model.newSourceBranch = $0 }
                        ))
                        .textFieldStyle(.plain)
                        .font(Typo.mono)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 8)
                        .background(formFieldBackground)
                    }

                    formField("Target branch", hint: "Usually the repository's default branch.") {
                        TextField("main", text: Binding(
                            get: { model.newTargetBranch },
                            set: { model.newTargetBranch = $0 }
                        ))
                        .textFieldStyle(.plain)
                        .font(Typo.mono)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 8)
                        .background(formFieldBackground)
                    }
                }

                formField("Description", hint: nil) {
                    TextEditor(text: Binding(
                        get: { model.newBody },
                        set: { model.newBody = $0 }
                    ))
                    .font(Typo.body)
                    .foregroundStyle(Palette.ink)
                    .scrollContentBackground(.hidden)
                    .frame(minHeight: 110)
                    .padding(7)
                    .background(formFieldBackground)
                }

                Toggle(isOn: Binding(
                    get: { model.newDraft },
                    set: { model.newDraft = $0 }
                )) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Create as draft")
                            .font(Typo.caption)
                            .foregroundStyle(Palette.secondaryInk)
                        Text("Draft \(model.pullRequestTermPlural) are visible but not ready for review.")
                            .font(Typo.micro)
                            .foregroundStyle(Palette.tertiaryInk)
                    }
                }
                .toggleStyle(.switch)
                .controlSize(.small)

                if let errorMessage = model.errorMessage {
                    InlineNotice(
                        icon: "exclamationmark.circle.fill",
                        title: "Couldn't create the \(model.pullRequestTerm)",
                        message: errorMessage,
                        tint: Palette.danger,
                        actionTitle: nil,
                        action: nil,
                        onDismiss: { model.errorMessage = nil }
                    )
                }

                HStack {
                    Spacer()
                    Button {
                        Task { await model.createPullRequest() }
                    } label: {
                        HStack(spacing: 5) {
                            if model.isWorking {
                                ProgressView().controlSize(.small)
                            }
                            Text("Create \(model.pullRequestTerm.capitalized)")
                                .font(Typo.captionMedium)
                        }
                        .foregroundStyle(Palette.onAccent)
                        .padding(.horizontal, 13)
                        .padding(.vertical, 8)
                        .background(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .fill(Palette.accent)
                        )
                    }
                    .buttonStyle(.plain)
                    .disabled(model.isWorking || model.newTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .padding(24)
            .frame(maxWidth: 660)
            .frame(maxWidth: .infinity)
        }
        .scrollIndicators(.never)
    }

    private func formField<Content: View>(
        _ title: String,
        hint: String?,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title)
                .font(Typo.captionMedium)
                .foregroundStyle(Palette.ink)
            content()
            if let hint {
                Text(hint)
                    .font(Typo.micro)
                    .foregroundStyle(Palette.faintInk)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var formFieldBackground: some View {
        RoundedRectangle(cornerRadius: 8, style: .continuous)
            .fill(Palette.surfaceSubtle)
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(Palette.line, lineWidth: 0.7)
            )
    }

    private func pill(_ title: String, color: Color) -> some View {
        Text(title)
            .font(.system(size: 8.5, weight: .semibold))
            .foregroundStyle(color)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Capsule(style: .continuous).fill(color.opacity(0.09)))
    }

    private func stateColor(_ state: PluginPullRequestState) -> Color {
        switch state {
        case .open: return Palette.success
        case .closed: return Palette.tertiaryInk
        case .merged: return Palette.info
        }
    }

    private func openPluginsSettings() {
        dismiss()
        app.requestedSettingsTab = "plugins"
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            openSettings()
        }
    }
}
