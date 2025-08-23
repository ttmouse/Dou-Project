// Linus风格Mock系统 - 简单直接，不装逼

import Foundation
import XCTest
@testable import ProjectManager

// AIDEV-NOTE: 这是测试基础设施的核心Mock系统
// 遵循Linus原则：简单、直接、易于理解
// 每个Mock类都专注单一职责

// MARK: - Mock文件系统

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

// MARK: - Mock存储

class MockTagStorage: TagStorage {
    private let mockFileSystem = MockFileSystem()
    private var mockTags: Set<String> = []
    private var mockTagColors: [String: TagColorInfo] = [:]
    
    override var appSupportURL: URL {
        return URL(fileURLWithPath: "/mock/app/support")
    }
    
    override func saveTags(_ tags: Set<String>) {
        mockTags = tags
        let data = try! JSONEncoder().encode(Array(tags))
        mockFileSystem.writeFile(data, to: "tags.json")
    }
    
    override func loadTags() -> Set<String> {
        guard let data = mockFileSystem.readFile(from: "tags.json") else {
            return mockTags
        }
        let tags = try! JSONDecoder().decode([String].self, from: data)
        return Set(tags)
    }
    
    override func saveTagColors(_ colors: [String: TagColorInfo]) {
        mockTagColors = colors
        let data = try! JSONEncoder().encode(colors)
        mockFileSystem.writeFile(data, to: "tag_colors.json")
    }
    
    override func loadTagColors() -> [String: TagColorInfo] {
        guard let data = mockFileSystem.readFile(from: "tag_colors.json") else {
            return mockTagColors
        }
        return try! JSONDecoder().decode([String: TagColorInfo].self, from: data)
    }
    
    func setMockTags(_ tags: Set<String>) {
        mockTags = tags
    }
    
    func getMockTags() -> Set<String> {
        return mockTags
    }
    
    func clear() {
        mockTags.removeAll()
        mockTagColors.removeAll()
        mockFileSystem.clear()
    }
}

// MARK: - Mock项目数据

class MockProject {
    static func createTestProject(
        name: String = "TestProject",
        path: String = "/test/path",
        tags: Set<String> = []
    ) -> Project {
        return Project(
            id: UUID(),
            name: name,
            path: path,
            lastModified: Date().timeIntervalSince1970,
            tags: tags
        )
    }
    
    static func createTestProjects(count: Int) -> [Project] {
        return (0..<count).map { i in
            createTestProject(
                name: "Project\(i)",
                path: "/test/path/project\(i)",
                tags: i % 2 == 0 ? ["tag1"] : ["tag2"]
            )
        }
    }
}

// MARK: - 测试辅助工具

class TestHelper {
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
        let tempDir = FileManager.default.temporaryDirectory
        let testDir = tempDir.appendingPathComponent("ProjectManagerTests-\(UUID().uuidString)")
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
    func assertProjectsEqual(_ actual: [Project], _ expected: [Project], file: StaticString = #file, line: UInt = #line) {
        let actualIds = Set(actual.map(\.id))
        let expectedIds = Set(expected.map(\.id))
        XCTAssertEqual(actualIds, expectedIds, "项目ID集合不匹配", file: file, line: line)
    }
    
    /// 断言标签集合相等
    func assertTagsEqual(_ actual: Set<String>, _ expected: Set<String>, file: StaticString = #file, line: UInt = #line) {
        XCTAssertEqual(actual, expected, "标签集合不匹配", file: file, line: line)
    }
    
    /// 断言异步条件
    func assertAsync(
        _ condition: @escaping () -> Bool,
        timeout: TimeInterval = 1.0,
        message: String = "异步条件失败",
        file: StaticString = #file,
        line: UInt = #line
    ) {
        let success = TestHelper.waitFor(condition, timeout: timeout)
        XCTAssertTrue(success, message, file: file, line: line)
    }
}

// AIDEV-NOTE: Mock系统设计原则
// 1. 简单：每个Mock类只模拟必需的功能
// 2. 独立：Mock对象之间没有依赖关系
// 3. 可控：测试可以完全控制Mock的行为
// 4. 清理：提供clear方法重置状态
// 5. 辅助：提供便利方法简化测试编写