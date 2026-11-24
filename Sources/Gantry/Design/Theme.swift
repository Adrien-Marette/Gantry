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

/// Warm graphite ramp with one terracotta accent, taken from the brand mark.
/// Surfaces stay neutral so the transcript carries the color; the accent marks
/// the selection, the live turn and the primary action, nothing else.
enum Palette {
    static let accent = dynamic(light: 0xA9472C, dark: 0xE58B6B)
    static let onAccent = dynamic(light: 0xFFFFFF, dark: 0x1A120E)

    static let ink = dynamic(light: 0x1F1B16, dark: 0xEFE9DE)
    static let secondaryInk = dynamic(light: 0x5E554A, dark: 0xAAA398)
    static let tertiaryInk = dynamic(light: 0x6F665A, dark: 0x8A847A)
    static let faintInk = dynamic(light: 0x746B5F, dark: 0x847E74)

    static let canvas = dynamic(light: 0xF7F4EE, dark: 0x161513)
    static let surface = dynamic(light: 0xFDFBF7, dark: 0x1C1A18)
    static let surfaceRaised = dynamic(light: 0xFFFFFF, dark: 0x262421)
    static let field = dynamic(light: 0xF2EDE4, dark: 0x201D1A)
    static let codeSurface = dynamic(light: 0xF4EFE8, dark: 0x0F0E0D)
    static let codeHeader = dynamic(light: 0xEDE6DD, dark: 0x181614)

    static let line = dynamic(light: 0x1F1B16, dark: 0xEFE9DE, lightAlpha: 0.09, darkAlpha: 0.10)
    static let lineStrong = dynamic(light: 0x1F1B16, dark: 0xEFE9DE, lightAlpha: 0.15, darkAlpha: 0.16)

    static let sidebarSelection = dynamic(light: 0x1F1B16, dark: 0xFFFFFF, lightAlpha: 0.06, darkAlpha: 0.07)
    static let sidebarHover = dynamic(light: 0x1F1B16, dark: 0xFFFFFF, lightAlpha: 0.035, darkAlpha: 0.04)

    /// Dims the workspace behind the command palette. Black in both
    /// appearances, because it only needs to recede, not carry a color.
    static let scrim = Color.black.opacity(0.24)

    static let success = dynamic(light: 0x3D6B4B, dark: 0x95B99A)
    static let warning = dynamic(light: 0x8A5A12, dark: 0xE0B36A)
    static let danger = dynamic(light: 0xA83A32, dark: 0xE48277)
    static let info = dynamic(light: 0x3D5F80, dark: 0x94B8DC)

    static let codeKeyword = dynamic(light: 0x9A3B27, dark: 0xE68E70)
    static let codeString = dynamic(light: 0x4A6A44, dark: 0xA6C99A)
    static let codeNumber = dynamic(light: 0x7E5A22, dark: 0xD7B47A)
    static let codeType = dynamic(light: 0x3D6182, dark: 0x9DC3E6)
    static let codeComment = dynamic(light: 0x7B7266, dark: 0x7A7368)
    static let codePlain = dynamic(light: 0x2B2723, dark: 0xE8E2D9)
    static let codeFunction = dynamic(light: 0x6B4D6D, dark: 0xD7A9D8)

    static let diffAddition = dynamic(light: 0xE3EEE2, dark: 0x17291C)
    static let diffDeletion = dynamic(light: 0xF4E2DF, dark: 0x2E1A18)
    static let diffAdditionText = dynamic(light: 0x2F5434, dark: 0xB8D9B7)
    static let diffDeletionText = dynamic(light: 0x83352F, dark: 0xE6A49B)

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

/// One family (SF), one scale, three weights. Hierarchy comes from size and
/// color. Figures are tabular wherever they are numbers.
enum Typo {
    static let display = Font.system(size: 30, weight: .semibold)
    static let pageTitle = Font.system(size: 22, weight: .semibold)
    static let sectionTitle = Font.system(size: 17, weight: .semibold)
    static let headline = Font.system(size: 13, weight: .semibold)
    static let body = Font.system(size: 14, weight: .regular)
    static let bodyMedium = Font.system(size: 14, weight: .medium)
    static let ui = Font.system(size: 13, weight: .medium)
    static let caption = Font.system(size: 12, weight: .regular)
    static let captionMedium = Font.system(size: 12, weight: .medium)
    static let micro = Font.system(size: 11, weight: .medium)
    static let mono = Font.system(size: 12, weight: .regular, design: .monospaced)
    static let monoSmall = Font.system(size: 11, weight: .regular, design: .monospaced)
    static let keycap = Font.system(size: 10, weight: .medium, design: .monospaced)
    static let figure = Font.system(size: 17, weight: .regular).monospacedDigit()
    static let figureSmall = Font.system(size: 14, weight: .regular).monospacedDigit()
}

enum Radius {
    static let control: CGFloat = 8
    static let card: CGFloat = 12
    static let panel: CGFloat = 16
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

/// The window is one quiet neutral. Color and material live in the transcript
/// and in the glass layer above it, never in a background wash.
struct CanvasBackground: View {
    var body: some View {
        Palette.canvas
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
                width: axis == .vertical ? 1 : nil,
                height: axis == .horizontal ? 1 : nil
            )
    }
}

/// A content surface: one flat neutral step and a hairline. No gradients, no
/// glow, no shadow. Glass is reserved for the floating layer via `glassPanel`.
struct SurfaceBackground: View {
    var radius: CGFloat = Radius.card
    var strong: Bool = false

    var body: some View {
        RoundedRectangle(cornerRadius: radius, style: .continuous)
            .fill(strong ? Palette.surfaceRaised : Palette.surface)
            .overlay(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .strokeBorder(Palette.line, lineWidth: 1)
            )
    }
}

struct FieldBackground: View {
    var radius: CGFloat = Radius.control
    var focused: Bool = false

    var body: some View {
        RoundedRectangle(cornerRadius: radius, style: .continuous)
            .fill(Palette.field)
            .overlay(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .strokeBorder(focused ? Palette.accent : Palette.line, lineWidth: focused ? 2 : 1)
            )
    }
}

extension View {
    func surfaceCard(radius: CGFloat = Radius.card, strong: Bool = false) -> some View {
        background(SurfaceBackground(radius: radius, strong: strong))
    }

    func hairlineBorder(radius: CGFloat, color: Color = Palette.line) -> some View {
        overlay(
            RoundedRectangle(cornerRadius: radius, style: .continuous)
                .strokeBorder(color, lineWidth: 1)
        )
    }

    /// Real Liquid Glass. Use only for the floating layer and the navigation
    /// rail; never stack a custom fill, stroke or shadow on top of it.
    func glassPanel(radius: CGFloat = Radius.panel, interactive: Bool = false) -> some View {
        glassEffect(
            interactive ? .regular.interactive() : .regular,
            in: RoundedRectangle(cornerRadius: radius, style: .continuous)
        )
    }
}
