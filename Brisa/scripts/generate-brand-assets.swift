#!/usr/bin/env swift
import AppKit
import CoreGraphics
import CoreText
import Foundation

// Reproducible Brisa brand asset pipeline.
// Generates editable vector SVG + PDF + scaled PNG masters under packaging/brand/
// and copies optimized runtime resources into Sources/BrisaApp/Resources/.

enum BrandVector {
    static func rawPaths(micro: Bool) -> (upper: CGPath, lower: CGPath) {
        let leftX: CGFloat = 175
        let topY: CGFloat = 95
        let botY: CGFloat = 905
        let corner: CGFloat = 24

        let upper = CGMutablePath()
        let mastBottomY: CGFloat = micro ? 580 : 614
        let innerTopY: CGFloat = micro ? 232 : 216

        upper.move(to: CGPoint(x: leftX, y: topY + corner))
        upper.addQuadCurve(to: CGPoint(x: leftX + corner, y: topY), control: CGPoint(x: leftX, y: topY))
        upper.addLine(to: CGPoint(x: 495, y: topY))
        upper.addCurve(to: CGPoint(x: 794, y: 288),
                       control1: CGPoint(x: 686, y: topY),
                       control2: CGPoint(x: 794, y: 172))
        upper.addCurve(to: CGPoint(x: 682, y: 448),
                       control1: CGPoint(x: 794, y: 368),
                       control2: CGPoint(x: 742, y: 422))
        upper.addLine(to: CGPoint(x: 560, y: 430))
        upper.addCurve(to: CGPoint(x: 638, y: 302),
                       control1: CGPoint(x: 616, y: 392),
                       control2: CGPoint(x: 638, y: 350))
        upper.addCurve(to: CGPoint(x: 486, y: innerTopY),
                       control1: CGPoint(x: 638, y: 248),
                       control2: CGPoint(x: 576, y: innerTopY))
        upper.addCurve(to: CGPoint(x: 312, y: 330),
                       control1: CGPoint(x: 396, y: innerTopY),
                       control2: CGPoint(x: 348, y: 264))
        upper.addCurve(to: CGPoint(x: leftX, y: mastBottomY),
                       control1: CGPoint(x: 262, y: 414),
                       control2: CGPoint(x: 214, y: 498))
        upper.closeSubpath()

        let lower = CGMutablePath()
        let heelTopY: CGFloat = micro ? 684 : 692
        let bridgeY: CGFloat = micro ? 406 : 398
        let botSlitX: CGFloat = micro ? 372 : 344
        let heelRightX: CGFloat = micro ? 268 : 272
        let lowerInnerTopY: CGFloat = micro ? 548 : 526
        let lowerInnerBotY: CGFloat = micro ? 762 : 776

        lower.move(to: CGPoint(x: leftX, y: botY - corner))
        lower.addLine(to: CGPoint(x: leftX, y: heelTopY))
        lower.addCurve(to: CGPoint(x: 515, y: bridgeY),
                       control1: CGPoint(x: 238, y: 512),
                       control2: CGPoint(x: 352, y: bridgeY))
        lower.addCurve(to: CGPoint(x: 682, y: 448),
                       control1: CGPoint(x: 604, y: bridgeY),
                       control2: CGPoint(x: 656, y: 428))
        lower.addCurve(to: CGPoint(x: 842, y: 656),
                       control1: CGPoint(x: 782, y: 490),
                       control2: CGPoint(x: 842, y: 558))
        lower.addCurve(to: CGPoint(x: 528, y: botY),
                       control1: CGPoint(x: 842, y: 808),
                       control2: CGPoint(x: 716, y: botY))
        lower.addLine(to: CGPoint(x: botSlitX, y: botY))
        lower.addCurve(to: CGPoint(x: 534, y: lowerInnerBotY),
                       control1: CGPoint(x: botSlitX + 42, y: 806),
                       control2: CGPoint(x: 444, y: lowerInnerBotY))
        lower.addCurve(to: CGPoint(x: 682, y: 652),
                       control1: CGPoint(x: 624, y: lowerInnerBotY),
                       control2: CGPoint(x: 682, y: 722))
        lower.addCurve(to: CGPoint(x: 514, y: lowerInnerTopY),
                       control1: CGPoint(x: 682, y: 580),
                       control2: CGPoint(x: 612, y: lowerInnerTopY))
        lower.addCurve(to: CGPoint(x: heelRightX, y: botY),
                       control1: CGPoint(x: 356, y: lowerInnerTopY),
                       control2: CGPoint(x: 274, y: 668))
        lower.addLine(to: CGPoint(x: leftX + corner, y: botY))
        lower.addQuadCurve(to: CGPoint(x: leftX, y: botY - corner), control: CGPoint(x: leftX, y: botY))
        lower.closeSubpath()

        return (upper, lower)
    }

    static func unifiedMark(micro: Bool) -> CGPath {
        let (u, l) = rawPaths(micro: micro)
        if #available(macOS 13.0, *) {
            return u.union(l)
        }
        let m = CGMutablePath()
        m.addPath(u)
        m.addPath(l)
        return m
    }

    static func wordmark(text: String = "brisa", fontSize: CGFloat = 556, tracking: CGFloat = -20, originX: CGFloat = 930, baselineY: CGFloat = 730) -> CGPath {
        let desc = NSFont.systemFont(ofSize: fontSize, weight: .semibold).fontDescriptor.withDesign(.rounded)!
        let font = (NSFont(descriptor: desc, size: fontSize) ?? NSFont.systemFont(ofSize: fontSize, weight: .semibold)) as CTFont
        let result = CGMutablePath()
        var cursorX = originX
        let chars = Array(text.utf16)
        var glyphs = [CGGlyph](repeating: 0, count: chars.count)
        CTFontGetGlyphsForCharacters(font, chars, &glyphs, chars.count)
        var advances = [CGSize](repeating: .zero, count: chars.count)
        CTFontGetAdvancesForGlyphs(font, .horizontal, glyphs, &advances, chars.count)

        for i in 0..<glyphs.count {
            if let glyphPath = CTFontCreatePathForGlyph(font, glyphs[i], nil) {
                let transform = CGAffineTransform(translationX: cursorX, y: baselineY).scaledBy(x: 1, y: -1)
                result.addPath(glyphPath, transform: transform)
            }
            cursorX += advances[i].width + tracking
        }
        return result
    }
}

enum BrandVariant: String, CaseIterable {
    case color
    case colorDark = "color-dark"
    case light, dark, mono

    var isColoredMark: Bool { self == .color || self == .colorDark }

    var wordmarkHex: String {
        switch self {
        case .color, .light: return "#1D1D1F"
        case .colorDark, .dark: return "#F5F5F7"
        case .mono: return "#000000"
        }
    }
    var markHex: String {
        switch self {
        case .color, .colorDark: return "url(#brisaGrad)"
        case .light: return "#1D1D1F"
        case .dark: return "#F5F5F7"
        case .mono: return "#000000"
        }
    }
    var nsInk: NSColor {
        switch self {
        case .color, .light: return NSColor(srgbRed: 29/255, green: 29/255, blue: 31/255, alpha: 1)
        case .colorDark, .dark: return NSColor(srgbRed: 245/255, green: 245/255, blue: 247/255, alpha: 1)
        case .mono: return .black
        }
    }
}

func svgD(from path: CGPath) -> String {
    var d = ""
    path.applyWithBlock { ptr in
        let e = ptr.pointee
        func f(_ v: CGFloat) -> String { String(format: "%.2f", v) }
        switch e.type {
        case .moveToPoint:
            d += "M\(f(e.points[0].x)) \(f(e.points[0].y)) "
        case .addLineToPoint:
            d += "L\(f(e.points[0].x)) \(f(e.points[0].y)) "
        case .addQuadCurveToPoint:
            d += "Q\(f(e.points[0].x)) \(f(e.points[0].y)) \(f(e.points[1].x)) \(f(e.points[1].y)) "
        case .addCurveToPoint:
            d += "C\(f(e.points[0].x)) \(f(e.points[0].y)) \(f(e.points[1].x)) \(f(e.points[1].y)) \(f(e.points[2].x)) \(f(e.points[2].y)) "
        case .closeSubpath:
            d += "Z "
        @unknown default:
            break
        }
    }
    return d.trimmingCharacters(in: .whitespaces)
}

func writeSVG(viewBox: String, width: Int, height: Int, variant: BrandVariant, markPath: CGPath, wordPath: CGPath?, to url: URL) throws {
    let defs = variant.isColoredMark ? """
      <defs>
        <linearGradient id="brisaGrad" x1="175" y1="100" x2="842" y2="900" gradientUnits="userSpaceOnUse">
          <stop offset="0%" stop-color="#0A84FF"/>
          <stop offset="52%" stop-color="#17C4C5"/>
          <stop offset="100%" stop-color="#28CD78"/>
        </linearGradient>
      </defs>

    """ : ""
    let markEl = "<path d=\"\(svgD(from: markPath))\" fill=\"\(variant.markHex)\"/>"
    let wordEl = wordPath.map { "\n  <path d=\"\(svgD(from: $0))\" fill=\"\(variant.wordmarkHex)\"/>" } ?? ""
    let svg = """
    <?xml version="1.0" encoding="UTF-8"?>
    <svg xmlns="http://www.w3.org/2000/svg" viewBox="\(viewBox)" width="\(width)" height="\(height)" fill="none">
    \(defs)  \(markEl)\(wordEl)
    </svg>
    """
    try svg.write(to: url, atomically: true, encoding: .utf8)
}

func drawBrand(cg: CGContext, variant: BrandVariant, markPath: CGPath, wordPath: CGPath?, boxSize: NSSize, scale: CGFloat) {
    cg.saveGState()
    cg.translateBy(x: 0, y: boxSize.height)
    cg.scaleBy(x: scale, y: -scale)

    if variant.isColoredMark {
        cg.saveGState()
        cg.addPath(markPath)
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
    } else {
        cg.setFillColor(variant.nsInk.cgColor)
        cg.addPath(markPath)
        cg.fillPath()
    }
    if let wp = wordPath {
        cg.setFillColor(variant.nsInk.cgColor)
        cg.addPath(wp)
        cg.fillPath()
    }
    cg.restoreGState()
}

func writePDF(mediaBox: CGRect, scale: CGFloat, variant: BrandVariant, markPath: CGPath, wordPath: CGPath?, to url: URL) throws {
    let data = NSMutableData()
    var box = mediaBox
    guard let consumer = CGDataConsumer(data: data),
          let pdf = CGContext(consumer: consumer, mediaBox: &box, nil) else { return }
    pdf.beginPDFPage(nil)
    drawBrand(cg: pdf, variant: variant, markPath: markPath, wordPath: wordPath, boxSize: box.size, scale: scale)
    pdf.endPDFPage()
    pdf.closePDF()
    try (data as Data).write(to: url)
}

func makeBitmap(_ w: Int, _ h: Int) -> NSBitmapImageRep {
    let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: w, pixelsHigh: h,
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
    )!
    rep.size = NSSize(width: w, height: h)
    return rep
}

func writePNG(width: Int, height: Int, scale: CGFloat, variant: BrandVariant, markPath: CGPath, wordPath: CGPath?, to url: URL) throws {
    let rep = makeBitmap(width, height)
    NSGraphicsContext.saveGraphicsState()
    let ctx = NSGraphicsContext(bitmapImageRep: rep)!
    NSGraphicsContext.current = ctx
    drawBrand(cg: ctx.cgContext, variant: variant, markPath: markPath, wordPath: wordPath, boxSize: NSSize(width: width, height: height), scale: scale)
    NSGraphicsContext.restoreGraphicsState()
    try rep.representation(using: .png, properties: [:])!.write(to: url)
}

func writeMenuBarPNG(pixels: Int, markPath: CGPath, to url: URL) throws {
    let rep = makeBitmap(pixels, pixels)
    NSGraphicsContext.saveGraphicsState()
    let ctx = NSGraphicsContext(bitmapImageRep: rep)!
    NSGraphicsContext.current = ctx
    let cg = ctx.cgContext
    let s = CGFloat(pixels)
    let pad = s * 0.06
    let inner = s - pad * 2
    cg.translateBy(x: pad, y: s - pad)
    cg.scaleBy(x: inner / 1000.0, y: -(inner / 1000.0))
    cg.setFillColor(NSColor.black.cgColor)
    cg.addPath(markPath)
    cg.fillPath()
    NSGraphicsContext.restoreGraphicsState()
    try rep.representation(using: .png, properties: [:])!.write(to: url)
}

func processIllustration(srcPath: String, mode: String, outURL: URL, targetWidth: Int) throws {
    guard let srcImg = NSImage(contentsOfFile: srcPath),
          let cgSrc = srcImg.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
        throw NSError(domain: "BrisaBrand", code: 1, userInfo: [NSLocalizedDescriptionKey: "Missing source image at \(srcPath)"])
    }
    let w = targetWidth
    let h = Int(Double(cgSrc.height) * Double(w) / Double(cgSrc.width))
    let rep = makeBitmap(w, h)
    guard let raw = rep.bitmapData,
          let ctx = CGContext(
              data: raw, width: w, height: h, bitsPerComponent: 8, bytesPerRow: rep.bytesPerRow,
              space: CGColorSpaceCreateDeviceRGB(),
              bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
          ) else { return }
    ctx.interpolationQuality = .high
    ctx.draw(cgSrc, in: CGRect(x: 0, y: 0, width: w, height: h))

    func offset(_ x: Int, _ y: Int) -> Int { y * rep.bytesPerRow + x * 4 }
    let samples = [(4, 4), (w - 5, 4), (4, h - 5), (w - 5, h - 5)]
    var bgR = 0.0, bgG = 0.0, bgB = 0.0
    for (sx, sy) in samples {
        let o = offset(sx, sy)
        bgR += Double(raw[o]); bgG += Double(raw[o + 1]); bgB += Double(raw[o + 2])
    }
    bgR /= 4.0; bgG /= 4.0; bgB /= 4.0

    for y in 0..<h {
        let ny = (Double(y) / Double(h - 1)) * 2.0 - 1.0
        for x in 0..<w {
            let nx = (Double(x) / Double(w - 1)) * 2.0 - 1.0
            let o = offset(x, y)
            let r = Double(raw[o])
            let g = Double(raw[o + 1])
            let b = Double(raw[o + 2])
            let dist = sqrt((r - bgR)*(r - bgR) + (g - bgG)*(g - bgG) + (b - bgB)*(b - bgB))

            if mode == "empty-light" || mode == "empty-dark" {
                let rad = sqrt(nx * nx + ny * ny)
                // Clean circular clip eliminating outer corner artifacts/vignette completely
                let circleMask = 1.0 - min(1.0, max(0.0, (rad - 0.68) / 0.10))
                var alpha = min(1.0, max(0.0, (dist - 6.0) / 30.0))
                alpha = pow(alpha, 0.72) * circleMask
                var outR = r, outG = g, outB = b
                if mode == "empty-dark" {
                    let maxC = max(r, max(g, b)), minC = min(r, min(g, b))
                    let sat = maxC > 1 ? (maxC - minC) / maxC : 0
                    let satBlend = min(1.0, max(0.0, (sat - 0.06) / 0.18))
                    let lum = 0.299 * r + 0.587 * g + 0.114 * b
                    let frost = min(238.0, max(160.0, 255.0 - lum * 0.34 + 48.0))
                    let grayR = frost * 0.94, grayG = frost * 0.97, grayB = frost
                    let colorR = min(255.0, r * 1.06 + 10.0)
                    let colorG = min(255.0, g * 1.05 + 12.0)
                    let colorB = min(255.0, b * 1.06 + 15.0)
                    outR = grayR * (1.0 - satBlend) + colorR * satBlend
                    outG = grayG * (1.0 - satBlend) + colorG * satBlend
                    outB = grayB * (1.0 - satBlend) + colorB * satBlend
                }
                raw[o]     = UInt8(min(255, max(0, outR * alpha)))
                raw[o + 1] = UInt8(min(255, max(0, outG * alpha)))
                raw[o + 2] = UInt8(min(255, max(0, outB * alpha)))
                raw[o + 3] = UInt8(min(255, max(0, alpha * 255.0)))
            } else if mode == "welcome-light" {
                let rad = sqrt(nx * nx * 0.85 + ny * ny * 1.02)
                let edge = 1.0 - min(1.0, max(0.0, (rad - 0.62) / 0.28))
                let smooth = edge * edge * (3.0 - 2.0 * edge)
                // Only gently key outer near-white margin while preserving 100% of glass/shadow core
                let coreMask = 1.0 - min(1.0, max(0.0, (rad - 0.52) / 0.16))
                let colorAlpha = min(1.0, max(0.0, (dist - 3.0) / 18.0))
                let alpha = smooth * max(coreMask, colorAlpha)
                raw[o]     = UInt8(min(255, max(0, r * alpha)))
                raw[o + 1] = UInt8(min(255, max(0, g * alpha)))
                raw[o + 2] = UInt8(min(255, max(0, b * alpha)))
                raw[o + 3] = UInt8(min(255, max(0, alpha * 255.0)))
            } else if mode == "welcome-dark" {
                // Keep dark smoked-glass platter core 100% solid (zero pinholes!), dissolve outer edge cleanly
                let rad = sqrt(nx * nx * 0.85 + ny * ny * 1.02)
                let edge = 1.0 - min(1.0, max(0.0, (rad - 0.56) / 0.34))
                let alpha = edge * edge * (3.0 - 2.0 * edge)
                // Shift flat charcoal #151922 perimeter subtly toward dark #1C1C1E background tone for invisible merge
                let bgMatch = min(1.0, max(0.0, (dist - 2.0) / 18.0))
                let adjR = r * bgMatch + 28.0 * (1.0 - bgMatch)
                let adjG = g * bgMatch + 28.0 * (1.0 - bgMatch)
                let adjB = b * bgMatch + 30.0 * (1.0 - bgMatch)
                raw[o]     = UInt8(min(255, max(0, adjR * alpha)))
                raw[o + 1] = UInt8(min(255, max(0, adjG * alpha)))
                raw[o + 2] = UInt8(min(255, max(0, adjB * alpha)))
                raw[o + 3] = UInt8(min(255, max(0, alpha * 255.0)))
            }
        }
    }
    try rep.representation(using: .png, properties: [:])!.write(to: outURL)
}

let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
let brandDir = root.appendingPathComponent("packaging/brand")
let sourcesDir = brandDir.appendingPathComponent("sources")
let resourcesDir = root.appendingPathComponent("Sources/BrisaApp/Resources")

let fm = FileManager.default
try fm.createDirectory(at: brandDir, withIntermediateDirectories: true)
try fm.createDirectory(at: resourcesDir, withIntermediateDirectories: true)

let markStd = BrandVector.unifiedMark(micro: false)
let markMicro = BrandVector.unifiedMark(micro: true)
let wordPath = BrandVector.wordmark()

for variant in BrandVariant.allCases {
    if variant != .colorDark {
        // Masters in packaging/brand/ (isotipo is shared between color & color-dark)
        try writeSVG(viewBox: "0 0 1000 1000", width: 1000, height: 1000, variant: variant, markPath: markStd, wordPath: nil,
                     to: brandDir.appendingPathComponent("isotipo-\(variant.rawValue).svg"))
        try writePDF(mediaBox: CGRect(x: 0, y: 0, width: 100, height: 100), scale: 0.1, variant: variant, markPath: markStd, wordPath: nil,
                     to: brandDir.appendingPathComponent("isotipo-\(variant.rawValue).pdf"))
        try writePNG(width: 1024, height: 1024, scale: 1.024, variant: variant, markPath: markStd, wordPath: nil,
                     to: brandDir.appendingPathComponent("isotipo-\(variant.rawValue)-1024.png"))
        try writePNG(width: 512, height: 512, scale: 0.512, variant: variant, markPath: markStd, wordPath: nil,
                     to: brandDir.appendingPathComponent("isotipo-\(variant.rawValue)-512.png"))
        try writePDF(mediaBox: CGRect(x: 0, y: 0, width: 100, height: 100), scale: 0.1, variant: variant, markPath: markStd, wordPath: nil,
                     to: resourcesDir.appendingPathComponent("brisa-isotipo-\(variant.rawValue).pdf"))
    }

    try writeSVG(viewBox: "0 0 2260 1000", width: 2260, height: 1000, variant: variant, markPath: markStd, wordPath: wordPath,
                 to: brandDir.appendingPathComponent("lockup-\(variant.rawValue).svg"))
    try writePDF(mediaBox: CGRect(x: 0, y: 0, width: 226, height: 100), scale: 0.1, variant: variant, markPath: markStd, wordPath: wordPath,
                 to: brandDir.appendingPathComponent("lockup-\(variant.rawValue).pdf"))
    try writePNG(width: 1130, height: 500, scale: 0.5, variant: variant, markPath: markStd, wordPath: wordPath,
                 to: brandDir.appendingPathComponent("lockup-\(variant.rawValue).png"))

    // Runtime vector PDFs in Sources/BrisaApp/Resources/
    try writePDF(mediaBox: CGRect(x: 0, y: 0, width: 226, height: 100), scale: 0.1, variant: variant, markPath: markStd, wordPath: wordPath,
                 to: resourcesDir.appendingPathComponent("brisa-lockup-\(variant.rawValue).pdf"))
}

// Menu Bar micro-compensated monochrome template assets
try writeSVG(viewBox: "0 0 1000 1000", width: 18, height: 18, variant: .mono, markPath: markMicro, wordPath: nil,
             to: brandDir.appendingPathComponent("menubar-template.svg"))
try writePDF(mediaBox: CGRect(x: 0, y: 0, width: 18, height: 18), scale: 0.018, variant: .mono, markPath: markMicro, wordPath: nil,
             to: brandDir.appendingPathComponent("menubar-template.pdf"))
try writeMenuBarPNG(pixels: 18, markPath: markMicro, to: brandDir.appendingPathComponent("menubar-template-18.png"))
try writeMenuBarPNG(pixels: 36, markPath: markMicro, to: brandDir.appendingPathComponent("menubar-template-36.png"))

try writeMenuBarPNG(pixels: 18, markPath: markMicro, to: resourcesDir.appendingPathComponent("brisa-menubar.png"))
try writeMenuBarPNG(pixels: 36, markPath: markMicro, to: resourcesDir.appendingPathComponent("brisa-menubar@2x.png"))

// Editorial Welcome & Empty Spot Illustrations (processed locally to transparent PNGs)
try processIllustration(srcPath: sourcesDir.appendingPathComponent("welcome-light-source.jpg").path, mode: "welcome-light",
                        outURL: resourcesDir.appendingPathComponent("brisa-welcome-light.png"), targetWidth: 960)
try processIllustration(srcPath: sourcesDir.appendingPathComponent("welcome-dark-source.jpg").path, mode: "welcome-dark",
                        outURL: resourcesDir.appendingPathComponent("brisa-welcome-dark.png"), targetWidth: 960)
try processIllustration(srcPath: sourcesDir.appendingPathComponent("empty-spot-source.jpg").path, mode: "empty-light",
                        outURL: resourcesDir.appendingPathComponent("brisa-empty-spot-light.png"), targetWidth: 320)
try processIllustration(srcPath: sourcesDir.appendingPathComponent("empty-spot-source.jpg").path, mode: "empty-dark",
                        outURL: resourcesDir.appendingPathComponent("brisa-empty-spot-dark.png"), targetWidth: 320)

print("Generated brand masters in \(brandDir.path) and runtime resources in \(resourcesDir.path)")
