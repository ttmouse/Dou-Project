import XCTest
@testable import ProjectManager

/// 热力图数据生成测试（P0 性能修复的回归护栏）
///
/// 症状背景：看板首帧曾卡 5 秒 —— 旧实现按「天 × 项目」双重循环，
/// 每次查询都新建 DateFormatter 并重新解析整条 git_daily。
/// 现改为「每个项目解析一次 + 日期倒排索引」，本文件锁住两件事：
///   1. 输出语义没变（每日提交数、当日项目及顺序、窗口形状）
///   2. 生成成本回到毫秒级（否则说明有人改回了逐日逐项目重算）
final class HeatmapLogicTests: XCTestCase {

    private let calendar = Calendar.current
    private let dayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()

    // MARK: - 辅助

    private var todayStart: Date { calendar.startOfDay(for: Date()) }

    /// 生成「N 天前」的 yyyy-MM-dd 键（N=0 即今天）
    private func key(daysAgo: Int) -> String {
        let date = calendar.date(byAdding: .day, value: -daysAgo, to: todayStart)!
        return dayFormatter.string(from: date)
    }

    private func cell(_ data: [HeatmapLogic.HeatmapData], daysAgo: Int) -> HeatmapLogic.HeatmapData? {
        let target = key(daysAgo: daysAgo)
        return data.first { dayFormatter.string(from: $0.date) == target }
    }

    private func makeData(_ name: String, gitDaily: String?) -> ProjectData {
        ProjectFixtures.make(name: name, path: "/tmp/heatmap/\(name)", gitDaily: gitDaily).toProjectData()
    }

    // MARK: - 窗口形状

    func testFullYearWindowShape() {
        let data = HeatmapLogic.generateHeatmapData(from: [makeData("A", gitDaily: nil)], days: 365)

        XCTAssertEqual(data.count, 365)
        XCTAssertEqual(dayFormatter.string(from: data.first!.date), key(daysAgo: 365), "窗口首日应为一年前")
        XCTAssertEqual(dayFormatter.string(from: data.last!.date), key(daysAgo: 1), "窗口末日应为昨天")

        // 每个数据点都对齐到当天 00:00，且逐日递增
        for point in data {
            XCTAssertEqual(point.date, calendar.startOfDay(for: point.date))
        }
        for index in 1..<data.count {
            let gap = calendar.dateComponents([.day], from: data[index - 1].date, to: data[index].date).day
            XCTAssertEqual(gap, 1, "第 \(index) 个数据点与前一天不相邻")
        }
    }

    /// 表征测试：窗口尾是「昨天」，今天的提交落在窗口外。
    /// 这是改动前就存在的边界行为（非本次性能修复引入），此处留痕以便后续单独讨论是否修正。
    func testTodayCommitsFallOutsideWindow() {
        let data = HeatmapLogic.generateHeatmapData(
            from: [makeData("今天提交", gitDaily: "\(key(daysAgo: 0)):5")],
            days: 365
        )

        XCTAssertNil(cell(data, daysAgo: 0), "窗口不含今天")
        XCTAssertEqual(data.reduce(0) { $0 + $1.commitCount }, 0)
    }

    // MARK: - 每日聚合语义

    func testSumsCommitsPerDayAndKeepsInputOrder() {
        let projects = [
            makeData("A", gitDaily: "\(key(daysAgo: 1)):2"),
            makeData("B", gitDaily: "\(key(daysAgo: 1)):3"),
            makeData("C", gitDaily: nil),
            makeData("D", gitDaily: "\(key(daysAgo: 1)):1"),
        ]

        let data = HeatmapLogic.generateHeatmapData(from: projects, days: 365)
        let yesterday = cell(data, daysAgo: 1)

        XCTAssertEqual(yesterday?.commitCount, 6)
        XCTAssertEqual(yesterday?.projects.map(\.name), ["A", "B", "D"], "当日项目应按输入顺序，且不含无提交项目")
    }

    func testTotalCommitsMatchInput() {
        let projects = [
            makeData("A", gitDaily: "\(key(daysAgo: 1)):2,\(key(daysAgo: 3)):4"),
            makeData("B", gitDaily: "\(key(daysAgo: 3)):1"),
            makeData("C", gitDaily: "\(key(daysAgo: 500)):99"),  // 窗口外，不应计入
        ]

        let data = HeatmapLogic.generateHeatmapData(from: projects, days: 365)

        XCTAssertEqual(data.reduce(0) { $0 + $1.commitCount }, 7)
        XCTAssertEqual(cell(data, daysAgo: 3)?.projects.map(\.name), ["A", "B"])
    }

    func testZeroCountEntriesAreNotListed() {
        let data = HeatmapLogic.generateHeatmapData(
            from: [makeData("A", gitDaily: "\(key(daysAgo: 2)):0")],
            days: 365
        )

        let day = cell(data, daysAgo: 2)
        XCTAssertEqual(day?.commitCount, 0)
        XCTAssertTrue(day?.projects.isEmpty ?? false, "0 次提交不应算作当日活跃项目")
    }

    func testEmptyProjectsProduceZeroedWindow() {
        let year = HeatmapLogic.generateHeatmapData(from: [], days: 365)
        XCTAssertEqual(year.count, 365)
        XCTAssertTrue(year.allSatisfy { $0.commitCount == 0 && $0.projects.isEmpty })

        let sidebar = HeatmapLogic.generateHeatmapData(from: [], days: 90)
        XCTAssertEqual(sidebar.count, 90)
    }

    // MARK: - 侧边栏（数据驱动范围）

    func testSidebarWindowStartsAtEarliestData() {
        let data = HeatmapLogic.generateHeatmapData(
            from: [makeData("A", gitDaily: "\(key(daysAgo: 10)):3")],
            days: 90
        )

        XCTAssertEqual(data.count, 10, "窗口应收缩到最早数据所在的那一天")
        XCTAssertEqual(cell(data, daysAgo: 10)?.commitCount, 3)
        XCTAssertEqual(dayFormatter.string(from: data.last!.date), key(daysAgo: 1))
    }

    func testSidebarWindowIsClampedByLookback() {
        let data = HeatmapLogic.generateHeatmapData(
            from: [makeData("A", gitDaily: "\(key(daysAgo: 200)):3")],
            days: 90
        )

        XCTAssertEqual(data.count, 90, "超过回溯上限时固定为 90 天")
        XCTAssertEqual(data.reduce(0) { $0 + $1.commitCount }, 0, "窗口外的历史数据不应显示")
    }

    // MARK: - 稳定性

    func testRepeatedCallsAreDeterministic() {
        let projects = [
            makeData("A", gitDaily: "\(key(daysAgo: 1)):2,\(key(daysAgo: 5)):1"),
            makeData("B", gitDaily: "\(key(daysAgo: 5)):3"),
        ]

        let first = HeatmapLogic.generateHeatmapData(from: projects, days: 365)
        let second = HeatmapLogic.generateHeatmapData(from: projects, days: 365)

        XCTAssertEqual(first.count, second.count)
        for (lhs, rhs) in zip(first, second) {
            XCTAssertEqual(lhs.date, rhs.date)
            XCTAssertEqual(lhs.commitCount, rhs.commitCount)
            XCTAssertEqual(lhs.projects.map(\.id), rhs.projects.map(\.id))
        }
    }

    // MARK: - 性能回归护栏

    /// 旧实现（逐日 × 逐项目新建 DateFormatter + 重解析）在 200 项目 × 365 天时实测约 3 秒。
    /// 现在应为毫秒级；超过 1 秒即说明复杂度退回了旧写法。
    func testFullYearGenerationStaysFast() {
        let projects: [ProjectData] = (0..<200).map { index in
            let daily = (1...20).map { "\(key(daysAgo: $0 + index % 5)):\(($0 % 3) + 1)" }.joined(separator: ",")
            return makeData("P\(index)", gitDaily: daily)
        }

        let start = Date()
        let data = HeatmapLogic.generateHeatmapData(from: projects, days: 365)
        let elapsed = Date().timeIntervalSince(start)

        XCTAssertEqual(data.count, 365)
        XCTAssertLessThan(elapsed, 1.0, "365 天 × 200 项目的热力图生成耗时 \(elapsed)s，疑似退回逐日重算实现")
    }
}
