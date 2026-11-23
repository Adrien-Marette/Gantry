import AppKit
import SwiftUI
import GantryCore

struct WelcomeView: View {
    var embedded: Bool = false

    @Environment(AppModel.self) private var app
    @Environment(\.openSettings) private var openSettings
    @State private var isDropTargeted = false
    @State private var dropError: String?

    var body: some View {
        GeometryReader { geometry in
            ScrollView {
                VStack(spacing: 0) {
                    if !embedded {
                        HStack(alignment: .center) {
                            GantryLockup()
                            Spacer()
                            Text("A native workspace for Claude Code")
                                .font(Typo.caption)
                                .foregroundStyle(Palette.tertiaryInk)
                                .padding(.horizontal, 11)
                                .padding(.vertical, 6)
                                .background(
                                    Capsule(style: .continuous)
                                        .fill(Palette.surface.opacity(0.34))
                                        .overlay(
                                            Capsule(style: .continuous)
                                                .strokeBorder(Palette.line, lineWidth: 0.7)
                                        )
                                )
                        }
                        .padding(.leading, 86)
                        .padding(.trailing, 28)
                        .padding(.top, 20)
                    }

                    Spacer(minLength: embedded ? 30 : 22)

                    hero

                    Spacer(minLength: 22)

                    footer
                        .padding(.bottom, 24)
                }
                .frame(maxWidth: .infinity)
                .frame(minHeight: geometry.size.height)
            }
            .scrollIndicators(.never)
        }
        .overlay {
            if isDropTargeted {
                RoundedRectangle(cornerRadius: 32, style: .continuous)
                    .strokeBorder(
                        Palette.accent.opacity(0.65),
                        style: StrokeStyle(lineWidth: 1.5, dash: [7, 5])
                    )
                    .padding(24)
                    .allowsHitTesting(false)
                    .transition(.opacity)
            }
        }
        .animation(.smooth(duration: 0.2), value: isDropTargeted)
        .dropDestination(for: URL.self) { urls, _ in
            guard let url = urls.first else { return false }
            var isDirectory: ObjCBool = false
            guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory),
                  isDirectory.boolValue else {
                dropError = "Please drop a project folder."
                return false
            }
            app.addProject(at: url)
            return true
        } isTargeted: { targeted in
            isDropTargeted = targeted
        }
        .alert("Couldn't open that item", isPresented: Binding(
            get: { dropError != nil },
            set: { if !$0 { dropError = nil } }
        )) {
            Button("OK", role: .cancel) { dropError = nil }
        } message: {
            Text(dropError ?? "")
        }
    }

    private var hero: some View {
        VStack(spacing: 28) {
            VStack(spacing: 18) {
                EmptyStateSpark()

                VStack(spacing: 14) {
                    Text("A calmer way to build\nwith Claude Code.")
                        .font(.system(size: 44, weight: .semibold, design: .default))
                        .tracking(-1.15)
                        .foregroundStyle(Palette.ink)
                        .multilineTextAlignment(.center)
                        .lineSpacing(1)

                    Text("Your projects, conversations, and permissions in one quiet native place.\nClaude Code does the work. Gantry gives it room to breathe.")
                        .font(.system(size: 15.5))
                        .foregroundStyle(Palette.secondaryInk)
                        .multilineTextAlignment(.center)
                        .lineSpacing(4)
                        .frame(maxWidth: 580)
                }
            }

            dropCard

            featureRow
        }
        .padding(.horizontal, 36)
        .frame(maxWidth: 800)
    }

    private var dropCard: some View {
        VStack(spacing: 16) {
            HStack(alignment: .top, spacing: 14) {
                ZStack {
                    RoundedRectangle(cornerRadius: 13, style: .continuous)
                        .fill(Palette.accent.opacity(0.12))
                    Image(systemName: isDropTargeted ? "arrow.down.doc.fill" : "folder.fill.badge.plus")
                        .font(.system(size: 20, weight: .regular))
                        .foregroundStyle(Palette.accent)
                }
                .frame(width: 46, height: 46)

                VStack(alignment: .leading, spacing: 4) {
                    Text(isDropTargeted ? "Drop to open" : "Open a project")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(Palette.ink)
                    Text("Choose a folder and Gantry will start a fresh Claude Code session inside it.")
                        .font(Typo.caption)
                        .foregroundStyle(Palette.secondaryInk)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 4)
            }

            HStack(spacing: 10) {
                Button {
                    app.chooseProjectFolder()
                } label: {
                    HStack(spacing: 7) {
                        Image(systemName: "folder")
                            .font(.system(size: 11.5, weight: .medium))
                        Text("Choose a Folder")
                            .font(Typo.ui)
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                }
                .foregroundStyle(Palette.onAccent)
                .background(
                    Capsule(style: .continuous)
                        .fill(Palette.accentGradient)
                        .overlay(
                            Capsule(style: .continuous)
                                .strokeBorder(Color.white.opacity(0.20), lineWidth: 0.7)
                        )
                        .shadow(color: Palette.accent.opacity(0.26), radius: 10, y: 4)
                )
                .buttonStyle(.plain)
                .keyboardShortcut(.defaultAction)

                Text("or drop a folder anywhere")
                    .font(Typo.caption)
                    .foregroundStyle(Palette.tertiaryInk)

                Spacer()

                HStack(spacing: 5) {
                    KeyHint(text: "⌘O")
                    Text("Open project")
                        .font(Typo.micro)
                        .foregroundStyle(Palette.tertiaryInk)
                }
            }
        }
        .padding(22)
        .frame(width: 540)
        .background(
            RoundedRectangle(cornerRadius: 25, style: .continuous)
                .fill(Palette.surfaceRaised.opacity(0.58))
        )
        .glassEffect(
            .regular.tint(Palette.accent.opacity(isDropTargeted ? 0.14 : 0.055)),
            in: RoundedRectangle(cornerRadius: 25, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 25, style: .continuous)
                .strokeBorder(Palette.lineStrong, lineWidth: 0.8)
        }
        .shadow(color: Palette.shadow.opacity(0.35), radius: 30, y: 14)
        .scaleEffect(isDropTargeted ? 1.012 : 1)
    }

    private var featureRow: some View {
        HStack(spacing: 0) {
            feature(
                icon: "lock.shield",
                title: "Native permissions",
                detail: "Approve actions here, not in a terminal."
            )
            featureDivider
            feature(
                icon: "internaldrive",
                title: "Sessions stay local",
                detail: "Projects and history live on your Mac."
            )
            featureDivider
            feature(
                icon: "terminal",
                title: "Your setup, unchanged",
                detail: "Works with your existing Claude Code."
            )
        }
        .frame(maxWidth: 700)
        .padding(.top, 4)
    }

    private var featureDivider: some View {
        Rectangle()
            .fill(Palette.line)
            .frame(width: 0.7, height: 34)
            .padding(.horizontal, 18)
    }

    private func feature(icon: String, title: String, detail: String) -> some View {
        HStack(alignment: .top, spacing: 9) {
            Image(systemName: icon)
                .font(.system(size: 12.5, weight: .medium))
                .foregroundStyle(Palette.accent)
                .frame(width: 16, height: 16)
                .padding(.top, 1)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(Typo.captionMedium)
                    .foregroundStyle(Palette.secondaryInk)
                Text(detail)
                    .font(Typo.micro)
                    .foregroundStyle(Palette.tertiaryInk)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var footer: some View {
        HStack(spacing: 10) {
            Circle()
                .fill(statusColor)
                .frame(width: 6, height: 6)

            Text(statusTitle)
                .font(Typo.micro)
                .foregroundStyle(Palette.tertiaryInk)

            Text("·")
                .font(Typo.micro)
                .foregroundStyle(Palette.faintInk)

            Button {
                app.showExtensions()
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "puzzlepiece.extension")
                        .font(.system(size: 9.5, weight: .medium))
                    Text("Extensions & Mods")
                        .font(Typo.micro)
                }
                .foregroundStyle(Palette.secondaryInk)
            }
            .buttonStyle(.plain)
            .help("Browse, install, and create extensions and mods")

            Text("·")
                .font(Typo.micro)
                .foregroundStyle(Palette.faintInk)

            Button {
                openSettings()
            } label: {
                Text("Settings")
                    .font(Typo.micro)
                    .foregroundStyle(Palette.secondaryInk)
                    .underline(false)
            }
            .buttonStyle(.plain)
            .help("Open Gantry settings")

            Text("·")
                .font(Typo.micro)
                .foregroundStyle(Palette.faintInk)

            Text("Gantry \(AppModel.appVersion)")
                .font(Typo.micro)
                .foregroundStyle(Palette.faintInk)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 7)
        .background(
            Capsule(style: .continuous)
                .fill(Palette.surface.opacity(0.30))
                .overlay(Capsule(style: .continuous).strokeBorder(Palette.line, lineWidth: 0.6))
        )
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
        case .checking:
            return "Looking for Claude Code…"
        case .ready(_, let version):
            if let version { return "Claude Code \(version.replacingOccurrences(of: " (Claude Code)", with: ""))" }
            return "Claude Code ready"
        case .missing:
            return "Claude Code not found"
        case .failed(let message):
            return message
        }
    }
}
