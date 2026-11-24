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
                        }
                        .padding(.leading, 88)
                        .padding(.trailing, 32)
                        .padding(.top, 24)
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
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .strokeBorder(
                        Palette.accent,
                        style: StrokeStyle(lineWidth: 2, dash: [8, 6])
                    )
                    .padding(24)
                    .allowsHitTesting(false)
                    .transition(.opacity)
            }
        }
        .animation(.easeOut(duration: 0.2), value: isDropTargeted)
        .dropDestination(for: URL.self) { urls, _ in
            guard let url = urls.first else { return false }
            var isDirectory: ObjCBool = false
            guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory),
                  isDirectory.boolValue else {
                dropError = "Drop a project folder."
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
        VStack(spacing: 32) {
            VStack(spacing: 20) {
                BrandMark(size: 48)

                VStack(spacing: 12) {
                    Text("Claude Code in a native window")
                        .font(Typo.display)
                        .tracking(-0.5)
                        .foregroundStyle(Palette.ink)
                        .multilineTextAlignment(.center)

                    Text("Choose a project folder to start a session. Permissions, tool activity, and history stay on this Mac.")
                        .font(.system(size: 15))
                        .foregroundStyle(Palette.secondaryInk)
                        .multilineTextAlignment(.center)
                        .lineSpacing(4)
                        .frame(maxWidth: 520)
                }
            }

            dropCard

            featureRow
        }
        .padding(.horizontal, 40)
        .frame(maxWidth: 800)
    }

    private var dropCard: some View {
        VStack(spacing: 16) {
            HStack(alignment: .top, spacing: 16) {
                Image(systemName: isDropTargeted ? "arrow.down.doc" : "folder.badge.plus")
                    .font(.system(size: 20, weight: .regular))
                    .foregroundStyle(Palette.secondaryInk)
                    .frame(width: 24, height: 24)

                VStack(alignment: .leading, spacing: 4) {
                    Text(isDropTargeted ? "Drop to open" : "Open a project")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(Palette.ink)
                    Text("Gantry starts a Claude Code session inside the folder you choose.")
                        .font(Typo.caption)
                        .foregroundStyle(Palette.secondaryInk)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 4)
            }

            HStack(spacing: 12) {
                Button {
                    app.chooseProjectFolder()
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "folder")
                            .font(.system(size: 12, weight: .medium))
                        Text("Choose a Folder")
                            .font(Typo.ui)
                    }
                }
                .buttonStyle(.glassProminent)
                .tint(Palette.accent)
                .keyboardShortcut(.defaultAction)

                Text("or drop a folder anywhere")
                    .font(Typo.caption)
                    .foregroundStyle(Palette.tertiaryInk)

                Spacer()

                HStack(spacing: 6) {
                    KeyHint(text: "⌘O")
                    Text("Open project")
                        .font(Typo.micro)
                        .foregroundStyle(Palette.tertiaryInk)
                }
            }
        }
        .padding(24)
        .frame(maxWidth: 560)
        .glassPanel(radius: 20)
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
            .frame(width: 1, height: 32)
            .padding(.horizontal, 20)
    }

    private func feature(icon: String, title: String, detail: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Palette.tertiaryInk)
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
                .foregroundStyle(Palette.tertiaryInk)

            Button {
                app.showExtensions()
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "puzzlepiece.extension")
                        .font(.system(size: 10, weight: .medium))
                    Text("Extensions & Mods")
                        .font(Typo.micro)
                }
                .foregroundStyle(Palette.secondaryInk)
            }
            .buttonStyle(.plain)
            .help("Browse, install, and create extensions and mods")

            Text("·")
                .font(Typo.micro)
                .foregroundStyle(Palette.tertiaryInk)

            Button {
                openSettings()
            } label: {
                Text("Settings")
                    .font(Typo.micro)
                    .foregroundStyle(Palette.secondaryInk)
            }
            .buttonStyle(.plain)
            .help("Open Gantry settings")

            Text("·")
                .font(Typo.micro)
                .foregroundStyle(Palette.tertiaryInk)

            Text("Gantry \(AppModel.appVersion)")
                .font(Typo.micro)
                .foregroundStyle(Palette.tertiaryInk)
        }
        .padding(.vertical, 8)
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
