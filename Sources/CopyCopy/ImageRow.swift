import AppKit
import ImageIO

/// A menu row for a stored image: the picture is the label. One row per
/// item, tall enough that the preview is recognisable, no text at all.
@MainActor
final class ImageRowView: NSView {
    static let height: CGFloat = 56
    static let thumbnailSize = NSSize(width: 48, height: 48)
    static let inset: CGFloat = 14
    static let radius: CGFloat = 6
    private static var cache: [URL: NSImage] = [:]

    private let thumbnail: NSImage

    init?(url: URL, width: CGFloat) {
        guard let thumbnail = Self.thumbnail(for: url) else { return nil }
        self.thumbnail = thumbnail
        super.init(frame: NSRect(x: 0, y: 0, width: width, height: Self.height))
        autoresizingMask = [.width]
        toolTip = nil
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override func updateTrackingAreas() {
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .activeInActiveApp, .inVisibleRect], owner: self))
        super.updateTrackingAreas()
    }

    override func mouseEntered(with event: NSEvent) { needsDisplay = true }
    override func mouseExited(with event: NSEvent) { needsDisplay = true }

    override func mouseUp(with event: NSEvent) {
        guard let item = enclosingMenuItem, let menu = item.menu else { return }
        menu.cancelTracking()
        menu.performActionForItem(at: menu.index(of: item))
    }

    override func draw(_ dirtyRect: NSRect) {
        if enclosingMenuItem?.isHighlighted == true {
            NSColor.selectedContentBackgroundColor.setFill()
            NSBezierPath(roundedRect: bounds.insetBy(dx: 5, dy: 0), xRadius: 5, yRadius: 5).fill()
        }
        let size = Self.thumbnailSize
        thumbnail.draw(in: NSRect(x: Self.inset, y: (bounds.height - size.height) / 2, width: size.width, height: size.height))
    }

    override func accessibilityLabel() -> String? { "Image" }

    /// Cover-crops the image into a rounded rectangle at row size.
    private static func thumbnail(for url: URL) -> NSImage? {
        if let cached = cache[url] { return cached }
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceThumbnailMaxPixelSize: 256,
                kCGImageSourceCreateThumbnailWithTransform: true
              ] as CFDictionary) else { return nil }
        let thumbnail = NSImage(size: thumbnailSize, flipped: false) { rect in
            NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius).addClip()
            let scale = max(rect.width / CGFloat(image.width), rect.height / CGFloat(image.height))
            let drawn = NSSize(width: CGFloat(image.width) * scale, height: CGFloat(image.height) * scale)
            NSImage(cgImage: image, size: .zero).draw(in: NSRect(x: rect.midX - drawn.width / 2, y: rect.midY - drawn.height / 2,
                                                                 width: drawn.width, height: drawn.height))
            return true
        }
        cache[url] = thumbnail
        return thumbnail
    }
}
