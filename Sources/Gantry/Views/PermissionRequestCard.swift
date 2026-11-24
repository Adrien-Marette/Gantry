import SwiftUI
import GantryCore

struct PermissionRequestCard: View {
    var request: ClaudePermissionRequest
    var project: Project
    var queuedCount: Int
    var glassNamespace: Namespace.ID?
    var onAction: (PermissionAction) -> Void

    @State private var showsDetails = false
    @Namespace private var ownGlassNamespace

    private var presentation: PermissionPresentation {
        PermissionPresentation.make(from: request, projectPath: project.path)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Palette.warning.opacity(0.12))
                    Image(systemName: presentation.icon)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(Palette.warning)
                }
                .frame(width: 32, height: 32)

                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 8) {
                        Text("Claude wants to \(presentation.title.lowercasedFirstWord)")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(Palette.ink)
                        Text(request.displayName ?? Format.prettyToolName(request.toolName))
                            .font(.system(size: 11, weight: .regular, design: .monospaced))
                            .foregroundStyle(Palette.tertiaryInk)
                    }

                    if let reason = request.decisionReason, !reason.isEmpty {
                        Text(reason)
                            .font(Typo.micro)
                            .foregroundStyle(Palette.tertiaryInk)
                            .lineLimit(2)
                    } else {
                        Text("Review the details before allowing this action.")
                            .font(Typo.micro)
                            .foregroundStyle(Palette.tertiaryInk)
                    }
                }

                Spacer(minLength: 4)

                if queuedCount > 0 {
                    Text("\(queuedCount) more")
                        .font(Typo.micro)
                        .monospacedDigit()
                        .foregroundStyle(Palette.tertiaryInk)
                }
            }

            VStack(alignment: .leading, spacing: 8) {
                if let path = presentation.pathPreview {
                    HStack(spacing: 6) {
                        Image(systemName: "doc.text")
                            .font(.system(size: 10))
                            .foregroundStyle(Palette.tertiaryInk)
                        Text(path)
                            .font(Typo.monoSmall)
                            .foregroundStyle(Palette.secondaryInk)
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Spacer()
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(
                        RoundedRectangle(cornerRadius: Radius.control, style: .continuous)
                            .fill(Palette.ink.opacity(0.04))
                    )
                }

                if let command = presentation.commandPreview, !command.isEmpty {
                    Text(command)
                        .font(.system(size: 12, weight: .regular, design: .monospaced))
                        .foregroundStyle(Palette.codePlain)
                        .textSelection(.enabled)
                        .lineLimit(8)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(12)
                        .background(
                            RoundedRectangle(cornerRadius: Radius.control, style: .continuous)
                                .fill(Palette.codeSurface)
                                .overlay(
                                    RoundedRectangle(cornerRadius: Radius.control, style: .continuous)
                                        .strokeBorder(Palette.line, lineWidth: 1)
                                )
                        )
                }
            }

            HStack(spacing: 8) {
                Button("Deny") {
                    onAction(.deny)
                }
                .buttonStyle(.glass)
                .controlSize(.small)

                Button {
                    withAnimation(.easeOut(duration: 0.2)) { showsDetails.toggle() }
                } label: {
                    HStack(spacing: 4) {
                        Text(showsDetails ? "Hide details" : "Details")
                            .font(Typo.micro)
                        Image(systemName: "chevron.down")
                            .font(.system(size: 10, weight: .medium))
                            .rotationEffect(.degrees(showsDetails ? 180 : 0))
                    }
                    .foregroundStyle(Palette.tertiaryInk)
                    .padding(.horizontal, 4)
                    .padding(.vertical, 4)
                }
                .buttonStyle(.plain)

                Spacer()

                if request.alwaysAllowSuggestion != nil {
                    Button(request.alwaysAllowLabel) {
                        onAction(.allowAlways)
                    }
                    .buttonStyle(.glass)
                    .controlSize(.small)
                    .help(request.alwaysAllowLabel)
                }

                Button {
                    onAction(.allowOnce)
                } label: {
                    HStack(spacing: 6) {
                        Text("Allow once")
                            .font(Typo.captionMedium)
                        Image(systemName: "arrow.right")
                            .font(.system(size: 10, weight: .medium))
                    }
                }
                .buttonStyle(.glassProminent)
                .tint(Palette.accent)
                .controlSize(.small)
            }

            if showsDetails {
                CodeBlockView(language: "json", code: presentation.details)
                    .transition(.opacity)
            }
        }
        .padding(16)
        .glassPanel(radius: 20)
        .glassEffectID("permission", in: glassNamespace ?? ownGlassNamespace)
    }
}

private extension String {
    var lowercasedFirstWord: String {
        guard let first else { return self }
        return first.lowercased() + dropFirst()
    }
}
