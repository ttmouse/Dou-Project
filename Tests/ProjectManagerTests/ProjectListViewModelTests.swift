import Combine
import AppKit
import SwiftUI
import XCTest
@testable import ProjectManager

@MainActor
final class ProjectListViewModelTests: XCTestCase {
    private final class Source: ProjectListSource {
        var projects: [UUID: Project]
        var listHiddenTags: Set<String> = []
        let changes = CurrentValueSubject<Void, Never>(())
        let hiddenChanges = CurrentValueSubject<Set<String>, Never>([])
        let gitChanges = PassthroughSubject<[UUID: Project], Never>()
        let sorter = ProjectSortManager()
        private(set) var sortedReads = 0
        private(set) var directoryReads = 0
        var listProjectsChanged: AnyPublisher<Void, Never> { changes.eraseToAnyPublisher() }
        var listHiddenTagsChanged: AnyPublisher<Set<String>, Never> { hiddenChanges.eraseToAnyPublisher() }
        var listGitDailyChanged: AnyPublisher<[UUID: Project], Never> { gitChanges.eraseToAnyPublisher() }
        init(_ projects: [Project]) {
            self.projects = Dictionary(uniqueKeysWithValues: projects.map { ($0.id, $0) })
            sorter.updateSortedProjects(projects)
        }
        func setSortCriteria(_ criteria: TagManager.SortCriteria, ascending: Bool) {
            sorter.setSortCriteria(criteria, ascending: ascending)
        }
        func getSortedProjects() -> [Project] {
            sortedReads += 1
            return sorter.getSortedProjects()
        }
        func projects(in directory: String) -> [Project] {
            directoryReads += 1
            return Array(projects.values)
        }
        func unassignedProjects() -> [Project] { Array(projects.values) }
    }

    func testSingleSortChangeUsesNewValue() async throws {
        let source = Source([ProjectFixtures.make(name: "zeta"), ProjectFixtures.make(name: "Alpha")])
        let model = ProjectListViewModel()
        model.setTagManager(source)
        model.sortOption = .nameDescending
        try await Task.sleep(nanoseconds: 30_000_000)
        XCTAssertEqual(model.filteredProjects.map(\.name), ["zeta", "Alpha"])
        model.sortOption = .nameAscending
        try await Task.sleep(nanoseconds: 30_000_000)
        XCTAssertEqual(model.filteredProjects.map(\.name), ["Alpha", "zeta"])
    }

    private func nextMainTurn() async {
        await withCheckedContinuation { continuation in
            DispatchQueue.main.async { continuation.resume() }
        }
    }

    private struct SearchInteractionHarness: View {
        @ObservedObject var model: ProjectListViewModel
        @ObservedObject var results: ProjectResultsStore
        var body: some View {
            VStack {
                SearchBar(input: model.searchInput)
                ScrollView {
                    LazyVStack {
                        ForEach(results.projects) { Text($0.name) }
                    }
                }
            }
        }
    }

    func testSearchMatchesOnlyNamesNotUsernamesOrParentDirectories() async {
        let named = ProjectFixtures.make(name: "DouTools", path: "/fixture/tools")
        let usernameOnly = ProjectFixtures.make(name: "Alpha", path: "/Users/example-dou/Projects/Alpha")
        let directoryOnly = ProjectFixtures.make(name: "beta", path: "/fixture/dou-projects/beta")
        let source = Source([named, usernameOnly, directoryOnly])
        let model = ProjectListViewModel()
        model.setTagManager(source)
        model.searchText = "dou"
        await nextMainTurn()
        XCTAssertEqual(model.filteredProjects.map(\.id), [named.id])
        let pureResults = ProjectLogic.filterProjects(
            [named, usernameOnly, directoryOnly].map { $0.toProjectData() }, by: "dou"
        )
        XCTAssertEqual(pureResults.map(\.id), [named.id])
        model.searchText = ""
        await nextMainTurn()
        XCTAssertEqual(model.filteredProjects.count, 3)
    }

    func testTypingDoesNotInvalidateWholeListBeforeResultsChange() {
        let source = Source([ProjectFixtures.make(name: "Alpha"), ProjectFixtures.make(name: "beta")])
        let model = ProjectListViewModel()
        model.setTagManager(source)
        var invalidations = 0
        let subscription = model.objectWillChange.sink { invalidations += 1 }
        model.searchText = "beta"
        XCTAssertEqual(invalidations, 0, "输入文字应只刷新搜索框，不立即刷新整页列表")
        withExtendedLifetime(subscription) {}
    }

    /// 搜索结果必须只通知结果对象；页面级 ViewModel 不能再被触发，
    /// 否则侧边栏标签统计、目录归属会跟着每次按键重算。
    func testSearchResultsDoNotInvalidatePageViewModel() async {
        let source = Source(ProjectFixtures.makeMany(200))
        let model = ProjectListViewModel()
        model.setTagManager(source)
        var pageInvalidations = 0
        var resultInvalidations = 0
        let pageSubscription = model.objectWillChange.sink { pageInvalidations += 1 }
        let resultSubscription = model.results.objectWillChange.sink { resultInvalidations += 1 }

        for query in ["Project1", "Project12", "Project123", ""] {
            model.searchText = query
            await nextMainTurn()
            await nextMainTurn()
        }

        XCTAssertGreaterThan(resultInvalidations, 0, "结果必须刷新")
        XCTAssertEqual(pageInvalidations, 0, "搜索不能触发页面级重绘")
        withExtendedLifetime((pageSubscription, resultSubscription)) {}
    }

    func testSearchRespondsNextMainTurnDuringContinuousTypingAndClearing() async {
        let source = Source([
            ProjectFixtures.make(name: "Alpha"), ProjectFixtures.make(name: "beta"),
            ProjectFixtures.make(name: "项目列表"),
        ])
        let model = ProjectListViewModel()
        model.setTagManager(source)
        for query in ["b", "be", "beta", "BET", "bet", "beta"] {
            model.searchText = query
            await nextMainTurn()
            XCTAssertEqual(model.filteredProjects.map(\.name), ["beta"], "不能等待用户停下打字才显示 \(query) 的结果")
        }
        model.searchText = "项目"
        await nextMainTurn()
        XCTAssertEqual(model.filteredProjects.map(\.name), ["项目列表"])
        model.searchText = ""
        await nextMainTurn()
        XCTAssertEqual(model.filteredProjects.count, 3, "清空搜索必须立即恢复结果")
    }

    func testRapidReplacementCannotPublishAnEarlierSearch() async {
        let source = Source([ProjectFixtures.make(name: "Alpha"), ProjectFixtures.make(name: "beta")])
        let model = ProjectListViewModel()
        model.setTagManager(source)
        model.searchText = "Alpha"
        model.searchText = "no match"
        model.searchText = "beta"
        await nextMainTurn()
        XCTAssertEqual(model.filteredProjects.map(\.name), ["beta"])
    }

    func testTypingReusesDirectoryCandidates() async throws {
        let source = Source([ProjectFixtures.make(name: "Alpha"), ProjectFixtures.make(name: "beta")])
        let model = ProjectListViewModel()
        model.setTagManager(source)
        model.selectedDirectory = "/test"
        try await Task.sleep(nanoseconds: 250_000_000)
        let reads = source.directoryReads
        model.searchText = "beta"
        await nextMainTurn()
        XCTAssertEqual(model.filteredProjects.map(\.name), ["beta"])
        XCTAssertEqual(source.directoryReads, reads, "连续输入不能反复解析目录归属")
    }

    func testNativeSearchFieldEditingUpdatesMatchingResults() async throws {
        let source = Source(ProjectFixtures.makeMany(500) + [ProjectFixtures.make(name: "beta")])
        let model = ProjectListViewModel()
        model.setTagManager(source)
        let hosting = NSHostingView(rootView: SearchInteractionHarness(model: model, results: model.results))
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 400, height: 500),
                              styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        defer { window.close() }
        window.contentView = hosting
        hosting.layoutSubtreeIfNeeded()

        func textField(in view: NSView) -> NSTextField? {
            if let field = view as? NSTextField, field.isEditable { return field }
            return view.subviews.lazy.compactMap { textField(in: $0) }.first
        }
        let field = try XCTUnwrap(textField(in: hosting))
        XCTAssertTrue(window.makeFirstResponder(field))
        let editor = try XCTUnwrap(field.currentEditor() as? NSTextView)
        var samples: [Double] = []
        for character in "beta" {
            let start = ProcessInfo.processInfo.systemUptime
            editor.insertText(String(character), replacementRange: NSRange(location: editor.string.utf16.count, length: 0))
            await nextMainTurn()
            await nextMainTurn()
            hosting.layoutSubtreeIfNeeded()
            samples.append((ProcessInfo.processInfo.systemUptime - start) * 1000)
            XCTAssertEqual(model.filteredProjects.map(\.name), ["beta"])
            XCTAssertTrue(field.currentEditor() === editor, "结果刷新不能重建编辑器或丢失输入焦点")
        }
        XCTAssertEqual(model.searchInput.text, "beta")
        editor.deleteBackward(nil)
        await nextMainTurn()
        await nextMainTurn()
        XCTAssertEqual(model.searchInput.text, "bet")
        XCTAssertEqual(model.filteredProjects.map(\.name), ["beta"])
        editor.insertText("", replacementRange: NSRange(location: 0, length: editor.string.utf16.count))
        await nextMainTurn()
        await nextMainTurn()
        XCTAssertEqual(model.searchInput.text, "")
        XCTAssertEqual(model.filteredProjects.count, 501)
        FileHandle.standardError.write(Data("PERF native field to result + fixture layout, 501 projects, ms: \(samples)\n".utf8))
    }

    func testGitDailyBackfillDoesNotRefilterResortOrPublishHiddenProjects() async throws {
        let visible = ProjectFixtures.make(name: "visible")
        let hidden = ProjectFixtures.make(name: "hidden", tags: ["private"])
        let source = Source([visible, hidden])
        source.listHiddenTags = ["private"]
        let model = ProjectListViewModel()
        model.setTagManager(source)
        try await Task.sleep(nanoseconds: 250_000_000)
        XCTAssertEqual(model.filteredProjects.map(\.id), [visible.id])
        let reads = source.sortedReads
        var publications = 0
        let subscription = model.results.$projects.dropFirst().sink { _ in publications += 1 }

        let visibleUpdate = visible.copyWith(gitDaily: "2026-10-21:1")
        source.gitChanges.send([visible.id: visibleUpdate])
        XCTAssertEqual(model.filteredProjects, [visibleUpdate])
        XCTAssertEqual(publications, 1)

        // 即使筛选条件尚在防抖等待，也不应因历史回填提前重跑搜索。
        model.searchText = "unmatched"
        source.gitChanges.send([hidden.id: hidden.copyWith(gitDaily: "2026-10-21:9")])
        XCTAssertEqual(model.filteredProjects, [visibleUpdate])
        XCTAssertEqual(publications, 1)
        XCTAssertEqual(source.sortedReads, reads)
        withExtendedLifetime(subscription) {}
    }

    func testSingleDateChangeUsesNewValue() async throws {
        let source = Source([
            ProjectFixtures.make(name: "old", mtime: Date.distantPast),
            ProjectFixtures.make(name: "recent", mtime: Date()),
        ])
        let model = ProjectListViewModel()
        model.setTagManager(source)
        model.dateFilter = .lastDay
        try await Task.sleep(nanoseconds: 30_000_000)
        XCTAssertEqual(model.filteredProjects.map(\.name), ["recent"])
        model.dateFilter = .all
        try await Task.sleep(nanoseconds: 30_000_000)
        XCTAssertEqual(model.filteredProjects.count, 2)
    }

    func testIdenticalFilterDoesNotPublishAnotherList() {
        let source = Source([ProjectFixtures.make()])
        let model = ProjectListViewModel()
        model.setTagManager(source)
        var publications = 0
        let subscription = model.results.$projects.dropFirst().sink { _ in publications += 1 }
        model.forceRefresh()
        model.forceRefresh()
        XCTAssertEqual(publications, 0)
        withExtendedLifetime(subscription) {}
    }

    func testHiddenTagChangeUpdatesList() async throws {
        let source = Source([ProjectFixtures.make(name: "hidden", tags: ["private"])])
        let model = ProjectListViewModel()
        model.setTagManager(source)
        XCTAssertEqual(model.filteredProjects.count, 1)
        source.listHiddenTags = ["private"]
        source.hiddenChanges.send(["private"])
        try await Task.sleep(nanoseconds: 250_000_000)
        XCTAssertTrue(model.filteredProjects.isEmpty)
    }

    func testTenThousandProjectsSearchKeepsOrderAndReflectsUpdatedName() async throws {
        let source = Source(ProjectFixtures.makeMany(10_000))
        let model = ProjectListViewModel()
        let start = ProcessInfo.processInfo.systemUptime
        model.setTagManager(source)
        let setupMilliseconds = (ProcessInfo.processInfo.systemUptime - start) * 1000
        model.sortOption = .nameAscending
        model.searchText = "PROJECT9999"
        try await Task.sleep(nanoseconds: 300_000_000)
        XCTAssertEqual(model.filteredProjects.map(\.name), ["Project9999"])
        let filterStart = ProcessInfo.processInfo.systemUptime
        for _ in 0..<20 { model.forceRefresh() }
        print("PERF 10000 projects: setup \(setupMilliseconds) ms; search mean \((ProcessInfo.processInfo.systemUptime - filterStart) * 1000 / 20) ms")
        let original = try XCTUnwrap(model.filteredProjects.first)
        source.projects[original.id] = ProjectFixtures.make(id: original.id, name: "renamed", path: "/test/path/renamed")
        source.sorter.updateSortedProjects(Array(source.projects.values))
        source.changes.send(())
        try await Task.sleep(nanoseconds: 250_000_000)
        XCTAssertTrue(model.filteredProjects.isEmpty, "改名后旧索引必须失效")
    }
}
