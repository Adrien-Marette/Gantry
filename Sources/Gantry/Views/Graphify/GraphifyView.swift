import AppKit
import SwiftUI
import GantryCore

/// A project's Graphify knowledge graph: install, build, open, and query it.
/// Claude Code also receives the graph MCP server automatically once a graph
/// exists, so this page is a workspace for the graph rather than a gate.
struct GraphifyView: View {
    @Environment(AppModel.self) private var app

    @State private var model: GraphifyModel
    @State private var showingInstall = false

    init(app: AppModel) {
        _model = State(initialValue: GraphifyModel(app: app))
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Hairline()
            content
        }
        .task(id: app.selectedProjectID) {
            if let project = app.selectedProject {
                await model.refresh(project: project)
            } else {
                model.clear()
            }
        }
        .sheet(isPresented: $showingInstall) {
            GraphifyInstallSheet(model: model)
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 12) {
            IconButton(systemName: "chevron.left", help: "Back to workspace", frame: 28) {
                app.hideGraphify()
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("Graphify")
                    .font(Typo.pageTitle)
                    .foregroundStyle(Palette.ink)
                Text("A queryable knowledge graph of this project, shared with Claude Code.")
                    .font(Typo.caption)
                    .foregroundStyle(Palette.secondaryInk)
                    .lineLimit(1)
            }

            Spacer(minLength: 12)

            if model.isRefreshing {
                Spinner(size: 14)
            }

            IconButton(systemName: "arrow.clockwise", help: "Refresh graph status", frame: 28) {
                Task { await model.reload() }
            }
            .disabled(model.projectURL == nil || model.isBusy)
        }
        .padding(.horizontal, 32)
        .padding(.vertical, 20)
    }

    // MARK: - Content

    @ViewBuilder
    private var content: some View {
        if model.projectURL == nil {
            ExtensionsEmptyState(
                icon: "network",
                title: "Open a project",
                message: "Select a project in the sidebar to build and query its knowledge graph.",
                actionTitle: nil,
                action: nil
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if model.status == nil {
            VStack(spacing: 10) {
                ProgressView()
                    .controlSize(.small)
                Text("Reading Graphify status…")
                    .font(Typo.caption)
                    .foregroundStyle(Palette.tertiaryInk)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if let message = model.actionError {
                        InlineNotice(
                            icon: "exclamationmark.triangle.fill",
                            title: "Graphify couldn't finish",
                            message: message,
                            tint: Palette.danger,
                            actionTitle: nil,
                            action: nil,
                            onDismiss: { model.actionError = nil }
                        )
                    }

                    statusCard
                    installCard
                    queryCard
                    actionOutputCard
                }
                .frame(maxWidth: 760, alignment: .leading)
                .frame(maxWidth: .infinity)
                .padding(32)
            }
        }
    }

    private var statusCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 12) {
                ExtensionIconTile(symbol: "network", size: 36)

                VStack(alignment: .leading, spacing: 3) {
                    Text(model.projectName)
                        .font(Typo.sectionTitle)
                        .foregroundStyle(Palette.ink)
                    Text(model.projectURL?.path ?? "")
                        .font(Typo.monoSmall)
                        .foregroundStyle(Palette.tertiaryInk)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Text(model.graphSummary)
                        .font(Typo.caption)
                        .foregroundStyle(Palette.secondaryInk)
                }

                Spacer(minLength: 12)

                graphActions
            }

            Hairline()

            HStack(spacing: 14) {
                QuietBadge(
                    text: "CLI · \(model.cliSummary)",
                    color: model.hasCLI ? Palette.success : Palette.warning
                )
                QuietBadge(
                    text: "MCP · \(model.mcpSummary)",
                    color: model.hasMCP ? Palette.success : Palette.warning
                )
                Spacer()
            }

            if model.hasGraph && model.hasMCP {
                Text("Claude Code gets this project's graph tools automatically. New chats pick them up now; a running chat picks them up after its next turn.")
                    .font(Typo.caption)
                    .foregroundStyle(Palette.secondaryInk)
                    .fixedSize(horizontal: false, vertical: true)
            } else if model.hasGraph && !model.hasMCP {
                Text("Install the MCP server to let Claude Code query this graph in chat.")
                    .font(Typo.caption)
                    .foregroundStyle(Palette.secondaryInk)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(18)
        .surfaceCard()
    }

    private var graphActions: some View {
        HStack(spacing: 8) {
            if model.hasGraph {
                ExtensionsPillButton(title: "Open Graph", systemName: "safari") {
                    model.openGraph()
                }
                .disabled(!model.hasHTML || model.isBusy)
                .help("Open graph.html in your browser")
            }

            ExtensionsPillButton(
                title: model.hasGraph ? "Update Graph" : "Build Graph",
                systemName: model.hasGraph ? "arrow.triangle.2.circlepath" : "hammer",
                prominent: true,
                isBusy: model.isBuilding
            ) {
                Task { await model.buildGraph() }
            }
            .disabled(!model.hasCLI || model.isBusy)
            .help(model.hasGraph ? "Refresh the graph from this project's code" : "Index this project's code")
        }
    }

    @ViewBuilder
    private var installCard: some View {
        if !model.hasCLI || !model.hasMCP {
            VStack(alignment: .leading, spacing: 10) {
                Text(model.hasCLI ? "Add the MCP server" : "Install Graphify")
                    .font(Typo.headline)
                    .foregroundStyle(Palette.ink)

                Text(model.hasCLI
                     ? "Graphify is installed without its MCP extra, so Claude Code can't query the graph yet. Reinstalling with the extra keeps the same tool."
                     : "Graphify is a local Python tool that indexes this project. Gantry can install it with uv after you confirm; nothing is installed automatically.")
                    .font(Typo.caption)
                    .foregroundStyle(Palette.secondaryInk)
                    .fixedSize(horizontal: false, vertical: true)

                HStack(spacing: 8) {
                    Text(model.installCommand)
                        .font(Typo.monoSmall)
                        .foregroundStyle(Palette.secondaryInk)
                        .textSelection(.enabled)
                        .lineLimit(1)
                        .truncationMode(.middle)

                    CopyButton(text: model.installCommand, showsLabel: false, compact: true)

                    Spacer()

                    ExtensionsPillButton(
                        title: "Install…",
                        systemName: "arrow.down.circle",
                        prominent: true,
                        isBusy: model.isInstalling
                    ) {
                        showingInstall = true
                    }
                    .disabled(!model.hasUV || model.isBusy)
                }

                if !model.hasUV {
                    Text("uv was not found. Install uv, or run this command in Terminal.")
                        .font(Typo.micro)
                        .foregroundStyle(Palette.warning)
                }
            }
            .padding(18)
            .surfaceCard()
        }
    }

    private var queryCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Query the graph")
                .font(Typo.headline)
                .foregroundStyle(Palette.ink)

            HStack(spacing: 8) {
                TextField("What connects the composer to the runtime?", text: Binding(
                    get: { model.query },
                    set: { model.query = $0 }
                ))
                .textFieldStyle(.plain)
                .font(Typo.body)
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .background(FieldBackground())
                .disabled(!model.canQuery)
                .onSubmit { Task { await model.runQuery() } }
                .accessibilityLabel("Graphify query")

                ExtensionsPillButton(
                    title: "Query",
                    systemName: "magnifyingglass",
                    prominent: true,
                    isBusy: model.isQuerying
                ) {
                    Task { await model.runQuery() }
                }
                .disabled(
                    !model.canQuery
                        || model.query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                )
            }

            if !model.hasGraph {
                Text("Build a graph before querying.")
                    .font(Typo.caption)
                    .foregroundStyle(Palette.tertiaryInk)
            } else if !model.hasCLI {
                Text("The Graphify CLI is required to query.")
                    .font(Typo.caption)
                    .foregroundStyle(Palette.tertiaryInk)
            }

            if let message = model.queryError {
                InlineNotice(
                    icon: "exclamationmark.triangle.fill",
                    title: "Query failed",
                    message: message,
                    tint: Palette.danger,
                    actionTitle: nil,
                    action: nil,
                    onDismiss: { model.queryError = nil }
                )
            }

            if let result = model.queryResult {
                outputBox(result)
            }
        }
        .padding(18)
        .surfaceCard()
    }

    @ViewBuilder
    private var actionOutputCard: some View {
        if let output = model.actionOutput, !output.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    SectionLabel(title: "Last run")
                    Spacer()
                    CopyButton(text: output)
                }
                outputBox(output)
            }
            .padding(18)
            .surfaceCard()
        }
    }

    private func outputBox(_ text: String) -> some View {
        ScrollView {
            Text(text)
                .font(Typo.monoSmall)
                .foregroundStyle(Palette.secondaryInk)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(12)
        }
        .frame(maxHeight: 220)
        .background(Palette.codeSurface)
        .clipShape(RoundedRectangle(cornerRadius: Radius.control, style: .continuous))
        .hairlineBorder(radius: Radius.control)
    }
}

private struct GraphifyInstallSheet: View {
    @Environment(\.dismiss) private var dismiss
    var model: GraphifyModel

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 10) {
                ExtensionIconTile(symbol: "shippingbox", size: 32)
                VStack(alignment: .leading, spacing: 2) {
                    Text(model.hasCLI ? "Add the MCP server" : "Install Graphify")
                        .font(Typo.sectionTitle)
                        .foregroundStyle(Palette.ink)
                    Text("This runs a package install on your Mac.")
                        .font(Typo.caption)
                        .foregroundStyle(Palette.secondaryInk)
                }
            }

            Text("Gantry runs this command with uv, without a shell. It installs the third-party graphifyy Python package and its MCP server into your uv tool directory.")
                .font(Typo.body)
                .foregroundStyle(Palette.secondaryInk)
                .fixedSize(horizontal: false, vertical: true)

            Text(model.installCommand)
                .font(Typo.mono)
                .foregroundStyle(Palette.ink)
                .textSelection(.enabled)
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Palette.codeSurface)
                .clipShape(RoundedRectangle(cornerRadius: Radius.control, style: .continuous))
                .hairlineBorder(radius: Radius.control)

            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                    .buttonStyle(.glass)
                    .keyboardShortcut(.cancelAction)
                Button("Install") {
                    dismiss()
                    Task { await model.install() }
                }
                .buttonStyle(.glassProminent)
                .tint(Palette.accent)
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        .frame(width: 460)
        .background(CanvasBackground())
    }
}
