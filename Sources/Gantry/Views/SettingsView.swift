import AppKit
import SwiftUI
import GantryCore

struct SettingsView: View {
    private enum Tab: String, Hashable {
        case general, plugins, providers, claude, about
    }

    @Environment(AppModel.self) private var app
    @State private var selectedTab: Tab = .general

    var body: some View {
        TabView(selection: $selectedTab) {
            GeneralSettingsView()
                .tabItem { Label("General", systemImage: "gearshape") }
                .tag(Tab.general)

            PluginsSettingsView()
                .tabItem { Label("Code Hosts", systemImage: "puzzlepiece") }
                .tag(Tab.plugins)

            ProvidersSettingsView()
                .tabItem { Label("Providers", systemImage: "server.rack") }
                .tag(Tab.providers)

            ClaudeSettingsView()
                .tabItem { Label("Claude Code", systemImage: "terminal") }
                .tag(Tab.claude)

            AboutSettingsView()
                .tabItem { Label("About", systemImage: "info.circle") }
                .tag(Tab.about)
        }
        .frame(width: 620, height: 460)
        .tint(Palette.accent)
        .preferredColorScheme(app.appearance.colorScheme)
        .onAppear { consumeRequestedTab() }
        .onChange(of: app.requestedSettingsTab) { _, _ in consumeRequestedTab() }
    }

    private func consumeRequestedTab() {
        guard let raw = app.requestedSettingsTab,
              let tab = Tab(rawValue: raw) else { return }
        selectedTab = tab
        app.requestedSettingsTab = nil
    }
}

private struct GeneralSettingsView: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                settingsIntro("Appearance, defaults for new conversations, and where Gantry keeps its data.")

                settingsSection("Appearance") {
                    settingsRow("Theme") {
                        Picker("", selection: Binding(
                            get: { app.appearance },
                            set: { app.setAppearance($0) }
                        )) {
                            ForEach(AppearanceMode.allCases) { mode in
                                Text(mode.title).tag(mode)
                            }
                        }
                        .labelsHidden()
                        .pickerStyle(.segmented)
                        .frame(width: 210)
                        .accessibilityLabel("Appearance")
                    }
                }

                Text("System follows your Mac's appearance.")
                    .font(Typo.micro)
                    .foregroundStyle(Palette.faintInk)
                    .padding(.horizontal, 2)

                settingsSection("New sessions") {
                    settingsRow("Model") {
                        Picker("", selection: Binding(
                            get: { app.settings.defaultModel },
                            set: { app.setDefaultModel($0) }
                        )) {
                            ForEach(ModelChoice.allCases) { model in
                                Text(model.title).tag(model)
                            }
                        }
                        .labelsHidden()
                        .frame(width: 150)
                    }

                    settingsDivider

                    settingsRow("Permission mode") {
                        Picker("", selection: Binding(
                            get: { app.settings.defaultPermissionMode },
                            set: { app.setDefaultPermissionMode($0) }
                        )) {
                            ForEach(PermissionMode.allCases) { mode in
                                Text(mode.title).tag(mode)
                            }
                        }
                        .labelsHidden()
                        .frame(width: 150)
                    }

                    settingsDivider

                    settingsRow("Remember import choice") {
                        Toggle("", isOn: Binding(
                            get: { (app.settings.transcriptImport ?? .ask) != .ask },
                            set: { app.setTranscriptImportPreference($0 ? .always : .ask) }
                        ))
                        .toggleStyle(.switch)
                        .labelsHidden()
                        .accessibilityLabel("Remember whether to import existing Claude Code conversations")
                    }

                    if let remembered = app.settings.transcriptImport, remembered != .ask {
                        settingsDivider

                        settingsRow("Claude Code history") {
                            Picker("", selection: Binding(
                                get: { remembered },
                                set: { app.setTranscriptImportPreference($0) }
                            )) {
                                Text(TranscriptImportPreference.always.title).tag(TranscriptImportPreference.always)
                                Text(TranscriptImportPreference.never.title).tag(TranscriptImportPreference.never)
                            }
                            .labelsHidden()
                            .frame(width: 150)
                            .accessibilityLabel("Import existing Claude Code conversations when opening a project")
                        }
                    }
                }

                Text("Existing sessions keep their own model and permission mode.")
                    .font(Typo.micro)
                    .foregroundStyle(Palette.faintInk)
                    .padding(.horizontal, 2)

                settingsSection("Storage") {
                    settingsRow("Session data") {
                        Button("Show in Finder") {
                            NSWorkspace.shared.activateFileViewerSelecting([app.dataStore.paths.stateFile])
                        }
                        .buttonStyle(.plain)
                        .font(Typo.caption)
                        .foregroundStyle(Palette.accent)
                    }

                    settingsDivider

                    settingsRow("Claude logs") {
                        Button("Open Folder") {
                            try? FileManager.default.createDirectory(
                                at: app.dataStore.paths.logsDirectory,
                                withIntermediateDirectories: true
                            )
                            NSWorkspace.shared.open(app.dataStore.paths.logsDirectory)
                        }
                        .buttonStyle(.plain)
                        .font(Typo.caption)
                        .foregroundStyle(Palette.accent)
                    }
                }

                Text("Gantry stores conversations as plain JSON on this Mac. Your project files are never copied into the app.")
                    .font(Typo.micro)
                    .foregroundStyle(Palette.faintInk)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 2)
            }
            .padding(24)
        }
    }
}

private struct ClaudeSettingsView: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                settingsIntro("Gantry runs the Claude Code you already have. Authentication stays with the CLI.")

                settingsSection("Installation") {
                    HStack(spacing: 12) {
                        Circle()
                            .fill(statusColor)
                            .frame(width: 6, height: 6)

                        VStack(alignment: .leading, spacing: 2) {
                            Text(statusTitle)
                                .font(Typo.captionMedium)
                                .foregroundStyle(Palette.ink)
                            if let path = app.claudeAvailability.path {
                                Text(path)
                                    .font(Typo.monoSmall)
                                    .foregroundStyle(Palette.tertiaryInk)
                                    .lineLimit(2)
                                    .truncationMode(.middle)
                                    .textSelection(.enabled)
                            } else {
                                Text("Install Claude Code or choose its executable below.")
                                    .font(Typo.micro)
                                    .foregroundStyle(Palette.tertiaryInk)
                            }
                        }

                        Spacer(minLength: 8)

                        Button("Rescan") {
                            app.resolveClaude()
                        }
                        .font(Typo.caption)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                }

                settingsSection("Executable") {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(app.settings.claudePathOverride ?? "Automatic detection")
                            .font(Typo.monoSmall)
                            .foregroundStyle(Palette.secondaryInk)
                            .lineLimit(2)
                            .truncationMode(.middle)
                            .textSelection(.enabled)

                        HStack(spacing: 8) {
                            Button("Choose…") {
                                chooseExecutable()
                            }
                            .font(Typo.caption)

                            if app.settings.claudePathOverride != nil {
                                Button("Use Automatic") {
                                    app.setClaudePathOverride(nil)
                                }
                                .font(Typo.caption)
                            }

                            Spacer()
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                }

                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "lock.shield")
                        .font(.system(size: 11))
                        .foregroundStyle(Palette.tertiaryInk)
                        .padding(.top, 1)
                    Text("Permissions are enforced by Claude Code. Ask mode sends approval requests into Gantry instead of a terminal.")
                        .font(Typo.micro)
                        .foregroundStyle(Palette.faintInk)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.horizontal, 2)
            }
            .padding(24)
        }
    }

    private var statusColor: Color {
        switch app.claudeAvailability {
        case .checking: return Palette.warning
        case .ready: return Palette.success
        case .missing, .failed: return Palette.danger
        }
    }

    private var statusTitle: String {
        switch app.claudeAvailability {
        case .checking: return "Looking for Claude Code…"
        case .ready(_, let version):
            if let version {
                return "Ready · \(version.replacingOccurrences(of: " (Claude Code)", with: ""))"
            }
            return "Ready"
        case .missing: return "Not found"
        case .failed(let message): return message
        }
    }

    private func chooseExecutable() {
        let panel = NSOpenPanel()
        panel.title = "Choose the Claude Code executable"
        panel.prompt = "Choose"
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.showsHiddenFiles = true
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            Task { @MainActor in
                app.setClaudePathOverride(url.path)
            }
        }
    }
}

private struct AboutSettingsView: View {
    var body: some View {
        VStack(spacing: 16) {
            Spacer(minLength: 4)
            BrandMark(size: 58)
            VStack(spacing: 4) {
                Text("Gantry")
                    .font(.system(size: 23, weight: .semibold))
                    .foregroundStyle(Palette.ink)
                Text("Version \(AppModel.appVersion)")
                    .font(Typo.micro)
                    .foregroundStyle(Palette.tertiaryInk)
            }

            Text("A native macOS workspace for Claude Code.\nBuilt with SwiftUI and Liquid Glass.")
                .font(Typo.caption)
                .foregroundStyle(Palette.secondaryInk)
                .multilineTextAlignment(.center)
                .lineSpacing(3)

            Text("An unofficial client. Not affiliated with Anthropic.")
                .font(Typo.micro)
                .foregroundStyle(Palette.tertiaryInk)
                .multilineTextAlignment(.center)
                .padding(.top, 4)

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(24)
    }
}

func settingsIntro(_ text: String) -> some View {
    Text(text)
        .font(Typo.caption)
        .foregroundStyle(Palette.secondaryInk)
        .fixedSize(horizontal: false, vertical: true)
        .padding(.bottom, 2)
}

func settingsSection<Content: View>(
    _ title: String,
    @ViewBuilder content: () -> Content
) -> some View {
    VStack(alignment: .leading, spacing: 8) {
        SectionLabel(title: title)
        VStack(spacing: 0) {
            content()
        }
        .surfaceCard(radius: 12)
    }
}

func settingsRow<Content: View>(
    _ title: String,
    @ViewBuilder content: () -> Content
) -> some View {
    HStack(spacing: 12) {
        Text(title)
            .font(Typo.caption)
            .foregroundStyle(Palette.secondaryInk)
        Spacer()
        content()
    }
    .padding(.horizontal, 16)
    .padding(.vertical, 12)
}

var settingsDivider: some View {
    Hairline()
        .padding(.leading, 16)
}
