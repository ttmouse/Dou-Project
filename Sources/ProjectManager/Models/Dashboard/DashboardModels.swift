import Foundation
import SwiftUI

// MARK: - Dashboard Namespace

enum Dashboard {
    /// 热力图统计信息
    struct HeatmapStats {
        let totalDays: Int
        let activeDays: Int
        let totalCommits: Int
        let maxCommitsInDay: Int
        let averageCommitsPerDay: Double
        let activityRate: Double
    }
    
    /// 热力图配置
    struct HeatmapConfig: Equatable {
        let daysToShow: Int
        let cellSize: CGFloat
        let cellSpacing: CGFloat
        let cornerRadius: CGFloat
        let showWeekdayLabels: Bool
        let showMonthLabels: Bool
        
        static let `default` = HeatmapConfig(
            daysToShow: 365,
            cellSize: 12,
            cellSpacing: 2,
            cornerRadius: 2,
            showWeekdayLabels: true,
            showMonthLabels: true
        )
    }
}

/// 时间范围枚举
enum TimeRange: CaseIterable {
    case oneMonth, threeMonths, sixMonths, oneYear
    
    var displayName: String {
        switch self {
        case .oneMonth: return "最近1个月"
        case .threeMonths: return "最近3个月"
        case .sixMonths: return "最近6个月"
        case .oneYear: return "最近1年"
        }
    }
    
    var days: Int {
        switch self {
        case .oneMonth: return 30
        case .threeMonths: return 90
        case .sixMonths: return 180
        case .oneYear: return 365
        }
    }
}

/// 日常活动数据模型
struct DailyActivity: Identifiable, Equatable, Codable {
    let id: String
    let date: Date
    let commitCount: Int
    let projects: Set<UUID>
    
    init(date: Date, commitCount: Int = 0, projects: Set<UUID> = []) {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        self.id = formatter.string(from: date)
        self.date = date
        self.commitCount = commitCount
        self.projects = projects
    }
    
    var activityLevel: ActivityLevel {
        switch commitCount {
        case 0: return .none
        case 1...3: return .low
        case 4...8: return .medium
        case 9...15: return .high
        default: return .extreme
        }
    }
}

/// 活动级别枚举
enum ActivityLevel: Int, CaseIterable {
    case none = 0, low = 1, medium = 2, high = 3, extreme = 4
    
    var color: Color {
        switch self {
        case .none: return Color.gray.opacity(0.2)
        case .low: return Color(.systemGreen).opacity(0.3)
        case .medium: return Color(.systemGreen).opacity(0.6)
        case .high: return Color(.systemGreen).opacity(0.8)
        case .extreme: return Color(.systemGreen)
        }
    }
}

