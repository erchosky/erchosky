import AppKit
import BrisaCore
import SwiftUI

enum BrandAssetVariant: String, Sendable {
    case color
    case colorDark = "color-dark"
    case light
    case dark
    case monochrome = "mono"
}

enum BrandIllustration: Sendable {
    case welcome
    case emptyState
}

@MainActor
enum BrandAssetCatalog {
    private static var cachedImages: [String: NSImage] = [:]

    static let resourceBundle: Bundle? = {
        ResourceBundleLocator.locate(named: "Brisa_BrisaApp") { Bundle.module }
    }()

    static func resourceURL(named name: String, extension ext: String) -> URL? {
        resourceBundle?.url(forResource: name, withExtension: ext)
    }

    static func isotipoImage(variant: BrandAssetVariant = .color) -> NSImage? {
        let resolvedVariant = variant == .colorDark ? .color : variant
        let key = "brisa-isotipo-\(resolvedVariant.rawValue)"
        if let cached = cachedImages[key] { return cached }
        guard let url = resourceURL(named: key, extension: "pdf"),
              let image = NSImage(contentsOf: url) else {
            return nil
        }
        image.isTemplate = (variant == .monochrome)
        cachedImages[key] = image
        return image
    }

    static func lockupImage(variant: BrandAssetVariant = .color) -> NSImage? {
        let key = "brisa-lockup-\(variant.rawValue)"
        if let cached = cachedImages[key] { return cached }
        guard let url = resourceURL(named: key, extension: "pdf"),
              let image = NSImage(contentsOf: url) else {
            return nil
        }
        image.isTemplate = (variant == .monochrome)
        cachedImages[key] = image
        return image
    }

    static func menuBarTemplateImage() -> NSImage? {
        let key = "brisa-menubar-template"
        if let cached = cachedImages[key] { return cached }

        let targetSize = NSSize(width: 18, height: 18)
        let image = NSImage(size: targetSize)

        if let url1x = resourceURL(named: "brisa-menubar", extension: "png"),
           let data1x = try? Data(contentsOf: url1x),
           let rep1x = NSBitmapImageRep(data: data1x) {
            rep1x.size = targetSize
            image.addRepresentation(rep1x)
        }
        if let url2x = resourceURL(named: "brisa-menubar@2x", extension: "png"),
           let data2x = try? Data(contentsOf: url2x),
           let rep2x = NSBitmapImageRep(data: data2x) {
            rep2x.size = targetSize
            image.addRepresentation(rep2x)
        }

        guard !image.representations.isEmpty else { return nil }
        image.size = targetSize
        image.isTemplate = true
        cachedImages[key] = image
        return image
    }

    static func illustrationImage(_ kind: BrandIllustration, colorScheme: ColorScheme) -> NSImage? {
        let suffix = colorScheme == .dark ? "dark" : "light"
        let key: String
        switch kind {
        case .welcome:
            key = "brisa-welcome-\(suffix)"
        case .emptyState:
            key = "brisa-empty-spot-\(suffix)"
        }
        if let cached = cachedImages[key] { return cached }
        guard let url = resourceURL(named: key, extension: "png"),
              let image = NSImage(contentsOf: url) else {
            return nil
        }
        cachedImages[key] = image
        return image
    }
}

struct BrandMenuBarGlyph: View {
    var body: some View {
        if let image = BrandAssetCatalog.menuBarTemplateImage() {
            Image(nsImage: image)
                .renderingMode(.template)
                .accessibilityHidden(true)
        } else {
            Image(systemName: "wind")
                .accessibilityHidden(true)
        }
    }
}

struct BrandLockup: View {
    var height: CGFloat = 34
    var variant: BrandAssetVariant? = nil
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let resolved = variant ?? (colorScheme == .dark ? .colorDark : .color)
        if let image = BrandAssetCatalog.lockupImage(variant: resolved) {
            Image(nsImage: image)
                .renderingMode(resolved == .monochrome ? .template : .original)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(height: height)
                .accessibilityHidden(true)
        } else {
            HStack(spacing: 10) {
                BrandMark(size: height)
                Text("brisa")
                    .font(.system(size: height * 0.68, weight: .semibold, design: .rounded))
                    .tracking(-0.8)
            }
        }
    }
}

struct BrandIllustrationView: View {
    let kind: BrandIllustration
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        if let image = BrandAssetCatalog.illustrationImage(kind, colorScheme: colorScheme) {
            Image(nsImage: image)
                .resizable()
                .interpolation(.high)
                .aspectRatio(contentMode: .fit)
                .accessibilityHidden(true)
        }
    }
}
