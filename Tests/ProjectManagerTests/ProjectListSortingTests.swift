import XCTest
@testable import ProjectManager

final class ProjectListSortingTests: XCTestCase {
    func testNameSortingSupportsAscendingAndDescendingOrder() {
        let projects = [
            makeProject(name: "zeta"),
            makeProject(name: "Alpha"),
            makeProject(name: "beta"),
        ]

        XCTAssertEqual(
            sortedNames(projects, criteria: .name, ascending: true),
            ["Alpha", "beta", "zeta"]
        )
        XCTAssertEqual(
            sortedNames(projects, criteria: .name, ascending: false),
            ["zeta", "beta", "Alpha"]
        )
    }

    func testClickingHeadersSelectsDefaultDirectionThenTogglesDirection() {
        XCTAssertEqual(SortOption.timeDescending.toggled(for: .name), .nameAscending)
        XCTAssertEqual(SortOption.nameAscending.toggled(for: .name), .nameDescending)
        XCTAssertEqual(SortOption.nameDescending.toggled(for: .name), .nameAscending)

        XCTAssertEqual(SortOption.nameAscending.toggled(for: .activity), .timeDescending)
        XCTAssertEqual(SortOption.timeDescending.toggled(for: .activity), .timeAscending)

        XCTAssertEqual(SortOption.timeAscending.toggled(for: .commits), .commitCountDescending)
        XCTAssertEqual(SortOption.commitCountDescending.toggled(for: .commits), .commitCountAscending)
    }

    func testActivityAndCommitSortingSupportBothDirections() {
        let older = makeProject(name: "older", activityAt: Date(timeIntervalSince1970: 100), commits: 8)
        let newer = makeProject(name: "newer", activityAt: Date(timeIntervalSince1970: 200), commits: 2)
        let projects = [older, newer]

        XCTAssertEqual(
            sortedNames(projects, criteria: .lastModified, ascending: true),
            ["older", "newer"]
        )
        XCTAssertEqual(
            sortedNames(projects, criteria: .lastModified, ascending: false),
            ["newer", "older"]
        )
        XCTAssertEqual(
            sortedNames(projects, criteria: .gitCommits, ascending: true),
            ["newer", "older"]
        )
        XCTAssertEqual(
            sortedNames(projects, criteria: .gitCommits, ascending: false),
            ["older", "newer"]
        )
    }

    func testEqualPrimaryValuesUseAStableNameTieBreak() {
        let projects = [
            makeProject(name: "beta", activityAt: Date(timeIntervalSince1970: 100), commits: 3),
            makeProject(name: "Alpha", activityAt: Date(timeIntervalSince1970: 100), commits: 3),
        ]

        XCTAssertEqual(
            sortedNames(projects, criteria: .lastModified, ascending: false),
            ["Alpha", "beta"]
        )
        XCTAssertEqual(
            sortedNames(projects, criteria: .gitCommits, ascending: false),
            ["Alpha", "beta"]
        )
    }

    private func sortedNames(
        _ projects: [Project],
        criteria: TagManager.SortCriteria,
        ascending: Bool
    ) -> [String] {
        let manager = ProjectSortManager()
        manager.updateSortedProjects(projects)
        manager.setSortCriteria(criteria, ascending: ascending)
        return manager.getSortedProjects().map(\.name)
    }

    private func makeProject(
        name: String,
        activityAt: Date = Date(),
        commits: Int = 0
    ) -> Project {
        Project(
            id: UUID(),
            name: name,
            path: "/tmp/\(name)",
            mtime: activityAt,
            activityAt: activityAt,
            git_commits: commits
        )
    }
}
