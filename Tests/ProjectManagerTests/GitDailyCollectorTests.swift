import XCTest
@testable import ProjectManager

/// GitDailyCollector 纯函数测试
///
/// 背景：git_daily 是磁盘上的紧凑字符串（`"2025-08-25:3,2025-08-24:5"`），
/// 解析/格式化是热力图、看板统计的公共底座，改错会静默污染所有活跃度数据。
final class GitDailyCollectorTests: XCTestCase {

    private let dayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()

    // MARK: - parseGitDaily

    func testParsesDateCountPairs() {
        let parsed = GitDailyCollector.parseGitDaily("2025-08-25:3,2025-08-24:5")
        XCTAssertEqual(parsed, ["2025-08-25": 3, "2025-08-24": 5])
    }

    func testIgnoresMalformedEntries() {
        let parsed = GitDailyCollector.parseGitDaily("abc,2025-08-25,2025-08-25:x,:3,2025-08-26:2")
        XCTAssertEqual(parsed, ["2025-08-26": 2], "只有形如 yyyy-MM-dd:数字 的片段应被采纳")
    }

    func testTrailingCommaIsIgnored() {
        XCTAssertEqual(GitDailyCollector.parseGitDaily("2025-08-25:1,"), ["2025-08-25": 1])
    }

    func testEmptyOrNilReturnsEmpty() {
        XCTAssertTrue(GitDailyCollector.parseGitDaily(nil).isEmpty)
        XCTAssertTrue(GitDailyCollector.parseGitDaily("").isEmpty)
    }

    func testDuplicateDatesLastWins() {
        XCTAssertEqual(GitDailyCollector.parseGitDaily("2025-08-25:1,2025-08-25:9")["2025-08-25"], 9)
    }

    // MARK: - formatGitDaily

    func testFormatsSortedAscending() {
        let formatted = GitDailyCollector.formatGitDaily(["2025-08-25": 3, "2025-08-01": 1, "2025-09-10": 2])
        XCTAssertEqual(formatted, "2025-08-01:1,2025-08-25:3,2025-09-10:2")
    }

    func testFormatEmptyReturnsEmptyString() {
        XCTAssertEqual(GitDailyCollector.formatGitDaily([:]), "")
    }

    func testRoundTripPreservesData() {
        let original = ["2025-08-25": 3, "2025-08-24": 5, "2024-01-01": 17]
        XCTAssertEqual(GitDailyCollector.parseGitDaily(GitDailyCollector.formatGitDaily(original)), original)
    }

    // MARK: - getCommitCount

    func testGetCommitCountForKnownDate() {
        let date = dayFormatter.date(from: "2025-08-25")!
        XCTAssertEqual(GitDailyCollector.getCommitCount(from: "2025-08-25:4,2025-08-24:1", for: date), 4)
    }

    func testGetCommitCountUsesCalendarDayOnly() {
        // 同一天的任意时刻都应命中同一天的数据点
        let noon = dayFormatter.date(from: "2025-08-25")!.addingTimeInterval(12 * 3600)
        XCTAssertEqual(GitDailyCollector.getCommitCount(from: "2025-08-25:4", for: noon), 4)
    }

    func testGetCommitCountReturnsZeroForUnknownDate() {
        let date = dayFormatter.date(from: "2025-08-25")!
        XCTAssertEqual(GitDailyCollector.getCommitCount(from: "2025-08-24:1", for: date), 0)
    }

    func testGetCommitCountReturnsZeroForNilOrEmpty() {
        let date = dayFormatter.date(from: "2025-08-25")!
        XCTAssertEqual(GitDailyCollector.getCommitCount(from: nil, for: date), 0)
        XCTAssertEqual(GitDailyCollector.getCommitCount(from: "", for: date), 0)
    }

    // MARK: - 性能回归护栏

    /// DateFormatter 创建成本高：热力图曾因「每个项目每天新建一个」而卡 5 秒。
    /// 这里锁住「格式化器是全模块共享的同一个实例」，防止有人改回每次新建。
    func testDateKeyFormatterIsSharedInstance() {
        XCTAssertTrue(
            GitDailyCollector.dateKeyFormatter === GitDailyCollector.dateKeyFormatter,
            "yyyy-MM-dd 格式化器必须是静态复用的单例"
        )
    }
}
