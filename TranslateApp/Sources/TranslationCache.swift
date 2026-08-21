import Foundation

actor TranslationCache {
    struct Key: Hashable, Sendable {
        let text: String
        let targetLanguage: String
    }

    private struct Entry {
        let result: TranslationResult
        let cost: Int
        var lastAccess: UInt64
    }

    private let capacity: Int
    private let maximumCost: Int
    private var entries: [Key: Entry] = [:]
    private var currentCost = 0
    private var accessCounter: UInt64 = 0
    private var epoch: UInt64 = 0

    init(capacity: Int = 128, maximumCost: Int = 1_000_000) {
        precondition(capacity > 0)
        precondition(maximumCost > 0)
        self.capacity = capacity
        self.maximumCost = maximumCost
    }

    func value(for key: Key) -> TranslationResult? {
        guard var entry = entries[key] else { return nil }
        entry.lastAccess = nextAccessValue()
        entries[key] = entry
        return entry.result
    }

    func currentEpoch() -> UInt64 {
        epoch
    }

    func insert(
        _ result: TranslationResult,
        for key: Key,
        ifEpochMatches expectedEpoch: UInt64
    ) {
        guard epoch == expectedEpoch else { return }
        let cost = key.text.utf8.count + result.translatedText.utf8.count
        guard cost <= maximumCost else { return }

        if let existing = entries[key] {
            currentCost -= existing.cost
        }
        entries[key] = Entry(result: result, cost: cost, lastAccess: nextAccessValue())
        currentCost += cost

        while entries.count > capacity || currentCost > maximumCost {
            guard let leastRecentlyUsed = entries.min(by: {
                $0.value.lastAccess < $1.value.lastAccess
            })?.key,
            let removed = entries.removeValue(forKey: leastRecentlyUsed) else {
                break
            }
            currentCost -= removed.cost
        }
    }

    func invalidate() {
        epoch &+= 1
        entries.removeAll(keepingCapacity: false)
        currentCost = 0
        accessCounter = 0
    }

    private func nextAccessValue() -> UInt64 {
        accessCounter &+= 1
        return accessCounter
    }
}
