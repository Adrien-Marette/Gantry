import AppKit
import SwiftUI
import GantryCore

struct ExtensionsView: View {
    enum Section: String, CaseIterable, Identifiable {
        case browse
        case installed
        case sources
        case create

        var id: String { rawValue }

        var title: String {
            switch self {
            case .browse: return "Browse"
            case .installed: return "Installed"
            case .sources: return "Sources"
            case .create: return "Create"
            }
        }
    }

    @Environment(AppModel.self) private var app
    @Environment(\.openSettings) private var openSettings

    @State private var model: ExtensionsModel
    @State private var section: Section = .browse
    @State private var showingAddSource = false

    init(app: AppModel) {
        _model = State(initialValue: ExtensionsModel(app: app))
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Hairline()

            VStack(spacing: 0) {
                sectionPicker

                if let message = model.errorMessage {
                    InlineNotice(
                        icon: "exclamationmark.circle.fill",
                        title: "Something went wrong",
                        message: message,
                        tint: Palette.danger,
                        actionTitle: nil,
                        action: nil,
                        onDismiss: { model.clearError() }
                    )
                    .padding(.horizontal, 28)
                    .padding(.bottom, 10)
                }

                content
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .task(id: app.claudeAvailability.path) {
            if model.loadState == .idle {
                await model.start()
            } else {
                await model.reload()
            }
        }
        .sheet(isPresented: $showingAddSource) {
            AddMarketplaceSheet(model: model)
        }
    }

    private var header: some View {
        HStack(spacing: 12) {
            IconButton(systemName: "chevron.left", help: "Back to workspace", frame: 28) {
                app.hideExtensions()
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("Extensions & Mods")
                    .font(Typo.pageTitle)
                    .foregroundStyle(Palette.ink)
                Text("Skills, commands, agents, hooks, MCP bundles, and UI mods for Claude Code.")
                    .font(Typo.caption)
                    .foregroundStyle(Palette.secondaryInk)
                    .lineLimit(1)
            }

            Spacer(minLength: 12)

            if model.isRefreshing {
                Spinner(size: 14)
            }

            ExtensionsPillButton(
                title: "Add Source",
                systemName: "plus",
                prominent: false
            ) {
                showingAddSource = true
            }

            ExtensionsPillButton(
                title: "Create Mod",
                systemName: "hammer",
                prominent: true
            ) {
                section = .create
            }

            IconButton(systemName: "arrow.clockwise", help: "Reload extensions", frame: 28) {
                Task { await model.reload() }
            }
        }
        .padding(.horizontal, 32)
        .padding(.vertical, 20)
    }

    private var sectionPicker: some View {
        HStack {
            Picker("Section", selection: $section) {
                ForEach(Section.allCases) { section in
                    Text(section.title).tag(section)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(width: 400)

            Spacer()

            if let lastLoadedAt = model.lastLoadedAt {
                Text("Updated \(Format.relativeTime(lastLoadedAt))")
                    .font(Typo.micro)
                    .foregroundStyle(Palette.tertiaryInk)
            }
        }
        .padding(.horizontal, 32)
        .padding(.bottom, 16)
    }

    @ViewBuilder
    private var content: some View {
        if section == .create {
            CreateModView(model: model)
        } else if section != .sources,
           case .failed(let message) = model.loadState,
           model.installedPlugins.isEmpty,
           model.availablePlugins.isEmpty {
            unavailableState(message)
        } else if model.loadState == .loading,
                  (section != .sources || model.marketplaces.isEmpty),
                  model.installedPlugins.isEmpty,
                  model.availablePlugins.isEmpty {
            loadingState
        } else {
            switch section {
            case .browse:
                ExtensionsBrowseView(model: model, onAddSource: { showingAddSource = true })
            case .installed:
                ExtensionsInstalledView(
                    model: model,
                    onBrowse: { section = .browse }
                )
            case .sources:
                ExtensionsSourcesView(
                    model: model,
                    onAddSource: { showingAddSource = true }
                )
            case .create:
                EmptyView()
            }
        }
    }

    private var loadingState: some View {
        VStack(spacing: 10) {
            ProgressView()
                .controlSize(.small)
            Text("Reading your Claude Code plugins…")
                .font(Typo.caption)
                .foregroundStyle(Palette.tertiaryInk)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func unavailableState(_ message: String) -> some View {
        ExtensionsEmptyState(
            icon: "terminal",
            title: "Claude Code needs attention",
            message: message,
            actionTitle: "Open Claude Code Settings"
        ) {
            app.requestedSettingsTab = "claude"
            openSettings()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Shared components

struct ExtensionsPillButton: View {
    var title: String
    var systemName: String?
    var prominent: Bool = false
    var tint: Color = Palette.accent
    var isBusy: Bool = false
    var action: () -> Void

    var body: some View {
        Group {
            if prominent {
                Button(action: action) { label }
                    .buttonStyle(.glassProminent)
                    .tint(tint)
            } else {
                Button(action: action) { label }
                    .buttonStyle(.glass)
            }
        }
        .controlSize(.small)
        .disabled(isBusy)
        .accessibilityLabel(title)
    }

    private var label: some View {
        HStack(spacing: 6) {
            if isBusy {
                ProgressView()
                    .controlSize(.small)
            } else if let systemName {
                Image(systemName: systemName)
                    .font(.system(size: 11, weight: .medium))
            }
            Text(title)
                .font(Typo.captionMedium)
        }
        .foregroundStyle(prominent ? Palette.onAccent : Palette.secondaryInk)
    }
}

struct ExtensionIconTile: View {
    var symbol: String
    var size: CGFloat = 32

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.25, style: .continuous)
                .fill(Palette.ink.opacity(0.04))
            Image(systemName: symbol)
                .font(.system(size: size * 0.38, weight: .medium))
                .foregroundStyle(Palette.secondaryInk)
        }
        .frame(width: size, height: size)
    }
}

struct ExtensionBadge: View {
    var text: String
    var color: Color

    var body: some View {
        HStack(spacing: 4) {
            Circle()
                .fill(color)
                .frame(width: 5, height: 5)
            Text(text)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(color)
                .lineLimit(1)
        }
    }
}

struct ExtensionsSearchField: View {
    @Binding var text: String
    var placeholder: String

    @FocusState private var focused: Bool

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(Palette.tertiaryInk)

            TextField(placeholder, text: $text)
                .textFieldStyle(.plain)
                .font(.system(size: 12))
                .foregroundStyle(Palette.ink)
                .focused($focused)

            if !text.isEmpty {
                Button {
                    text = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 11))
                        .foregroundStyle(Palette.tertiaryInk)
                }
                .buttonStyle(.plain)
                .help("Clear search")
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(FieldBackground(radius: 8, focused: focused))
        .animation(.easeOut(duration: 0.15), value: focused)
    }
}

struct ExtensionsEmptyState: View {
    var icon: String
    var title: String
    var message: String
    var actionTitle: String?
    var action: (() -> Void)?

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 24, weight: .regular))
                .foregroundStyle(Palette.tertiaryInk)

            Text(title)
                .font(Typo.sectionTitle)
                .foregroundStyle(Palette.ink)

            Text(message)
                .font(Typo.caption)
                .foregroundStyle(Palette.secondaryInk)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: 440)

            if let actionTitle, let action {
                ExtensionsPillButton(title: actionTitle, prominent: true, action: action)
                    .padding(.top, 4)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(32)
    }
}

struct ExtensionsNotice: View {
    var icon: String
    var title: String
    var message: String
    var tint: Color
    var onDismiss: (() -> Void)?

    var body: some View {
        InlineNotice(
            icon: icon,
            title: title,
            message: message,
            tint: tint,
            actionTitle: nil,
            action: nil,
            onDismiss: onDismiss
        )
    }
}
