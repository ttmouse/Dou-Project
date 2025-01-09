import Foundation

class TagUsageTracker {
    private var tagUsageCount: [String: Int] = [:]
    private var tagLastUsed: [String: Date] = [:]

    func incrementUsage(for tag: String, count: Int = 1) {
        tagUsageCount[tag] = (tagUsageCount[tag] ?? 0) + count
        tagLastUsed[tag] = Date()
        print("标签 '\(tag)' 使用次数: \(tagUsageCount[tag] ?? 0)")
    }

    func decrementUsage(for tag: String) {
        if let count = tagUsageCount[tag] {
            if count > 1 {
                tagUsageCount[tag] = count - 1
            } else {
                tagUsageCount.removeValue(forKey: tag)
            }
        }
        print("标签 '\(tag)' 使用次数: \(tagUsageCount[tag] ?? 0)")
    }

    func getUsageCount(for tag: String) -> Int {
        return tagUsageCount[tag] ?? 0
    }

    func getLastUsed(for tag: String) -> Date? {
        return tagLastUsed[tag]
    }

    func clearUsage(for tag: String) {
        tagUsageCount.removeValue(forKey: tag)
        tagLastUsed.removeValue(forKey: tag)
    }

    func getMostUsedTags(limit: Int = 10) -> [(String, Int)] {
        return Array(tagUsageCount)
            .sorted { $0.1 > $1.1 }
            .prefix(limit)
            .map { ($0.key, $0.value) }
    }

    func getRecentlyUsedTags(limit: Int = 10) -> [String] {
        return Array(tagLastUsed)
            .sorted { $0.1 > $1.1 }
            .prefix(limit)
            .map { $0.key }
    }
}
