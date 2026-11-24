import AppKit
import SwiftUI
import GantryCore

struct ExtensionCommandPrompt: Identifiable, Hashable {
    enum Kind: Hashable {
        case install
        case update
    }

    let id = UUID()
    var pluginID: String
    var kind: Kind
    var command: String
    var sha256: String?
}

struct ExtensionInstallSheet: View {
    let model: ExtensionsModel
    let plugin: ClaudeAvailablePlugin
    let marketplace: ClaudeMarketplace?
    var onInstalled: () -> Void = {}

    @Environment(\.dismiss) private var dismiss

    @State private var stage: Stage = .review
    @State private var isWorking = false
    @State private var errorMessage: String?

    private enum Stage {
        case review
        case approval(command: String, sha256: String?)
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Hairline()

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    switch stage {
                    case .review:
                        reviewContent
                    case .approval(let command, let sha256):
                        approvalContent(command: command, sha256: sha256)
                    }

                    if let errorMessage {
                        ExtensionsNotice(
                            icon: "exclamationmark.circle.fill",
                            title: "Install failed",
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
        .frame(width: 580, height: 540)
                .interactiveDismissDisabled(isWorking)
    }

    private var header: some View {
        HStack(spacing: 12) {
            ExtensionIconTile(
                symbol: isApprovalStage ? "terminal" : "puzzlepiece.extension",
                size: 32
            )

            VStack(alignment: .leading, spacing: 2) {
                Text(isApprovalStage ? "Approve Install Command" : "Install \(plugin.name)")
                    .font(Typo.sectionTitle)
                    .foregroundStyle(Palette.ink)
                    .lineLimit(1)
                Text(isApprovalStage ? "Review the exact command first" : plugin.marketplaceName)
                    .font(Typo.micro)
                    .foregroundStyle(Palette.tertiaryInk)
                    .lineLimit(1)
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

    private var reviewContent: some View {
        VStack(alignment: .leading, spacing: 14) {
            if let description = plugin.description, !description.isEmpty {
                Text(description)
                    .font(Typo.caption)
                    .foregroundStyle(Palette.secondaryInk)
                    .fixedSize(horizontal: false, vertical: true)
            }

            VStack(spacing: 0) {
                detailRow("Marketplace", plugin.marketplaceName)
                settingsDivider
                detailRow("Source", sourceDescription)
                if let ref = plugin.source?.ref, !ref.isEmpty {
                    settingsDivider
                    detailRow("Ref", ref)
                }
                if let sha = plugin.source?.sha, !sha.isEmpty {
                    settingsDivider
                    detailRow("Commit", String(sha.prefix(12)))
                }
            }
            .surfaceCard(radius: 12)

            ExtensionTrustWarning(
                message: "Extensions can add commands, hooks, agents, and MCP servers that run with your permissions. Install only sources you trust."
            )
        }
    }

    private func approvalContent(command: String, sha256: String?) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Claude Code wants to run a command to install this extension. Review it before approving.")
                .font(Typo.caption)
                .foregroundStyle(Palette.secondaryInk)
                .fixedSize(horizontal: false, vertical: true)

            ExtensionCommandBlock(command: command, sha256: sha256)

            if sha256 == nil {
                ExtensionTrustWarning(
                    message: "This command cannot be approved from Gantry automatically. Copy and run it in Terminal, then install again."
                )
            } else {
                Text("Approving applies only to this command and this install. Gantry does not remember the approval.")
                    .font(Typo.micro)
                    .foregroundStyle(Palette.faintInk)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var footer: some View {
        HStack(spacing: 9) {
            Text(footerHint)
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
                title: primaryTitle,
                prominent: true,
                isBusy: isWorking
            ) {
                submit()
            }
            .disabled(isWorking || primaryDisabled || model.isMutating)
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 16)
    }

    private var footerHint: String {
        switch stage {
        case .review:
            return "The extension is installed into your Claude Code plugin library."
        case .approval:
            return "The command runs once, for this extension."
        }
    }

    private var primaryTitle: String {
        if isWorking {
            return "Installing…"
        }
        switch stage {
        case .review:
            return "Install"
        case .approval:
            return "Run Command and Install"
        }
    }

    private var primaryDisabled: Bool {
        switch stage {
        case .review:
            return false
        case .approval(_, let sha256):
            return sha256 == nil
        }
    }

    private var isApprovalStage: Bool {
        if case .approval = stage { return true }
        return false
    }

    private var sourceDescription: String {
        if let source = plugin.source?.displayLocation, !source.isEmpty {
            return source
        }
        if let marketplace {
            return marketplace.displayLocation
        }
        return plugin.marketplaceName
    }

    private func submit() {
        guard !isWorking else { return }
        switch stage {
        case .review:
            install(acceptCommandSHA256: nil)
        case .approval(_, let sha256):
            guard let sha256 else { return }
            install(acceptCommandSHA256: sha256)
        }
    }

    private func install(acceptCommandSHA256: String?) {
        isWorking = true
        errorMessage = nil
        Task { @MainActor in
            do {
                try await model.install(
                    pluginID: plugin.pluginId,
                    acceptCommandSHA256: acceptCommandSHA256
                )
                onInstalled()
                dismiss()
            } catch let error as ClaudePluginError {
                if case .confirmationRequired(let command, let sha256) = error {
                    stage = .approval(command: command, sha256: sha256)
                } else {
                    errorMessage = model.userMessage(error)
                }
                isWorking = false
            } catch {
                errorMessage = model.userMessage(error)
                isWorking = false
            }
        }
    }

    private func detailRow(_ title: String, _ value: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text(title)
                .font(Typo.caption)
                .foregroundStyle(Palette.secondaryInk)
            Spacer(minLength: 12)
            Text(value)
                .font(Typo.micro)
                .foregroundStyle(Palette.tertiaryInk)
                .multilineTextAlignment(.trailing)
                .lineLimit(2)
                .truncationMode(.middle)
                .textSelection(.enabled)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }
}

// MARK: - Shared approval sheet

struct ExtensionCommandApprovalSheet: View {
    let model: ExtensionsModel
    let prompt: ExtensionCommandPrompt
    var onCompleted: () -> Void = {}

    @Environment(\.dismiss) private var dismiss

    @State private var command: String
    @State private var sha256: String?
    @State private var isWorking = false
    @State private var errorMessage: String?

    init(
        model: ExtensionsModel,
        prompt: ExtensionCommandPrompt,
        onCompleted: @escaping () -> Void = {}
    ) {
        self.model = model
        self.prompt = prompt
        self.onCompleted = onCompleted
        _command = State(initialValue: prompt.command)
        _sha256 = State(initialValue: prompt.sha256)
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Hairline()

            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    Text("Claude Code wants to run this command before updating the extension. Review it before approving.")
                        .font(Typo.caption)
                        .foregroundStyle(Palette.secondaryInk)
                        .fixedSize(horizontal: false, vertical: true)

                    ExtensionCommandBlock(command: command, sha256: sha256)

                    if sha256 == nil {
                        ExtensionTrustWarning(
                            message: "This command cannot be approved from Gantry automatically. Copy and run it in Terminal, then try the update again."
                        )
                    } else {
                        Text("Approving applies only to this command and this update.")
                            .font(Typo.micro)
                            .foregroundStyle(Palette.faintInk)
                    }

                    if let errorMessage {
                        ExtensionsNotice(
                            icon: "exclamationmark.circle.fill",
                            title: "Update failed",
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
        .frame(width: 580, height: 480)
                .interactiveDismissDisabled(isWorking)
    }

    private var header: some View {
        HStack(spacing: 11) {
            ExtensionIconTile(symbol: "terminal", size: 32)

            VStack(alignment: .leading, spacing: 2) {
                Text("Approve Update Command")
                    .font(Typo.sectionTitle)
                    .foregroundStyle(Palette.ink)
                Text(prompt.pluginID)
                    .font(Typo.micro)
                    .foregroundStyle(Palette.tertiaryInk)
                    .lineLimit(1)
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
            Text("The command runs once, for this update.")
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
                title: isWorking ? "Updating…" : "Run Command and Update",
                prominent: true,
                isBusy: isWorking
            ) {
                submit()
            }
            .disabled(isWorking || sha256 == nil || model.isMutating)
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 16)
    }

    private func submit() {
        guard let sha256, !isWorking else { return }
        isWorking = true
        errorMessage = nil
        Task { @MainActor in
            do {
                switch prompt.kind {
                case .install:
                    try await model.install(
                        pluginID: prompt.pluginID,
                        acceptCommandSHA256: sha256
                    )
                case .update:
                    try await model.update(
                        pluginID: prompt.pluginID,
                        acceptCommandSHA256: sha256
                    )
                }
                onCompleted()
                dismiss()
            } catch let error as ClaudePluginError {
                if case .confirmationRequired(let newCommand, let newSHA) = error {
                    // The catalog moved between approval and execution. Do not
                    // reuse the old approval; show the new command in place.
                    command = newCommand
                    self.sha256 = newSHA
                    errorMessage = "The command changed. Review the new command and approve it."
                } else {
                    errorMessage = model.userMessage(error)
                }
                isWorking = false
            } catch {
                errorMessage = model.userMessage(error)
                isWorking = false
            }
        }
    }
}

// MARK: - Shared pieces

struct ExtensionCommandBlock: View {
    var command: String
    var sha256: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Command")
                    .font(Typo.captionMedium)
                    .foregroundStyle(Palette.ink)
                Spacer()
                CopyButton(text: command, showsLabel: true)
            }

            ScrollView(.horizontal) {
                Text(command)
                    .font(Typo.mono)
                    .foregroundStyle(Palette.codePlain)
                    .textSelection(.enabled)
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .scrollIndicators(.automatic)
            .background(
                RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
                    .fill(Palette.codeSurface)
                    .overlay(
                        RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
                            .strokeBorder(Palette.line, lineWidth: 1)
                    )
            )

            if let sha256 {
                Text("SHA-256 \(sha256)")
                    .font(Typo.monoSmall)
                    .foregroundStyle(Palette.tertiaryInk)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .textSelection(.enabled)
            }
        }
    }
}

struct ExtensionTrustWarning: View {
    var message: String

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "exclamationmark.shield")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(Palette.warning)
                .padding(.top, 1)

            Text(message)
                .font(Typo.micro)
                .foregroundStyle(Palette.secondaryInk)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: Radius.control, style: .continuous)
                .fill(Palette.warning.opacity(0.07))
                .overlay(
                    RoundedRectangle(cornerRadius: Radius.control, style: .continuous)
                        .strokeBorder(Palette.warning.opacity(0.25), lineWidth: 1)
                )
        )
    }
}
