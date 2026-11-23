import AppKit
import SwiftUI
import GantryCore

struct ExtensionsInstalledView: View {
    let model: ExtensionsModel
    var onBrowse: () -> Void = {}

    @State private var search = ""
    @State private var pendingUninstall: ClaudeInstalledPlugin?
    @State private var commandPrompt: ExtensionCommandPrompt?

    var body: some View {
        VStack(spacing: 0) {
            controls
                .padding(.horizontal, 28)
                .padding(.bottom, 12)

            if plugins.isEmpty {
                ExtensionsEmptyState(
                    icon: "puzzlepiece.extension",
                    title: search.isEmpty ? "Nothing installed yet" : "No matches",
                    message: search.isEmpty
                        ? "Install an extension or mod from Browse. Installed plugins are shared with the Claude Code CLI."
                        : "Try another search.",
                    actionTitle: search.isEmpty ? "Browse Extensions" : nil
                ) {
                    onBrowse()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 8) {
                        ForEach(plugins, id: \.identity) { plugin in
                            pluginRow(plugin)
                        }
                    }
                    .frame(maxWidth: 980)
                    .frame(maxWidth: .infinity)
                    .padding(.horizontal, 28)
                    .padding(.bottom, 24)
                }
                .scrollIndicators(.never)
            }
        }
        .sheet(item: $commandPrompt) { prompt in
            ExtensionCommandApprovalSheet(
                model: model,
                prompt: prompt,
                onCompleted: { commandPrompt = nil }
            )
        }
        .alert(
            "Uninstall extension?",
            isPresented: Binding(
                get: { pendingUninstall != nil },
                set: { if !$0 { pendingUninstall = nil } }
            ),
            presenting: pendingUninstall
        ) { plugin in
            Button("Uninstall", role: .destructive) {
                uninstall(plugin)
            }
            Button("Cancel", role: .cancel) { pendingUninstall = nil }
        } message: { plugin in
            Text("“\(plugin.name)” will be removed from Claude Code. Its saved data is kept. Marketplace sources and favorites are not affected.")
        }
    }

    private var controls: some View {
        HStack(spacing: 9) {
            ExtensionsSearchField(text: $search, placeholder: "Search installed extensions")
                .frame(width: 300)

            Spacer()

            Text("\(plugins.count) installed")
                .font(Typo.micro)
                .foregroundStyle(Palette.faintInk)
        }
    }

    private var plugins: [ClaudeInstalledPlugin] {
        let query = search.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let filtered = query.isEmpty
            ? model.installedPlugins
            : model.installedPlugins.filter { plugin in
                plugin.name.lowercased().contains(query)
                    || plugin.id.lowercased().contains(query)
                    || (plugin.marketplaceName ?? "").lowercased().contains(query)
            }
        return filtered.sorted { lhs, rhs in
            if lhs.enabled != rhs.enabled {
                return lhs.enabled
            }
            return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
        }
    }

    private func pluginRow(_ plugin: ClaudeInstalledPlugin) -> some View {
        let isUserScope = model.isUserScope(plugin)

        return HStack(alignment: .top, spacing: 12) {
            ExtensionIconTile(
                symbol: plugin.readFromFolder == nil ? "puzzlepiece.extension" : "hammer",
                tint: plugin.enabled ? Palette.success : Palette.tertiaryInk
            )
            .padding(.top, 1)

            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 7) {
                    Text(plugin.name)
                        .font(Typo.headline)
                        .foregroundStyle(Palette.ink)
                        .lineLimit(1)

                    ExtensionBadge(
                        text: plugin.enabled ? "Enabled" : "Disabled",
                        color: plugin.enabled ? Palette.success : Palette.warning
                    )

                    ExtensionBadge(
                        text: scopeTitle(plugin),
                        color: isUserScope ? Palette.info : Palette.tertiaryInk
                    )

                    if plugin.hasUserConfig == true {
                        ExtensionBadge(text: "Has settings", color: Palette.accent)
                    }
                }

                HStack(spacing: 6) {
                    Text(plugin.id)
                        .font(Typo.micro)
                        .foregroundStyle(Palette.tertiaryInk)
                        .lineLimit(1)

                    if let version = plugin.version {
                        Text("· v\(version)")
                            .font(Typo.micro)
                            .foregroundStyle(Palette.faintInk)
                    }

                    if let folder = plugin.readFromFolder, !folder.isEmpty {
                        Text("·")
                            .font(Typo.micro)
                            .foregroundStyle(Palette.faintInk)
                        Text("Local development")
                            .font(Typo.micro)
                            .foregroundStyle(Palette.accent)
                    }
                }

                if let path = plugin.installPath, !path.isEmpty, plugin.readFromFolder == nil {
                    Text(path)
                        .font(Typo.monoSmall)
                        .foregroundStyle(Palette.faintInk)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .textSelection(.enabled)
                }
            }

            Spacer(minLength: 8)

            if isUserScope {
                HStack(spacing: 8) {
                    Toggle("", isOn: Binding(
                        get: { plugin.enabled },
                        set: { setEnabled(plugin, enabled: $0) }
                    ))
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .controlSize(.mini)
                    .disabled(model.isMutating)
                    .help(plugin.enabled ? "Disable extension" : "Enable extension")

                    Menu {
                        Button("Update…") { update(plugin) }
                        Button("Show in Finder") { reveal(plugin) }
                            .disabled(plugin.installPath == nil && plugin.readFromFolder == nil)
                        if plugin.hasUserConfig == true {
                            Button("Copy Configure Command") { copyConfigureCommand(plugin) }
                        }
                        Divider()
                        Button("Uninstall…", role: .destructive) {
                            pendingUninstall = plugin
                        }
                    } label: {
                        HStack(spacing: 5) {
                            if model.isBusy("toggle:\(plugin.identity)")
                                || model.isBusy("update:\(plugin.id)") {
                                ProgressView()
                                    .controlSize(.small)
                            } else {
                                Image(systemName: "ellipsis")
                                    .font(.system(size: 9.5, weight: .semibold))
                            }
                        }
                        .foregroundStyle(Palette.tertiaryInk)
                        .frame(width: 24, height: 22)
                        .background(
                            RoundedRectangle(cornerRadius: 7, style: .continuous)
                                .fill(Palette.surface.opacity(0.6))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                                        .strokeBorder(Palette.lineStrong, lineWidth: 0.7)
                                )
                        )
                    }
                    .menuStyle(.borderlessButton)
                    .menuIndicator(.hidden)
                    .fixedSize()
                    .disabled(model.isMutating)
                }
            } else {
                ExtensionBadge(text: "Read only", color: Palette.tertiaryInk)
            }
        }
        .padding(.horizontal, 13)
        .padding(.vertical, 12)
        .surfaceCard(radius: 12)
        .opacity(plugin.enabled ? 1 : 0.78)
    }

    private func scopeTitle(_ plugin: ClaudeInstalledPlugin) -> String {
        switch plugin.knownScope {
        case .user: return "User"
        case .project: return "Project"
        case .local: return "Local"
        case nil: return plugin.scope?.capitalized ?? "Unknown"
        }
    }

    private func setEnabled(_ plugin: ClaudeInstalledPlugin, enabled: Bool) {
        Task { @MainActor in
            do {
                try await model.setEnabled(plugin, enabled: enabled)
            } catch {
                model.errorMessage = model.userMessage(error)
            }
        }
    }

    private func update(_ plugin: ClaudeInstalledPlugin) {
        Task { @MainActor in
            do {
                try await model.update(plugin)
            } catch let error as ClaudePluginError {
                if case .confirmationRequired(let command, let sha256) = error {
                    commandPrompt = ExtensionCommandPrompt(
                        pluginID: plugin.id,
                        kind: .update,
                        command: command,
                        sha256: sha256
                    )
                } else {
                    model.errorMessage = model.userMessage(error)
                }
            } catch {
                model.errorMessage = model.userMessage(error)
            }
        }
    }

    private func uninstall(_ plugin: ClaudeInstalledPlugin) {
        pendingUninstall = nil
        Task { @MainActor in
            do {
                try await model.uninstall(plugin)
            } catch {
                model.errorMessage = model.userMessage(error)
            }
        }
    }

    private func reveal(_ plugin: ClaudeInstalledPlugin) {
        let path = plugin.readFromFolder ?? plugin.installPath
        guard let path, FileManager.default.fileExists(atPath: path) else { return }
        NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)])
    }

    private func copyConfigureCommand(_ plugin: ClaudeInstalledPlugin) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString("claude plugin configure \(plugin.id)", forType: .string)
    }
}
