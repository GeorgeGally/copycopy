import Foundation

/// Remembers the history item the bezel should open on. Items are kept by
/// identity, never by index, because a copy shifts the history under them.
struct SelectionMemory: Equatable {
    private static let itemKey = "lastSelectedItemID"
    private static let headKey = "lastHeadItemID"

    var itemID: String?
    var headID: String?

    static func load(from defaults: UserDefaults = .standard) -> SelectionMemory {
        SelectionMemory(itemID: defaults.string(forKey: itemKey), headID: defaults.string(forKey: headKey))
    }

    func save(to defaults: UserDefaults = .standard) {
        defaults.set(itemID, forKey: Self.itemKey)
        defaults.set(headID, forKey: Self.headKey)
    }

    /// Records the item being left behind beside the newest item at that
    /// moment, so a later open can tell whether anything was copied since.
    mutating func remember(_ item: HistoryItem?, in items: [HistoryItem]) {
        guard let item else { return }
        itemID = item.id
        headID = items.first?.id
    }

    /// The item to open on: a copy newer than the remembered head wins once;
    /// otherwise the remembered item, and the newest when it has gone.
    func selectedID(in items: [HistoryItem]) -> String? {
        guard let newest = items.first else { return nil }
        guard headID == newest.id, let itemID, items.contains(where: { $0.id == itemID }) else {
            return newest.id
        }
        return itemID
    }
}
