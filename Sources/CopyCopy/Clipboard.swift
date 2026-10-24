import AppKit
import ImageIO
import UniformTypeIdentifiers

@MainActor
final class ClipboardWatcher: NSObject {
    private let store: HistoryStore
    private let pasteboard: NSPasteboard
    private var lastChange = -1
    private var timer: Timer?

    init(store: HistoryStore, pasteboard: NSPasteboard = .general) {
        self.store = store
        self.pasteboard = pasteboard
    }

    func start() {
        poll()
        let timer = Timer(timeInterval: 0.3, target: self, selector: #selector(poll), userInfo: nil, repeats: true)
        timer.tolerance = 0.05
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    @objc func poll() {
        guard pasteboard.changeCount != lastChange else { return }
        lastChange = pasteboard.changeCount
        let concealed = NSPasteboard.PasteboardType("org.nspasteboard.ConcealedType")
        guard !(pasteboard.types ?? []).contains(concealed),
              !(pasteboard.pasteboardItems ?? []).contains(where: { $0.types.contains(concealed) }) else { return }

        if let files = pasteboard.readObjects(forClasses: [NSURL.self],
                                             options: [.urlReadingFileURLsOnly: true]) as? [URL], !files.isEmpty {
            store.recordFiles(files)
            return
        }
        for type in [NSPasteboard.PasteboardType.png, .tiff] {
            if pasteboard.types?.contains(type) == true {
                guard let data = pasteboard.data(forType: type), data.count <= HistoryStore.imageLimit,
                      let png = Self.pngData(from: data) else { return }
                store.recordPNG(png)
                return
            }
        }
        if let text = pasteboard.string(forType: .string) {
            store.recordText(text)
        }
    }

    func restore(_ item: HistoryItem) throws {
        // Read image data before clearing the current clipboard so a missing file cannot erase it.
        let imageData: Data?
        if let url = store.imageURL(for: item) {
            imageData = try Data(contentsOf: url)
        } else {
            imageData = nil
        }
        pasteboard.clearContents()
        let succeeded: Bool
        switch item.content {
        case .text(let text): succeeded = pasteboard.setString(text, forType: .string)
        case .image:
            if let imageData {
                succeeded = pasteboard.setData(imageData, forType: .png)
            } else { succeeded = false }
        case .files(let urls): succeeded = pasteboard.writeObjects(urls.map { $0 as NSURL })
        }
        lastChange = pasteboard.changeCount
        guard succeeded else { throw ClipboardError.writeFailed }
        store.promote(item)
    }

    private static func pngData(from data: Data) -> Data? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else { return nil }
        let result = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(result, UTType.png.identifier as CFString, 1, nil) else { return nil }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination), result.length <= HistoryStore.imageLimit else { return nil }
        return result as Data
    }

    private enum ClipboardError: LocalizedError {
        case writeFailed
        var errorDescription: String? { "The item could not be copied to the clipboard." }
    }
}
