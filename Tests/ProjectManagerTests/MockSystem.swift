// 测试基础设施：遵循「简单、直接、单一职责」

import Foundation
import XCTest
@testable import ProjectManager

// MARK: - Mock 文件系统

class MockFileSystem {
    private var files: [String: Data] = [:]
    private var directories: Set<String> = []

    func writeFile(_ data: Data, to path: String) {
        files[path] = data
    }

    func readFile(from path: String) -> Data? {
        return files[path]
    }

    func fileExists(at path: String) -> Bool {
        return files[path] != nil
    }

    func createDirectory(at path: String) {
        directories.insert(path)
    }

    func directoryExists(at path: String) -> Bool {
        return directories.contains(path)
    }

    func removeFile(at path: String) {
        files.removeValue(forKey: path)
    }

    func clear() {
        files.removeAll()
        directories.removeAll()
    }
}

// MARK: - 存储 Mock（已移除）
//
// 症状：原先的 `MockTagStorage: TagStorage` 无法编译 ——
//   - `TagStorage.appSupportURL` 是 `let`，无法 override；
//   - `TagStorage` 非 open，跨模块无法子类化。
// 结论：要在测试里隔离文件系统，必须先在生产侧提供注入点
//   （`init(appSupportURL:)`，或让 `AppStateStorage`/`TagStorage` 接受目录参数）。
// 在此之前不保留不可编译的假 mock，避免掩盖真实问题。

// MARK: - 项目测试数据

enum ProjectFixtures {

    /// 统一的 Project 构造入口（当前扁平模型，字段与 projects.json 一一对应）
    static func make(
        id: UUID = UUID(),
        name: String = "TestProject",
        path: String = "/test/path",
        tags: Set<String> = [],
        mtime: Date = Date(timeIntervalSince1970: 1_700_000_000),
        size: Int64 = 0,
        checksum: String = "sha256:test",
        gitCommits: Int = 0,
        gitLastCommit: Date = Date(timeIntervalSince1970: 1_700_000_000),
        gitDaily: String? = nil,
        startupCommand: String? = nil,
        customPort: Int? = nil,
        created: Date = Date(timeIntervalSince1970: 1_700_000_000),
        checked: Date = Date(timeIntervalSince1970: 1_700_000_000)
    ) -> Project {
        return Project(
            id: id,
            name: name,
            path: path,
            tags: tags,
            mtime: mtime,
            size: size,
            checksum: checksum,
            git_commits: gitCommits,
            git_last_commit: gitLastCommit,
            git_daily: gitDaily,
            startupCommand: startupCommand,
            customPort: customPort,
            created: created,
            checked: checked
        )
    }

    static func makeMany(_ count: Int) -> [Project] {
        return (0..<count).map { index in
            make(
                name: "Project\(index)",
                path: "/test/path/project\(index)",
                tags: index % 2 == 0 ? ["tag1"] : ["tag2"]
            )
        }
    }
}

// MARK: - 测试辅助工具

enum TestHelper {
    static func waitFor(
        _ condition: @escaping () -> Bool,
        timeout: TimeInterval = 1.0
    ) -> Bool {
        let start = Date()
        while Date().timeIntervalSince(start) < timeout {
            if condition() {
                return true
            }
            RunLoop.current.run(mode: .default, before: Date(timeIntervalSinceNow: 0.01))
        }
        return false
    }

    static func createTempDirectory() -> URL {
        let testDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("ProjectManagerTests-\(UUID().uuidString)")
        try! FileManager.default.createDirectory(at: testDir, withIntermediateDirectories: true)
        return testDir
    }

    static func cleanupTempDirectory(_ url: URL) {
        try? FileManager.default.removeItem(at: url)
    }
}

// MARK: - 断言扩展

extension XCTestCase {
    /// 断言两个项目数组相等（忽略顺序）
    func assertProjectsEqual(_ actual: [Project], _ expected: [Project], file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(Set(actual.map(\.id)), Set(expected.map(\.id)), "项目ID集合不匹配", file: file, line: line)
    }

    /// 断言标签集合相等
    func assertTagsEqual(_ actual: Set<String>, _ expected: Set<String>, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(actual, expected, "标签集合不匹配", file: file, line: line)
    }

    /// 断言异步条件
    func assertAsync(
        _ condition: @escaping () -> Bool,
        timeout: TimeInterval = 1.0,
        message: String = "异步条件失败",
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertTrue(TestHelper.waitFor(condition, timeout: timeout), message, file: file, line: line)
    }
}
