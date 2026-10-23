import Foundation

enum ProjectCardDateDisplay {
    static func label(for date: Date, relativeTo now: Date = Date(), calendar: Calendar = .current) -> String {
        let start = calendar.startOfDay(for: date)
        let end = calendar.startOfDay(for: now)
        let days = calendar.dateComponents([.day], from: start, to: end).day ?? 0

        switch days {
        case 0: return "今天"
        case 1: return "昨天"
        case 2...: return "\(days) 天前"
        case -1: return "明天"
        default: return "\(-days) 天后"
        }
    }
}
