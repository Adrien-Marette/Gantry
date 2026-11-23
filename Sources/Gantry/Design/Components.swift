import AppKit
import SwiftUI

struct BrandMark: View {
    var size: CGFloat = 28
    var castsShadow: Bool = true

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.27, style: .continuous)
                .fill(
                    LinearGradient(
                        stops: [
                            .init(color: Color(red: 0.96, green: 0.66, blue: 0.49), location: 0),
                            .init(color: Color(red: 0.82, green: 0.40, blue: 0.28), location: 0.48),
                            .init(color: Color(red: 0.44, green: 0.20, blue: 0.28), location: 1)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )

            Circle()
                .fill(Color.white.opacity(0.34))
                .frame(width: size * 0.78, height: size * 0.78)
                .blur(radius: size * 0.22)
                .offset(x: -size * 0.24, y: -size * 0.28)
                .clipShape(RoundedRectangle(cornerRadius: size * 0.27, style: .continuous))

            RoundedRectangle(cornerRadius: size * 0.27, style: .continuous)
                .strokeBorder(
                    LinearGradient(
                        colors: [Color.white.opacity(0.46), Color.white.opacity(0.08)],
                        startPoint: .top,
                        endPoint: .bottom
                    ),
                    lineWidth: max(0.8, size * 0.022)
                )

            PromptGlyph()
                .stroke(
                    Color.white.opacity(0.96),
                    style: StrokeStyle(
                        lineWidth: max(1.3, size * 0.085),
                        lineCap: .round,
                        lineJoin: .round
                    )
                )
                .padding(size * 0.25)

            if size >= 30 {
                SparkleShape()
                    .fill(Color.white.opacity(0.92))
                    .frame(width: size * 0.16, height: size * 0.16)
                    .offset(x: size * 0.28, y: -size * 0.27)
            }
        }
        .frame(width: size, height: size)
        .shadow(
            color: castsShadow ? Color(red: 0.45, green: 0.18, blue: 0.10).opacity(0.30) : .clear,
            radius: size * 0.18,
            x: 0,
            y: size * 0.08
        )
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

private struct SparkleShape: Shape {
    func path(in rect: CGRect) -> Path {
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let radius = min(rect.width, rect.height) / 2
        var path = Path()
        path.move(to: CGPoint(x: center.x, y: center.y - radius))
        path.addQuadCurve(
            to: CGPoint(x: center.x + radius, y: center.y),
            control: CGPoint(x: center.x + radius * 0.18, y: center.y - radius * 0.18)
        )
        path.addQuadCurve(
            to: CGPoint(x: center.x, y: center.y + radius),
            control: CGPoint(x: center.x + radius * 0.18, y: center.y + radius * 0.18)
        )
        path.addQuadCurve(
            to: CGPoint(x: center.x - radius, y: center.y),
            control: CGPoint(x: center.x - radius * 0.18, y: center.y + radius * 0.18)
        )
        path.addQuadCurve(
            to: CGPoint(x: center.x, y: center.y - radius),
            control: CGPoint(x: center.x - radius * 0.18, y: center.y - radius * 0.18)
        )
        return path
    }
}

struct GantryLockup: View {
    var compact: Bool = false

    var body: some View {
        HStack(spacing: compact ? 8 : 10) {
            BrandMark(size: compact ? 25 : 29)
            Text("Gantry")
                .font(.system(size: compact ? 14.5 : 16, weight: .semibold))
                .foregroundStyle(Palette.ink)
                .tracking(-0.2)
        }
        .accessibilityElement(children: .combine)
    }
}

struct ActivityDots: View {
    var color: Color = Palette.accent
    var size: CGFloat = 3.2

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        TimelineView(.animation(minimumInterval: reduceMotion ? 60 : 1.0 / 18.0)) { timeline in
            let phase = timeline.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 1.1) / 1.1
            HStack(spacing: size * 0.9) {
                ForEach(0..<3, id: \.self) { index in
                    Circle()
                        .fill(color)
                        .frame(width: size, height: size)
                        .opacity(dotOpacity(index: index, phase: phase))
                }
            }
            .frame(width: size * 5.6, alignment: .leading)
        }
        .accessibilityHidden(true)
    }

    private func dotOpacity(index: Int, phase: Double) -> Double {
        guard !reduceMotion else { return 0.75 }
        let shifted = (phase - Double(index) * 0.17).truncatingRemainder(dividingBy: 1)
        let wave = max(0, 1 - abs(shifted - 0.20) * 4.2)
        return 0.28 + wave * 0.72
    }
}

struct StatusPill: View {
    var title: String
    var color: Color = Palette.accent
    var showsDots: Bool = true

    var body: some View {
        HStack(spacing: 7) {
            if showsDots {
                ActivityDots(color: color)
            } else {
                Circle().fill(color).frame(width: 5, height: 5)
            }
            Text(title)
                .font(Typo.captionMedium)
                .foregroundStyle(Palette.secondaryInk)
                .lineLimit(1)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5.5)
        .background(
            Capsule(style: .continuous)
                .fill(Palette.surface.opacity(0.48))
                .overlay(Capsule(style: .continuous).strokeBorder(Palette.line, lineWidth: 0.7))
        )
    }
}

struct IconButton: View {
    var systemName: String
    var help: String?
    var size: CGFloat = 14
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
                    RoundedRectangle(cornerRadius: frame * 0.32, style: .continuous)
                        .fill(isHovering ? Palette.ink.opacity(0.065) : Color.clear)
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
            HStack(spacing: 4.5) {
                Image(systemName: copied ? "checkmark" : "doc.on.doc")
                    .font(.system(size: compact ? 10 : 10.5, weight: .medium))
                if showsLabel {
                    Text(copied ? "Copied" : "Copy")
                        .font(Typo.micro)
                }
            }
            .foregroundStyle(copied ? Palette.success : (isHovering ? Palette.ink : Palette.tertiaryInk))
            .padding(.horizontal, showsLabel ? 7 : 5)
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
            .font(.system(size: 9.5, weight: .medium, design: .rounded))
            .foregroundStyle(Palette.tertiaryInk)
            .padding(.horizontal, 4.5)
            .padding(.vertical, 2.5)
            .background(
                RoundedRectangle(cornerRadius: 4.5, style: .continuous)
                    .fill(Palette.ink.opacity(0.045))
                    .overlay(
                        RoundedRectangle(cornerRadius: 4.5, style: .continuous)
                            .strokeBorder(Palette.line, lineWidth: 0.6)
                    )
            )
    }
}

struct ControlPillLabel: View {
    var systemName: String?
    var title: String
    var tint: Color = Palette.secondaryInk
    var chevron: Bool = true

    var body: some View {
        HStack(spacing: 5) {
            if let systemName {
                Image(systemName: systemName)
                    .font(.system(size: 10.5, weight: .medium))
                    .foregroundStyle(tint)
            }
            Text(title.count > 28 ? String(title.prefix(27)) + "…" : title)
                .font(Typo.ui)
                .foregroundStyle(Palette.secondaryInk)
                .lineLimit(1)
            if chevron {
                Image(systemName: "chevron.down")
                    .font(.system(size: 8, weight: .semibold))
                    .foregroundStyle(Palette.tertiaryInk)
                    .padding(.leading, -1)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Palette.ink.opacity(0.045))
        )
        .contentShape(Rectangle())
    }
}

struct SectionLabel: View {
    var title: String

    var body: some View {
        Text(title.uppercased())
            .font(.system(size: 9.5, weight: .semibold))
            .tracking(0.7)
            .foregroundStyle(Palette.tertiaryInk)
    }
}

struct LoadingDotRing: View {
    var size: CGFloat = 14
    var color: Color = Palette.accent

    @State private var rotating = false

    var body: some View {
        Circle()
            .trim(from: 0.08, to: 0.72)
            .stroke(
                color,
                style: StrokeStyle(lineWidth: 1.8, lineCap: .round)
            )
            .frame(width: size, height: size)
            .rotationEffect(.degrees(rotating ? 360 : 0))
            .animation(.linear(duration: 0.9).repeatForever(autoreverses: false), value: rotating)
            .onAppear { rotating = true }
    }
}

struct EmptyStateSpark: View {
    var body: some View {
        ZStack {
            Circle()
                .fill(Palette.accent.opacity(0.10))
                .frame(width: 92, height: 92)
                .blur(radius: 18)
            BrandMark(size: 54)
        }
    }
}
