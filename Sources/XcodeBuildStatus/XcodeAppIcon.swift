import AppKit
import BuildStatusCore

/// Reads the OS-provided icon of the local Xcode app. No Apple artwork is redistributed.
/// One lookup/render per launch, including a cached failure; no polling or runtime file writes.
final class XcodeAppIcon {
    private var loaded = false
    private var cached: Data?
    private(set) var signature = "hammer"
    func invalidate() { loaded = false; cached = nil; signature = "hammer" }
    func png() -> Data? {
        if loaded { return cached }
        loaded = true
        let workspace = NSWorkspace.shared
        let runningURL = workspace.runningApplications.first { $0.bundleIdentifier == "com.apple.dt.Xcode" }?.bundleURL
        guard let url = runningURL ?? workspace.urlForApplication(withBundleIdentifier: "com.apple.dt.Xcode") else { return nil }
        cached = Self.render(workspace.icon(forFile: url.path))
        if let cached { signature = historyKey(cached.base64EncodedString()) }
        if cached == nil { diagnostic("Xcode icon unavailable; using the hammer symbol.") }
        return cached
    }
    static func render(_ image: NSImage) -> Data? {
        guard image.size.width > 0, image.size.height > 0 else { return nil }
        for side in [128, 96, 64, 32] {
            guard let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: side, pixelsHigh: side,
                bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0),
                let context = NSGraphicsContext(bitmapImageRep: bitmap) else { continue }
            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current = context
            context.imageInterpolation = .high
            let canvas = NSRect(x: 0, y: 0, width: side, height: side)
            NSColor.clear.setFill(); canvas.fill(using: .copy)
            let scale = min(CGFloat(side) / image.size.width, CGFloat(side) / image.size.height)
            let size = NSSize(width: image.size.width * scale, height: image.size.height * scale)
            image.draw(in: NSRect(x: (CGFloat(side) - size.width) / 2, y: (CGFloat(side) - size.height) / 2,
                width: size.width, height: size.height), from: .zero, operation: .sourceOver, fraction: 1)
            NSGraphicsContext.restoreGraphicsState()
            if let data = bitmap.representation(using: .png, properties: [:]), data.count <= Messages.maximumIconBytes {
                return data
            }
        }
        return nil
    }
}
