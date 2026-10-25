import AppKit
import Carbon.HIToolbox
import ImageIO
import SwiftUI

/// Every radius in the bezel is concentric: the panel's inner radius equals
/// the item radius plus the inset between them, and an image is clipped at
/// the item radius because it fills its item edge to edge.
enum BezelMetrics {
    static let cornerRadius: CGFloat = 24
    static let inset: CGFloat = 14
    static let itemRadius: CGFloat = cornerRadius - inset
    static let itemSize = CGSize(width: 236, height: 184)
    static let itemSpacing: CGFloat = 20
    static let counterGap: CGFloat = 10
    static let counterHeight: CGFloat = 16
    static let width: CGFloat = 720
    static let height = inset + itemSize.height + counterGap + counterHeight + inset
    static let edgeFade: CGFloat = 36
    /// Transparent margin around the surface that holds its shadow.
    static let shadowMargin: CGFloat = 64
    static let selectionSpring = Animation.spring(duration: 0.26, bounce: 0)
}

/// The window's content: one rounded surface with a soft layered shadow
/// around it. The shadow is cut out under the surface so it never darkens
/// the glass, and nothing else paints anywhere in the window.
@MainActor
private final class BezelRootView: NSView {
    let surface = NSView()
    private let shadows: [CALayer] = [(28.0, 0.38, -18.0), (6.0, 0.22, -2.0)].map { radius, opacity, dy in
        let layer = CALayer()
        layer.shadowColor = NSColor.black.cgColor
        layer.shadowRadius = radius
        layer.shadowOpacity = Float(opacity)
        layer.shadowOffset = CGSize(width: 0, height: dy)
        return layer
    }

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor
        shadows.forEach { layer?.addSublayer($0) }
        surface.wantsLayer = true
        surface.layer?.backgroundColor = NSColor.clear.cgColor
        surface.layer?.cornerRadius = BezelMetrics.cornerRadius
        surface.layer?.masksToBounds = true
        surface.frame = bounds.insetBy(dx: BezelMetrics.shadowMargin, dy: BezelMetrics.shadowMargin)
        addSubview(surface)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override func layout() {
        super.layout()
        let frame = bounds.insetBy(dx: BezelMetrics.shadowMargin, dy: BezelMetrics.shadowMargin)
        let radius = BezelMetrics.cornerRadius
        let path = CGPath(roundedRect: frame, cornerWidth: radius, cornerHeight: radius, transform: nil)
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        surface.frame = frame
        for shadow in shadows {
            shadow.frame = bounds
            shadow.shadowPath = path
            let cutout = CAShapeLayer()
            cutout.fillRule = .evenOdd
            let outline = CGMutablePath()
            outline.addRect(bounds)
            outline.addPath(path)
            cutout.path = outline
            shadow.mask = cutout
        }
        CATransaction.commit()
    }
}

@MainActor
final class BezelState: ObservableObject {
    @Published var items: [HistoryItem] = []
    @Published var selection = 0
    /// Replaces the counter for a moment when Return could only copy.
    @Published var notice: String?
    private var wrapped = false

    var selected: HistoryItem? { items.indices.contains(selection) ? items[selection] : nil }

    func step(_ direction: Int) {
        guard !items.isEmpty else { return }
        let next = (selection + direction + items.count) % items.count
        wrapped = items.count > 1 && next != selection
            && (direction > 0 ? next < selection : next > selection)
        if wrapped { NSLog("CopyCopy selection wrapped %d -> %d", selection, next) }
        withAnimation(BezelMetrics.selectionSpring) {
            selection = next
        }
    }

    func consumeWrap() -> Bool {
        defer { wrapped = false }
        return wrapped
    }
}

@MainActor
final class BezelPanel: NSPanel {
    var onStep: ((Int) -> Void)?
    var onSelect: (() -> Void)?
    var onDismiss: (() -> Void)?
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    override func keyDown(with event: NSEvent) {
        switch Int(event.keyCode) {
        case kVK_ANSI_V, kVK_RightArrow, kVK_DownArrow:
            onStep?(event.modifierFlags.contains(.shift) ? -1 : 1)
        case kVK_LeftArrow, kVK_UpArrow: onStep?(-1)
        case kVK_Return, kVK_ANSI_KeypadEnter: onSelect?()
        case kVK_Escape: onDismiss?()
        default: break
        }
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        let keys = [kVK_ANSI_V, kVK_RightArrow, kVK_DownArrow, kVK_LeftArrow, kVK_UpArrow,
                    kVK_Return, kVK_ANSI_KeypadEnter, kVK_Escape]
        guard keys.contains(Int(event.keyCode)) else { return super.performKeyEquivalent(with: event) }
        keyDown(with: event)
        return true
    }
}

@MainActor
final class BezelController: NSObject, NSWindowDelegate {
    let state = BezelState()
    private let panel: BezelPanel
    private var transition = 0
    private(set) var isOpen = false
    var onSelect: ((HistoryItem) -> Void)?
    /// False while macOS has not granted Accessibility: Return then copies
    /// and says so instead of pretending to paste.
    var pasteAvailable = true

    init(store: HistoryStore) {
        let margin = BezelMetrics.shadowMargin
        panel = BezelPanel(contentRect: NSRect(x: 0, y: 0, width: BezelMetrics.width + margin * 2, height: BezelMetrics.height + margin * 2),
                          styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        super.init()
        panel.title = "CopyCopy"
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.level = .popUpMenu
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        panel.appearance = NSAppearance(named: .darkAqua)
        panel.delegate = self

        let root = BezelRootView(frame: panel.contentView?.bounds ?? .zero)
        let bounds = root.surface.bounds
        let radius = BezelMetrics.cornerRadius

        let material = NSVisualEffectView(frame: bounds)
        material.material = .hudWindow
        material.blendingMode = .behindWindow
        material.state = .active
        material.autoresizingMask = [.width, .height]
        material.maskImage = Self.roundedMask(radius: radius)

        let tint = NSView(frame: bounds)
        tint.wantsLayer = true
        tint.autoresizingMask = [.width, .height]
        tint.layer?.backgroundColor = NSColor.black.withAlphaComponent(0.4).cgColor

        // The hosting view sits beside the material, not inside it, so text is
        // drawn at full strength instead of being blended into the backdrop.
        let content = NSHostingView(rootView: BezelView(state: state, store: store))
        content.frame = bounds
        content.autoresizingMask = [.width, .height]

        root.surface.addSubview(material)
        root.surface.addSubview(tint)
        root.surface.addSubview(content)
        panel.contentView = root
        panel.onStep = { [weak self] in self?.state.step($0) }
        panel.onSelect = { [weak self] in self?.select() }
        panel.onDismiss = { [weak self] in self?.dismiss() }
    }

    private static func roundedMask(radius: CGFloat) -> NSImage {
        let side = radius * 2 + 1
        let image = NSImage(size: NSSize(width: side, height: side), flipped: false) { rect in
            NSColor.black.setFill()
            NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius).fill()
            return true
        }
        image.capInsets = NSEdgeInsets(top: radius, left: radius, bottom: radius, right: radius)
        image.resizingMode = .stretch
        return image
    }

    var isVisible: Bool { panel.isVisible }

    /// Opens on `selectedID` when it is still in the history, so the bezel
    /// picks up where the last paste left off.
    func show(items: [HistoryItem], selectedID: String? = nil, frontApp: NSRunningApplication?) {
        if isOpen {
            state.step(NSEvent.modifierFlags.contains(.shift) ? -1 : 1)
            return
        }
        state.items = items
        state.selection = items.firstIndex { $0.id == selectedID } ?? 0
        state.notice = nil
        transition += 1
        isOpen = true
        let screen = activeScreen(frontApp: frontApp)
        let visible = screen?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1_440, height: 900)
        let width = min(BezelMetrics.width, visible.width - 32)
        let height = BezelMetrics.height
        let destination = NSRect(x: visible.midX - width / 2, y: visible.midY - height / 2, width: width, height: height)
            .insetBy(dx: -BezelMetrics.shadowMargin, dy: -BezelMetrics.shadowMargin)
        let reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        panel.setFrame(destination.offsetBy(dx: 0, dy: reduceMotion ? 0 : -8), display: true)
        panel.alphaValue = 0
        panel.makeKeyAndOrderFront(nil)
        panel.makeFirstResponder(panel)
        NSAnimationContext.runAnimationGroup { context in
            context.duration = reduceMotion ? 0 : 0.14
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            panel.animator().alphaValue = 1
            panel.animator().setFrame(destination, display: true)
        }
    }

    func dismiss() {
        guard isOpen else { return }
        isOpen = false
        transition += 1
        let currentTransition = transition
        // Give keyboard focus back immediately; the fade must not swallow the paste.
        panel.resignKey()
        NSAnimationContext.runAnimationGroup { context in
            context.duration = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion ? 0 : 0.09
            panel.animator().alphaValue = 0
        } completionHandler: { [weak self] in
            MainActor.assumeIsolated {
                guard let self, self.transition == currentTransition else { return }
                self.panel.orderOut(nil)
            }
        }
    }

    func windowDidResignKey(_ notification: Notification) { dismiss() }

    /// Return closes the panel at once, with no fade, so keyboard focus is back
    /// with the target app before the paste keystroke is posted.
    private func select() {
        guard let item = state.selected else { return }
        guard pasteAvailable else {
            state.notice = "Copied. Pasting needs Accessibility access."
            onSelect?(item)
            transition += 1
            let currentTransition = transition
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.6) { [weak self] in
                guard let self, self.transition == currentTransition else { return }
                self.dismiss()
            }
            return
        }
        isOpen = false
        transition += 1
        panel.orderOut(nil)
        onSelect?(item)
    }

    private func activeScreen(frontApp: NSRunningApplication?) -> NSScreen? {
        if let pid = frontApp?.processIdentifier,
           let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]],
           let window = windows.first(where: {
               ($0[kCGWindowOwnerPID as String] as? Int32) == pid && ($0[kCGWindowLayer as String] as? Int) == 0
           }),
           let bounds = window[kCGWindowBounds as String] as? [String: Any],
           let quartzRect = CGRect(dictionaryRepresentation: bounds as CFDictionary),
           let primary = NSScreen.screens.first {
            let rect = NSRect(x: quartzRect.minX, y: primary.frame.maxY - quartzRect.maxY,
                              width: quartzRect.width, height: quartzRect.height)
            return NSScreen.screens.max(by: {
                let a = $0.frame.intersection(rect), b = $1.frame.intersection(rect)
                return a.width * a.height < b.width * b.height
            })
        }
        return NSScreen.screens.first { NSMouseInRect(NSEvent.mouseLocation, $0.frame, false) } ?? NSScreen.main
    }
}

private struct BezelView: View {
    @ObservedObject var state: BezelState
    let store: HistoryStore
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var scrolled: Int?

    var body: some View {
        GeometryReader { geometry in
            VStack(spacing: BezelMetrics.counterGap) {
                if state.items.isEmpty {
                    Text("Nothing copied yet")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(.white.opacity(0.5))
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    ScrollView(.horizontal) {
                        LazyHStack(spacing: BezelMetrics.itemSpacing) {
                            ForEach(Array(state.items.enumerated()), id: \.element.id) { index, item in
                                ClipCard(item: item, imageURL: store.imageURL(for: item), selected: state.selection == index)
                                    .id(index)
                            }
                        }
                        .scrollTargetLayout()
                        .padding(.horizontal, max(BezelMetrics.inset, (geometry.size.width - BezelMetrics.itemSize.width) / 2))
                    }
                    .scrollPosition(id: $scrolled, anchor: .center)
                    .scrollIndicators(.hidden)
                    .scrollClipDisabled()
                    .mask(
                        HStack(spacing: 0) {
                            LinearGradient(colors: [.clear, .black], startPoint: .leading, endPoint: .trailing)
                                .frame(width: BezelMetrics.edgeFade)
                            Color.black
                            LinearGradient(colors: [.black, .clear], startPoint: .leading, endPoint: .trailing)
                                .frame(width: BezelMetrics.edgeFade)
                        }
                    )
                    .onChange(of: state.selection) { _, selected in
                        if state.consumeWrap() {
                            var transaction = Transaction()
                            transaction.disablesAnimations = true
                            withTransaction(transaction) { scrolled = selected }
                        } else {
                            withAnimation(reduceMotion ? nil : BezelMetrics.selectionSpring) { scrolled = selected }
                        }
                    }
                    .onChange(of: state.items) { _, _ in scrolled = state.selection }
                    .onAppear { scrolled = state.selection }
                    .frame(height: BezelMetrics.itemSize.height)
                }
                Text(state.notice ?? (state.items.isEmpty ? "0 of 0" : "\(state.selection + 1) of \(state.items.count)"))
                    .font(.system(size: 12, weight: .medium))
                    .monospacedDigit()
                    .foregroundStyle(.white.opacity(0.5))
                    .frame(height: BezelMetrics.counterHeight)
                    .contentTransition(.numericText())
                    .accessibilityLabel("Item \(state.selection + 1) of \(state.items.count)")
            }
            .padding(.vertical, BezelMetrics.inset)
            .frame(width: geometry.size.width, height: geometry.size.height)
        }
        .preferredColorScheme(.dark)
    }
}

/// One item on the glass. Nothing frames it: the selected item is the only
/// thing at full size and full brightness, and its neighbours fall back.
private struct ClipCard: View {
    let item: HistoryItem
    let imageURL: URL?
    let selected: Bool
    @State private var thumbnail: NSImage?

    private let size = BezelMetrics.itemSize

    var body: some View {
        Group {
            switch item.content {
            case .text(let text):
                // Centred both ways; the slight lift offsets the line spacing
                // and descenders that make mathematically centred text sit low.
                Text(String(text.prefix(1_200)))
                    .font(.system(size: 15, weight: .regular, design: .monospaced))
                    .lineSpacing(4)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.white.opacity(0.94))
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
                    .offset(y: -2)
            case .image:
                if let thumbnail {
                    Image(nsImage: thumbnail).resizable().scaledToFill()
                        .frame(width: size.width, height: size.height)
                        .clipShape(RoundedRectangle(cornerRadius: BezelMetrics.itemRadius))
                } else {
                    Color.white.opacity(0.06)
                        .clipShape(RoundedRectangle(cornerRadius: BezelMetrics.itemRadius))
                }
            case .files(let urls):
                VStack(spacing: 14) {
                    if let url = urls.first {
                        Image(nsImage: NSWorkspace.shared.icon(forFile: url.path))
                            .resizable().frame(width: 64, height: 64)
                    }
                    Text(item.label)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(.white.opacity(0.94))
                        .lineLimit(2).multilineTextAlignment(.center)
                }
                .padding(16)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(width: size.width, height: size.height)
        .scaleEffect(selected ? 1 : 0.92)
        .opacity(selected ? 1 : 0.34)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(item.label)
        .accessibilityAddTraits(selected ? .isSelected : [])
        .onAppear { loadThumbnail() }
        .onDisappear { thumbnail = nil }
    }

    private func loadThumbnail() {
        guard let imageURL, let source = CGImageSourceCreateWithURL(imageURL as CFURL, nil),
              let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceThumbnailMaxPixelSize: 480,
                kCGImageSourceCreateThumbnailWithTransform: true
              ] as CFDictionary) else { return }
        thumbnail = NSImage(cgImage: image, size: .zero)
    }
}
