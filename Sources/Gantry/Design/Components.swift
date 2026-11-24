import AppKit
import SwiftUI

/// Flat brand mark: the terminal prompt glyph in one solid accent, no gloss,
/// no sparkle, no colored shadow.
struct BrandMark: View {
    var size: CGFloat = 28

    var body: some View {
        RoundedRectangle(cornerRadius: size * 0.25, style: .continuous)
            .fill(Palette.accent)
            .overlay(
                PromptGlyph()
                    .stroke(
                        Palette.onAccent,
                        style: StrokeStyle(
                            lineWidth: max(1.5, size * 0.09),
                            lineCap: .round,
                            lineJoin: .round
                        )
                    )
                    .padding(size * 0.24)
            )
            .frame(width: size, height: size)
            .accessibilityLabel("Gantry")
    }
}

private struct PromptGlyph: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let startX = rect.minX + rect.width * 0.08
        let centerY = rect.midY
        path.move(to: CGPoint(x: startX, y: rect.minY + rect.height * 0.20))
        path.addLine(to: CGPoint(x: startX + rect.width * 0.34, y: centerY))
        path.addLine(to: CGPoint(x: startX, y: rect.maxY - rect.height * 0.20))
        path.move(to: CGPoint(x: rect.midX + rect.width * 0.12, y: rect.maxY - rect.height * 0.22))
        path.addLine(to: CGPoint(x: rect.maxX - rect.width * 0.06, y: rect.maxY - rect.height * 0.22))
        return path
    }
}

struct GantryLockup: View {
    var compact: Bool = false

    var body: some View {
        HStack(spacing: 8) {
            BrandMark(size: compact ? 24 : 28)
            Text("Gantry")
                .font(.system(size: compact ? 15 : 16, weight: .medium))
                .foregroundStyle(Palette.ink)
        }
        .accessibilityElement(children: .combine)
    }
}

/// The live state of a turn. Uses the system indeterminate progress view so
/// the motion matches the rest of macOS and stops with reduce motion.
struct LiveIndicator: View {
    var color: Color = Palette.accent
    var size: CGFloat = 12

    var body: some View {
        ProgressView()
            .controlSize(.mini)
            .tint(color)
            .frame(width: size, height: size)
            .accessibilityLabel("Working")
    }
}

struct QuietBadge: View {
    var text: String
    var color: Color = Palette.tertiaryInk

    var body: some View {
        HStack(spacing: 4) {
            Circle()
                .fill(color)
                .frame(width: 5, height: 5)
            Text(text)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(color)
                .lineLimit(1)
        }
    }
}

struct IconButton: View {
    var systemName: String
    var help: String?
    var size: CGFloat = 13
    var frame: CGFloat = 28
    var foreground: Color = Palette.secondaryInk
    var action: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: size, weight: .medium))
                .foregroundStyle(isHovering ? Palette.ink : foreground)
                .frame(width: frame, height: frame)
                .background(
                    RoundedRectangle(cornerRadius: Radius.control, style: .continuous)
                        .fill(isHovering ? Palette.ink.opacity(0.06) : Color.clear)
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
        .help(help ?? "")
        .accessibilityLabel(help ?? systemName)
    }
}

struct CopyButton: View {
    var text: String
    var showsLabel: Bool = true
    var compact: Bool = false

    @State private var copied = false
    @State private var isHovering = false

    var body: some View {
        Button {
            let pasteboard = NSPasteboard.general
            pasteboard.clearContents()
            pasteboard.setString(text, forType: .string)
            copied = true
            Task { @MainActor in
                try? await Task.sleep(for: .seconds(1.4))
                copied = false
            }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: copied ? "checkmark" : "doc.on.doc")
                    .font(.system(size: 10, weight: .medium))
                if showsLabel {
                    Text(copied ? "Copied" : "Copy")
                        .font(.system(size: 11, weight: .medium))
                }
            }
            .foregroundStyle(copied ? Palette.success : (isHovering ? Palette.ink : Palette.tertiaryInk))
            .padding(.horizontal, showsLabel ? 6 : 4)
            .padding(.vertical, 4)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(isHovering ? Palette.ink.opacity(0.06) : Color.clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
        .help(copied ? "Copied" : "Copy")
    }
}

struct KeyHint: View {
    var text: String

    var body: some View {
        Text(text)
            .font(Typo.keycap)
            .foregroundStyle(Palette.tertiaryInk)
            .padding(.horizontal, 4)
            .padding(.vertical, 2)
            .background(
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .fill(Palette.ink.opacity(0.04))
                    .overlay(
                        RoundedRectangle(cornerRadius: 5, style: .continuous)
                            .strokeBorder(Palette.line, lineWidth: 1)
                    )
            )
    }
}

/// A menu label: icon, text, chevron. Quiet text, no pill.
struct ControlLabel: View {
    var systemName: String?
    var title: String
    var tint: Color = Palette.secondaryInk
    var chevron: Bool = true

    var body: some View {
        HStack(spacing: 5) {
            if let systemName {
                Image(systemName: systemName)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(tint)
            }
            Text(title.count > 28 ? String(title.prefix(27)) + "…" : title)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Palette.secondaryInk)
                .lineLimit(1)
            if chevron {
                Image(systemName: "chevron.down")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(Palette.tertiaryInk)
            }
        }
        .padding(.horizontal, 4)
        .padding(.vertical, 4)
        .contentShape(Rectangle())
    }
}

struct SectionLabel: View {
    var title: String

    var body: some View {
        Text(title)
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(Palette.tertiaryInk)
    }
}

struct Spinner: View {
    var size: CGFloat = 14

    var body: some View {
        ProgressView()
            .controlSize(.mini)
            .frame(width: size, height: size)
    }
}
