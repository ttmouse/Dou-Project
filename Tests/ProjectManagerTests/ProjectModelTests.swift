import XCTest
@testable import ProjectManager

/// Project 扁平模型的数据契约测试
///
/// 背景：`projects.json` / `app_state.json` 直接与本结构互映，字段名就是磁盘契约；
/// 其他组件（热力图、看板、目录归属）都读这些字段。改字段名/改 Equatable 语义
/// 会静默损坏用户数据或造成无意义重绘。
final class ProjectModelTests: XCTestCase {

    private func encodeToJSONObject(_ project: Project) throws -> [String: Any] {
        let data = try JSONEncoder().encode(project)
        return try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    // MARK: - 磁盘契约

    func testEncodesExpectedFieldNames() throws {
        let project = ProjectFixtures.make(
            name: "契约项目",
            path: "/tmp/contract",
            tags: ["swift"],
            size: 2048,
            gitCommits: 7,
            gitDaily: "2025-08-25:3",
            startupCommand: "npm run dev",
            customPort: 5173
        )

        let json = try encodeToJSONObject(project)

        // 这些键名是 projects.json 的既有契约，改动等于破坏用户已有数据
        for key in [
            "id", "name", "path", "tags", "mtime", "size", "checksum",
            "git_commits", "git_last_commit", "git_daily",
            "startupCommand", "customPort", "created", "checked",
        ] {
            XCTAssertNotNil(json[key], "projects.json 契约字段缺失: \(key)")
        }
    }

    func testRoundTripPreservesAllFields() throws {
        let original = ProjectFixtures.make(
            name: "往返项目",
            path: "/tmp/round-trip/中文目录",
            tags: ["a", "标签", "c"],
            mtime: Date(timeIntervalSince1970: 1_600_000_000),
            size: 4096,
            checksum: "sha256:deadbeef",
            gitCommits: 42,
            gitLastCommit: Date(timeIntervalSince1970: 1_650_000_000),
            gitDaily: "2025-08-25:3,2025-08-24:5",
            startupCommand: "pnpm dev",
            customPort: 3000,
            created: Date(timeIntervalSince1970: 1_500_000_000),
            checked: Date(timeIntervalSince1970: 1_700_000_000)
        )

        let decoded = try JSONDecoder().decode(Project.self, from: JSONEncoder().encode(original))

        XCTAssertEqual(decoded.id, original.id)
        XCTAssertEqual(decoded.name, original.name)
        XCTAssertEqual(decoded.path, original.path)
        XCTAssertEqual(decoded.tags, original.tags)
        XCTAssertEqual(decoded.mtime, original.mtime)
        XCTAssertEqual(decoded.size, original.size)
        XCTAssertEqual(decoded.checksum, original.checksum)
        XCTAssertEqual(decoded.git_commits, original.git_commits)
        XCTAssertEqual(decoded.git_last_commit, original.git_last_commit)
        XCTAssertEqual(decoded.git_daily, original.git_daily)
        XCTAssertEqual(decoded.startupCommand, original.startupCommand)
        XCTAssertEqual(decoded.customPort, original.customPort)
        XCTAssertEqual(decoded.created, original.created)
        XCTAssertEqual(decoded.checked, original.checked)
        XCTAssertEqual(decoded, original, "Equatable 必须认为往返后的对象相等")
    }

    func testUnknownJSONFieldsAreIgnored() throws {
        // 前向兼容：未来版本写入的额外字段不应导致旧版本解析失败
        let json = """
        {
          "id": "\(UUID().uuidString)",
          "name": "旧版本读取新数据",
          "path": "/tmp/forward-compat",
          "tags": [],
          "mtime": 1600000000,
          "size": 0,
          "checksum": "sha256:x",
          "git_commits": 0,
          "git_last_commit": 1600000000,
          "created": 1600000000,
          "checked": 1600000000,
          "some_future_field": {"nested": true}
        }
        """.data(using: .utf8)!

        let decoded = try JSONDecoder().decode(Project.self, from: json)
        XCTAssertEqual(decoded.name, "旧版本读取新数据")
        XCTAssertNil(decoded.git_daily)
    }

    func testMissingOptionalGitDailyDecodesAsNil() throws {
        let project = ProjectFixtures.make(gitDaily: nil)
        let decoded = try JSONDecoder().decode(Project.self, from: JSONEncoder().encode(project))
        XCTAssertNil(decoded.git_daily)
    }

    // MARK: - Equatable 语义（ProjectCard 靠它避免重绘）

    func testEqualityIgnoresNothingButNotes() {
        let a = ProjectFixtures.make(tags: ["x"], gitDaily: "2025-08-25:1")
        XCTAssertEqual(a, a)

        XCTAssertNotEqual(a, ProjectFixtures.make(name: a.name, path: a.path, tags: ["y"]), "标签变化必须视为不等")
        XCTAssertNotEqual(a, ProjectFixtures.make(name: a.name, path: a.path, gitDaily: nil), "git_daily 变化必须视为不等")
        XCTAssertNotEqual(
            a,
            ProjectFixtures.make(name: a.name, path: a.path, mtime: a.mtime.addingTimeInterval(60)),
            "mtime 变化必须视为不等"
        )
        XCTAssertNotEqual(
            a,
            ProjectFixtures.make(id: UUID(), name: a.name, path: a.path),
            "ID 不同必须视为不等"
        )
    }

    // MARK: - 向后兼容计算属性

    func testLastModifiedMirrorsMtime() {
        let mtime = Date(timeIntervalSince1970: 1_234_567_890)
        XCTAssertEqual(ProjectFixtures.make(mtime: mtime).lastModified, mtime)
    }

    func testGitInfoIsNilWithoutCommits() {
        XCTAssertNil(ProjectFixtures.make(gitCommits: 0).gitInfo)

        let date = Date(timeIntervalSince1970: 1_650_000_000)
        let gitInfo = ProjectFixtures.make(gitCommits: 12, gitLastCommit: date).gitInfo
        XCTAssertEqual(gitInfo?.commitCount, 12)
        XCTAssertEqual(gitInfo?.lastCommitDate, date)
    }

    func testFileSystemInfoMirrorsFields() {
        let checked = Date(timeIntervalSince1970: 1_700_000_000)
        let info = ProjectFixtures.make(size: 8192, checksum: "sha256:abc", checked: checked).fileSystemInfo
        XCTAssertEqual(info.size, 8192)
        XCTAssertEqual(info.checksum, "sha256:abc")
        XCTAssertEqual(info.lastCheckTime, checked)
        XCTAssertEqual(info.modificationDate, Date(timeIntervalSince1970: 1_700_000_000))
    }

    // MARK: - 模型转换

    func testToProjectDataPreservesFields() {
        let project = ProjectFixtures.make(
            name: "转换项目",
            tags: ["solo"],
            size: 1024,
            gitCommits: 3,
            gitDaily: "2025-08-25:2"
        )
        let data = project.toProjectData()

        XCTAssertEqual(data.id, project.id)
        XCTAssertEqual(data.name, project.name)
        XCTAssertEqual(data.path, project.path)
        XCTAssertEqual(data.tags, project.tags)
        XCTAssertEqual(data.size, project.size)
        XCTAssertEqual(data.git_commits, project.git_commits)
        XCTAssertEqual(data.git_daily, project.git_daily)
        XCTAssertEqual(data.lastModified, project.mtime)
    }

    func testToProjectDataArrayKeepsCount() {
        let projects = ProjectFixtures.makeMany(5)
        XCTAssertEqual(projects.toProjectDataArray().count, 5)
    }
}
