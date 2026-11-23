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
        HStack(spacing: 13) {
            IconButton(systemName: "chevron.left", help: "Back to workspace", frame: 27) {
                app.hideExtensions()
            }

            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Palette.accent.opacity(0.12))
                Image(systemName: "puzzlepiece.extension")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(Palette.accent)
            }
            .frame(width: 38, height: 38)

            VStack(alignment: .leading, spacing: 3) {
                Text("Extensions & Mods")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(Palette.ink)
                Text("Skills, commands, agents, hooks, MCP bundles, and UI mods for Claude Code.")
                    .font(Typo.caption)
                    .foregroundStyle(Palette.secondaryInk)
                    .lineLimit(1)
            }

            Spacer(minLength: 12)

            if model.isRefreshing {
                ProgressView()
                    .controlSize(.small)
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
        .padding(.horizontal, 28)
        .padding(.vertical, 18)
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
            .frame(width: 410)

            Spacer()

            if let lastLoadedAt = model.lastLoadedAt {
                Text("Updated \(Format.relativeTime(lastLoadedAt))")
                    .font(Typo.micro)
                    .foregroundStyle(Palette.faintInk)
            }
        }
        .padding(.horizontal, 28)
        .padding(.bottom, 14)
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

    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 5.5) {
                if isBusy {
                    ProgressView()
                        .controlSize(.small)
                } else if let systemName {
                    Image(systemName: systemName)
                        .font(.system(size: 10, weight: .semibold))
                }
                Text(title)
                    .font(Typo.captionMedium)
            }
            .foregroundStyle(prominent ? Palette.onAccent : Palette.secondaryInk)
            .padding(.horizontal, 11)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(
                        prominent
                            ? tint
                            : Palette.surface.opacity(isHovering ? 0.82 : 0.52)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .strokeBorder(
                                prominent ? Color.clear : Palette.lineStrong,
                                lineWidth: 0.7
                            )
                    )
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(isBusy)
        .onHover { isHovering = $0 }
        .accessibilityLabel(title)
    }
}

struct ExtensionIconTile: View {
    var symbol: String
    var tint: Color = Palette.accent
    var size: CGFloat = 32

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.27, style: .continuous)
                .fill(tint.opacity(0.11))
            Image(systemName: symbol)
                .font(.system(size: size * 0.38, weight: .medium))
                .foregroundStyle(tint)
        }
        .frame(width: size, height: size)
    }
}

struct ExtensionBadge: View {
    var text: String
    var color: Color

    var body: some View {
        Text(text)
            .font(.system(size: 8.5, weight: .semibold))
            .foregroundStyle(color)
            .padding(.horizontal, 5.5)
            .padding(.vertical, 1.5)
            .background(
                Capsule(style: .continuous)
                    .fill(color.opacity(0.10))
            )
    }
}

struct ExtensionsSearchField: View {
    @Binding var text: String
    var placeholder: String

    @FocusState private var focused: Bool

    var body: some View {
        HStack(spacing: 7) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(Palette.tertiaryInk)

            TextField(placeholder, text: $text)
                .textFieldStyle(.plain)
                .font(Typo.ui)
                .foregroundStyle(Palette.ink)
                .focused($focused)

            if !text.isEmpty {
                Button {
                    text = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 10.5))
                        .foregroundStyle(Palette.tertiaryInk)
                }
                .buttonStyle(.plain)
                .help("Clear search")
            }
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Palette.ink.opacity(0.045))
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .strokeBorder(
                            focused ? Palette.accent.opacity(0.35) : Palette.line,
                            lineWidth: 0.7
                        )
                )
        )
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
        VStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 24, weight: .light))
                .foregroundStyle(Palette.faintInk)

            Text(title)
                .font(Typo.sectionTitle)
                .foregroundStyle(Palette.ink)

            Text(message)
                .font(Typo.caption)
                .foregroundStyle(Palette.secondaryInk)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: 430)

            if let actionTitle, let action {
                ExtensionsPillButton(title: actionTitle, prominent: true, action: action)
                    .padding(.top, 4)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(28)
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
