import AppKit
import SwiftUI
import GantryCore

struct ExtensionsBrowseView: View {
    let model: ExtensionsModel
    var onAddSource: () -> Void = {}

    @Environment(AppModel.self) private var app

    @State private var search = ""
    @State private var marketplaceFilter: String?
    @State private var favoritesOnly = false
    @State private var installTarget: ClaudeAvailablePlugin?
    @State private var commandPrompt: ExtensionCommandPrompt?
    @State private var pendingUninstall: ClaudeInstalledPlugin?

    var body: some View {
        VStack(spacing: 0) {
            controls
                .padding(.horizontal, 28)
                .padding(.bottom, 12)

            if let browseError = model.browseError {
                ExtensionsNotice(
                    icon: "exclamationmark.triangle.fill",
                    title: "Catalog unavailable",
                    message: browseError,
                    tint: Palette.warning
                )
                .padding(.horizontal, 28)
                .padding(.bottom, 10)
            }

            results
        }
        .sheet(item: $installTarget) { plugin in
            ExtensionInstallSheet(
                model: model,
                plugin: plugin,
                marketplace: model.marketplace(named: plugin.marketplaceName),
                onInstalled: { installTarget = nil }
            )
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

    // MARK: - Controls

    private var controls: some View {
        HStack(spacing: 9) {
            ExtensionsSearchField(text: $search, placeholder: "Search extensions and mods")
                .frame(width: 300)

            Menu {
                Button("All Sources") {
                    marketplaceFilter = nil
                }
                if favoritesOnly {
                    Button("Turn Off Favorites Filter") {
                        favoritesOnly = false
                    }
                }
                Divider()
                ForEach(model.marketplaces) { marketplace in
                    Button(marketplace.name) {
                        marketplaceFilter = marketplace.name
                    }
                }
            } label: {
                HStack(spacing: 5) {
                    Image(systemName: "line.3.horizontal.decrease.circle")
                        .font(.system(size: 10, weight: .medium))
                    Text(filterTitle)
                        .font(Typo.micro)
                        .lineLimit(1)
                }
                .foregroundStyle(Palette.secondaryInk)
                .padding(.horizontal, 9)
                .padding(.vertical, 6)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Palette.surface.opacity(0.52))
                        .overlay(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .strokeBorder(Palette.lineStrong, lineWidth: 0.7)
                        )
                )
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()

            Button {
                favoritesOnly.toggle()
            } label: {
                HStack(spacing: 5) {
                    Image(systemName: favoritesOnly ? "star.fill" : "star")
                        .font(.system(size: 10, weight: .medium))
                    Text("Favorites")
                        .font(Typo.micro)
                }
                .foregroundStyle(favoritesOnly ? Palette.accent : Palette.secondaryInk)
                .padding(.horizontal, 9)
                .padding(.vertical, 6)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(favoritesOnly ? Palette.accent.opacity(0.10) : Palette.surface.opacity(0.52))
                        .overlay(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .strokeBorder(
                                    favoritesOnly ? Palette.accent.opacity(0.30) : Palette.lineStrong,
                                    lineWidth: 0.7
                                )
                        )
                )
            }
            .buttonStyle(.plain)
            .help(favoritesOnly ? "Show all sources" : "Show favorites only")

            Spacer()

            Text("\(filteredPlugins.count) of \(model.availablePlugins.count)")
                .font(Typo.micro)
                .foregroundStyle(Palette.faintInk)
        }
    }

    private var filterTitle: String {
        if favoritesOnly, marketplaceFilter == nil {
            return "Favorite sources"
        }
        return marketplaceFilter ?? "All sources"
    }

    private var filteredPlugins: [ClaudeAvailablePlugin] {
        let query = search.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()

        var items = model.availablePlugins
        if !query.isEmpty {
            items = items.filter { plugin in
                plugin.name.lowercased().contains(query)
                    || plugin.marketplaceName.lowercased().contains(query)
                    || (plugin.description ?? "").lowercased().contains(query)
                    || (plugin.source?.displayLocation ?? "").lowercased().contains(query)
            }
        }
        if let marketplaceFilter {
            items = items.filter { $0.marketplaceName == marketplaceFilter }
        }
        if favoritesOnly {
            items = items.filter { isFavorite(marketplaceName: $0.marketplaceName) }
        }

        return items.sorted { lhs, rhs in
            let lhsFavorite = isFavorite(marketplaceName: lhs.marketplaceName)
            let rhsFavorite = isFavorite(marketplaceName: rhs.marketplaceName)
            if lhsFavorite != rhsFavorite {
                return lhsFavorite
            }
            return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
        }
    }

    // MARK: - Results

    @ViewBuilder
    private var results: some View {
        if model.marketplaces.isEmpty {
            ExtensionsEmptyState(
                icon: "tray",
                title: "No sources yet",
                message: "Add a marketplace repository to browse extensions and mods. A source is a git repo with a .claude-plugin/marketplace.json file.",
                actionTitle: "Add a Source"
            ) {
                onAddSource()
            }
        } else if filteredPlugins.isEmpty {
            ExtensionsEmptyState(
                icon: "magnifyingglass",
                title: "No extensions found",
                message: model.availablePlugins.isEmpty
                    ? "This marketplace has no available extensions, or the catalog is still loading."
                    : "Try another search or turn off the favorites filter."
            )
        } else {
            ScrollView {
                LazyVStack(spacing: 8) {
                    ForEach(filteredPlugins) { plugin in
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

    private func pluginRow(_ plugin: ClaudeAvailablePlugin) -> some View {
        let installed = model.installedEntry(for: plugin.pluginId)
        let marketplace = model.marketplace(named: plugin.marketplaceName)

        return HStack(alignment: .top, spacing: 12) {
            ExtensionIconTile(
                symbol: "puzzlepiece.extension",
                tint: tint(for: plugin)
            )
            .padding(.top, 1)

            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 7) {
                    Text(plugin.name)
                        .font(Typo.headline)
                        .foregroundStyle(Palette.ink)
                        .lineLimit(1)

                    if let installed {
                        ExtensionBadge(
                            text: installed.enabled ? "Installed" : "Disabled",
                            color: installed.enabled ? Palette.success : Palette.warning
                        )
                        if !model.isUserScope(installed) {
                            ExtensionBadge(text: "Managed in a project", color: Palette.tertiaryInk)
                        }
                    }
                    if marketplace.map({ model.isFavorite($0) }) == true {
                        Image(systemName: "star.fill")
                            .font(.system(size: 8.5))
                            .foregroundStyle(Palette.accent)
                            .accessibilityLabel("Favorite source")
                    }
                }

                if let description = plugin.description, !description.isEmpty {
                    Text(description)
                        .font(Typo.micro)
                        .foregroundStyle(Palette.secondaryInk)
                        .lineLimit(3)
                        .fixedSize(horizontal: false, vertical: true)
                }

                HStack(spacing: 6) {
                    Text(plugin.marketplaceName)
                        .font(Typo.micro)
                        .foregroundStyle(Palette.tertiaryInk)
                        .lineLimit(1)

                    if let version = installed?.version {
                        Text("· v\(version)")
                            .font(Typo.micro)
                            .foregroundStyle(Palette.faintInk)
                    }

                    if let source = plugin.source?.displayLocation, !source.isEmpty {
                        Text("·")
                            .font(Typo.micro)
                            .foregroundStyle(Palette.faintInk)
                        Text(source)
                            .font(Typo.monoSmall)
                            .foregroundStyle(Palette.faintInk)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                }
            }

            Spacer(minLength: 8)

            trailingActions(plugin: plugin, installed: installed, marketplace: marketplace)
                .padding(.top, 1)
        }
        .padding(.horizontal, 13)
        .padding(.vertical, 12)
        .surfaceCard(radius: 12)
    }

    @ViewBuilder
    private func trailingActions(
        plugin: ClaudeAvailablePlugin,
        installed: ClaudeInstalledPlugin?,
        marketplace: ClaudeMarketplace?
    ) -> some View {
        if let installed {
            if model.isUserScope(installed) {
                Menu {
                    if installed.enabled {
                        Button("Disable") { setEnabled(installed, enabled: false) }
                    } else {
                        Button("Enable") { setEnabled(installed, enabled: true) }
                    }
                    Button("Update…") { update(installed) }
                    Divider()
                    Button("Uninstall…", role: .destructive) {
                        pendingUninstall = installed
                    }
                } label: {
                    HStack(spacing: 5) {
                        if model.isBusy("toggle:\(installed.identity)")
                            || model.isBusy("update:\(installed.id)") {
                            ProgressView()
                                .controlSize(.small)
                        } else {
                            Text("Manage")
                                .font(Typo.micro)
                            Image(systemName: "ellipsis")
                                .font(.system(size: 9, weight: .semibold))
                        }
                    }
                    .foregroundStyle(Palette.secondaryInk)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 5.5)
                    .background(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(Palette.surface.opacity(0.6))
                            .overlay(
                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .strokeBorder(Palette.lineStrong, lineWidth: 0.7)
                            )
                    )
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .fixedSize()
                .disabled(model.isMutating)
            } else {
                ExtensionBadge(text: "Read only", color: Palette.tertiaryInk)
            }
        } else {
            HStack(spacing: 6) {
                if let marketplace, !model.isFavorite(marketplace) {
                    Button {
                        app.toggleFavoriteMarketplace(
                            name: marketplace.name,
                            sourceKey: marketplace.stableKey
                        )
                    } label: {
                        Image(systemName: "star")
                            .font(.system(size: 10.5, weight: .medium))
                            .foregroundStyle(Palette.tertiaryInk)
                            .frame(width: 22, height: 22)
                    }
                    .buttonStyle(.plain)
                    .help("Favorite \(marketplace.name)")
                    .accessibilityLabel("Favorite \(marketplace.name)")
                }

                ExtensionsPillButton(
                    title: "Install",
                    systemName: "arrow.down.circle",
                    isBusy: model.isBusy("install:\(plugin.pluginId)")
                ) {
                    installTarget = plugin
                }
                .disabled(model.isMutating)
            }
        }
    }

    // MARK: - Actions

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

    // MARK: - Presentation

    private func isFavorite(marketplaceName: String) -> Bool {
        guard let marketplace = model.marketplace(named: marketplaceName) else { return false }
        return model.isFavorite(marketplace)
    }

    private func tint(for plugin: ClaudeAvailablePlugin) -> Color {
        let colors = [Palette.accent, Palette.info, Palette.success, Palette.warning]
        let sum = plugin.marketplaceName.unicodeScalars.reduce(0) { $0 + Int($1.value) }
        return colors[sum % colors.count]
    }
}
