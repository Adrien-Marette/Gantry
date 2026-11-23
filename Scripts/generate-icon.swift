#!/usr/bin/env swift

import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

let outputDirectory = CommandLine.arguments.count > 1
    ? URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
    : URL(fileURLWithPath: "build/AppIcon.iconset", isDirectory: true)

try FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)

let variants: [(pixels: Int, filename: String)] = [
    (16, "icon_16x16.png"),
    (32, "icon_16x16@2x.png"),
    (32, "icon_32x32.png"),
    (64, "icon_32x32@2x.png"),
    (128, "icon_128x128.png"),
    (256, "icon_128x128@2x.png"),
    (256, "icon_256x256.png"),
    (512, "icon_256x256@2x.png"),
    (512, "icon_512x512.png"),
    (1024, "icon_512x512@2x.png")
]

for variant in variants {
    guard let image = drawIcon(pixels: variant.pixels) else {
        fatalError("Could not draw icon at \(variant.pixels)px")
    }
    let url = outputDirectory.appendingPathComponent(variant.filename)
    guard let destination = CGImageDestinationCreateWithURL(
        url as CFURL,
        UTType.png.identifier as CFString,
        1,
        nil
    ) else {
        fatalError("Could not create PNG destination")
    }
    CGImageDestinationAddImage(destination, image, nil)
    guard CGImageDestinationFinalize(destination) else {
        fatalError("Could not write \(url.path)")
    }
    print("wrote \(url.path)")
}

func drawIcon(pixels: Int) -> CGImage? {
    guard let context = CGContext(
        data: nil,
        width: pixels,
        height: pixels,
        bitsPerComponent: 8,
        bytesPerRow: 0,
        space: CGColorSpace(name: CGColorSpace.sRGB)!,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    ) else { return nil }

    let scale = CGFloat(pixels) / 1024
    context.scaleBy(x: scale, y: scale)
    context.setShouldAntialias(true)
    context.interpolationQuality = .high

    let tile = CGRect(x: 92, y: 92, width: 840, height: 840)
    let tilePath = CGPath(
        roundedRect: tile,
        cornerWidth: 188,
        cornerHeight: 188,
        transform: nil
    )

    context.saveGState()
    context.addPath(tilePath)
    context.clip()

    let gradient = CGGradient(
        colorsSpace: CGColorSpace(name: CGColorSpace.sRGB),
        colors: [
            color(0xF5A57D),
            color(0xD06A49),
            color(0x9B4156),
            color(0x5A2B40)
        ] as CFArray,
        locations: [0, 0.42, 0.74, 1]
    )!
    context.drawLinearGradient(
        gradient,
        start: CGPoint(x: 150, y: 940),
        end: CGPoint(x: 900, y: 120),
        options: []
    )

    let glow = CGGradient(
        colorsSpace: CGColorSpace(name: CGColorSpace.sRGB),
        colors: [
            CGColor(red: 1, green: 0.90, blue: 0.80, alpha: 0.45),
            CGColor(red: 1, green: 0.90, blue: 0.80, alpha: 0.0)
        ] as CFArray,
        locations: [0, 1]
    )!
    context.drawRadialGradient(
        glow,
        startCenter: CGPoint(x: 330, y: 780),
        startRadius: 0,
        endCenter: CGPoint(x: 330, y: 780),
        endRadius: 500,
        options: []
    )

    let lowerGlow = CGGradient(
        colorsSpace: CGColorSpace(name: CGColorSpace.sRGB),
        colors: [
            CGColor(red: 0.18, green: 0.05, blue: 0.12, alpha: 0.38),
            CGColor(red: 0.18, green: 0.05, blue: 0.12, alpha: 0.0)
        ] as CFArray,
        locations: [0, 1]
    )!
    context.drawRadialGradient(
        lowerGlow,
        startCenter: CGPoint(x: 790, y: 160),
        startRadius: 0,
        endCenter: CGPoint(x: 790, y: 160),
        endRadius: 480,
        options: []
    )

    context.restoreGState()

    context.saveGState()
    context.addPath(tilePath)
    context.clip()
    context.setStrokeColor(CGColor(red: 1, green: 1, blue: 1, alpha: 0.34))
    context.setLineWidth(9)
    context.addPath(tilePath)
    context.strokePath()

    let highlightPath = CGMutablePath()
    highlightPath.move(to: CGPoint(x: 158, y: 780))
    highlightPath.addCurve(
        to: CGPoint(x: 680, y: 900),
        control1: CGPoint(x: 290, y: 900),
        control2: CGPoint(x: 510, y: 930)
    )
    context.setStrokeColor(CGColor(red: 1, green: 1, blue: 1, alpha: 0.18))
    context.setLineWidth(18)
    context.setLineCap(.round)
    context.addPath(highlightPath)
    context.strokePath()
    context.restoreGState()

    context.saveGState()
    context.setShadow(
        offset: CGSize(width: 0, height: -10),
        blur: 24,
        color: CGColor(red: 0.20, green: 0.06, blue: 0.08, alpha: 0.35)
    )
    context.setStrokeColor(CGColor(red: 1, green: 1, blue: 1, alpha: 0.96))
    context.setLineWidth(58)
    context.setLineCap(.round)
    context.setLineJoin(.round)

    let prompt = CGMutablePath()
    prompt.move(to: CGPoint(x: 318, y: 676))
    prompt.addLine(to: CGPoint(x: 468, y: 512))
    prompt.addLine(to: CGPoint(x: 318, y: 348))
    context.addPath(prompt)
    context.strokePath()

    let cursor = CGMutablePath()
    cursor.move(to: CGPoint(x: 542, y: 348))
    cursor.addLine(to: CGPoint(x: 714, y: 348))
    context.addPath(cursor)
    context.strokePath()
    context.restoreGState()

    context.saveGState()
    context.setShadow(
        offset: CGSize(width: 0, height: -4),
        blur: 12,
        color: CGColor(red: 0.20, green: 0.06, blue: 0.08, alpha: 0.32)
    )
    context.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 0.92))
    context.addPath(sparklePath(center: CGPoint(x: 754, y: 746), radius: 54))
    context.fillPath()
    context.restoreGState()

    return context.makeImage()
}

func color(_ hex: UInt32) -> CGColor {
    CGColor(
        red: CGFloat((hex >> 16) & 0xFF) / 255,
        green: CGFloat((hex >> 8) & 0xFF) / 255,
        blue: CGFloat(hex & 0xFF) / 255,
        alpha: 1
    )
}

func sparklePath(center: CGPoint, radius: CGFloat) -> CGPath {
    let path = CGMutablePath()
    path.move(to: CGPoint(x: center.x, y: center.y + radius))
    path.addQuadCurve(
        to: CGPoint(x: center.x + radius, y: center.y),
        control: CGPoint(x: center.x + radius * 0.18, y: center.y + radius * 0.18)
    )
    path.addQuadCurve(
        to: CGPoint(x: center.x, y: center.y - radius),
        control: CGPoint(x: center.x + radius * 0.18, y: center.y - radius * 0.18)
    )
    path.addQuadCurve(
        to: CGPoint(x: center.x - radius, y: center.y),
        control: CGPoint(x: center.x - radius * 0.18, y: center.y - radius * 0.18)
    )
    path.addQuadCurve(
        to: CGPoint(x: center.x, y: center.y + radius),
        control: CGPoint(x: center.x - radius * 0.18, y: center.y + radius * 0.18)
    )
    path.closeSubpath()
    return path
}
