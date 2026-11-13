#!/usr/bin/env swift
import AppKit
import CoreGraphics
import Foundation

// Generates Brisa's macOS AppIcon iconset (16..1024px) from packaging/brand/sources/app-icon-source.jpg
// inside standard macOS 824/1024 squircle geometry with specular rim highlight and ambient shadow.
// Includes a crisp Concept A geometric vector fallback if the raster studio master is absent.

let args = Array(CommandLine.arguments.dropFirst())
let output = URL(fileURLWithPath: args.first ?? "packaging/Brisa.iconset")
let previewOutURL: URL? = {
    if let idx = args.firstIndex(of: "--preview"), idx + 1 < args.count {
        return URL(fileURLWithPath: args[idx + 1])
    }
    return nil
}()

let fm = FileManager.default
try? fm.createDirectory(at: output, withIntermediateDirectories: true)

let cwd = URL(fileURLWithPath: fm.currentDirectoryPath)
let masterImageURL = cwd.appendingPathComponent("packaging/brand/sources/app-icon-source.jpg")
let sourceImage = NSImage(contentsOf: masterImageURL)
let standalone1024URL = cwd.appendingPathComponent("packaging/brand/Brisa-1024.png")
try? fm.createDirectory(at: standalone1024URL.deletingLastPathComponent(), withIntermediateDirectories: true)

func fallbackVectorMark() -> CGPath {
    let leftX: CGFloat = 175, topY: CGFloat = 95, botY: CGFloat = 905, corner: CGFloat = 24
    let upper = CGMutablePath()
    upper.move(to: CGPoint(x: leftX, y: topY + corner))
    upper.addQuadCurve(to: CGPoint(x: leftX + corner, y: topY), control: CGPoint(x: leftX, y: topY))
    upper.addLine(to: CGPoint(x: 495, y: topY))
    upper.addCurve(to: CGPoint(x: 794, y: 288), control1: CGPoint(x: 686, y: topY), control2: CGPoint(x: 794, y: 172))
    upper.addCurve(to: CGPoint(x: 682, y: 448), control1: CGPoint(x: 794, y: 368), control2: CGPoint(x: 742, y: 422))
    upper.addLine(to: CGPoint(x: 560, y: 430))
    upper.addCurve(to: CGPoint(x: 638, y: 302), control1: CGPoint(x: 616, y: 392), control2: CGPoint(x: 638, y: 350))
    upper.addCurve(to: CGPoint(x: 486, y: 216), control1: CGPoint(x: 638, y: 248), control2: CGPoint(x: 576, y: 216))
    upper.addCurve(to: CGPoint(x: 312, y: 330), control1: CGPoint(x: 396, y: 216), control2: CGPoint(x: 348, y: 264))
    upper.addCurve(to: CGPoint(x: leftX, y: 614), control1: CGPoint(x: 262, y: 414), control2: CGPoint(x: 214, y: 498))
    upper.closeSubpath()

    let lower = CGMutablePath()
    lower.move(to: CGPoint(x: leftX, y: botY - corner))
    lower.addLine(to: CGPoint(x: leftX, y: 692))
    lower.addCurve(to: CGPoint(x: 515, y: 398), control1: CGPoint(x: 238, y: 512), control2: CGPoint(x: 352, y: 398))
    lower.addCurve(to: CGPoint(x: 682, y: 448), control1: CGPoint(x: 604, y: 398), control2: CGPoint(x: 656, y: 428))
    lower.addCurve(to: CGPoint(x: 842, y: 656), control1: CGPoint(x: 782, y: 490), control2: CGPoint(x: 842, y: 558))
    lower.addCurve(to: CGPoint(x: 528, y: botY), control1: CGPoint(x: 842, y: 808), control2: CGPoint(x: 716, y: botY))
    lower.addLine(to: CGPoint(x: 344, y: botY))
    lower.addCurve(to: CGPoint(x: 534, y: 776), control1: CGPoint(x: 386, y: 806), control2: CGPoint(x: 444, y: 776))
    lower.addCurve(to: CGPoint(x: 682, y: 652), control1: CGPoint(x: 624, y: 776), control2: CGPoint(x: 682, y: 722))
    lower.addCurve(to: CGPoint(x: 514, y: 526), control1: CGPoint(x: 682, y: 580), control2: CGPoint(x: 612, y: 526))
    lower.addCurve(to: CGPoint(x: 272, y: botY), control1: CGPoint(x: 356, y: 526), control2: CGPoint(x: 274, y: 668))
    lower.addLine(to: CGPoint(x: leftX + corner, y: botY))
    lower.addQuadCurve(to: CGPoint(x: leftX, y: botY - corner), control: CGPoint(x: leftX, y: botY))
    lower.closeSubpath()

    if #available(macOS 13.0, *) { return upper.union(lower) }
    let m = CGMutablePath(); m.addPath(upper); m.addPath(lower); return m
}

func renderIcon(pixels: Int) -> NSBitmapImageRep {
    let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: pixels,
        pixelsHigh: pixels,
        bitsPerSample: 8,
        samplesPerPixel: 4,
        hasAlpha: true,
        isPlanar: false,
        colorSpaceName: .deviceRGB,
        bytesPerRow: 0,
        bitsPerPixel: 0
    )!
    rep.size = NSSize(width: pixels, height: pixels)

    NSGraphicsContext.saveGraphicsState()
    let ctx = NSGraphicsContext(bitmapImageRep: rep)!
    NSGraphicsContext.current = ctx
    ctx.imageInterpolation = .high

    let s = CGFloat(pixels)
    let inset = s * (100.0 / 1024.0)
    let yBias = pixels <= 32 ? s * 0.004 : s * 0.008
    let box = NSRect(x: inset, y: inset + yBias, width: s - inset * 2, height: s - inset * 2)
    let radius = box.width * 0.2237
    let squircle = NSBezierPath(roundedRect: box, xRadius: radius, yRadius: radius)

    // macOS HIG soft downward ambient shadow (subtle tight shadow at <=32px to preserve crisp edges)
    ctx.cgContext.saveGState()
    let shadow = NSShadow()
    shadow.shadowColor = NSColor.black.withAlphaComponent(pixels <= 32 ? 0.24 : 0.36)
    shadow.shadowBlurRadius = pixels <= 32 ? max(0.5, s * 0.015) : max(1.0, s * 0.022)
    shadow.shadowOffset = NSSize(width: 0, height: -max(0.4, s * 0.011))
    shadow.set()
    NSColor(srgbRed: 0.06, green: 0.09, blue: 0.14, alpha: 1).setFill()
    squircle.fill()
    ctx.cgContext.restoreGState()

    // Interior composition clipped to Apple squircle
    NSGraphicsContext.saveGraphicsState()
    squircle.addClip()

    if let sourceImage {
        let zoom: CGFloat = pixels <= 32 ? 1.22 : (pixels <= 64 ? 1.15 : 1.10)
        let drawW = box.width * zoom
        let drawH = box.height * zoom
        let drawRect = NSRect(
            x: box.midX - drawW / 2,
            y: box.midY - drawH / 2,
            width: drawW,
            height: drawH
        )
        sourceImage.draw(in: drawRect, from: .zero, operation: .sourceOver, fraction: 1.0)
    } else {
        let bg = NSGradient(
            starting: NSColor(srgbRed: 0.09, green: 0.13, blue: 0.20, alpha: 1),
            ending: NSColor(srgbRed: 0.04, green: 0.07, blue: 0.11, alpha: 1)
        )
        bg?.draw(in: box, angle: -90)
        let cg = ctx.cgContext
        cg.saveGState()
        let pad = box.width * 0.16
        let markBox = box.insetBy(dx: pad, dy: pad)
        cg.translateBy(x: markBox.minX, y: markBox.maxY)
        cg.scaleBy(x: markBox.width / 1000.0, y: -(markBox.height / 1000.0))
        cg.addPath(fallbackVectorMark())
        cg.clip()
        let space = CGColorSpaceCreateDeviceRGB()
        let colors = [
            NSColor(srgbRed: 10/255, green: 132/255, blue: 255/255, alpha: 1).cgColor,
            NSColor(srgbRed: 23/255, green: 196/255, blue: 197/255, alpha: 1).cgColor,
            NSColor(srgbRed: 40/255, green: 205/255, blue: 120/255, alpha: 1).cgColor
        ] as CFArray
        let grad = CGGradient(colorsSpace: space, colors: colors, locations: [0, 0.52, 1])!
        cg.drawLinearGradient(grad, start: CGPoint(x: 175, y: 100), end: CGPoint(x: 842, y: 900), options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
        cg.restoreGState()
    }

    // Subtle glass rim bevel
    let rim = NSBezierPath(roundedRect: box.insetBy(dx: max(0.35, s * 0.0012), dy: max(0.35, s * 0.0012)), xRadius: radius, yRadius: radius)
    rim.lineWidth = max(0.45, s * 0.0022)
    NSColor.white.withAlphaComponent(0.16).setStroke()
    rim.stroke()

    NSGraphicsContext.restoreGraphicsState()
    NSGraphicsContext.restoreGraphicsState()
    return rep
}

let entries: [(String, Int)] = [
    ("icon_16x16", 16),
    ("icon_16x16@2x", 32),
    ("icon_32x32", 32),
    ("icon_32x32@2x", 64),
    ("icon_128x128", 128),
    ("icon_128x128@2x", 256),
    ("icon_256x256", 256),
    ("icon_256x256@2x", 512),
    ("icon_512x512", 512),
    ("icon_512x512@2x", 1024),
]

var renderedBySize: [Int: NSBitmapImageRep] = [:]
for (name, pixels) in entries {
    let rep = renderedBySize[pixels] ?? renderIcon(pixels: pixels)
    renderedBySize[pixels] = rep
    let data = rep.representation(using: .png, properties: [:])!
    try data.write(to: output.appendingPathComponent("\(name).png"))
    if pixels == 1024 {
        try data.write(to: standalone1024URL)
    }
}

if let previewOutURL {
    let scales = [16, 32, 64, 128, 256, 512]
    let width = 1360
    let height = 980
    let sheet = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: width, pixelsHigh: height,
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
    )!
    sheet.size = NSSize(width: width, height: height)
    NSGraphicsContext.saveGraphicsState()
    let ctx = NSGraphicsContext(bitmapImageRep: sheet)!
    NSGraphicsContext.current = ctx

    // Light Dock backdrop top half, Dark Dock backdrop bottom half
    NSColor(srgbRed: 245/255, green: 245/255, blue: 247/255, alpha: 1).setFill()
    NSRect(x: 0, y: height / 2, width: width, height: height / 2).fill()
    NSColor(srgbRed: 28/255, green: 28/255, blue: 30/255, alpha: 1).setFill()
    NSRect(x: 0, y: 0, width: width, height: height / 2).fill()

    func drawStrip(yCenter: CGFloat, textColor: NSColor) {
        var x: CGFloat = 44
        for px in scales {
            if let rep = renderedBySize[px] {
                let img = NSImage(size: NSSize(width: px, height: px))
                img.addRepresentation(rep)
                let y = yCenter - CGFloat(px) / 2
                img.draw(in: NSRect(x: x, y: y, width: CGFloat(px), height: CGFloat(px)))
                let label = "\(px)px" as NSString
                let attrs: [NSAttributedString.Key: Any] = [
                    .font: NSFont.monospacedSystemFont(ofSize: 12, weight: .medium),
                    .foregroundColor: textColor
                ]
                label.draw(at: NSPoint(x: x, y: yCenter - 290 + (yCenter > 490 ? 75 : 55)), withAttributes: attrs)
                x += CGFloat(px) + 34
            }
        }
    }
    drawStrip(yCenter: CGFloat(height) * 0.75, textColor: .darkGray)
    drawStrip(yCenter: CGFloat(height) * 0.25, textColor: .lightGray)

    NSGraphicsContext.restoreGraphicsState()
    try? fm.createDirectory(at: previewOutURL.deletingLastPathComponent(), withIntermediateDirectories: true)
    try sheet.representation(using: .png, properties: [:])!.write(to: previewOutURL)
}
print("Built iconset at \(output.path)")
