import AppKit
import Testing
@testable import CopyCopy

@Suite(.serialized)
@MainActor
struct HistoryTests {
    private func directory() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("CopyCopyTests-\(UUID().uuidString)")
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
        let store = HistoryStore(directory: path)
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
        let board = NSPasteboard(name: NSPasteboard.Name("CopyCopyTests-\(UUID().uuidString)"))
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
        let files = [URL(fileURLWithPath: "/tmp/CopyCopy test.txt")]
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
        let board = NSPasteboard(name: NSPasteboard.Name("CopyCopyTests-\(UUID().uuidString)"))
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
        state.step(1)
        #expect(state.selection == 0)
        state.step(1)
        #expect(state.selected?.content == .text("1"))
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
