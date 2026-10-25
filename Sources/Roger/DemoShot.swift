import AppKit

/// `--demo-shot bezel|menu --demo-out <png>` seeds a throwaway history,
/// opens the bezel or the menu over a plain backdrop and saves what is on
/// screen. The pixels are the app's own windows as the window server draws
/// them, at the display's scale; nothing is painted by hand.
enum DemoShot: String {
    case bezel
    case menu

    struct Invocation {
        let kind: DemoShot
        let output: URL
        let photo: URL?
    }

    static func parse(_ arguments: [String]) -> Invocation? {
        guard let shot = arguments.firstIndex(of: "--demo-shot"),
              arguments.indices.contains(shot + 1),
              let kind = DemoShot(rawValue: arguments[shot + 1]),
              let out = arguments.firstIndex(of: "--demo-out"),
              arguments.indices.contains(out + 1) else { return nil }
        let photo = arguments.firstIndex(of: "--demo-photo").flatMap { index -> URL? in
            arguments.indices.contains(index + 1) ? URL(fileURLWithPath: arguments[index + 1]) : nil
        }
        return Invocation(kind: kind, output: URL(fileURLWithPath: arguments[out + 1]), photo: photo)
    }

    var directory: URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("roger-demo-\(rawValue)", isDirectory: true)
    }

    /// Both pictures are this wide, in points, so they line up in the README.
    static let width = BezelMetrics.width + BezelMetrics.shadowMargin * 2

    /// The bezel opens on the line of prose, between the photo and the file.
    static let selection = 1

    /// Recorded oldest first, so the strip reads photo, prose, file, command,
    /// link from the newest end and the menu lists them in that order.
    @MainActor
    func seed(into store: HistoryStore, photo: URL?) {
        store.recordText("https://github.com/GeorgeGally/roger/releases")
        store.recordText("git rebase --autosquash origin/main")
        let file = directory.appendingPathComponent("Launch checklist.pdf")
        FileManager.default.createFile(atPath: file.path, contents: Data())
        store.recordFiles([file])
        store.recordText("Coffee with Sam at 11, then the design review.")
        if let photo, let data = try? Data(contentsOf: photo) {
            store.recordPNG(data)
        }
    }
}

@MainActor
enum DemoCapture {
    /// Room above and below the menu for its shadow.
    static let menuMarginTop: CGFloat = 24
    static let menuMarginBottom: CGFloat = 40

    /// A flat window just under the panel or menu, so the glass has something
    /// quiet to blur and the shadow has something to fall on.
    static func backdrop(_ frame: NSRect) -> NSWindow {
        let window = NSWindow(contentRect: frame, styleMask: .borderless, backing: .buffered, defer: false)
        window.level = NSWindow.Level(rawValue: NSWindow.Level.popUpMenu.rawValue - 1)
        window.isOpaque = true
        window.hasShadow = false
        window.ignoresMouseEvents = true
        window.isReleasedWhenClosed = false
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        window.contentView = BackdropView(frame: NSRect(origin: .zero, size: frame.size))
        window.orderFrontRegardless()
        return window
    }

    /// Writes the given windows, back to front, as they appear inside
    /// `region`, at the display's pixel density. Each window is read from the
    /// window server on its own and the pictures are stacked, which is what
    /// the server does on screen; an app may read its own windows this way
    /// without screen-recording access.
    @discardableResult
    static func write(_ windows: [NSWindow], region: NSRect, to url: URL) -> Bool {
        guard let primary = NSScreen.screens.first else { return false }
        let bounds = CGRect(x: region.minX, y: primary.frame.maxY - region.maxY,
                            width: region.width, height: region.height)
        let layers = windows.compactMap {
            CGWindowListCreateImage(bounds, .optionIncludingWindow, CGWindowID($0.windowNumber), [.bestResolution])
        }
        guard layers.count == windows.count, let first = layers.first,
              let context = CGContext(data: nil, width: first.width, height: first.height, bitsPerComponent: 8,
                                      bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
            NSLog("Roger demo: could not read %d windows", windows.count)
            return false
        }
        let frame = CGRect(x: 0, y: 0, width: first.width, height: first.height)
        for layer in layers { context.draw(layer, in: frame) }
        guard let image = context.makeImage() else { return false }
        let bitmap = NSBitmapImageRep(cgImage: image)
        bitmap.size = region.size
        guard let data = bitmap.representation(using: .png, properties: [:]) else { return false }
        do { try data.write(to: url, options: .atomic) } catch {
            NSLog("Roger demo: %@", error.localizedDescription)
            return false
        }
        return true
    }
}

private final class BackdropView: NSView {
    override func draw(_ dirtyRect: NSRect) {
        let top = NSColor(srgbRed: 0.86, green: 0.86, blue: 0.875, alpha: 1)
        let bottom = NSColor(srgbRed: 0.80, green: 0.80, blue: 0.815, alpha: 1)
        NSGradient(starting: top, ending: bottom)?.draw(in: bounds, angle: -90)
    }
}
