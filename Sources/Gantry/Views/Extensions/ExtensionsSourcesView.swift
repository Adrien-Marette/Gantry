import AppKit
import SwiftUI
import GantryCore

struct ExtensionsSourcesView: View {
    let model: ExtensionsModel
    var onAddSource: () -> Void = {}

    @Environment(AppModel.self) private var app

    @State private var pendingRemove: ClaudeMarketplace?

    var body: some View {
        VStack(spacing: 0) {
            controls
                .padding(.horizontal, 32)
                .padding(.bottom, 12)

            if model.marketplaces.isEmpty {
                ExtensionsEmptyState(
                    icon: "tray",
                    title: "No sources yet",
                    message: "Add a marketplace repository to browse its extensions. The repo must contain a .claude-plugin/marketplace.json file.",
                    actionTitle: "Add a Source"
                ) {
                    onAddSource()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 8) {
                        ForEach(sortedMarketplaces) { marketplace in
                            marketplaceRow(marketplace)
                        }
                    }
                    .frame(maxWidth: 980)
                    .frame(maxWidth: .infinity)
                    .padding(.horizontal, 32)
                    .padding(.bottom, 24)
                }
                .scrollIndicators(.never)
            }
        }
        .alert(
            "Remove source?",
            isPresented: Binding(
                get: { pendingRemove != nil },
                set: { if !$0 { pendingRemove = nil } }
            ),
            presenting: pendingRemove
        ) { marketplace in
            Button("Remove Source", role: .destructive) {
                remove(marketplace)
            }
            Button("Cancel", role: .cancel) { pendingRemove = nil }
        } message: { marketplace in
            Text("“\(marketplace.name)” will be removed from Claude Code's marketplace list. Claude Code decides what happens to extensions installed from it. Favorite entries for this source are removed.")
        }
    }

    private var controls: some View {
        HStack(spacing: 9) {
            Text("\(model.marketplaces.count) source\(model.marketplaces.count == 1 ? "" : "s")")
                .font(Typo.caption)
                .foregroundStyle(Palette.secondaryInk)

            Spacer()

            ExtensionsPillButton(
                title: "Add Source",
                systemName: "plus",
                prominent: false
            ) {
                onAddSource()
            }

            ExtensionsPillButton(
                title: "Refresh All",
                systemName: "arrow.clockwise",
                isBusy: model.isBusy("marketplace-refresh")
            ) {
                refreshAll()
            }
            .disabled(model.isMutating)
        }
    }

    private var sortedMarketplaces: [ClaudeMarketplace] {
        model.marketplaces.sorted { lhs, rhs in
            let lhsFavorite = model.isFavorite(lhs)
            let rhsFavorite = model.isFavorite(rhs)
            if lhsFavorite != rhsFavorite {
                return lhsFavorite
            }
            return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
        }
    }

    private func marketplaceRow(_ marketplace: ClaudeMarketplace) -> some View {
        let isFavorite = model.isFavorite(marketplace)
        let count = model.availableCount(for: marketplace)
        let busyKey = "marketplace:\(marketplace.name)"

        return HStack(alignment: .top, spacing: 12) {
            Button {
                app.toggleFavoriteMarketplace(
                    name: marketplace.name,
                    sourceKey: marketplace.stableKey
                )
            } label: {
                Image(systemName: isFavorite ? "star.fill" : "star")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(isFavorite ? Palette.accent : Palette.tertiaryInk)
                    .frame(width: 24, height: 24)
            }
            .buttonStyle(.plain)
            .help(isFavorite ? "Remove from favorites" : "Add to favorites")
            .accessibilityLabel(isFavorite ? "Unfavorite \(marketplace.name)" : "Favorite \(marketplace.name)")

            ExtensionIconTile(
                symbol: "shippingbox",
                size: 32
            )
            .padding(.top, 1)

            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    Text(marketplace.name)
                        .font(Typo.headline)
                        .foregroundStyle(Palette.ink)
                        .lineLimit(1)

                    if isFavorite {
                        ExtensionBadge(text: "Favorite", color: Palette.tertiaryInk)
                    }
                }

                Text(marketplace.displayLocation)
                    .font(Typo.monoSmall)
                    .foregroundStyle(Palette.tertiaryInk)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .textSelection(.enabled)

                Text("\(count) extension\(count == 1 ? "" : "s") available")
                    .font(Typo.micro)
                    .monospacedDigit()
                    .foregroundStyle(Palette.tertiaryInk)
            }

            Spacer(minLength: 8)

            Menu {
                Button("Update Source") { update(marketplace) }
                Divider()
                Button("Remove Source…", role: .destructive) {
                    pendingRemove = marketplace
                }
            } label: {
                HStack(spacing: 5) {
                    if model.isBusy(busyKey) {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        Image(systemName: "ellipsis")
                            .font(.system(size: 11, weight: .medium))
                    }
                }
                .foregroundStyle(Palette.tertiaryInk)
                .frame(width: 24, height: 24)
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .disabled(model.isMutating)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .surfaceCard(radius: Radius.card)
    }

    private func refreshAll() {
        Task { @MainActor in
            do {
                try await model.refreshMarketplaces()
            } catch {
                model.errorMessage = model.userMessage(error)
            }
        }
    }

    private func update(_ marketplace: ClaudeMarketplace) {
        Task { @MainActor in
            do {
                try await model.refreshMarketplaces(name: marketplace.name)
            } catch {
                model.errorMessage = model.userMessage(error)
            }
        }
    }

    private func remove(_ marketplace: ClaudeMarketplace) {
        pendingRemove = nil
        Task { @MainActor in
            do {
                try await model.removeMarketplace(marketplace)
            } catch {
                model.errorMessage = model.userMessage(error)
            }
        }
    }
}

// MARK: - Add source

struct AddMarketplaceSheet: View {
    let model: ExtensionsModel

    @Environment(\.dismiss) private var dismiss
    @FocusState private var sourceFocused: Bool

    @State private var source = ""
    @State private var favorite = true
    @State private var isWorking = false
    @State private var errorMessage: String?

    var body: some View {
        VStack(spacing: 0) {
            header
            Hairline()

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    fieldSection(
                        title: "Marketplace source",
                        hint: "Use owner/repo, a git or HTTPS URL, or a local path. The repo must contain .claude-plugin/marketplace.json, not just a single plugin folder."
                    ) {
                        TextField("owner/repo", text: $source)
                            .textFieldStyle(.plain)
                            .font(Typo.body)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 8)
                            .background(fieldBackground)
                            .focused($sourceFocused)
                            .onSubmit { add() }
                    }

                    Toggle(isOn: $favorite) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Add to favorites")
                                .font(Typo.captionMedium)
                                .foregroundStyle(Palette.ink)
                            Text("Favorites sort first in Browse and Sources.")
                                .font(Typo.micro)
                                .foregroundStyle(Palette.faintInk)
                        }
                    }
                    .toggleStyle(.switch)
                    .controlSize(.small)

                    HStack(alignment: .top, spacing: 8) {
                        Image(systemName: "lock.shield")
                            .font(.system(size: 10))
                            .foregroundStyle(Palette.tertiaryInk)
                            .padding(.top, 1)
                        Text("Adding a source only configures a marketplace. Extensions are not installed until you choose one and confirm its trust sheet.")
                            .font(Typo.micro)
                            .foregroundStyle(Palette.faintInk)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    if let errorMessage {
                        ExtensionsNotice(
                            icon: "exclamationmark.circle.fill",
                            title: "Couldn't add source",
                            message: errorMessage,
                            tint: Palette.danger
                        )
                    }
                }
                .padding(24)
            }

            Hairline()
            footer
        }
        .frame(width: 560, height: 440)
        .interactiveDismissDisabled(isWorking)
        .task { sourceFocused = true }
    }

    private var header: some View {
        HStack(spacing: 12) {
            ExtensionIconTile(symbol: "shippingbox", size: 32)

            VStack(alignment: .leading, spacing: 2) {
                Text("Add Marketplace Source")
                    .font(Typo.sectionTitle)
                    .foregroundStyle(Palette.ink)
                Text("Repositories that publish Claude Code extensions and mods")
                    .font(Typo.micro)
                    .foregroundStyle(Palette.tertiaryInk)
            }

            Spacer()

            IconButton(systemName: "xmark", help: "Close", size: 11, frame: 28) {
                dismiss()
            }
            .disabled(isWorking)
        }
        .padding(.horizontal, 24)
        .padding(.top, 20)
        .padding(.bottom, 16)
    }

    private var footer: some View {
        HStack(spacing: 9) {
            Text("The source URL is added to your Claude Code marketplace list.")
                .font(Typo.micro)
                .foregroundStyle(Palette.faintInk)
                .lineLimit(2)

            Spacer()

            Button("Cancel") {
                dismiss()
            }
            .font(Typo.caption)
            .disabled(isWorking)

            ExtensionsPillButton(
                title: isWorking ? "Adding…" : "Add Source",
                prominent: true,
                isBusy: isWorking
            ) {
                add()
            }
            .disabled(isWorking || source.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 16)
    }

    private func fieldSection<Content: View>(
        title: String,
        hint: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title)
                .font(Typo.captionMedium)
                .foregroundStyle(Palette.ink)
            content()
            Text(hint)
                .font(Typo.micro)
                .foregroundStyle(Palette.faintInk)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var fieldBackground: some View {
        FieldBackground()
    }

    private func add() {
        let trimmed = source.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !isWorking else { return }
        do {
            _ = try ClaudeMarketplaceSource.sanitized(trimmed)
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            return
        }

        errorMessage = nil
        isWorking = true
        Task { @MainActor in
            do {
                _ = try await model.addMarketplace(source: trimmed, favorite: favorite)
                dismiss()
            } catch {
                errorMessage = model.userMessage(error)
                isWorking = false
            }
        }
    }
}
