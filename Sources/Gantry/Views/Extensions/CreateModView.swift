import AppKit
import SwiftUI
import GantryCore

struct CreateModView: View {
    let model: ExtensionsModel

    @Environment(AppModel.self) private var app

    @State private var template: ModTemplate = .statusLine
    @State private var name = ""
    @State private var summary = ""
    @State private var author = ""
    @State private var destination = ""
    @State private var includeTest = false
    @State private var isCreating = false
    @State private var isValidating = false
    @State private var isTesting = false
    @State private var result: ModScaffoldResult?
    @State private var validation: ClaudePluginValidationResult?
    @State private var testResult: ClaudePluginValidationResult?
    @State private var errorMessage: String?
    @State private var validationError: String?
    @State private var testError: String?

    private let columns = [
        GridItem(.flexible(), spacing: 8),
        GridItem(.flexible(), spacing: 8)
    ]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                intro
                templateGrid
                form
                if let result {
                    resultSection(result)
                }
            }
            .frame(maxWidth: 980)
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 28)
            .padding(.bottom, 28)
        }
        .scrollIndicators(.never)
        .onAppear {
            if destination.isEmpty {
                destination = app.resolveModsDirectory().path
            }
        }
    }

    private var intro: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Create a mod")
                .font(Typo.sectionTitle)
                .foregroundStyle(Palette.ink)
            Text("Scaffold a valid Claude Code mod, validate it, then open it in Gantry with the mod loaded for that project.")
                .font(Typo.caption)
                .foregroundStyle(Palette.secondaryInk)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var templateGrid: some View {
        LazyVGrid(columns: columns, spacing: 8) {
            ForEach(ModTemplate.allCases, id: \.self) { candidate in
                Button {
                    template = candidate
                } label: {
                    HStack(alignment: .top, spacing: 10) {
                        ExtensionIconTile(
                            symbol: symbol(for: candidate),
                            tint: tint(for: candidate),
                            size: 30
                        )

                        VStack(alignment: .leading, spacing: 3) {
                            Text(candidate.title)
                                .font(Typo.captionMedium)
                                .foregroundStyle(Palette.ink)
                            Text(candidate.summary)
                                .font(Typo.micro)
                                .foregroundStyle(Palette.tertiaryInk)
                                .multilineTextAlignment(.leading)
                                .fixedSize(horizontal: false, vertical: true)
                        }

                        Spacer(minLength: 4)

                        if template == candidate {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.system(size: 12))
                                .foregroundStyle(Palette.accent)
                        }
                    }
                    .padding(11)
                    .frame(maxWidth: .infinity, minHeight: 74, alignment: .topLeading)
                    .background(
                        RoundedRectangle(cornerRadius: 11, style: .continuous)
                            .fill(
                                template == candidate
                                    ? Palette.accent.opacity(0.075)
                                    : Palette.surface.opacity(0.52)
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 11, style: .continuous)
                                    .strokeBorder(
                                        template == candidate
                                            ? Palette.accent.opacity(0.35)
                                            : Palette.line,
                                        lineWidth: 0.7
                                    )
                            )
                    )
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("\(candidate.title). \(candidate.summary)")
            }
        }
    }

    private var form: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionLabel(title: "Details")

            VStack(alignment: .leading, spacing: 14) {
                field("Name", hint: "Lowercase letters, numbers, and hyphens. This becomes the folder name.") {
                    TextField("turn-counter", text: $name)
                        .textFieldStyle(.plain)
                        .font(Typo.body)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 8)
                        .background(fieldBackground)
                }

                if let nameIssue {
                    inlineError(nameIssue)
                }

                field("Description", hint: "Shown in the mod manifest and README.") {
                    TextField("A short description of what this mod does", text: $summary)
                        .textFieldStyle(.plain)
                        .font(Typo.body)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 8)
                        .background(fieldBackground)
                }

                field("Author", hint: "Optional. Added to the plugin manifest.") {
                    TextField("Your name", text: $author)
                        .textFieldStyle(.plain)
                        .font(Typo.body)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 8)
                        .background(fieldBackground)
                }

                field("Folder", hint: "Gantry creates a subfolder with the mod name here.") {
                    HStack(spacing: 8) {
                        TextField("~/Developer/Gantry Mods", text: $destination)
                            .textFieldStyle(.plain)
                            .font(Typo.body)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 8)
                            .background(fieldBackground)

                        Button("Choose…") { chooseFolder() }
                            .font(Typo.caption)
                    }
                }

                if template.supportsTest {
                    Toggle(isOn: $includeTest) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Include a starter test")
                                .font(Typo.captionMedium)
                                .foregroundStyle(Palette.ink)
                            Text("The test is generated only for the pane template and can be run with claude plugin test.")
                                .font(Typo.micro)
                                .foregroundStyle(Palette.faintInk)
                        }
                    }
                    .toggleStyle(.switch)
                    .controlSize(.small)
                }

                HStack(spacing: 10) {
                    ExtensionsPillButton(
                        title: isCreating ? "Creating…" : "Create Mod",
                        systemName: "hammer",
                        prominent: true,
                        isBusy: isCreating
                    ) {
                        create()
                    }
                    .disabled(isCreating || name.isEmpty || nameIssue != nil)

                    if let errorMessage {
                        Text(errorMessage)
                            .font(Typo.micro)
                            .foregroundStyle(Palette.danger)
                            .lineLimit(2)
                    }

                    Spacer()
                }
            }
            .padding(14)
            .surfaceCard(radius: 12)
        }
    }

    private func resultSection(_ result: ModScaffoldResult) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                SectionLabel(title: "Created")
                Spacer()
                Text(result.directoryURL.path)
                    .font(Typo.monoSmall)
                    .foregroundStyle(Palette.faintInk)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .textSelection(.enabled)
            }

            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .top, spacing: 10) {
                    ExtensionIconTile(symbol: "checkmark.seal", tint: Palette.success, size: 30)

                    VStack(alignment: .leading, spacing: 2) {
                        Text("Mod scaffolded")
                            .font(Typo.captionMedium)
                            .foregroundStyle(Palette.ink)
                        Text("\(result.files.count) files written. Validate before loading it in a chat.")
                            .font(Typo.micro)
                            .foregroundStyle(Palette.tertiaryInk)
                    }

                    Spacer()
                }

                VStack(alignment: .leading, spacing: 3) {
                    ForEach(relativeFiles(result), id: \.self) { file in
                        Text(file)
                            .font(Typo.monoSmall)
                            .foregroundStyle(Palette.secondaryInk)
                    }
                }
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .fill(Palette.codeSurface)
                        .overlay(
                            RoundedRectangle(cornerRadius: 9, style: .continuous)
                                .strokeBorder(Palette.line, lineWidth: 0.7)
                        )
                )

                HStack(spacing: 8) {
                    ExtensionsPillButton(
                        title: "Validate",
                        systemName: "checkmark.shield",
                        isBusy: isValidating
                    ) {
                        runValidation(result)
                    }
                    .disabled(isValidating || isTesting || model.isMutating)

                    if result.hasTest {
                        ExtensionsPillButton(
                            title: "Test",
                            systemName: "testtube.2",
                            isBusy: isTesting
                        ) {
                            runTest(result)
                        }
                        .disabled(isValidating || isTesting || model.isMutating)
                    }

                    ExtensionsPillButton(title: "Reveal in Finder", systemName: "folder") {
                        NSWorkspace.shared.activateFileViewerSelecting([result.directoryURL])
                    }

                    Spacer()
                }

                HStack(spacing: 8) {
                    ExtensionsPillButton(
                        title: "Open in Gantry",
                        systemName: "arrow.up.forward.app",
                        prominent: true
                    ) {
                        app.openModInGantry(at: result.directoryURL)
                    }

                    ExtensionsPillButton(
                        title: "Draft with Claude",
                        systemName: "bubble.left.and.text.bubble.right"
                    ) {
                        draftWithClaude(result)
                    }

                    Spacer()
                }

                if let validationError {
                    inlineError(validationError)
                } else if let validation {
                    validationOutput(
                        title: "Validation",
                        result: validation
                    )
                }

                if let testError {
                    inlineError(testError)
                } else if let testResult {
                    validationOutput(
                        title: "Test",
                        result: testResult
                    )
                }
            }
            .padding(14)
            .surfaceCard(radius: 12)
        }
    }

    private func validationOutput(
        title: String,
        result: ClaudePluginValidationResult
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: result.succeeded ? "checkmark.circle.fill" : "xmark.octagon.fill")
                    .font(.system(size: 11))
                    .foregroundStyle(result.succeeded ? Palette.success : Palette.danger)
                Text("\(title) \(result.succeeded ? "passed" : "failed")")
                    .font(Typo.captionMedium)
                    .foregroundStyle(Palette.ink)
            }

            ScrollView {
                Text(result.output)
                    .font(Typo.monoSmall)
                    .foregroundStyle(Palette.codePlain)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(10)
            }
            .frame(maxHeight: 190)
            .background(
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(Palette.codeSurface)
                    .overlay(
                        RoundedRectangle(cornerRadius: 9, style: .continuous)
                            .strokeBorder(Palette.line, lineWidth: 0.7)
                    )
            )
        }
    }

    private var nameIssue: String? {
        guard !name.isEmpty else { return nil }
        do {
            try ModScaffolder.validateName(name)
            return nil
        } catch {
            return (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    private func field<Content: View>(
        _ title: String,
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

    private func inlineError(_ message: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "exclamationmark.circle.fill")
                .font(.system(size: 10.5))
                .foregroundStyle(Palette.danger)
                .padding(.top, 1)
            Text(message)
                .font(Typo.micro)
                .foregroundStyle(Palette.danger)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(9)
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

    private func relativeFiles(_ result: ModScaffoldResult) -> [String] {
        let prefix = result.directoryURL.path + "/"
        return result.files.map { file in
            file.path.hasPrefix(prefix)
                ? String(file.path.dropFirst(prefix.count))
                : file.lastPathComponent
        }
    }

    private func chooseFolder() {
        let panel = NSOpenPanel()
        panel.title = "Choose where to create the mod"
        panel.prompt = "Choose"
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            destination = url.path
        }
    }

    private func create() {
        guard !isCreating else { return }
        errorMessage = nil
        validation = nil
        testResult = nil
        validationError = nil
        testError = nil

        let expanded = (destination as NSString)
            .expandingTildeInPath
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !expanded.isEmpty else {
            errorMessage = "Choose a folder for the mod."
            return
        }

        let request = ModScaffoldRequest(
            name: name,
            description: summary,
            author: author,
            template: template,
            destinationDirectory: URL(fileURLWithPath: expanded, isDirectory: true),
            includeTest: includeTest && template.supportsTest
        )

        isCreating = true
        Task { @MainActor in
            do {
                let scaffold = try await Task.detached(priority: .userInitiated) {
                    try ModScaffolder.scaffold(request)
                }.value
                result = scaffold
                isCreating = false
                app.setModsDirectory(URL(fileURLWithPath: expanded, isDirectory: true))
                runValidation(scaffold)
            } catch {
                errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
                isCreating = false
            }
        }
    }

    private func runValidation(_ scaffold: ModScaffoldResult) {
        isValidating = true
        validationError = nil
        Task { @MainActor in
            defer { isValidating = false }
            do {
                validation = try await model.validate(path: scaffold.directoryURL)
            } catch {
                validation = nil
                validationError = model.userMessage(error)
            }
        }
    }

    private func runTest(_ scaffold: ModScaffoldResult) {
        guard scaffold.hasTest else { return }
        isTesting = true
        testError = nil
        Task { @MainActor in
            defer { isTesting = false }
            do {
                testResult = try await model.test(path: scaffold.directoryURL)
            } catch {
                testResult = nil
                testError = model.userMessage(error)
            }
        }
    }

    private func draftWithClaude(_ scaffold: ModScaffoldResult) {
        guard let sessionID = app.openModInGantry(at: scaffold.directoryURL) else {
            errorMessage = "Couldn't open the mod folder in Gantry."
            return
        }
        app.drafts[sessionID] = """
        Help me finish this Claude Code mod. Use the plugin-authoring guidance if it is available, keep the manifest and hooks valid, and run `claude plugin validate .` after changes.
        """
    }

    private func symbol(for template: ModTemplate) -> String {
        switch template {
        case .statusLine: return "text.badge.checkmark"
        case .slashCommand: return "slash.circle"
        case .pane: return "sidebar.right"
        case .toolGuard: return "shield.lefthalf.filled"
        case .blank: return "doc"
        }
    }

    private func tint(for template: ModTemplate) -> Color {
        switch template {
        case .statusLine: return Palette.accent
        case .slashCommand: return Palette.info
        case .pane: return Palette.success
        case .toolGuard: return Palette.warning
        case .blank: return Palette.tertiaryInk
        }
    }
}
