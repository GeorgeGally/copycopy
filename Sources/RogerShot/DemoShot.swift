import AppKit
import RogerCore
import ScreenCaptureKit
import os

/// `roger-shot bezel|menu|menubar --out <png> [--photo <png>] [--icon <png>]`
/// seeds a throwaway history, opens the bezel or the menu over a plain
/// backdrop, or finds the status item in the menu bar, and saves what is on
/// screen. The pixels are the windows as the window server draws them, at
/// the display's scale; nothing is painted by hand.
///
/// This is a development tool for the README. It reads other processes'
/// windows, so it needs Screen Recording; the shipped app never links
/// ScreenCaptureKit and never asks for it.
enum DemoShot: String {
    case bezel
    case menu
    case menuBar = "menubar"

    struct Invocation {
        let kind: DemoShot
        let output: URL
        let photo: URL?
        /// The menu-bar icon, since the tool has no bundle to load it from.
        let icon: URL?
    }

    static let usage = "usage: roger-shot bezel|menu|menubar --out <png> [--photo <png>] [--icon <png>]"

    private static func path(_ flag: String, in arguments: [String]) -> URL? {
        arguments.firstIndex(of: flag).flatMap { index -> URL? in
            arguments.indices.contains(index + 1) ? URL(fileURLWithPath: arguments[index + 1]) : nil
        }
    }

    static func parse(_ arguments: [String]) -> Invocation? {
        guard arguments.count > 1, let kind = DemoShot(rawValue: arguments[1]),
              let output = path("--out", in: arguments) else { return nil }
        return Invocation(kind: kind, output: output, photo: path("--photo", in: arguments), icon: path("--icon", in: arguments))
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
        let file = directory.appendingPathComponent("Mission brief.pdf")
        FileManager.default.createFile(atPath: file.path, contents: Data())
        store.recordFiles([file])
        store.recordText("""
        Pick up tux.
        Return Aston Martin
        (no bullet holes).
        Martini: shaken.\
        """)
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

    /// Writes `region` as the window server draws it, at the display's pixel
    /// density: the given windows and the backdrop under them, with every
    /// other app's windows left out, or the whole screen when `windows` is
    /// nil. Reading another process's windows needs Screen Recording access,
    /// so this fails loudly without it rather than writing a blank picture.
    ///
    /// The capture is asynchronous, but the menu runs its own tracking loop
    /// that never drains a task queued on the main actor, so this waits here.
    @discardableResult
    static func write(_ windows: [NSWindow]?, region: NSRect, to url: URL) -> Bool {
        guard let screen = NSScreen.screens.first(where: { $0.frame.contains(NSPoint(x: region.midX, y: region.midY)) })
                ?? NSScreen.screens.first else { return false }
        let windowIDs = windows.map { $0.map { CGWindowID($0.windowNumber) } }
        let displayID = screen.displayID
        let scale = screen.backingScaleFactor
        let source = CGRect(x: region.minX - screen.frame.minX, y: screen.frame.maxY - region.maxY,
                            width: region.width, height: region.height)
        let pixels = CGSize(width: (region.width * scale).rounded(), height: (region.height * scale).rounded())
        let wrote = OSAllocatedUnfairLock(initialState: false)
        let finished = DispatchSemaphore(value: 0)
        Task.detached {
            let result = await capture(windowIDs: windowIDs, displayID: displayID, source: source, pixels: pixels, to: url)
            wrote.withLock { $0 = result }
            finished.signal()
        }
        guard finished.wait(timeout: .now() + 10) == .success else {
            report("the window server did not answer the capture")
            return false
        }
        return wrote.withLock { $0 }
    }

    private nonisolated static func capture(windowIDs: [CGWindowID]?, displayID: CGDirectDisplayID,
                                            source: CGRect, pixels: CGSize, to url: URL) async -> Bool {
        let content: SCShareableContent
        do {
            content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        } catch {
            report("""
            screen capture is not allowed (\(error.localizedDescription)). \
            Allow the terminal running roger-shot in System Settings > Privacy & Security > Screen Recording, then take the shot again.
            """)
            return false
        }
        guard let display = content.displays.first(where: { $0.displayID == displayID }) else {
            report("could not find the display holding the demo windows")
            return false
        }
        let own = windowIDs.map(Set.init)
        let filter = SCContentFilter(display: display,
                                     excludingWindows: content.windows.filter { own?.contains($0.windowID) == false })
        let configuration = SCStreamConfiguration()
        configuration.sourceRect = source
        configuration.width = Int(pixels.width)
        configuration.height = Int(pixels.height)
        configuration.showsCursor = false
        configuration.capturesAudio = false
        let image: CGImage
        do {
            image = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: configuration)
        } catch {
            report("screen capture failed (\(error.localizedDescription))")
            return false
        }
        let bitmap = NSBitmapImageRep(cgImage: image)
        bitmap.size = source.size
        guard let data = bitmap.representation(using: .png, properties: [:]) else { return false }
        do { try data.write(to: url, options: .atomic) } catch {
            report(error.localizedDescription)
            return false
        }
        return true
    }

    private nonisolated static func report(_ message: String) {
        FileHandle.standardError.write(Data("roger-shot: \(message)\n".utf8))
    }
}

private extension NSScreen {
    var displayID: CGDirectDisplayID {
        (deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value ?? 0
    }
}

private final class BackdropView: NSView {
    override func draw(_ dirtyRect: NSRect) {
        let top = NSColor(srgbRed: 0.86, green: 0.86, blue: 0.875, alpha: 1)
        let bottom = NSColor(srgbRed: 0.80, green: 0.80, blue: 0.815, alpha: 1)
        NSGradient(starting: top, ending: bottom)?.draw(in: bounds, angle: -90)
    }
}
