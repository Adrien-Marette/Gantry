import AppKit
import SwiftUI
import GantryCore

extension AppearanceMode {
    var colorScheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .light: return .light
        case .dark: return .dark
        }
    }
}

enum Palette {
    static let accent = dynamic(light: 0xC45F3F, dark: 0xE58B6B)
    static let accentBright = dynamic(light: 0xD97757, dark: 0xF09B7D)
    static let accentDeep = dynamic(light: 0x9C3E29, dark: 0xC2684A)
    static let onAccent = Color.white

    static let ink = dynamic(light: 0x1D1916, dark: 0xF7F2EA)
    static let secondaryInk = dynamic(light: 0x625A52, dark: 0xB8ACA0)
    static let tertiaryInk = dynamic(light: 0x83796F, dark: 0x988D83)
    static let faintInk = dynamic(light: 0xA79D93, dark: 0x6D645C)

    static let canvasTop = dynamic(light: 0xF6F1E8, dark: 0x17130F)
    static let canvasBottom = dynamic(light: 0xEBE3D7, dark: 0x0E0C0A)
    static let sidebarTop = dynamic(light: 0xF0E9DE, dark: 0x1A1511)
    static let sidebarBottom = dynamic(light: 0xE7DED1, dark: 0x120F0C)

    static let surface = dynamic(light: 0xFFFFFF, dark: 0x261F1A)
    static let surfaceSubtle = dynamic(light: 0xFCFAF6, dark: 0x1A1612)
    static let surfaceRaised = dynamic(light: 0xFFFFFF, dark: 0x2F2822)
    static let codeSurface = dynamic(light: 0xF4EFE8, dark: 0x0E0F10)
    static let codeHeader = dynamic(light: 0xEDE6DD, dark: 0x181A1B)

    static let line = dynamic(light: 0x211D18, dark: 0xF8F2E9, lightAlpha: 0.105, darkAlpha: 0.115)
    static let lineStrong = dynamic(light: 0x211D18, dark: 0xF8F2E9, lightAlpha: 0.17, darkAlpha: 0.18)
    static let shadow = Color.black.opacity(0.18)

    static let sidebarSelection = dynamic(light: 0xFFFFFF, dark: 0xFFFFFF, lightAlpha: 0.66, darkAlpha: 0.105)
    static let sidebarHover = dynamic(light: 0xFFFFFF, dark: 0xFFFFFF, lightAlpha: 0.30, darkAlpha: 0.055)
    static let userBubble = dynamic(light: 0xFEFCF9, dark: 0x302720, lightAlpha: 0.84, darkAlpha: 0.92)
    static let userBubbleBorder = accent.opacity(0.18)

    static let success = dynamic(light: 0x56785B, dark: 0x95B99A)
    static let warning = dynamic(light: 0xA87524, dark: 0xE0B36A)
    static let danger = dynamic(light: 0xB74840, dark: 0xE48277)
    static let info = dynamic(light: 0x4C6D8E, dark: 0x94B8DC)

    static let auroraCoral = dynamic(light: 0xEEAE95, dark: 0x7C3D2C)
    static let auroraIris = dynamic(light: 0xBAC8DF, dark: 0x293A55)
    static let auroraSage = dynamic(light: 0xC2D4BF, dark: 0x2B4335)
    static let auroraGold = dynamic(light: 0xE8D0A2, dark: 0x4E3A24)

    static let codeKeyword = dynamic(light: 0xA5412D, dark: 0xE68E70)
    static let codeString = dynamic(light: 0x54704A, dark: 0xA6C99A)
    static let codeNumber = dynamic(light: 0x8A652E, dark: 0xD7B47A)
    static let codeType = dynamic(light: 0x456A8C, dark: 0x9DC3E6)
    static let codeComment = dynamic(light: 0x958B80, dark: 0x6E675F)
    static let codePlain = dynamic(light: 0x2B2723, dark: 0xE8E2D9)
    static let codeFunction = dynamic(light: 0x735375, dark: 0xD7A9D8)

    static let diffAddition = dynamic(light: 0xDCEBDD, dark: 0x183021).opacity(0.85)
    static let diffDeletion = dynamic(light: 0xF3DEDB, dark: 0x351D1C).opacity(0.85)
    static let diffAdditionText = dynamic(light: 0x335937, dark: 0xB8D9B7)
    static let diffDeletionText = dynamic(light: 0x8C3A34, dark: 0xE6A49B)

    static var accentGradient: LinearGradient {
        LinearGradient(
            colors: [accentBright, accent, accentDeep],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    static var canvasGradient: LinearGradient {
        LinearGradient(
            colors: [canvasTop, canvasBottom],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    static var sidebarGradient: LinearGradient {
        LinearGradient(
            colors: [sidebarTop, sidebarBottom],
            startPoint: .top,
            endPoint: .bottom
        )
    }

    private static func dynamic(
        light: UInt32,
        dark: UInt32,
        lightAlpha: CGFloat = 1,
        darkAlpha: CGFloat = 1
    ) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            let match = appearance.bestMatch(from: [.darkAqua, .aqua])
            let isDark = match == .darkAqua
            return NSColor(hex: isDark ? dark : light, alpha: isDark ? darkAlpha : lightAlpha)
        })
    }
}

enum Typo {
    static let display = Font.system(size: 34, weight: .semibold, design: .default)
    static let pageTitle = Font.system(size: 24, weight: .semibold, design: .default)
    static let sectionTitle = Font.system(size: 18, weight: .semibold, design: .default)
    static let headline = Font.system(size: 14, weight: .semibold, design: .default)
    static let body = Font.system(size: 14.5, weight: .regular, design: .default)
    static let bodyMedium = Font.system(size: 14.5, weight: .medium, design: .default)
    static let ui = Font.system(size: 12.5, weight: .medium, design: .default)
    static let caption = Font.system(size: 11.5, weight: .regular, design: .default)
    static let captionMedium = Font.system(size: 11.5, weight: .medium, design: .default)
    static let micro = Font.system(size: 10.5, weight: .medium, design: .default)
    static let mono = Font.system(size: 12, weight: .regular, design: .monospaced)
    static let monoSmall = Font.system(size: 11, weight: .regular, design: .monospaced)
    static let serif = Font.system(size: 31, weight: .regular, design: .serif)
}

extension NSColor {
    convenience init(hex: UInt32, alpha: CGFloat = 1) {
        self.init(
            srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255,
            alpha: alpha
        )
    }
}

struct AuroraBackground: View {
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                Palette.canvasGradient

                Circle()
                    .fill(Palette.auroraCoral)
                    .frame(width: geometry.size.width * 0.68, height: geometry.size.width * 0.68)
                    .blur(radius: 140)
                    .opacity(colorScheme == .dark ? 0.30 : 0.24)
                    .offset(
                        x: geometry.size.width * 0.30,
                        y: -geometry.size.height * 0.34
                    )

                Circle()
                    .fill(Palette.auroraIris)
                    .frame(width: geometry.size.width * 0.55, height: geometry.size.width * 0.55)
                    .blur(radius: 130)
                    .opacity(colorScheme == .dark ? 0.22 : 0.18)
                    .offset(
                        x: -geometry.size.width * 0.36,
                        y: geometry.size.height * 0.14
                    )

                Circle()
                    .fill(Palette.auroraSage)
                    .frame(width: geometry.size.width * 0.45, height: geometry.size.width * 0.45)
                    .blur(radius: 150)
                    .opacity(colorScheme == .dark ? 0.18 : 0.14)
                    .offset(
                        x: geometry.size.width * 0.26,
                        y: geometry.size.height * 0.44
                    )

                LinearGradient(
                    colors: [
                        Color.white.opacity(colorScheme == .dark ? 0.015 : 0.16),
                        Color.clear,
                        Color.black.opacity(colorScheme == .dark ? 0.20 : 0.015)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
            }
            .drawingGroup()
        }
        .ignoresSafeArea()
        .accessibilityHidden(true)
    }
}

struct Hairline: View {
    var axis: Axis = .horizontal
    var color: Color = Palette.line

    var body: some View {
        Rectangle()
            .fill(color)
            .frame(
                width: axis == .vertical ? 0.7 : nil,
                height: axis == .horizontal ? 0.7 : nil
            )
    }
}

struct SurfaceBackground: View {
    var radius: CGFloat = 16
    var strong: Bool = false

    var body: some View {
        RoundedRectangle(cornerRadius: radius, style: .continuous)
            .fill(strong ? Palette.surfaceRaised.opacity(0.86) : Palette.surface.opacity(0.52))
            .overlay(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .strokeBorder(Palette.line, lineWidth: 0.7)
            )
    }
}

extension View {
    func surfaceCard(radius: CGFloat = 16, strong: Bool = false) -> some View {
        background(SurfaceBackground(radius: radius, strong: strong))
    }

    func hairlineBorder(radius: CGFloat, color: Color = Palette.line) -> some View {
        overlay(
            RoundedRectangle(cornerRadius: radius, style: .continuous)
                .strokeBorder(color, lineWidth: 0.7)
        )
    }
}
