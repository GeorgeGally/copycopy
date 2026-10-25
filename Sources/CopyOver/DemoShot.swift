import AppKit

enum DemoShot: String {
    case bezelText = "bezel-text"
    case bezelImage = "bezel-image"
    case menu

    struct Invocation {
        let kind: DemoShot
        let output: URL
    }

    static func parse(_ arguments: [String]) -> Invocation? {
        guard let shot = arguments.firstIndex(of: "--demo-shot"),
              arguments.indices.contains(shot + 1),
              let kind = DemoShot(rawValue: arguments[shot + 1]),
              let out = arguments.firstIndex(of: "--demo-out"),
              arguments.indices.contains(out + 1) else { return nil }
        return Invocation(kind: kind, output: URL(fileURLWithPath: arguments[out + 1]))
    }

    var directory: URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("copyover-demo-\(rawValue)", isDirectory: true)
    }

    var selection: Int {
        switch self {
        case .bezelText: return 2
        case .bezelImage: return 3
        case .menu: return 0
        }
    }

    @MainActor
    func seed(into store: HistoryStore) {
        let image = ProcessInfo.processInfo.environment["COPYOVER_DEMO_IMAGE"]
            .flatMap { try? Data(contentsOf: URL(fileURLWithPath: $0)) }
        store.recordText("Coffee with Sam at 11, then the copy-over review.")
        store.recordText("git rebase --autosquash origin/main")
        store.recordText("Meeting notes: the copy-over review is at 11.")
        if let image { store.recordPNG(image) }
        store.recordText("Ship the bezel animation before Friday, then take the README screenshots.")
        store.recordText("https://developer.apple.com/design/human-interface-guidelines/typography")
        store.recordText("npm run build -- --watch")
    }
}

@MainActor
enum DemoRender {
    static let padding: CGFloat = 56
    static let bezelRadius = BezelMetrics.cornerRadius
    static let menuRadius: CGFloat = 11

    @discardableResult
    static func write(_ view: NSView, radius: CGFloat, light: Bool, to url: URL) -> Bool {
        let size = view.bounds.size
        guard size.width > 1, size.height > 1,
              let source = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return false }
        view.cacheDisplay(in: view.bounds, to: source)
        let image = NSImage(size: size)
        image.addRepresentation(source)
        return compose(image, scale: max(CGFloat(source.pixelsWide) / size.width, 1), radius: radius, light: light, to: url)
    }

    private static func compose(_ image: NSImage, scale: CGFloat, radius: CGFloat, light: Bool, to url: URL) -> Bool {
        let size = image.size
        let canvas = NSSize(width: size.width + padding * 2, height: size.height + padding * 2)
        guard let output = NSBitmapImageRep(bitmapDataPlanes: nil,
                                            pixelsWide: Int((canvas.width * scale).rounded()),
                                            pixelsHigh: Int((canvas.height * scale).rounded()),
                                            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                                            isPlanar: false, colorSpaceName: .deviceRGB,
                                            bytesPerRow: 0, bitsPerPixel: 0),
              let context = NSGraphicsContext(bitmapImageRep: output) else { return false }

        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = context
        let cg = context.cgContext
        cg.scaleBy(x: scale, y: scale)

        let full = NSRect(origin: .zero, size: canvas)
        let backdrop = light
            ? [NSColor(srgbRed: 0.94, green: 0.94, blue: 0.95, alpha: 1), NSColor(srgbRed: 0.87, green: 0.87, blue: 0.89, alpha: 1)]
            : [NSColor(srgbRed: 0.11, green: 0.11, blue: 0.12, alpha: 1), NSColor(srgbRed: 0.045, green: 0.045, blue: 0.05, alpha: 1)]
        NSGradient(colors: backdrop)?.draw(in: full, angle: -90)

        let frame = full.insetBy(dx: padding, dy: padding)
        let path = NSBezierPath(roundedRect: frame, xRadius: radius, yRadius: radius)

        cg.saveGState()
        cg.setShadow(offset: CGSize(width: 0, height: -12), blur: 30,
                     color: NSColor.black.withAlphaComponent(0.6).cgColor)
        (light ? NSColor(srgbRed: 0.92, green: 0.92, blue: 0.93, alpha: 1) : NSColor.black).setFill()
        path.fill()
        cg.restoreGState()

        NSGraphicsContext.saveGraphicsState()
        path.addClip()
        image.draw(in: frame, from: .zero, operation: .sourceOver, fraction: 1)
        NSGraphicsContext.restoreGraphicsState()
        NSGraphicsContext.restoreGraphicsState()

        guard let data = output.representation(using: .png, properties: [:]) else { return false }
        return (try? data.write(to: url, options: .atomic)) != nil
    }
}
