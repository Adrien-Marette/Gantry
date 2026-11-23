import AppKit
import SwiftUI
import GantryCore

struct PluginsSettingsView: View {
    @Environment(AppModel.self) private var app

    @State private var editingKind: PluginKind?
    @State private var pluginToDelete: PluginConnection?
    @State private var errorMessage: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                settingsIntro("Connect code-host integrations so Gantry can browse pull requests, post comments, and read CI checks for your projects. Extensions and mods for Claude Code live on the Extensions page.")

                if app.plugins.isEmpty {
                    emptyPlugins
                } else {
                    connectedPlugins
                }

                keychainNote

                if let errorMessage {
                    errorNotice(errorMessage)
                }
            }
            .padding(26)
        }
        .sheet(item: $editingKind) { kind in
            PluginConnectionEditor(kind: kind)
        }
        .alert(
            "Remove code host?",
            isPresented: Binding(
                get: { pluginToDelete != nil },
                set: { if !$0 { pluginToDelete = nil } }
            ),
            presenting: pluginToDelete
        ) { plugin in
            Button("Remove", role: .destructive) {
                remove(plugin)
            }
            Button("Cancel", role: .cancel) { pluginToDelete = nil }
        } message: { plugin in
            Text("“\(plugin.name)” and its saved access token will be removed. Projects using it will use another matching code host if one is available.")
        }
    }

    private var emptyPlugins: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionLabel(title: "Built-in code hosts")

            VStack(spacing: 0) {
                ForEach(Array(PluginKind.allCases.enumerated()), id: \.element.id) { index, kind in
                    HStack(spacing: 11) {
                        pluginIcon(kind)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(kind.title)
                                .font(Typo.captionMedium)
                                .foregroundStyle(Palette.ink)
                            Text(pluginDescription(kind))
                                .font(Typo.micro)
                                .foregroundStyle(Palette.tertiaryInk)
                                .lineLimit(2)
                        }
                        Spacer(minLength: 8)
                        Button("Connect…") {
                            editingKind = kind
                        }
                        .font(Typo.caption)
                    }
                    .padding(.horizontal, 13)
                    .padding(.vertical, 11)
                    if index < PluginKind.allCases.count - 1 {
                        settingsDivider
                    }
                }
            }
            .surfaceCard(radius: 12)
        }
    }

    private var connectedPlugins: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                SectionLabel(title: "Connected code hosts")
                Spacer()
                addPluginMenu
            }

            VStack(spacing: 0) {
                ForEach(Array(app.plugins.enumerated()), id: \.element.id) { index, plugin in
                    pluginRow(plugin)
                    if index < app.plugins.count - 1 {
                        settingsDivider
                    }
                }

                settingsDivider
                addPluginMenuRow
            }
            .surfaceCard(radius: 12)
        }
    }

    private func pluginRow(_ plugin: PluginConnection) -> some View {
        HStack(spacing: 11) {
            pluginIcon(plugin.kind)

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(plugin.name)
                        .font(Typo.captionMedium)
                        .foregroundStyle(Palette.ink)
                        .lineLimit(1)
                    Text("Connected")
                        .font(.system(size: 8, weight: .semibold))
                        .foregroundStyle(Palette.success)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1.5)
                        .background(
                            Capsule(style: .continuous)
                                .fill(Palette.success.opacity(0.09))
                        )
                }

                Text(PluginPresentation.summary(for: plugin))
                    .font(Typo.micro)
                    .foregroundStyle(Palette.tertiaryInk)
                    .lineLimit(1)

                Text(plugin.capabilities.map(\.title).joined(separator: " · "))
                    .font(Typo.micro)
                    .foregroundStyle(Palette.faintInk)
                    .lineLimit(1)
            }

            Spacer(minLength: 8)

            Menu {
                Button("Open \(plugin.kind.title)…") {
                    if let url = plugin.serverBaseURL {
                        NSWorkspace.shared.open(url)
                    }
                }
                Divider()
                Button("Remove Code Host…", role: .destructive) {
                    pluginToDelete = plugin
                }
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(Palette.tertiaryInk)
                    .frame(width: 20, height: 20)
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .frame(width: 20)
        }
        .padding(.horizontal, 13)
        .padding(.vertical, 11)
    }

    private var addPluginMenu: some View {
        Menu {
            pluginAddButtons
        } label: {
            Label("Add", systemImage: "plus")
                .font(Typo.micro)
                .foregroundStyle(Palette.accent)
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
    }

    private var addPluginMenuRow: some View {
        Menu {
            pluginAddButtons
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "plus")
                    .font(.system(size: 10.5, weight: .semibold))
                    .foregroundStyle(Palette.accent)
                    .frame(width: 23, height: 23)
                    .background(Circle().fill(Palette.accent.opacity(0.09)))
                Text("Add Another Account")
                    .font(Typo.captionMedium)
                    .foregroundStyle(Palette.secondaryInk)
                Spacer()
            }
            .padding(.horizontal, 13)
            .padding(.vertical, 9)
            .contentShape(Rectangle())
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
    }

    @ViewBuilder
    private var pluginAddButtons: some View {
        ForEach(PluginKind.allCases) { kind in
            Button {
                editingKind = kind
            } label: {
                Label(kind.title, systemImage: PluginPresentation.symbol(for: kind))
            }
        }
    }

    private func pluginIcon(_ kind: PluginKind) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(PluginPresentation.tint(for: kind).opacity(0.10))
            Image(systemName: PluginPresentation.symbol(for: kind))
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(PluginPresentation.tint(for: kind))
        }
        .frame(width: 32, height: 32)
    }

    private var keychainNote: some View {
        HStack(alignment: .top, spacing: 9) {
            Image(systemName: "key.fill")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(Palette.accent)
                .padding(.top, 1)
            VStack(alignment: .leading, spacing: 5) {
                Text("Access tokens live in Apple Keychain.")
                    .font(Typo.captionMedium)
                    .foregroundStyle(Palette.secondaryInk)
                Text("Gantry stores one token per code host as a Keychain internet password. Tokens are sent only to the code host you configure and never go into session files or logs. When a project's origin matches, Claude Code gets scoped MCP tools that call back into Gantry; it never receives the token. Use the narrowest scopes that let the integration do its job.")
                    .font(Typo.micro)
                    .foregroundStyle(Palette.faintInk)
                    .fixedSize(horizontal: false, vertical: true)
                Button("Open Apple Passwords") {
                    openPasswords()
                }
                .buttonStyle(.plain)
                .font(Typo.micro)
                .foregroundStyle(Palette.accent)
                .padding(.top, 1)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .surfaceCard(radius: 12)
    }

    private func errorNotice(_ message: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "exclamationmark.circle.fill")
                .font(.system(size: 11))
                .foregroundStyle(Palette.danger)
                .padding(.top, 1)
            Text(message)
                .font(Typo.micro)
                .foregroundStyle(Palette.danger)
                .fixedSize(horizontal: false, vertical: true)
            Spacer()
            Button {
                errorMessage = nil
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 8, weight: .semibold))
                    .foregroundStyle(Palette.tertiaryInk)
            }
            .buttonStyle(.plain)
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(Palette.danger.opacity(0.06))
                .overlay(
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .strokeBorder(Palette.danger.opacity(0.20), lineWidth: 0.7)
                )
        )
    }

    private func remove(_ plugin: PluginConnection) {
        pluginToDelete = nil
        Task { @MainActor in
            do {
                try await app.deletePlugin(plugin)
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    private func pluginDescription(_ kind: PluginKind) -> String {
        switch kind {
        case .github:
            return "GitHub.com or GitHub Enterprise. Pull requests, comments, and checks."
        case .gitlab:
            return "GitLab.com or a self-hosted instance. Merge requests, notes, and pipelines."
        case .gitea:
            return "Gitea or Forgejo. Pull requests, comments, and commit statuses."
        }
    }

    private func openPasswords() {
        let url = URL(fileURLWithPath: "/System/Applications/Passwords.app")
        if FileManager.default.fileExists(atPath: url.path) {
            NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
        } else if let settingsURL = URL(string: "x-apple.systempreferences:com.apple.Passwords-Settings.extension") {
            NSWorkspace.shared.open(settingsURL)
        }
    }
}

// MARK: - Editor

private struct PluginConnectionEditor: View {
    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss

    let kind: PluginKind

    @State private var serverURL: String
    @State private var displayName = ""
    @State private var token = ""
    @State private var isWorking = false
    @State private var errorMessage: String?
    @FocusState private var tokenFocused: Bool

    init(kind: PluginKind) {
        self.kind = kind
        _serverURL = State(initialValue: kind.defaultServerURL)
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Hairline()

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    fieldSection(
                        title: "Server",
                        hint: "Use the web address of the instance. API paths are added automatically."
                    ) {
                        TextField("https://github.com", text: $serverURL)
                            .textFieldStyle(.plain)
                            .font(Typo.body)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 8)
                            .background(fieldBackground)
                    }

                    fieldSection(
                        title: "Display name",
                        hint: "Optional. Defaults to the account name from \(kind.title)."
                    ) {
                        TextField("Personal account", text: $displayName)
                            .textFieldStyle(.plain)
                            .font(Typo.body)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 8)
                            .background(fieldBackground)
                    }

                    fieldSection(
                        title: "Access token",
                        hint: kind.tokenScopeHint
                    ) {
                        SecureField("Paste access token", text: $token)
                            .textFieldStyle(.plain)
                            .font(Typo.body)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 8)
                            .background(fieldBackground)
                            .focused($tokenFocused)
                    }

                    Button {
                        if let url = tokenPageURL {
                            NSWorkspace.shared.open(url)
                        }
                    } label: {
                        Label("Create a token on \(kind.title)…", systemImage: "arrow.up.right.square")
                            .font(Typo.micro)
                            .foregroundStyle(Palette.accent)
                    }
                    .buttonStyle(.plain)
                    .disabled(tokenPageURL == nil)

                    HStack(alignment: .top, spacing: 8) {
                        Image(systemName: "lock.shield")
                            .font(.system(size: 10))
                            .foregroundStyle(Palette.tertiaryInk)
                            .padding(.top, 1)
                        Text("The token is verified against \(kind.title) before it is saved, then stored in the macOS Keychain. Gantry never writes it to its session data or logs.")
                            .font(Typo.micro)
                            .foregroundStyle(Palette.faintInk)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    if let errorMessage {
                        HStack(alignment: .top, spacing: 8) {
                            Image(systemName: "exclamationmark.circle.fill")
                                .font(.system(size: 11))
                                .foregroundStyle(Palette.danger)
                                .padding(.top, 1)
                            Text(errorMessage)
                                .font(Typo.micro)
                                .foregroundStyle(Palette.danger)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .padding(10)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(
                            RoundedRectangle(cornerRadius: 9, style: .continuous)
                                .fill(Palette.danger.opacity(0.06))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                                        .strokeBorder(Palette.danger.opacity(0.20), lineWidth: 0.7)
                                )
                        )
                    }
                }
                .padding(22)
            }

            Hairline()
            footer
        }
        .frame(width: 560, height: 520)
        .background(Palette.canvasGradient)
        .interactiveDismissDisabled(isWorking)
        .task { tokenFocused = true }
    }

    private var header: some View {
        HStack(spacing: 11) {
            ZStack {
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(PluginPresentation.tint(for: kind).opacity(0.11))
                Image(systemName: PluginPresentation.symbol(for: kind))
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(PluginPresentation.tint(for: kind))
            }
            .frame(width: 34, height: 34)

            VStack(alignment: .leading, spacing: 2) {
                Text("Connect \(kind.title)")
                    .font(Typo.sectionTitle)
                    .foregroundStyle(Palette.ink)
                Text("Built-in code host · \(kind.pullRequestTermPlural.capitalized)")
                    .font(Typo.micro)
                    .foregroundStyle(Palette.tertiaryInk)
            }

            Spacer()

            IconButton(systemName: "xmark", help: "Close", size: 10, frame: 24) {
                dismiss()
            }
            .disabled(isWorking)
        }
        .padding(.horizontal, 22)
        .padding(.top, 18)
        .padding(.bottom, 14)
    }

    private var footer: some View {
        HStack(spacing: 9) {
            Text("Gantry uses this account only for actions you start from a repository panel.")
                .font(Typo.micro)
                .foregroundStyle(Palette.faintInk)
                .lineLimit(2)
            Spacer()
            Button("Cancel") {
                dismiss()
            }
            .font(Typo.caption)
            .disabled(isWorking)

            Button {
                connect()
            } label: {
                HStack(spacing: 5) {
                    if isWorking {
                        ProgressView().controlSize(.small)
                    }
                    Text(isWorking ? "Verifying…" : "Verify & Connect")
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
            .disabled(isWorking || token.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
        .padding(.horizontal, 22)
        .padding(.vertical, 14)
    }

    private var tokenPageURL: URL? {
        let server = PluginKind.normalizedServerURL(serverURL)
            ?? PluginKind.normalizedServerURL(kind.defaultServerURL)
        guard let server else { return nil }
        return kind.tokenPageURL(serverURL: server)
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
        RoundedRectangle(cornerRadius: 8, style: .continuous)
            .fill(Palette.surfaceSubtle)
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(Palette.line, lineWidth: 0.7)
            )
    }

    private func connect() {
        errorMessage = nil
        isWorking = true
        let server = serverURL
        let displayName = displayName
        let token = token
        Task { @MainActor in
            do {
                try await app.connectPlugin(
                    kind: kind,
                    serverURL: server,
                    displayName: displayName,
                    token: token
                )
                dismiss()
            } catch {
                errorMessage = error.localizedDescription
                isWorking = false
            }
        }
    }
}
