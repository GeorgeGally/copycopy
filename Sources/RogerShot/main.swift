import AppKit
import RogerCore

/// Drives the real bezel and menu-bar menu from RogerCore with a seeded
/// history, then photographs them. Nothing here ships in Roger.app.
@MainActor
final class ShotDelegate: NSObject, NSApplicationDelegate {
    private let shot: DemoShot.Invocation
    private let store: HistoryStore
    /// The app's own delegate builds the menu, so the picture shows the
    /// menu users get. It is never installed as the application delegate, so
    /// it registers no hotkey and watches no pasteboard.
    private let menuSource: AppDelegate
    private lazy var bezel = BezelController(store: store)
    private var statusItem: NSStatusItem?

    init(shot: DemoShot.Invocation) {
        self.shot = shot
        try? FileManager.default.removeItem(at: shot.kind.directory)
        store = HistoryStore(directory: shot.kind.directory)
        menuSource = AppDelegate(store: store)
        super.init()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        let status = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        status.button?.image = AppDelegate.menuBarIcon(file: shot.icon)
        let menu = NSMenu()
        menu.delegate = menuSource
        status.menu = menu
        statusItem = status
        shot.kind.seed(into: store, photo: shot.photo)
        switch shot.kind {
        case .bezel:
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [weak self] in
                guard let self else { return }
                let selected = self.store.items.indices.contains(DemoShot.selection) ? self.store.items[DemoShot.selection].id : nil
                self.bezel.show(items: self.store.items, selectedID: selected, frontApp: nil)
                let region = self.bezel.frame
                let backdrop = DemoCapture.backdrop(region)
                DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                    self.finish(DemoCapture.write([backdrop, self.bezel.window], region: region, to: self.shot.output))
                }
            }
        case .menu:
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { [weak self] in
                self?.popMenu()
            }
        case .menuBar:
            // The status item and its neighbours, in whichever appearance
            // the menu bar is in right now.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { [weak self] in
                guard let self, let item = self.statusItem?.button?.window?.frame else {
                    self?.finish(false)
                    return
                }
                self.finish(DemoCapture.write(nil, region: item.insetBy(dx: -90, dy: 0), to: self.shot.output))
            }
        }
    }

    /// The menu runs its own tracking loop, so the shot is taken from timers
    /// on the common run-loop modes: one to stage the backdrop once the menu
    /// is up, one to capture after the glass has settled over it.
    private func popMenu() {
        guard statusItem?.button?.window != nil else {
            finish(false)
            return
        }
        var staged: (backdrop: NSWindow, menu: NSWindow, region: NSRect)?
        let stage = Timer(timeInterval: 0.8, repeats: false) { _ in
            MainActor.assumeIsolated {
                guard let menu = NSApp.windows.first(where: { $0.level == .popUpMenu && $0.isVisible }) else { return }
                let frame = menu.frame
                let region = NSRect(x: frame.midX - DemoShot.width / 2,
                                    y: frame.minY - DemoCapture.menuMarginBottom,
                                    width: DemoShot.width,
                                    height: frame.height + DemoCapture.menuMarginTop + DemoCapture.menuMarginBottom)
                staged = (DemoCapture.backdrop(region), menu, region)
            }
        }
        let shoot = Timer(timeInterval: 1.4, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated {
                var wrote = false
                if let self, let staged {
                    wrote = DemoCapture.write([staged.backdrop, staged.menu], region: staged.region, to: self.shot.output)
                }
                self?.statusItem?.menu?.cancelTracking()
                self?.finish(wrote)
            }
        }
        let stop = Timer(timeInterval: 8, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.statusItem?.menu?.cancelTracking()
                self?.finish(false)
            }
        }
        for timer in [stage, shoot, stop] { RunLoop.main.add(timer, forMode: .common) }
        statusItem?.button?.performClick(nil)
    }

    /// `terminate` only unwinds to the run loop, so the temporary history is
    /// removed here and the process is left directly.
    private func finish(_ wrote: Bool) {
        try? FileManager.default.removeItem(at: shot.kind.directory)
        exit(wrote ? 0 : 1)
    }
}

guard let shot = DemoShot.parse(CommandLine.arguments) else {
    FileHandle.standardError.write(Data((DemoShot.usage + "\n").utf8))
    exit(64)
}
let application = NSApplication.shared
let delegate = ShotDelegate(shot: shot)
application.delegate = delegate
application.run()
