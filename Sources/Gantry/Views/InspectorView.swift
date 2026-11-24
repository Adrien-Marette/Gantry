import AppKit
import SwiftUI
import GantryCore

struct InspectorView: View {
    @Environment(AppModel.self) private var app
    var session: ChatSession
    var project: Project

    @State private var branch: String?
    @State private var remote: RepositoryRemote?

    private var activity: SessionActivity? {
        app.activities[session.id]
    }

    private var provider: AIProvider {
        app.provider(for: session)
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    sessionSection
                    activitySection
                    filesSection
                    usageSection
                    footerActions
                }
                .padding(.horizontal, 16)
                .padding(.top, 16)
                .padding(.bottom, 24)
            }
            .scrollIndicators(.never)
        }
        .background(Palette.surface)
        .task(id: project.path) {
            branch = GitContext.read(from: project.url).branch
            remote = GitRepositoryReader.originRemote(at: project.url)
        }
    }

    private var header: some View {
        HStack(spacing: 8) {
            Text("Inspector")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(Palette.ink)
            Spacer()
            IconButton(systemName: "xmark", help: "Hide inspector", size: 11, frame: 28) {
                app.inspectorVisible = false
            }
        }
        .padding(.leading, 20)
        .padding(.trailing, 12)
        .frame(height: 56)
        .overlay(alignment: .bottom) { Hairline() }
    }

    private var sessionSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionLabel(title: "Session")

            VStack(spacing: 0) {
                infoRow(
                    icon: "folder.fill",
                    title: "Project",
                    value: project.name,
                    detail: Format.abbreviatedPath(project.path)
                )

                rowDivider

                infoRow(
                    icon: "arrow.triangle.branch",
                    title: "Branch",
                    value: branch ?? "No repository",
                    detail: nil
                )

                rowDivider

                infoRow(
                    icon: "network",
                    title: "Remote",
                    value: remote?.fullName ?? "No remote",
                    detail: remote?.host
                )

                rowDivider

                infoRow(
                    icon: ProviderPresentation.symbol(for: provider.preset),
                    title: "Provider",
                    value: provider.name,
                    detail: provider.preset == .claudeCode ? "Current setup" : provider.displayBaseURL
                )

                rowDivider

                infoRow(
                    icon: "cpu",
                    title: "Model",
                    value: session.actualModelName ?? session.model.title,
                    detail: session.model == .automatic ? "Automatic" : session.model.title
                )

                rowDivider

                infoRow(
                    icon: session.permissionMode.symbol,
                    title: "Permissions",
                    value: session.permissionMode.title,
                    detail: nil
                )
            }
            .padding(.vertical, 3)
            .surfaceCard(radius: Radius.card)
        }
    }

    private var activitySection: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionLabel(title: "Activity")

            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 7) {
                    if activity?.isRunning == true {
                        LiveIndicator(color: Palette.accent, size: 12)
                        Text(activity?.statusText ?? "Working")
                            .font(Typo.captionMedium)
                            .foregroundStyle(Palette.secondaryInk)
                    } else if activity?.hasPendingPermission == true {
                        Image(systemName: "hand.raised.fill")
                            .font(.system(size: 10))
                            .foregroundStyle(Palette.accent)
                        Text("Waiting for you")
                            .font(Typo.captionMedium)
                            .foregroundStyle(Palette.secondaryInk)
                    } else {
                        Circle()
                            .fill(Palette.tertiaryInk)
                            .frame(width: 5, height: 5)
                        Text(session.turns.isEmpty ? "Not started" : "Ready")
                            .font(Typo.captionMedium)
                            .foregroundStyle(Palette.secondaryInk)
                    }
                    Spacer()
                }

                Hairline()

                HStack(spacing: 8) {
                    miniMetric(
                        value: "\(session.tools.count)",
                        label: "Tool calls"
                    )
                    miniMetric(
                        value: "\(session.changedFilePaths.count)",
                        label: "Files edited"
                    )
                    miniMetric(
                        value: "\(session.turns.filter { $0.role == .user }.count)",
                        label: "Messages"
                    )
                }
            }
            .padding(16)
            .surfaceCard(radius: Radius.card)
        }
    }

    private var filesSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                SectionLabel(title: "Edited files")
                Spacer()
                if !session.changedFilePaths.isEmpty {
                    Button("Review") {
                        app.reviewRequested = true
                    }
                    .buttonStyle(.plain)
                    .font(Typo.micro)
                    .foregroundStyle(Palette.accent)
                    .help("Review these changes and commit them")
                    Text("\(session.changedFilePaths.count)")
                        .font(Typo.micro)
                        .foregroundStyle(Palette.tertiaryInk)
                }
            }

            if session.changedFilePaths.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text("No file edits yet")
                        .font(Typo.caption)
                        .foregroundStyle(Palette.secondaryInk)
                    Text("Files Claude edits will appear here.")
                        .font(Typo.micro)
                        .foregroundStyle(Palette.tertiaryInk)
                }
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
                .surfaceCard(radius: Radius.card)
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(session.changedFilePaths.enumerated()), id: \.offset) { index, path in
                        fileRow(path)
                        if index < session.changedFilePaths.count - 1 {
                            rowDivider
                        }
                    }
                }
                .padding(.vertical, 3)
                .surfaceCard(radius: Radius.card)
            }
        }
    }

    private var usageSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionLabel(title: "Usage")

            HStack(spacing: 8) {
                metricCard(
                    label: "Estimated cost",
                    value: Format.cost(session.totalCostUSD) ?? "—"
                )
                metricCard(
                    label: "Tokens",
                    value: session.totalTokens > 0 ? Format.tokens(session.totalTokens) : "—"
                )
            }

            Text("Estimated from the reported model's token usage and published pricing when available. Not a billing statement.")
                .font(Typo.micro)
                .foregroundStyle(Palette.faintInk)
                .padding(.horizontal, 2)
        }
    }

    private var footerActions: some View {
        VStack(spacing: 8) {
            Hairline()
                .padding(.bottom, 3)

            actionRow(icon: "folder", title: "Show project in Finder") {
                NSWorkspace.shared.activateFileViewerSelecting([project.url])
            }

            actionRow(icon: "doc.text.magnifyingglass", title: "Open Claude Code log") {
                let logURL = app.dataStore.logURL(for: session.id)
                if FileManager.default.fileExists(atPath: logURL.path) {
                    NSWorkspace.shared.open(logURL)
                } else {
                    try? FileManager.default.createDirectory(
                        at: app.dataStore.paths.logsDirectory,
                        withIntermediateDirectories: true
                    )
                    NSWorkspace.shared.open(app.dataStore.paths.logsDirectory)
                }
            }
        }
    }

    private func infoRow(icon: String, title: String, value: String, detail: String?) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(Palette.tertiaryInk)
                .frame(width: 16)
            Text(title)
                .font(Typo.caption)
                .foregroundStyle(Palette.tertiaryInk)
                .frame(width: 72, alignment: .leading)
            VStack(alignment: .trailing, spacing: 2) {
                Text(value)
                    .font(Typo.captionMedium)
                    .foregroundStyle(Palette.secondaryInk)
                    .lineLimit(1)
                    .truncationMode(.middle)
                if let detail {
                    Text(detail)
                        .font(Typo.micro)
                        .foregroundStyle(Palette.tertiaryInk)
                        .lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    private func miniMetric(value: String, label: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value)
                .font(Typo.figureSmall)
                .foregroundStyle(Palette.ink)
            Text(label)
                .font(Typo.micro)
                .foregroundStyle(Palette.tertiaryInk)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func metricCard(label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label)
                .font(Typo.micro)
                .foregroundStyle(Palette.tertiaryInk)
            Text(value)
                .font(Typo.figure)
                .foregroundStyle(Palette.ink)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .surfaceCard(radius: Radius.card)
    }

    private func fileRow(_ path: String) -> some View {
        Button {
            NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)])
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "doc.text")
                    .font(.system(size: 11, weight: .regular))
                    .foregroundStyle(Palette.tertiaryInk)
                    .frame(width: 16)
                Text(Format.abbreviatedPath(path, root: project.path))
                    .font(Typo.monoSmall)
                    .foregroundStyle(Palette.secondaryInk)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer(minLength: 4)
                Image(systemName: "arrow.up.forward.square")
                    .font(.system(size: 10))
                    .foregroundStyle(Palette.tertiaryInk)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("Show in Finder")
    }

    private func actionRow(icon: String, title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 11, weight: .regular))
                    .foregroundStyle(Palette.tertiaryInk)
                    .frame(width: 16)
                Text(title)
                    .font(Typo.caption)
                    .foregroundStyle(Palette.secondaryInk)
                Spacer()
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var rowDivider: some View {
        Hairline()
            .padding(.leading, 36)
    }
}
