import AppKit
import Carbon.HIToolbox
import ImageIO
import SwiftUI

@MainActor
final class BezelState: ObservableObject {
    @Published var items: [HistoryItem] = []
    @Published var selection = 0
    private var wrapped = false

    var selected: HistoryItem? { items.indices.contains(selection) ? items[selection] : nil }

    func step(_ direction: Int) {
        guard !items.isEmpty else { return }
        let next = (selection + direction + items.count) % items.count
        wrapped = items.count > 1 && next != selection
            && (direction > 0 ? next < selection : next > selection)
        if wrapped { NSLog("CopyCopy selection wrapped %d -> %d", selection, next) }
        withAnimation(.spring(response: 0.26, dampingFraction: 0.88)) {
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

    init(store: HistoryStore) {
        panel = BezelPanel(contentRect: NSRect(x: 0, y: 0, width: 720, height: 300),
                          styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        super.init()
        panel.title = "CopyCopy"
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.level = .popUpMenu
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        panel.appearance = NSAppearance(named: .darkAqua)
        panel.delegate = self

        let material = NSVisualEffectView(frame: panel.contentView?.bounds ?? .zero)
        material.material = .hudWindow
        material.blendingMode = .behindWindow
        material.state = .active
        material.wantsLayer = true
        material.layer?.cornerRadius = 26
        material.layer?.masksToBounds = true
        material.layer?.borderWidth = 0.5
        material.layer?.borderColor = NSColor.white.withAlphaComponent(0.23).cgColor
        let content = NSHostingView(rootView: BezelView(state: state, store: store) { [weak self] index in
            guard let self else { return }
            self.state.selection = index
            self.select()
        })
        content.frame = material.bounds
        content.autoresizingMask = [.width, .height]
        material.addSubview(content)
        panel.contentView = material
        panel.onStep = { [weak self] in self?.state.step($0) }
        panel.onSelect = { [weak self] in self?.select() }
        panel.onDismiss = { [weak self] in self?.dismiss() }
    }

    func show(items: [HistoryItem], frontApp: NSRunningApplication?) {
        if isOpen {
            state.step(NSEvent.modifierFlags.contains(.shift) ? -1 : 1)
            return
        }
        state.items = items
        state.selection = 0
        transition += 1
        isOpen = true
        let screen = activeScreen(frontApp: frontApp)
        let visible = screen?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1_440, height: 900)
        let width = min(720, visible.width - 32)
        let destination = NSRect(x: visible.midX - width / 2, y: visible.midY - 150, width: width, height: 300)
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

    private func select() {
        guard let item = state.selected else { return }
        dismiss()
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
    let choose: (Int) -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        GeometryReader { geometry in
            VStack(spacing: 12) {
                if state.items.isEmpty {
                    Text("Nothing copied yet")
                        .font(.system(size: 18, weight: .medium))
                        .foregroundStyle(.white.opacity(0.6))
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    ScrollViewReader { proxy in
                        ScrollView(.horizontal) {
                            LazyHStack(spacing: 20) {
                                ForEach(Array(state.items.enumerated()), id: \.element.id) { index, item in
                                    ClipCard(item: item, imageURL: store.imageURL(for: item), selected: state.selection == index)
                                        .id(index)
                                        .onTapGesture { choose(index) }
                                }
                            }
                            .padding(.horizontal, max(24, (geometry.size.width - 236) / 2))
                            .padding(.top, 12)
                            .padding(.bottom, 10)
                        }
                        .scrollIndicators(.hidden)
                        .onChange(of: state.selection) { _, selected in
                            if state.consumeWrap() {
                                var transaction = Transaction()
                                transaction.disablesAnimations = true
                                withTransaction(transaction) { proxy.scrollTo(selected, anchor: .center) }
                            } else {
                                withAnimation(reduceMotion ? nil : .spring(response: 0.26, dampingFraction: 0.88)) {
                                    proxy.scrollTo(selected, anchor: .center)
                                }
                            }
                        }
                        .onChange(of: state.items) { _, _ in proxy.scrollTo(0, anchor: .center) }
                        .onAppear { proxy.scrollTo(state.selection, anchor: .center) }
                    }
                    .frame(height: 214)
                }
                Text(state.items.isEmpty ? "0 of 0" : "\(state.selection + 1) of \(state.items.count)")
                    .font(.system(size: 12, weight: .medium, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.48))
                    .contentTransition(.numericText())
                    .accessibilityLabel("Item \(state.selection + 1) of \(state.items.count)")
            }
            .padding(.top, 26)
            .padding(.bottom, 24)
            .frame(width: geometry.size.width, height: geometry.size.height)
        }
        .background(.black.opacity(0.18))
        .preferredColorScheme(.dark)
    }
}

private struct ClipCard: View {
    let item: HistoryItem
    let imageURL: URL?
    let selected: Bool
    @State private var thumbnail: NSImage?

    var body: some View {
        Group {
            switch item.content {
            case .text(let text):
                Text(String(text.prefix(1_200)))
                    .font(.system(size: 15, weight: .regular, design: .monospaced))
                    .lineSpacing(4)
                    .foregroundStyle(.white.opacity(0.92))
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    .padding(20)
            case .image:
                if let thumbnail {
                    Image(nsImage: thumbnail).resizable().scaledToFit()
                        .clipShape(RoundedRectangle(cornerRadius: 8)).padding(10)
                } else {
                    Image(systemName: "photo").font(.system(size: 40)).foregroundStyle(.secondary)
                }
            case .files(let urls):
                VStack(spacing: 16) {
                    if let url = urls.first {
                        Image(nsImage: NSWorkspace.shared.icon(forFile: url.path))
                            .resizable().frame(width: 64, height: 64)
                    }
                    Text(item.label)
                        .font(.system(size: 14, weight: .medium))
                        .lineLimit(2).multilineTextAlignment(.center)
                }
                .padding(20)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(width: 236, height: 184)
        .background(.white.opacity(selected ? 0.085 : 0.035))
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(.white.opacity(selected ? 0.45 : 0.1), lineWidth: 0.7))
        .shadow(color: .black.opacity(selected ? 0.25 : 0), radius: 12, y: 8)
        .offset(y: selected ? -6 : 0)
        .opacity(selected ? 1 : 0.65)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(item.label)
        .accessibilityAddTraits(selected ? [.isSelected, .isButton] : .isButton)
        .onAppear { loadThumbnail() }
        .onDisappear { thumbnail = nil }
    }

    private func loadThumbnail() {
        guard let imageURL, let source = CGImageSourceCreateWithURL(imageURL as CFURL, nil),
              let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceThumbnailMaxPixelSize: 472,
                kCGImageSourceCreateThumbnailWithTransform: true
              ] as CFDictionary) else { return }
        thumbnail = NSImage(cgImage: image, size: .zero)
    }
}
