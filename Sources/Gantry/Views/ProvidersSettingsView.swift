import AppKit
import SwiftUI
import GantryCore

struct ProvidersSettingsView: View {
    @Environment(AppModel.self) private var app

    @State private var editingContext: ProviderEditorContext?
    @State private var providerToDelete: AIProvider?
    @State private var keyPresence: [UUID: Bool] = [:]
    @State private var errorMessage: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                settingsIntro("Choose which AI provider Claude Code uses. Switching a session restarts its process and resumes the same conversation.")

                settingsSection("Default for new sessions") {
                    settingsRow("Provider") {
                        Picker("", selection: Binding(
                            get: { app.defaultProviderID },
                            set: { app.setDefaultProvider($0) }
                        )) {
                            ForEach(app.providers) { provider in
                                Text(provider.name).tag(provider.id)
                            }
                        }
                        .labelsHidden()
                        .frame(width: 190)
                    }
                }

                Text("Existing sessions keep the provider they were using. You can change it from the provider menu in any chat.")
                    .font(Typo.micro)
                    .foregroundStyle(Palette.faintInk)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 2)

                VStack(alignment: .leading, spacing: 8) {
                    SectionLabel(title: "AI Providers")

                    VStack(spacing: 0) {
                        ForEach(Array(app.providers.enumerated()), id: \.element.id) { index, provider in
                            providerRow(provider)
                            if index < app.providers.count - 1 {
                                settingsDivider
                            }
                        }

                        settingsDivider

                        addProviderMenu
                    }
                    .surfaceCard(radius: 12)
                }

                keychainNote

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
                        Spacer()
                        Button {
                            self.errorMessage = nil
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
            }
            .padding(26)
        }
        .task(id: app.providers) {
            await refreshKeyPresence()
        }
        .sheet(item: $editingContext, onDismiss: {
            Task { await refreshKeyPresence() }
        }) { context in
            ProviderEditorView(
                provider: context.provider,
                isNew: context.isNew,
                initiallyHasKey: keyPresence[context.provider.id] ?? false
            )
        }
        .alert(
            "Delete provider?",
            isPresented: Binding(
                get: { providerToDelete != nil },
                set: { if !$0 { providerToDelete = nil } }
            ),
            presenting: providerToDelete
        ) { provider in
            Button("Delete", role: .destructive) {
                delete(provider)
            }
            Button("Cancel", role: .cancel) { providerToDelete = nil }
        } message: { provider in
            Text("“\(provider.name)” and its saved API key will be removed. Sessions using it will move to your default provider.")
        }
    }

    private func providerRow(_ provider: AIProvider) -> some View {
        HStack(spacing: 10) {
            Button {
                if !provider.isBuiltIn {
                    editingContext = ProviderEditorContext(provider: provider, isNew: false)
                }
            } label: {
                HStack(spacing: 10) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(ProviderPresentation.tint(for: provider.preset).opacity(0.10))
                        Image(systemName: ProviderPresentation.symbol(for: provider.preset))
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(ProviderPresentation.tint(for: provider.preset))
                    }
                    .frame(width: 30, height: 30)

                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 6) {
                            Text(provider.name)
                                .font(Typo.captionMedium)
                                .foregroundStyle(Palette.ink)
                                .lineLimit(1)
                            if provider.id == app.defaultProviderID {
                                Text("Default")
                                    .font(.system(size: 8, weight: .semibold))
                                    .foregroundStyle(Palette.accent)
                                    .padding(.horizontal, 5)
                                    .padding(.vertical, 1.5)
                                    .background(
                                        Capsule(style: .continuous)
                                            .fill(Palette.accent.opacity(0.09))
                                    )
                            }
                        }

                        HStack(spacing: 5) {
                            Text(provider.isBuiltIn ? ProviderPresentation.summary(for: provider) : provider.displayBaseURL)
                                .font(Typo.micro)
                                .foregroundStyle(Palette.tertiaryInk)
                                .lineLimit(1)
                                .truncationMode(.middle)
                            if !provider.isBuiltIn {
                                Text("·")
                                    .font(Typo.micro)
                                    .foregroundStyle(Palette.faintInk)
                                keyStatus(for: provider)
                            }
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .allowsHitTesting(!provider.isBuiltIn)
            .help(provider.isBuiltIn ? "The built-in Claude Code provider" : "Edit \(provider.name)")

            Spacer(minLength: 4)

            if provider.isBuiltIn {
                Text("Built-in")
                    .font(Typo.micro)
                    .foregroundStyle(Palette.faintInk)
            } else {
                Menu {
                    Button("Edit…") {
                        editingContext = ProviderEditorContext(provider: provider, isNew: false)
                    }
                    Button("Set as Default") {
                        app.setDefaultProvider(provider.id)
                    }
                    .disabled(provider.id == app.defaultProviderID)
                    Divider()
                    Button("Delete…", role: .destructive) {
                        providerToDelete = provider
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
        }
        .padding(.horizontal, 13)
        .padding(.vertical, 9)
    }

    @ViewBuilder
    private func keyStatus(for provider: AIProvider) -> some View {
        if !provider.requiresAPIKey {
            Label("Claude Code login", systemImage: "person.crop.circle")
                .font(Typo.micro)
                .foregroundStyle(Palette.tertiaryInk)
        } else if let hasKey = keyPresence[provider.id] {
            if hasKey {
                Label("Key saved", systemImage: "checkmark.circle")
                    .font(Typo.micro)
                    .foregroundStyle(Palette.success)
            } else {
                Label("Key needed", systemImage: "key.slash")
                    .font(Typo.micro)
                    .foregroundStyle(Palette.warning)
            }
        } else {
            Label("Checking key…", systemImage: "ellipsis")
                .font(Typo.micro)
                .foregroundStyle(Palette.faintInk)
        }
    }

    private var addProviderMenu: some View {
        Menu {
            Button {
                addProvider(preset: .anthropic)
            } label: {
                Label("Anthropic API", systemImage: "sparkles")
            }
            Button {
                addProvider(preset: .deepSeek)
            } label: {
                Label("DeepSeek", systemImage: "server.rack")
            }
            Button {
                addProvider(preset: .custom)
            } label: {
                Label("Custom endpoint", systemImage: "slider.horizontal.3")
            }
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "plus")
                    .font(.system(size: 10.5, weight: .semibold))
                    .foregroundStyle(Palette.accent)
                    .frame(width: 23, height: 23)
                    .background(Circle().fill(Palette.accent.opacity(0.09)))
                Text("Add Provider")
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

    private var keychainNote: some View {
        HStack(alignment: .top, spacing: 9) {
            Image(systemName: "key.fill")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(Palette.accent)
                .padding(.top, 1)
            VStack(alignment: .leading, spacing: 5) {
                Text("API keys live in Apple Keychain.")
                    .font(Typo.captionMedium)
                    .foregroundStyle(Palette.secondaryInk)
                Text("Gantry stores provider keys as internet passwords in the macOS Keychain. They never go into session files or logs. When iCloud Keychain is available, they can appear in Apple Passwords and sync across devices.")
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

    private func addProvider(preset: ProviderPreset) {
        let name = app.uniqueProviderName(basedOn: preset.title)
        let provider = AIProvider.make(preset: preset, name: name)
        editingContext = ProviderEditorContext(provider: provider, isNew: true)
    }

    private func delete(_ provider: AIProvider) {
        providerToDelete = nil
        Task { @MainActor in
            do {
                try await app.deleteProvider(provider)
                await refreshKeyPresence()
            } catch {
                errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            }
        }
    }

    @MainActor
    private func refreshKeyPresence() async {
        var result: [UUID: Bool] = [:]
        for provider in app.providers where provider.requiresAPIKey {
            let provider = provider
            result[provider.id] = await Task.detached(priority: .utility) {
                ProviderKeychain.hasKey(for: provider)
            }.value
        }
        guard !Task.isCancelled else { return }
        keyPresence = result
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

private struct ProviderEditorContext: Identifiable {
    var provider: AIProvider
    var isNew: Bool
    var id: UUID { provider.id }
}

private struct ProviderEditorView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss

    let original: AIProvider
    let isNew: Bool
    let initiallyHasKey: Bool

    @State private var name: String
    @State private var baseURL: String
    @State private var authMode: ProviderAuthMode
    @State private var mainModel: String
    @State private var opusModel: String
    @State private var sonnetModel: String
    @State private var haikuModel: String
    @State private var subagentModel: String
    @State private var extraEnvironmentText: String
    @State private var apiKey = ""
    @State private var removeExistingKey = false
    @State private var keyExists: Bool
    @State private var keyIsSynchronized = false
    @State private var keyIsBeingChecked = false
    @State private var isSaving = false
    @State private var errorMessage: String?

    init(provider: AIProvider, isNew: Bool, initiallyHasKey: Bool) {
        self.original = provider
        self.isNew = isNew
        self.initiallyHasKey = initiallyHasKey
        _name = State(initialValue: provider.name)
        _baseURL = State(initialValue: provider.baseURL)
        _authMode = State(initialValue: provider.authMode)
        _mainModel = State(initialValue: provider.mainModel)
        _opusModel = State(initialValue: provider.opusModel)
        _sonnetModel = State(initialValue: provider.sonnetModel)
        _haikuModel = State(initialValue: provider.haikuModel)
        _subagentModel = State(initialValue: provider.subagentModel)
        _extraEnvironmentText = State(initialValue: provider.extraEnvironment
            .sorted(by: { $0.key < $1.key })
            .map { "\($0.key)=\($0.value)" }
            .joined(separator: "\n"))
        _keyExists = State(initialValue: initiallyHasKey)
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Hairline()
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if let errorMessage {
                        HStack(alignment: .top, spacing: 7) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .font(.system(size: 10.5))
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
                        )
                    }

                    editorSection("Provider") {
                        labeledField("Name", hint: "A name for this provider in the menu.", text: $name)
                        fieldDivider
                        labeledField("Base URL", hint: "An Anthropic-compatible endpoint. Leave blank to use Claude Code's default endpoint.", text: $baseURL)
                        fieldDivider

                        HStack(alignment: .top, spacing: 10) {
                            VStack(alignment: .leading, spacing: 3) {
                                Text("Authentication")
                                    .font(Typo.captionMedium)
                                    .foregroundStyle(Palette.ink)
                                Text(authMode.detail)
                                    .font(Typo.micro)
                                    .foregroundStyle(Palette.tertiaryInk)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            Spacer(minLength: 8)
                            Picker("", selection: $authMode) {
                                ForEach(ProviderAuthMode.allCases, id: \.self) { mode in
                                    Text(mode.title).tag(mode)
                                }
                            }
                            .labelsHidden()
                            .frame(width: 170)
                        }
                        .padding(.vertical, 3)
                    }

                    if authMode != .inherit || keyExists {
                        keySection
                    }

                    modelSection

                    editorSection("Advanced environment") {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Extra environment variables, one KEY=value per line. These are passed only to Claude Code processes using this provider.")
                                .font(Typo.micro)
                                .foregroundStyle(Palette.tertiaryInk)
                                .fixedSize(horizontal: false, vertical: true)
                            TextEditor(text: $extraEnvironmentText)
                                .font(.system(size: 11, weight: .regular, design: .monospaced))
                                .scrollContentBackground(.hidden)
                                .frame(height: 84)
                                .padding(7)
                                .background(
                                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                                        .fill(Palette.codeSurface)
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                                .strokeBorder(Palette.line, lineWidth: 0.7)
                                        )
                                )
                            Text("Use the API key field for secrets. Keys written here are not protected by Keychain.")
                                .font(Typo.micro)
                                .foregroundStyle(Palette.faintInk)
                        }
                    }

                    HStack {
                        Button {
                            importClaudeCodeSettings()
                        } label: {
                            Label("Fill from Claude Code", systemImage: "arrow.down.doc")
                                .font(Typo.micro)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(
                                    Capsule(style: .continuous)
                                        .fill(Palette.ink.opacity(0.045))
                                )
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(Palette.secondaryInk)
                        .help("Fill the base URL and model fields from ~/.claude/settings.json without importing any secret.")

                        Text("Only base URL and model fields are imported.")
                            .font(Typo.micro)
                            .foregroundStyle(Palette.faintInk)
                    }
                }
                .padding(22)
            }
            Hairline()
            footer
        }
        .frame(width: 590, height: 660)
        .background(Palette.canvasGradient)
        .task {
            keyIsBeingChecked = true
            let provider = original
            let hasKey = await Task.detached(priority: .utility) {
                ProviderKeychain.hasKey(for: provider)
            }.value
            keyExists = hasKey
            if hasKey {
                keyIsSynchronized = await Task.detached(priority: .utility) {
                    ProviderKeychain.isSynchronized(for: provider)
                }.value
            }
            keyIsBeingChecked = false
        }
        .onChange(of: apiKey) { _, newValue in
            if !newValue.isEmpty { removeExistingKey = false }
        }
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 11) {
            ZStack {
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(ProviderPresentation.tint(for: original.preset).opacity(0.11))
                Image(systemName: ProviderPresentation.symbol(for: original.preset))
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(ProviderPresentation.tint(for: original.preset))
            }
            .frame(width: 34, height: 34)

            VStack(alignment: .leading, spacing: 2) {
                Text(isNew ? "Add Provider" : "Edit Provider")
                    .font(Typo.sectionTitle)
                    .foregroundStyle(Palette.ink)
                Text(original.preset.title)
                    .font(Typo.micro)
                    .foregroundStyle(Palette.tertiaryInk)
            }

            Spacer()

            IconButton(systemName: "xmark", help: "Close", size: 10, frame: 24) {
                dismiss()
            }
        }
        .padding(.horizontal, 22)
        .padding(.top, 18)
        .padding(.bottom, 14)
    }

    private var keySection: some View {
        editorSection("API key") {
            VStack(alignment: .leading, spacing: 7) {
                HStack(spacing: 6) {
                    Image(systemName: keyExists ? "checkmark.circle.fill" : "key.slash")
                        .font(.system(size: 10))
                        .foregroundStyle(keyExists ? Palette.success : Palette.warning)
                    Text(keyStatusText)
                        .font(Typo.micro)
                        .foregroundStyle(Palette.secondaryInk)
                }

                if authMode != .inherit {
                    SecureField(keyExists ? "Enter a new key to replace the saved one" : "Paste API key", text: $apiKey)
                        .textFieldStyle(.plain)
                        .font(Typo.body)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 8)
                        .background(fieldBackground)

                    Text(keyExists
                         ? "Stored for \(original.keychainServer) · \(original.keychainAccount). The key is not shown again after saving."
                         : "Will be stored as a Keychain internet password for \(original.keychainServer) · \(original.keychainAccount). The key is not shown again after saving.")
                        .font(Typo.micro)
                        .foregroundStyle(Palette.faintInk)
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    Text("This provider uses your existing Claude Code login. Any key saved here is currently unused.")
                        .font(Typo.micro)
                        .foregroundStyle(Palette.tertiaryInk)
                        .fixedSize(horizontal: false, vertical: true)
                }

                if keyExists || removeExistingKey {
                    Button(removeExistingKey ? "Saved key will be removed" : "Remove saved key") {
                        removeExistingKey.toggle()
                        if removeExistingKey { apiKey = "" }
                    }
                    .buttonStyle(.plain)
                    .font(Typo.micro)
                    .foregroundStyle(removeExistingKey ? Palette.danger : Palette.tertiaryInk)
                }
            }
        }
    }

    private var modelSection: some View {
        editorSection("Model aliases") {
            VStack(alignment: .leading, spacing: 10) {
                Text("Optional. These map Gantry's Fable, Opus, Sonnet, and Haiku menu choices onto this provider's model IDs.")
                    .font(Typo.micro)
                    .foregroundStyle(Palette.tertiaryInk)
                    .fixedSize(horizontal: false, vertical: true)

                labeledField("Default model", hint: "Used when the session is set to Automatic.", text: $mainModel)

                LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
                    labeledField("Opus alias", hint: nil, text: $opusModel)
                    labeledField("Sonnet alias", hint: nil, text: $sonnetModel)
                    labeledField("Haiku alias", hint: nil, text: $haikuModel)
                    labeledField("Subagent model", hint: nil, text: $subagentModel)
                }
            }
        }
    }

    private var footer: some View {
        HStack(spacing: 9) {
            Text("Changes apply to sessions using this provider after their current turn.")
                .font(Typo.micro)
                .foregroundStyle(Palette.faintInk)
                .lineLimit(2)
            Spacer()
            Button("Cancel") {
                dismiss()
            }
            .font(Typo.caption)

            Button {
                save()
            } label: {
                HStack(spacing: 5) {
                    if isSaving {
                        ProgressView().controlSize(.small)
                    }
                    Text(isSaving ? "Saving…" : "Save Provider")
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
            .disabled(isSaving)
        }
        .padding(.horizontal, 22)
        .padding(.vertical, 14)
    }

    private var keyStatusText: String {
        if keyIsBeingChecked { return "Checking your Keychain…" }
        if removeExistingKey { return "The saved key will be removed when you save." }
        if keyExists && keyIsSynchronized { return "A key is saved in iCloud Keychain." }
        if keyExists { return "A key is saved in the local login Keychain." }
        if authMode == .inherit { return "No key stored. Claude Code login will be used." }
        return "No key saved yet. Add one before using this provider."
    }

    private var fieldBackground: some View {
        RoundedRectangle(cornerRadius: 8, style: .continuous)
            .fill(Palette.surfaceSubtle)
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(Palette.line, lineWidth: 0.7)
            )
    }

    private func labeledField(_ label: String, hint: String?, text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(Typo.captionMedium)
                .foregroundStyle(Palette.ink)
            TextField("", text: text)
                .textFieldStyle(.plain)
                .font(Typo.body)
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
                .background(fieldBackground)
            if let hint {
                Text(hint)
                    .font(Typo.micro)
                    .foregroundStyle(Palette.faintInk)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func editorSection<Content: View>(
        _ title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionLabel(title: title)
            VStack(alignment: .leading, spacing: 10) {
                content()
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .surfaceCard(radius: 12)
        }
    }

    private var fieldDivider: some View {
        Hairline()
    }

    private func save() {
        errorMessage = nil
        let parsedExtra: [String: String]
        do {
            parsedExtra = try ProviderEnvironmentParser.parse(extraEnvironmentText)
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            return
        }

        var provider = original
        provider.name = name
        provider.baseURL = baseURL
        provider.authMode = authMode
        provider.mainModel = mainModel
        provider.opusModel = opusModel
        provider.sonnetModel = sonnetModel
        provider.haikuModel = haikuModel
        provider.subagentModel = subagentModel
        provider.extraEnvironment = parsedExtra
        if isNew {
            provider.keychainServer = AIProvider.host(from: baseURL)
                ?? (original.keychainServer.isEmpty ? "Gantry.local" : original.keychainServer)
            provider.keychainAccount = "Gantry · \(name.trimmingCharacters(in: .whitespacesAndNewlines))"
        }

        isSaving = true
        let keyToSave = authMode == .inherit ? nil : apiKey
        let shouldRemove = removeExistingKey
        Task { @MainActor in
            do {
                try await app.persistProvider(
                    provider,
                    apiKey: keyToSave,
                    removeExistingKey: shouldRemove
                )
                dismiss()
            } catch {
                errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
                isSaving = false
            }
        }
    }

    private func importClaudeCodeSettings() {
        guard let defaults = ClaudeCodeSettingsDefaults.load() else {
            errorMessage = "No provider settings were found in ~/.claude/settings.json."
            return
        }
        if !defaults.baseURL.isEmpty { baseURL = defaults.baseURL }
        if !defaults.mainModel.isEmpty { mainModel = defaults.mainModel }
        if !defaults.opusModel.isEmpty { opusModel = defaults.opusModel }
        if !defaults.sonnetModel.isEmpty { sonnetModel = defaults.sonnetModel }
        if !defaults.haikuModel.isEmpty { haikuModel = defaults.haikuModel }
        if !defaults.subagentModel.isEmpty { subagentModel = defaults.subagentModel }
        errorMessage = nil
    }
}

private enum ProviderEnvironmentParser {
    static func parse(_ text: String) throws -> [String: String] {
        var result: [String: String] = [:]
        let forbidden: Set<String> = [
            "ANTHROPIC_API_KEY",
            "ANTHROPIC_AUTH_TOKEN",
            "CLAUDE_CODE_OAUTH_TOKEN"
        ]
        for rawLine in text.components(separatedBy: .newlines) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            guard !line.isEmpty, !line.hasPrefix("#") else { continue }
            guard let separator = line.firstIndex(of: "=") else {
                throw ProviderEnvironmentError.invalidLine(rawLine)
            }
            let key = String(line[..<separator]).trimmingCharacters(in: .whitespaces)
            let value = String(line[line.index(after: separator)...]).trimmingCharacters(in: .whitespaces)
            guard !key.isEmpty,
                  key.range(of: #"^[A-Za-z_][A-Za-z0-9_]*$"#, options: .regularExpression) != nil else {
                throw ProviderEnvironmentError.invalidKey(key)
            }
            guard !forbidden.contains(key) else {
                throw ProviderEnvironmentError.secretInAdvancedEnvironment(key)
            }
            result[key] = value
        }
        return result
    }
}

private enum ProviderEnvironmentError: Error, LocalizedError {
    case invalidLine(String)
    case invalidKey(String)
    case secretInAdvancedEnvironment(String)

    var errorDescription: String? {
        switch self {
        case .invalidLine(let line):
            return "Environment line “\(line)” must use KEY=value."
        case .invalidKey(let key):
            return "“\(key)” isn't a valid environment variable name."
        case .secretInAdvancedEnvironment(let key):
            return "Put \(key) in the API key field instead of Advanced environment."
        }
    }
}

private enum ClaudeCodeSettingsDefaults {
    struct Values {
        var baseURL = ""
        var mainModel = ""
        var opusModel = ""
        var sonnetModel = ""
        var haikuModel = ""
        var subagentModel = ""
    }

    static func load() -> Values? {
        let url = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".claude/settings.json")
        guard let data = try? Data(contentsOf: url),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let environment = object["env"] as? [String: Any] else {
            return nil
        }
        let string: (String) -> String = { key in
            (environment[key] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        }
        return Values(
            baseURL: string("ANTHROPIC_BASE_URL"),
            mainModel: string("ANTHROPIC_MODEL"),
            opusModel: string("ANTHROPIC_DEFAULT_OPUS_MODEL"),
            sonnetModel: string("ANTHROPIC_DEFAULT_SONNET_MODEL"),
            haikuModel: string("ANTHROPIC_DEFAULT_HAIKU_MODEL"),
            subagentModel: string("CLAUDE_CODE_SUBAGENT_MODEL")
        )
    }
}
