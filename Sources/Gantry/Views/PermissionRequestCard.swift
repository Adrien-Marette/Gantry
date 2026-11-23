import SwiftUI
import GantryCore

struct PermissionRequestCard: View {
    var request: ClaudePermissionRequest
    var project: Project
    var queuedCount: Int
    var onAction: (PermissionAction) -> Void

    @State private var showsDetails = false

    private var presentation: PermissionPresentation {
        PermissionPresentation.make(from: request, projectPath: project.path)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 10) {
                ZStack {
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .fill(presentation.tint.opacity(0.13))
                    Image(systemName: presentation.icon)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(presentation.tint)
                }
                .frame(width: 34, height: 34)

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 7) {
                        Text("Claude wants to \(presentation.title.lowercasedFirstWord)")
                            .font(.system(size: 13.5, weight: .semibold))
                            .foregroundStyle(Palette.ink)
                        Text(request.displayName ?? Format.prettyToolName(request.toolName))
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(Palette.secondaryInk)
                            .padding(.horizontal, 5.5)
                            .padding(.vertical, 2)
                            .background(
                                Capsule(style: .continuous)
                                    .fill(Palette.ink.opacity(0.055))
                            )
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
                        .foregroundStyle(Palette.tertiaryInk)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(
                            Capsule(style: .continuous)
                                .fill(Palette.ink.opacity(0.045))
                        )
                }
            }

            VStack(alignment: .leading, spacing: 7) {
                if let path = presentation.pathPreview {
                    HStack(spacing: 6) {
                        Image(systemName: "doc.text")
                            .font(.system(size: 9.5))
                            .foregroundStyle(Palette.tertiaryInk)
                        Text(path)
                            .font(Typo.monoSmall)
                            .foregroundStyle(Palette.secondaryInk)
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Spacer()
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(Palette.ink.opacity(0.035))
                    )
                }

                if let command = presentation.commandPreview, !command.isEmpty {
                    Text(command)
                        .font(.system(size: 11.5, design: .monospaced))
                        .foregroundStyle(Palette.codePlain)
                        .textSelection(.enabled)
                        .lineLimit(8)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(10)
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

            HStack(spacing: 8) {
                Button {
                    onAction(.deny)
                } label: {
                    Text("Deny")
                        .font(Typo.captionMedium)
                        .foregroundStyle(Palette.secondaryInk)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .fill(Palette.ink.opacity(0.045))
                        )
                }
                .buttonStyle(.plain)

                Button {
                    withAnimation(.smooth(duration: 0.2)) { showsDetails.toggle() }
                } label: {
                    HStack(spacing: 4) {
                        Text(showsDetails ? "Hide details" : "Details")
                            .font(Typo.micro)
                        Image(systemName: "chevron.down")
                            .font(.system(size: 7, weight: .semibold))
                            .rotationEffect(.degrees(showsDetails ? 180 : 0))
                    }
                    .foregroundStyle(Palette.tertiaryInk)
                    .padding(.horizontal, 3)
                    .padding(.vertical, 6)
                }
                .buttonStyle(.plain)

                Spacer()

                if request.alwaysAllowSuggestion != nil {
                    Button {
                        onAction(.allowAlways)
                    } label: {
                        Text(request.alwaysAllowLabel)
                            .font(Typo.captionMedium)
                            .foregroundStyle(Palette.secondaryInk)
                            .padding(.horizontal, 11)
                            .padding(.vertical, 6)
                            .background(
                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .fill(Palette.ink.opacity(0.055))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                                            .strokeBorder(Palette.lineStrong, lineWidth: 0.7)
                                    )
                            )
                    }
                    .buttonStyle(.plain)
                    .help(request.alwaysAllowLabel)
                }

                Button {
                    onAction(.allowOnce)
                } label: {
                    HStack(spacing: 5) {
                        Text("Allow once")
                            .font(Typo.captionMedium)
                        Image(systemName: "arrow.right")
                            .font(.system(size: 9, weight: .semibold))
                    }
                    .foregroundStyle(Palette.onAccent)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6.5)
                    .background(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(Palette.accent)
                            .overlay(
                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .strokeBorder(Color.white.opacity(0.18), lineWidth: 0.7)
                            )
                    )
                }
                .buttonStyle(.plain)
            }

            if showsDetails {
                CodeBlockView(language: "json", code: presentation.details)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 21, style: .continuous)
                .fill(Palette.warning.opacity(0.035))
        )
        .glassEffect(
            .regular.tint(Palette.warning.opacity(0.055)),
            in: RoundedRectangle(cornerRadius: 21, style: .continuous)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 21, style: .continuous)
                .strokeBorder(Palette.warning.opacity(0.22), lineWidth: 0.8)
        )
        .shadow(color: Palette.shadow.opacity(0.25), radius: 18, y: 7)
    }
}

private extension String {
    var lowercasedFirstWord: String {
        guard let first else { return self }
        return first.lowercased() + dropFirst()
    }
}
