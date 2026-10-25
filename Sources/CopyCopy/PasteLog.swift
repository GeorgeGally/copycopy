import Foundation

/// Plain-text trail of every paste attempt, because NSLog from this app does
/// not reach the unified log. Lives beside the history:
/// ~/Library/Application Support/CopyCopy/paste.log
@MainActor
enum PasteLog {
    static let url = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("CopyCopy", isDirectory: true).appendingPathComponent("paste.log")
    private static let stamp: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss.SSS"
        return formatter
    }()

    static func write(_ message: String) {
        NSLog("CopyCopy %@", message)
        let line = "\(stamp.string(from: Date())) \(message)\n"
        guard let data = line.data(using: .utf8) else { return }
        if let size = try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int, size > 512 * 1_024 {
            try? FileManager.default.removeItem(at: url)
        }
        if let handle = try? FileHandle(forWritingTo: url) {
            handle.seekToEndOfFile()
            handle.write(data)
            try? handle.close()
        } else {
            try? data.write(to: url, options: .atomic)
        }
    }
}
