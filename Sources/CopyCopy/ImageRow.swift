import AppKit
import ImageIO

/// What a menu row shows for a stored image: the picture itself, small,
/// square and rounded, and its pixel dimensions.
@MainActor
enum ImageRow {
    static let side: CGFloat = 20
    static let radius: CGFloat = 4
    private static var cache: [URL: (thumbnail: NSImage, label: String)] = [:]

    static func content(for url: URL) -> (thumbnail: NSImage, label: String)? {
        if let cached = cache[url] { return cached }
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceThumbnailMaxPixelSize: 96,
                kCGImageSourceCreateThumbnailWithTransform: true
              ] as CFDictionary) else { return nil }
        let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]
        let width = properties?[kCGImagePropertyPixelWidth] as? Int ?? image.width
        let height = properties?[kCGImagePropertyPixelHeight] as? Int ?? image.height
        let content = (thumbnail: squareThumbnail(image), label: "\(width)×\(height)")
        cache[url] = content
        return content
    }

    /// Cover-crops the image into a rounded square at menu-icon size.
    private static func squareThumbnail(_ image: CGImage) -> NSImage {
        let size = NSSize(width: side, height: side)
        let thumbnail = NSImage(size: size, flipped: false) { rect in
            NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius).addClip()
            let scale = max(rect.width / CGFloat(image.width), rect.height / CGFloat(image.height))
            let drawn = NSSize(width: CGFloat(image.width) * scale, height: CGFloat(image.height) * scale)
            let origin = NSPoint(x: rect.midX - drawn.width / 2, y: rect.midY - drawn.height / 2)
            NSImage(cgImage: image, size: .zero).draw(in: NSRect(origin: origin, size: drawn))
            return true
        }
        thumbnail.isTemplate = false
        return thumbnail
    }
}
