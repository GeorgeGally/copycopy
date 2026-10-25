import Combine
import CryptoKit
import Foundation

enum ClipContent: Codable, Equatable {
    case text(String)
    case image(filename: String, bytes: Int)
    case files([URL])
}

struct HistoryItem: Codable, Identifiable, Equatable {
    let id: String
    let content: ClipContent
    var copiedAt: Date

    var label: String {
        switch content {
        case .text(let text):
            let line = text.split(whereSeparator: { $0.isNewline }).joined(separator: " ")
            return line.isEmpty ? "Whitespace" : String(line.prefix(80))
        case .image: return "Image"
        case .files(let urls):
            let name = urls.first?.lastPathComponent ?? "File"
            return urls.count > 1 ? "\(name) + \(urls.count - 1)" : name
        }
    }

    static func fingerprint(kind: String, data: Data) -> String {
        var hash = SHA256()
        hash.update(data: Data(kind.utf8))
        hash.update(data: data)
        return hash.finalize().map { String(format: "%02x", $0) }.joined()
    }
}

@MainActor
final class HistoryStore: ObservableObject {
    static let textLimit = 2 * 1_024 * 1_024
    static let imageLimit = 40 * 1_024 * 1_024
    @Published private(set) var items: [HistoryItem] = []
    @Published private(set) var errorMessage: String?
    let directory: URL
    private let itemLimit: Int
    private let imageBudget: Int
    private let fileManager = FileManager.default
    private var indexURL: URL { directory.appendingPathComponent("history.json") }

    private struct Index: Codable {
        var version = 1
        var items: [HistoryItem]
    }

    init(directory: URL? = nil, itemLimit: Int = 200, imageBudget: Int = 500 * 1_024 * 1_024) {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        self.directory = directory ?? support.appendingPathComponent("CopyOver", isDirectory: true)
        self.itemLimit = itemLimit
        self.imageBudget = imageBudget
        if directory == nil {
            do {
                try Self.copyLegacyStore(from: support.appendingPathComponent("CopyCopy", isDirectory: true),
                                         to: self.directory)
            } catch {
                NSLog("CopyOver could not migrate the CopyCopy history: %@", error.localizedDescription)
            }
        }
        do {
            try fileManager.createDirectory(at: self.directory, withIntermediateDirectories: true,
                                            attributes: [.posixPermissions: 0o700])
            if fileManager.fileExists(atPath: indexURL.path) {
                let index = try JSONDecoder().decode(Index.self, from: Data(contentsOf: indexURL))
                guard index.version == 1 else { throw StoreError.unsupportedIndex }
                var seen = Set<String>()
                items = index.items.filter { item in
                    guard seen.insert(item.id).inserted else { return false }
                    if case .image(let filename, _) = item.content {
                        return filename == item.id + ".png" && !filename.contains("/")
                            && fileManager.fileExists(atPath: self.directory.appendingPathComponent(filename).path)
                    }
                    return true
                }
            }
            try persist(items)
        } catch {
            errorMessage = "History could not be loaded: \(error.localizedDescription)"
        }
    }

    static func copyLegacyStore(from legacy: URL, to destination: URL) throws {
        guard !FileManager.default.fileExists(atPath: destination.path),
              FileManager.default.fileExists(atPath: legacy.path) else { return }
        try FileManager.default.copyItem(at: legacy, to: destination)
    }

    func recordText(_ text: String) {
        guard !text.isEmpty, text.utf8.count <= Self.textLimit else { return }
        let id = HistoryItem.fingerprint(kind: "text", data: Data(text.utf8))
        insert(HistoryItem(id: id, content: .text(text), copiedAt: Date()))
    }

    func recordPNG(_ data: Data) {
        guard !data.isEmpty, data.count <= Self.imageLimit else { return }
        let id = HistoryItem.fingerprint(kind: "image", data: data)
        let filename = id + ".png"
        do {
            let url = directory.appendingPathComponent(filename)
            if !fileManager.fileExists(atPath: url.path) {
                try data.write(to: url, options: .atomic)
                try fileManager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
            }
            insert(HistoryItem(id: id, content: .image(filename: filename, bytes: data.count), copiedAt: Date()))
        } catch {
            errorMessage = "Image could not be saved: \(error.localizedDescription)"
        }
    }

    func recordFiles(_ urls: [URL]) {
        let urls = urls.filter(\.isFileURL).map(\.standardizedFileURL)
        guard !urls.isEmpty else { return }
        do {
            let data = try JSONEncoder().encode(urls.map(\.absoluteString))
            let id = HistoryItem.fingerprint(kind: "files", data: data)
            insert(HistoryItem(id: id, content: .files(urls), copiedAt: Date()))
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func clear() {
        save([])
    }

    func imageURL(for item: HistoryItem) -> URL? {
        guard case .image(let filename, _) = item.content else { return nil }
        return directory.appendingPathComponent(filename)
    }

    private func insert(_ item: HistoryItem) {
        save([item] + items.filter { $0.id != item.id })
    }

    private func save(_ updated: [HistoryItem]) {
        do {
            try persist(updated)
            errorMessage = nil
        } catch {
            errorMessage = "History could not be saved: \(error.localizedDescription)"
        }
    }

    private func persist(_ updated: [HistoryItem]) throws {
        var retained = Array(updated.prefix(itemLimit))
        var bytes = retained.reduce(0) { total, item in
            if case .image(_, let size) = item.content { return total + size }
            return total
        }
        for index in retained.indices.reversed() where bytes > imageBudget {
            if case .image(_, let size) = retained[index].content {
                bytes -= size
                retained.remove(at: index)
            }
        }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(Index(items: retained)).write(to: indexURL, options: .atomic)
        try fileManager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: indexURL.path)
        items = retained
        let filenames = Set(retained.compactMap { item -> String? in
            if case .image(let filename, _) = item.content { return filename }
            return nil
        })
        for url in try fileManager.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
            where url.pathExtension == "png" && !filenames.contains(url.lastPathComponent) {
            try fileManager.removeItem(at: url)
        }
    }

    private enum StoreError: LocalizedError {
        case unsupportedIndex
        var errorDescription: String? { "This history was written by a newer version of CopyOver." }
    }
}
