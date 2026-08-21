import Foundation

actor TranslationCache {
    struct Key: Hashable, Sendable {
        let text: String
        let targetLanguage: String
    }

    private struct Entry {
        let result: TranslationResult
        var lastAccess: UInt64
    }

    private let capacity: Int
    private var entries: [Key: Entry] = [:]
    private var accessCounter: UInt64 = 0

    init(capacity: Int = 128) {
        precondition(capacity > 0)
        self.capacity = capacity
    }

    func value(for key: Key) -> TranslationResult? {
        guard var entry = entries[key] else { return nil }
        entry.lastAccess = nextAccessValue()
        entries[key] = entry
        return entry.result
    }

    func insert(_ result: TranslationResult, for key: Key) {
        entries[key] = Entry(result: result, lastAccess: nextAccessValue())
        guard entries.count > capacity,
              let leastRecentlyUsed = entries.min(by: { $0.value.lastAccess < $1.value.lastAccess })?.key else {
            return
        }
        entries.removeValue(forKey: leastRecentlyUsed)
    }

    func removeAll() {
        entries.removeAll(keepingCapacity: false)
        accessCounter = 0
    }

    private func nextAccessValue() -> UInt64 {
        accessCounter &+= 1
        return accessCounter
    }
}
