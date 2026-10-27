import AppKit
import Carbon.HIToolbox
import ImageIO
import SwiftUI

/// Every radius in the bezel is concentric: the panel's inner radius equals
/// the item radius plus the inset between them, and an image is clipped at
/// the item radius because it fills its item edge to edge.
package enum BezelMetrics {
    static let cornerRadius: CGFloat = 24
    static let inset: CGFloat = 14
    static let itemRadius: CGFloat = cornerRadius - inset
    static let itemSize = CGSize(width: 236, height: 184)
    static let itemSpacing: CGFloat = 20
    static let counterGap: CGFloat = 10
    static let counterHeight: CGFloat = 16
    package static let width: CGFloat = 720
    static let height = inset + itemSize.height + counterGap + counterHeight + inset
    static let edgeFade: CGFloat = 36
    /// Transparent margin around the surface that holds its shadow.
    package static let shadowMargin: CGFloat = 64
    static let selectionSpring = Animation.spring(duration: 0.26, bounce: 0)
    /// Clear space between the item and the selection ring, then the stroke.
    /// Strong is Increase Contrast: two points, still a line.
    static let selectionGap: CGFloat = 3
    static let selectionStroke: CGFloat = 1
    static let selectionStrokeStrong: CGFloat = 2
    /// Half strength. Increase Contrast ignores this and paints the line solid.
    static let selectionOpacity = 0.5
    /// How fast the ring leaves one item and settles on the next.
    static let selectionMove = Animation.easeOut(duration: 0.12)
}

/// The window's content: one rounded surface with a soft layered shadow
/// around it. The shadow is cut out under the surface so it never darkens
/// the glass, and nothing else paints anywhere in the window.
@MainActor
final class BezelRootView: NSView {
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
    @Published private(set) var selection = 0
    /// Replaces the counter for a moment when Return could only copy.
    @Published var notice: String?
    /// Ticks whenever the selection moves, so the strip follows even when the
    /// item under it did not change. Zero direction means it was placed, not
    /// stepped, and the strip should jump to it instead of scrolling.
    @Published private(set) var moves = 0
    private(set) var direction = 0

    var selected: HistoryItem? { items.indices.contains(selection) ? items[selection] : nil }

    func step(_ direction: Int) {
        guard !items.isEmpty else { return }
        self.direction = direction
        moves += 1
        withAnimation(BezelMetrics.selectionSpring) {
            selection = (selection + direction + items.count) % items.count
        }
    }

    func place(_ index: Int) {
        guard items.indices.contains(index) else { return }
        direction = 0
        moves += 1
        selection = index
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
package final class BezelController: NSObject, NSWindowDelegate {
    let state = BezelState()
    private let panel: BezelPanel
    private var transition = 0
    private(set) var isOpen = false
    var onSelect: ((HistoryItem) -> Void)?
    /// The item on screen when the panel closes, so the next open can start there.
    var onClose: ((HistoryItem?) -> Void)?
    /// False while macOS has not granted Accessibility: Return then copies
    /// and says so instead of pretending to paste.
    var pasteAvailable = true

    package init(store: HistoryStore) {
        let margin = BezelMetrics.shadowMargin
        panel = BezelPanel(contentRect: NSRect(x: 0, y: 0, width: BezelMetrics.width + margin * 2, height: BezelMetrics.height + margin * 2),
                          styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        super.init()
        panel.title = "Roger"
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
    package var window: NSWindow { panel }
    package var frame: NSRect { panel.frame }

    /// Opens on `selectedID` when it is still in the history, so the bezel
    /// picks up where the last paste left off.
    package func show(items: [HistoryItem], selectedID: String? = nil, frontApp: NSRunningApplication?) {
        if isOpen {
            state.step(NSEvent.modifierFlags.contains(.shift) ? -1 : 1)
            return
        }
        state.items = items
        state.place(items.firstIndex { $0.id == selectedID } ?? 0)
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
        onClose?(state.selected)
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

    package func windowDidResignKey(_ notification: Notification) { dismiss() }

    /// Return closes the panel at once, with no fade, so keyboard focus is back
    /// with the target app before the paste keystroke is posted.
    private func select() {
        guard let item = state.selected else { return }
        guard pasteAvailable else {
            state.notice = "Copied. Pasting needs Accessibility access for this build."
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
    @State private var position = 0
    /// Horizontal offset of the selection ring while it eases onto the next item.
    @State private var ringOffset: CGFloat = 0

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
                            ForEach(Array(0..<(state.items.count * 3)), id: \.self) { ring in
                                let index = ring % state.items.count
                                ClipCard(item: state.items[index], imageURL: store.imageURL(for: state.items[index]),
                                         selected: state.selection == index)
                                    .id(ring)
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
                    .onChange(of: state.moves) { _, _ in
                        if state.direction == 0 {
                            ringOffset = 0
                            center()
                        } else {
                            moveRing()
                            advance()
                        }
                    }
                    .onAppear { center() }
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
            .overlay(alignment: .top) {
                if !state.items.isEmpty {
                    SelectionRing(offset: ringOffset)
                        .frame(height: BezelMetrics.itemSize.height)
                        .allowsHitTesting(false)
                }
            }
            .padding(.vertical, BezelMetrics.inset)
            .frame(width: geometry.size.width, height: geometry.size.height)
        }
        .preferredColorScheme(.dark)
    }

    /// The ring appears on the incoming item and eases to the centre slot
    /// ahead of the strip, so the mark arrives before the card.
    private func moveRing() {
        guard !reduceMotion else {
            ringOffset = 0
            return
        }
        let pitch = BezelMetrics.itemSize.width + BezelMetrics.itemSpacing
        let move = state.moves
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            ringOffset = CGFloat(state.direction) * pitch
        }
        DispatchQueue.main.async {
            guard state.moves == move else { return }
            withAnimation(BezelMetrics.selectionMove) { ringOffset = 0 }
        }
    }

    /// The list is drawn three times; the live item sits in the middle copy so
    /// a step past either end lands on a real neighbour and scrolls there.
    private func advance() {
        let count = state.items.count
        guard count > 1 else { return }
        let settled = count + position % count
        if settled != position {
            scroll(to: settled, animated: false)
            position = settled
        }
        position += state.direction
        scroll(to: position, animated: !reduceMotion)
        let moved = position
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
            guard position == moved, state.items.count == count else { return }
            center()
        }
    }

    private func center() {
        guard !state.items.isEmpty else { return }
        position = state.items.count + state.selection
        scroll(to: position, animated: false)
    }

    private func scroll(to target: Int, animated: Bool) {
        if animated {
            withAnimation(BezelMetrics.selectionSpring) { scrolled = target }
        } else {
            var transaction = Transaction()
            transaction.disablesAnimations = true
            withTransaction(transaction) { scrolled = target }
        }
    }
}

/// One item on the glass. The selected item is the only one at full size
/// and full brightness; the ring around that slot is drawn separately.
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
        .scaleEffect(selected ? 1 : 0.86)
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

/// The item Return will paste. A warm plate stroke, the colour of the ground
/// the bowtie is shown on, held off the item so it never touches the type.
private struct SelectionRing: View {
    var offset: CGFloat
    @Environment(\.colorScheme) private var scheme
    @Environment(\.colorSchemeContrast) private var contrast
    @Environment(\.displayScale) private var displayScale

    /// Bowtie ink, and the warm plate behind it. Not a new brand colour.
    private static let ink = Color(red: 28 / 255, green: 27 / 255, blue: 25 / 255)
    private static let plate = Color(red: 230 / 255, green: 211 / 255, blue: 176 / 255)

    private var strong: Bool { contrast == .increased }
    private var stroke: CGFloat { strong ? BezelMetrics.selectionStrokeStrong : BezelMetrics.selectionStroke }
    private var color: Color {
        if strong { return scheme == .light ? .black : .white }
        let base = scheme == .light ? Self.ink : Self.plate
        return base.opacity(BezelMetrics.selectionOpacity)
    }

    var body: some View {
        GeometryReader { geometry in
            let scale = max(displayScale, 1)
            // Whole device pixels. A 1pt stroke that straddles a pixel is
            // painted at half coverage and disappears at @1x.
            let strokePx = max(1, (stroke * scale).rounded())
            let gapPx = BezelMetrics.selectionGap * scale
            let widthPx = (BezelMetrics.itemSize.width * scale + (gapPx + strokePx) * 2).rounded()
            let heightPx = (BezelMetrics.itemSize.height * scale + (gapPx + strokePx) * 2).rounded()
            let originX = ((geometry.size.width * scale - widthPx) / 2 + offset * scale).rounded()
            let originY = ((geometry.size.height * scale - heightPx) / 2).rounded()
            RoundedRectangle(cornerRadius: (BezelMetrics.itemRadius * scale + gapPx + strokePx) / scale)
                .strokeBorder(color, lineWidth: strokePx / scale)
                .frame(width: widthPx / scale, height: heightPx / scale)
                .position(x: (originX + widthPx / 2) / scale,
                          y: (originY + heightPx / 2) / scale)
        }
        .accessibilityHidden(true)
    }
}
