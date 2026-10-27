import AppKit
import Carbon.HIToolbox
import Testing
@testable import RogerCore

@Suite(.serialized)
@MainActor
struct HistoryTests {
    private func directory() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("RogerTests-\(UUID().uuidString)")
    }

    @Test func duplicateMovesToTopAndSurvivesRelaunch() throws {
        let path = directory()
        defer { try? FileManager.default.removeItem(at: path) }
        let store = HistoryStore(directory: path)
        store.recordText("first")
        store.recordText("second")
        store.recordText("first")
        #expect(store.items.map(\.content) == [.text("first"), .text("second")])
        let restored = HistoryStore(directory: path)
        #expect(restored.items == store.items)
        #expect(restored.errorMessage == nil)
    }

    @Test func textLimitsUseUTF8BytesAndIgnoreEmpty() {
        let path = directory()
        defer { try? FileManager.default.removeItem(at: path) }
        let store = HistoryStore(directory: path)
        store.recordText("")
        store.recordText(String(repeating: "é", count: 1_048_577))
        #expect(store.items.isEmpty)
        store.recordText(String(repeating: "a", count: 2_097_152))
        #expect(store.items.count == 1)
        store.recordText(" ")
        #expect(store.items.first?.content == .text(" "))
    }

    @Test func keepsNewest200Items() {
        let path = directory()
        defer { try? FileManager.default.removeItem(at: path) }
        let store = HistoryStore(directory: path, itemLimit: 200)
        for value in 0..<205 { store.recordText("Item \(value)") }
        #expect(store.items.count == 200)
        #expect(store.items.first?.content == .text("Item 204"))
        #expect(store.items.last?.content == .text("Item 5"))
    }

    @Test func imageBudgetEvictsOldestFirst() throws {
        let path = directory()
        defer { try? FileManager.default.removeItem(at: path) }
        let store = HistoryStore(directory: path, imageBudget: 10)
        store.recordPNG(Data(repeating: 1, count: 1))
        store.recordText("Keep this text")
        store.recordPNG(Data(repeating: 2, count: 6))
        store.recordPNG(Data(repeating: 3, count: 6))
        #expect(store.items.count == 2)
        #expect(store.items.last?.content == .text("Keep this text"))
        let images = try FileManager.default.contentsOfDirectory(at: path, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "png" }
        #expect(images.count == 1)
        let retainedImage = try #require(images.first)
        #expect(try Data(contentsOf: retainedImage) == Data(repeating: 3, count: 6))
    }

    @Test func imageLimitAndDuplicate() throws {
        let path = directory()
        defer { try? FileManager.default.removeItem(at: path) }
        let store = HistoryStore(directory: path)
        store.recordPNG(Data(repeating: 0, count: 40 * 1_024 * 1_024 + 1))
        #expect(store.items.isEmpty)
        let png = try imageData()
        store.recordPNG(png)
        store.recordText("between")
        store.recordPNG(png)
        #expect(store.items.count == 2)
        let item = try #require(store.items.first)
        let imageURL = try #require(store.imageURL(for: item))
        #expect(try Data(contentsOf: imageURL) == png)
        let restored = HistoryStore(directory: path)
        #expect(restored.items == store.items)
        store.clear()
        #expect(store.items.isEmpty)
        #expect(!FileManager.default.fileExists(atPath: imageURL.path))
        #expect(HistoryStore(directory: path).items.isEmpty)
    }

    @Test func itemLimitRemovesUnreferencedImageFiles() throws {
        let path = directory()
        defer { try? FileManager.default.removeItem(at: path) }
        let store = HistoryStore(directory: path, itemLimit: 2)
        store.recordPNG(try imageData())
        let item = try #require(store.items.first)
        let url = try #require(store.imageURL(for: item))
        store.recordText("one")
        store.recordText("two")
        #expect(!FileManager.default.fileExists(atPath: url.path))
        #expect(store.items.map(\.content) == [.text("two"), .text("one")])
    }

    @Test func fileReferencesPersistAndDeduplicate() {
        let path = directory()
        defer { try? FileManager.default.removeItem(at: path) }
        let store = HistoryStore(directory: path)
        let files = [URL(fileURLWithPath: "/tmp/one.txt"), URL(fileURLWithPath: "/tmp/two.png")]
        store.recordFiles(files)
        store.recordText("between")
        store.recordFiles(files)
        #expect(store.items.count == 2)
        #expect(store.items.first?.content == .files(files))
        #expect(store.items.first?.label == "one.txt + 1")
        #expect(HistoryStore(directory: path).items == store.items)
    }

    @Test func clipboardCaptureAndRestoreAllTypes() throws {
        let path = directory()
        defer { try? FileManager.default.removeItem(at: path) }
        let store = HistoryStore(directory: path)
        let board = NSPasteboard(name: NSPasteboard.Name("RogerTests-\(UUID().uuidString)"))
        defer { board.releaseGlobally() }
        let watcher = ClipboardWatcher(store: store, pasteboard: board)
        board.clearContents()
        board.setString("A real pasteboard value", forType: .string)
        watcher.poll()
        let text = try #require(store.items.first)
        #expect(text.content == .text("A real pasteboard value"))
        board.clearContents()
        board.setData(try imageData(), forType: .png)
        watcher.poll()
        let image = try #require(store.items.first)
        #expect(store.imageURL(for: image) != nil)
        board.clearContents()
        let files = [URL(fileURLWithPath: "/tmp/Roger test.txt")]
        board.writeObjects(files.map { $0 as NSURL })
        watcher.poll()
        let file = try #require(store.items.first)
        #expect(file.content == .files(files))
        try watcher.restore(text)
        #expect(board.string(forType: .string) == "A real pasteboard value")
        try watcher.restore(image)
        let data = try #require(board.data(forType: .png))
        #expect(NSImage(data: data)?.size == NSSize(width: 32, height: 24))
        try watcher.restore(file)
        #expect(board.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL] == files)
        watcher.poll()
        #expect(store.items.count == 3)
    }

    @Test func concealedItemsNeverEnterHistory() throws {
        let path = directory()
        defer { try? FileManager.default.removeItem(at: path) }
        let store = HistoryStore(directory: path)
        let board = NSPasteboard(name: NSPasteboard.Name("RogerTests-\(UUID().uuidString)"))
        defer { board.releaseGlobally() }
        let watcher = ClipboardWatcher(store: store, pasteboard: board)
        let concealed = NSPasteboard.PasteboardType("org.nspasteboard.ConcealedType")
        for type in [NSPasteboard.PasteboardType.string, .png, .fileURL] {
            board.clearContents()
            switch type {
            case .png: board.setData(try imageData(), forType: .png)
            case .fileURL: board.writeObjects([URL(fileURLWithPath: "/tmp/private.txt") as NSURL])
            default: board.setString("secret", forType: .string)
            }
            board.setData(Data(), forType: concealed)
            watcher.poll()
        }
        #expect(store.items.isEmpty)
    }

    @Test func selectionWrapsInBothDirections() {
        let state = BezelState()
        state.items = (0..<3).map { HistoryItem(id: "\($0)", content: .text("\($0)"), copiedAt: Date()) }
        state.step(-1)
        #expect(state.selection == 2)
        #expect(state.direction == -1)
        state.step(1)
        #expect(state.selection == 0)
        #expect(state.direction == 1)
        state.step(1)
        #expect(state.selected?.content == .text("1"))
    }

    @Test func failedRegistrationKeepsTheOldShortcut() throws {
        UserDefaults.standard.removeObject(forKey: Shortcut.defaultsKey)
        defer { UserDefaults.standard.removeObject(forKey: Shortcut.defaultsKey) }
        let first = HotKey()
        let second = HotKey()
        let custom = Shortcut(keyCode: UInt32(kVK_ANSI_J), modifiers: [.control, .option, .shift])
        let other = Shortcut(keyCode: UInt32(kVK_ANSI_K), modifiers: [.control, .option, .shift])
        defer {
            first.unregister()
            second.unregister()
        }
        #expect(first.register(custom) == noErr)
        #expect(first.shortcut == custom)
        #expect(second.register(other) == noErr)
        #expect(second.register(custom) != noErr)
        #expect(second.shortcut == other)
        #expect(Shortcut.stored() == other)
    }

    @Test func preferencesRecordsAndCancelsShortcut() throws {
        UserDefaults.standard.removeObject(forKey: Shortcut.defaultsKey)
        defer { UserDefaults.standard.removeObject(forKey: Shortcut.defaultsKey) }
        let hotKey = HotKey()
        defer { hotKey.unregister() }
        let path = directory()
        defer { try? FileManager.default.removeItem(at: path) }
        let preferences = PreferencesController(hotKey: hotKey, store: HistoryStore(directory: path))
        preferences.show()
        let window = try #require(NSApp.windows.first { $0.title == "Preferences" && $0.isVisible })
        defer { window.close() }
        let field = try #require(window.contentView?.subviews.compactMap { $0 as? ShortcutField }.first)
        let click = try #require(NSEvent.mouseEvent(with: .leftMouseDown, location: .zero, modifierFlags: [],
                                                    timestamp: 0, windowNumber: window.windowNumber, context: nil,
                                                    eventNumber: 1, clickCount: 1, pressure: 1))
        field.mouseDown(with: click)
        #expect(field.isRecording)

        let capture = try #require(NSEvent.keyEvent(with: .keyDown, location: .zero,
                                                    modifierFlags: [.command, .option, .control], timestamp: 0,
                                                    windowNumber: window.windowNumber, context: nil,
                                                    characters: "j", charactersIgnoringModifiers: "j",
                                                    isARepeat: false, keyCode: UInt16(kVK_ANSI_J)))
        field.keyDown(with: capture)
        let custom = Shortcut(keyCode: UInt32(kVK_ANSI_J), modifiers: [.command, .option, .control])
        #expect(hotKey.shortcut == custom)
        #expect(Shortcut.stored() == custom)
        #expect(!field.isRecording)

        field.mouseDown(with: click)
        #expect(field.isRecording)
        let escape = try #require(NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0,
                                                   windowNumber: window.windowNumber, context: nil,
                                                   characters: "\u{1b}", charactersIgnoringModifiers: "\u{1b}",
                                                   isARepeat: false, keyCode: UInt16(kVK_Escape)))
        field.keyDown(with: escape)
        #expect(!field.isRecording)
        #expect(hotKey.shortcut == custom)
    }

    @Test func bezelOpensAndWrapsPastBothEnds() throws {
        let path = directory()
        defer { try? FileManager.default.removeItem(at: path) }
        let store = HistoryStore(directory: path)
        for text in ["one", "two", "three"] { store.recordText(text) }
        let bezel = BezelController(store: store)
        bezel.show(items: store.items, frontApp: nil)
        #expect(bezel.isOpen)
        bezel.state.step(-1)
        #expect(bezel.state.selection == 2)
        #expect(bezel.state.direction == -1)
        bezel.state.step(1)
        #expect(bezel.state.selection == 0)
        #expect(bezel.state.direction == 1)
        bezel.dismiss()
        #expect(!bezel.isOpen)
    }

    /// Nothing copied since the last open: reopen on the item that was on
    /// screen, scrolled into the strip, and wrap from there.
    @Test func reopenStaysOnTheItemItWasClosedOn() throws {
        let path = directory()
        defer { try? FileManager.default.removeItem(at: path) }
        let store = HistoryStore(directory: path)
        for text in ["A", "B", "C"] { store.recordText(text) }
        var memory = SelectionMemory()
        memory.remember(store.items.first, in: store.items)
        let bezel = BezelController(store: store)
        bezel.onClose = { memory.remember($0, in: store.items) }

        bezel.show(items: store.items, selectedID: memory.selectedID(in: store.items), frontApp: nil)
        #expect(bezel.state.selection == 0)
        bezel.state.step(1)
        #expect(bezel.state.selected?.content == .text("B"))
        bezel.dismiss()
        #expect(memory.itemID == store.items[1].id)

        bezel.show(items: store.items, selectedID: memory.selectedID(in: store.items), frontApp: nil)
        #expect(bezel.state.selection == 1)
        #expect(bezel.state.selected?.content == .text("B"))
        bezel.state.step(1)
        #expect(bezel.state.selected?.content == .text("A"))
        bezel.state.step(1)
        #expect(bezel.state.selection == 0)
        #expect(bezel.state.selected?.content == .text("C"))
        bezel.dismiss()

        var gone = memory
        gone.itemID = "no such item"
        #expect(gone.selectedID(in: store.items) == store.items.first?.id)
    }

    /// A copy since the last open is what the captain wants next: the bezel
    /// opens at the top for it once, and does not stay glued to the top.
    @Test func aNewCopyIsOpenedOnAtTheTopOnce() throws {
        let path = directory()
        defer { try? FileManager.default.removeItem(at: path) }
        let store = HistoryStore(directory: path)
        for text in ["A", "B", "C"] { store.recordText(text) }
        var memory = SelectionMemory()
        memory.remember(store.items.first, in: store.items)
        store.recordText("D")
        let newest = try #require(store.items.first)
        #expect(newest.content == .text("D"))
        #expect(memory.selectedID(in: store.items) == newest.id)

        let bezel = BezelController(store: store)
        bezel.onClose = { memory.remember($0, in: store.items) }
        bezel.show(items: store.items, selectedID: memory.selectedID(in: store.items), frontApp: nil)
        #expect(bezel.state.selection == 0)
        #expect(bezel.state.selected?.content == .text("D"))
        bezel.dismiss()
        bezel.show(items: store.items, selectedID: memory.selectedID(in: store.items), frontApp: nil)
        #expect(bezel.state.selected?.content == .text("D"))
        bezel.dismiss()

        let c = try #require(store.items.first { $0.content == .text("C") })
        memory.remember(c, in: store.items)
        #expect(memory.selectedID(in: store.items) == c.id)
    }

    /// The item that was open before a new copy keeps its place; it is just
    /// no longer the one selected.
    @Test func aNewCopyLeavesThePreviouslyOpenItemWhereItWas() throws {
        let path = directory()
        defer { try? FileManager.default.removeItem(at: path) }
        let store = HistoryStore(directory: path)
        for text in ["A", "B", "C"] { store.recordText(text) }
        var memory = SelectionMemory()
        let b = try #require(store.items.first { $0.content == .text("B") })
        memory.remember(b, in: store.items)
        store.recordText("D")
        #expect(store.items.map(\.content) == [.text("D"), .text("C"), .text("B"), .text("A")])
        #expect(store.items.first { $0.id == memory.itemID }?.content == .text("B"))
        #expect(memory.selectedID(in: store.items) == store.items.first?.id)
    }

    @Test func shortcutRoundTripsThroughUserDefaults() throws {
        let name = "RogerTests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        #expect(Shortcut.stored(in: defaults) == .standard)
        let custom = Shortcut(keyCode: UInt32(kVK_ANSI_J), modifiers: [.command, .shift])
        #expect(custom.carbonModifiers == UInt32(cmdKey | shiftKey))
        #expect(Shortcut(keyCode: UInt32(kVK_Space), modifiers: [.command, .shift]).title == "⇧⌘Space")
        #expect(Shortcut(keyCode: UInt32(kVK_Space), modifiers: [.command, .shift]).words == "Shift Command Space")
        custom.store(in: defaults)
        #expect(defaults.string(forKey: Shortcut.defaultsKey) == custom.storedValue)
        #expect(Shortcut.stored(in: defaults) == custom)
        #expect(Shortcut(storedValue: "not a shortcut") == nil)
    }

    @Test func legacyStoreIsCopiedAndKept() throws {
        let support = FileManager.default.temporaryDirectory.appendingPathComponent("RogerTests-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: support) }
        let legacy = support.appendingPathComponent("CopyCopy", isDirectory: true)
        let destination = support.appendingPathComponent("Roger", isDirectory: true)
        let old = HistoryStore(directory: legacy)
        old.recordText("kept")
        let legacyIndex = legacy.appendingPathComponent("history.json")
        let saved = try Data(contentsOf: legacyIndex)

        try HistoryStore.copyLegacyStore(from: legacy, to: destination)

        #expect(HistoryStore(directory: destination).items.map(\.content) == [.text("kept")])
        #expect(try Data(contentsOf: legacyIndex) == saved)
        try HistoryStore.copyLegacyStore(from: legacy, to: destination)
        #expect(HistoryStore(directory: destination).items.count == 1)
    }

    @Test func historyDefaultsToFiftyAndTrimsAsSoonAsItIsLowered() throws {
        let name = "RogerTests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        let path = directory()
        defer { try? FileManager.default.removeItem(at: path) }
        let store = HistoryStore(directory: path, defaults: defaults)
        #expect(store.itemLimit == HistoryLimit.standard)
        #expect(HistoryLimit.standard == 50)
        for value in 0..<60 { store.recordText("Item \(value)") }
        #expect(store.items.count == 50)
        #expect(store.items.first?.content == .text("Item 59"))
        #expect(store.items.last?.content == .text("Item 10"))

        store.setItemLimit(25)
        #expect(store.itemLimit == 25)
        #expect(store.items.count == 25)
        #expect(store.items.first?.content == .text("Item 59"))
        #expect(store.items.last?.content == .text("Item 35"))
        #expect(HistoryLimit.stored(in: defaults) == 25)

        let restored = HistoryStore(directory: path, defaults: defaults)
        #expect(restored.itemLimit == 25)
        #expect(restored.items.count == 25)

        store.setItemLimit(10)
        #expect(store.itemLimit == HistoryLimit.standard)
        #expect(HistoryLimit.stored(in: defaults) == HistoryLimit.standard)
    }

    /// The ring is the middle of the viewport. `scrollPosition`'s id is one
    /// card to the right, because the leading inset is almost a whole pitch.
    /// The counter and Return follow this mapping, including a stop in the gap.
    @Test func offsetMapsToTheCardUnderTheRingNotTheNeighbourOnTheRight() throws {
        let width = BezelMetrics.width
        let count = 50
        let cards = count * 3
        let third = count + 2
        let centred = BezelMetrics.offset(centering: third, viewportWidth: width)
        #expect(BezelMetrics.centeredIndex(offset: centred, viewportWidth: width, cards: cards) == third)
        #expect(BezelMetrics.centeredIndex(offset: centred, viewportWidth: width, cards: cards) % count == 2)

        let inset = BezelMetrics.leadingInset(viewportWidth: width)
        let reportedByScrollPosition = Int(((centred + inset) / BezelMetrics.pitch).rounded(.toNearestOrAwayFromZero))
        #expect(reportedByScrollPosition == third + 1)
        #expect(reportedByScrollPosition % count == 3)

        let pitch = BezelMetrics.pitch
        #expect(BezelMetrics.centeredIndex(offset: centred + pitch * 0.25, viewportWidth: width, cards: cards) == third)
        #expect(BezelMetrics.centeredIndex(offset: centred + pitch * 0.75, viewportWidth: width, cards: cards) == third + 1)
        #expect(BezelMetrics.centeredIndex(offset: centred + pitch * 0.5, viewportWidth: width, cards: cards) == third + 1)
        #expect(BezelMetrics.centeredIndex(offset: -400, viewportWidth: width, cards: cards) == 0)
        #expect(BezelMetrics.centeredIndex(offset: 1_000_000, viewportWidth: width, cards: cards) == cards - 1)

        let narrow: CGFloat = 200
        let narrowInset = BezelMetrics.leadingInset(viewportWidth: narrow)
        #expect(narrowInset == BezelMetrics.inset)
        let parked = BezelMetrics.offset(centering: 4, viewportWidth: narrow, inset: narrowInset)
        #expect(BezelMetrics.centeredIndex(offset: parked, viewportWidth: narrow, cards: cards, inset: narrowInset) == 4)
        #expect(BezelMetrics.centeredIndex(offset: parked + pitch * 0.2, viewportWidth: narrow, cards: cards, inset: narrowInset) == 4)

        let path = directory()
        defer { try? FileManager.default.removeItem(at: path) }
        let store = HistoryStore(directory: path, itemLimit: 200)
        for value in 0..<count { store.recordText("Item \(value)") }
        let itemIndex = BezelMetrics.centeredIndex(offset: centred, viewportWidth: width, cards: cards) % count
        let underRing = try #require(store.items.dropFirst(itemIndex).first)
        let onTheRight = try #require(store.items.dropFirst(itemIndex + 1).first)
        let bezel = BezelController(store: store)
        var pasted: HistoryItem?
        bezel.onSelect = { pasted = $0 }
        bezel.show(items: store.items, frontApp: nil)
        defer { bezel.dismiss() }
        bezel.state.adoptCentered(itemIndex)
        #expect(bezel.state.selection + 1 == 3)
        #expect(bezel.state.selected?.id == underRing.id)
        try pressReturn(on: bezel)
        #expect(pasted?.id == underRing.id)
        #expect(pasted?.id != onTheRight.id)
    }

    /// Keyboard steps follow the card under the ring, not the index left
    /// behind when the strip was last opened.
    @Test func stepContinuesFromTheCenteredItem() {
        let state = BezelState()
        state.items = (0..<30).map { HistoryItem(id: "\($0)", content: .text("Item \($0)"), copiedAt: Date()) }
        state.place(0)
        state.adoptCentered(22)
        state.step(1)
        #expect(state.selection == 23)
        #expect(state.selected?.id == "23")
        state.adoptCentered(29)
        state.step(1)
        #expect(state.selection == 0)
        #expect(state.selected?.id == "0")
    }

    /// The ring sits on the centred card. Return used to paste items[selection],
    /// and selection stayed at 0 when the strip was scrolled instead of stepped.
    @Test func returnPastesTheCenteredItemAfterScrolling() throws {
        let path = directory()
        defer { try? FileManager.default.removeItem(at: path) }
        let store = HistoryStore(directory: path, itemLimit: 200)
        for value in 0..<30 { store.recordText("Item \(value)") }
        let highlighted = try #require(store.items.dropFirst(22).first)
        let bezel = BezelController(store: store)
        var pasted: HistoryItem?
        bezel.onSelect = { pasted = $0 }
        bezel.show(items: store.items, frontApp: nil)
        defer { bezel.dismiss() }

        bezel.state.adoptCentered(22)
        #expect(bezel.state.selection == 22)
        #expect(bezel.state.selected?.id == highlighted.id)
        try pressReturn(on: bezel)
        #expect(pasted?.id == highlighted.id)
        #expect(pasted?.id != store.items[0].id)
    }

    /// A copy while the bezel is open is inserted at the front. The highlight
    /// stays on the same paste, and Return does not jump to the new first item.
    @Test func returnKeepsTheHighlightedItemWhenHistoryChangesUnderIt() throws {
        let path = directory()
        defer { try? FileManager.default.removeItem(at: path) }
        let store = HistoryStore(directory: path, itemLimit: 200)
        for value in 0..<30 { store.recordText("Item \(value)") }
        let bezel = BezelController(store: store)
        var pasted: HistoryItem?
        bezel.onSelect = { pasted = $0 }
        bezel.show(items: store.items, frontApp: nil)
        defer { bezel.dismiss() }

        bezel.state.adoptCentered(22)
        let highlighted = try #require(bezel.state.selected)
        store.recordText("fresh")
        #expect(store.items.first?.content == .text("fresh"))
        #expect(bezel.state.selected?.id == highlighted.id)
        #expect(bezel.state.selection == 23)

        let kept = store.items.filter { $0.id == highlighted.id || $0.id == store.items[0].id }
        bezel.state.replace(kept)
        #expect(bezel.state.selected?.id == highlighted.id)

        try pressReturn(on: bezel)
        #expect(pasted?.id == highlighted.id)
    }

    @Test func preferencesTrimHistoryFromThePopup() throws {
        let name = "RogerTests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        let path = directory()
        defer { try? FileManager.default.removeItem(at: path) }
        let store = HistoryStore(directory: path, defaults: defaults)
        for value in 0..<40 { store.recordText("Item \(value)") }
        let hotKey = HotKey()
        defer { hotKey.unregister() }
        let preferences = PreferencesController(hotKey: hotKey, store: store)
        preferences.show()
        let window = try #require(NSApp.windows.first { $0.title == "Preferences" && $0.isVisible })
        defer { window.close() }
        let popup = try #require(window.contentView?.subviews.compactMap { $0 as? NSPopUpButton }.first)
        #expect(popup.titleOfSelectedItem == "50")
        popup.selectItem(withTitle: "25")
        #expect(popup.sendAction(popup.action, to: popup.target))
        #expect(store.itemLimit == 25)
        #expect(store.items.count == 25)
        #expect(store.items.first?.content == .text("Item 39"))
    }

    private func pressReturn(on bezel: BezelController) throws {
        let event = try #require(NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0,
                                                  windowNumber: bezel.window.windowNumber, context: nil,
                                                  characters: "\r", charactersIgnoringModifiers: "\r",
                                                  isARepeat: false, keyCode: UInt16(kVK_Return)))
        #expect(bezel.window.performKeyEquivalent(with: event))
    }

    private func imageData() throws -> Data {
        let bitmap = try #require(NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 32, pixelsHigh: 24,
                                                  bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                                                  isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0))
        for y in 0..<24 {
            for x in 0..<32 { bitmap.setColor(NSColor(deviceRed: 0.2, green: 0.7, blue: 0.7, alpha: 1), atX: x, y: y) }
        }
        return try #require(bitmap.representation(using: .png, properties: [:]))
    }
}
