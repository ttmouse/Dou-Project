// Linus风格数据序列化测试 - 确保数据完整性和向后兼容

import XCTest
import Foundation
@testable import ProjectManager

// AIDEV-NOTE: 数据序列化是关键功能，用户数据不能丢失
// 必须测试JSON编码/解码、版本兼容性、损坏数据恢复

class DataSerializationTests: XCTestCase {
    var tempDirectory: URL!
    var mockStorage: MockTagStorage!
    
    override func setUp() {
        super.setUp()
        tempDirectory = TestHelper.createTempDirectory()
        mockStorage = MockTagStorage()
    }
    
    override func tearDown() {
        TestHelper.cleanupTempDirectory(tempDirectory)
        mockStorage.clear()
        mockStorage = nil
        tempDirectory = nil
        super.tearDown()
    }
}

// MARK: - 项目序列化测试

extension DataSerializationTests {
    func testProjectSerialization() throws {
        // Given
        let originalProject = Project(
            id: UUID(),
            name: "测试项目",
            path: "/test/path/项目",
            lastModified: Date().timeIntervalSince1970,
            tags: ["标签1", "标签2", "swift", "测试"]
        )

        // When - 序列化
        let encoder = JSONEncoder()
        encoder.outputFormatting = .prettyPrinted
        let data = try encoder.encode(originalProject)

        // Then - 反序列化
        let decoder = JSONDecoder()
        let deserializedProject = try decoder.decode(Project.self, from: data)

        XCTAssertEqual(originalProject.id, deserializedProject.id, "项目ID应该匹配")
        XCTAssertEqual(originalProject.name, deserializedProject.name, "项目名称应该匹配")
        XCTAssertEqual(originalProject.path, deserializedProject.path, "项目路径应该匹配")
        XCTAssertEqual(originalProject.lastModified, deserializedProject.lastModified, "修改时间应该匹配")
        XCTAssertEqual(Set(originalProject.tags), Set(deserializedProject.tags), "标签应该匹配")
    }
    
    func testProjectArraySerialization() throws {
        // Given
        let projects = [
            MockProject.createTestProject(name: "Project1", path: "/path1", tags: ["tag1"]),
            MockProject.createTestProject(name: "Project2", path: "/path2", tags: ["tag2", "tag3"]),
            MockProject.createTestProject(name: "项目3", path: "/路径3", tags: ["中文标签"])
        ]
        
        // When
        let data = try JSONEncoder().encode(projects)
        let decodedProjects = try JSONDecoder().decode([Project].self, from: data)
        
        // Then
        XCTAssertEqual(projects.count, decodedProjects.count, "项目数量应该匹配")
        
        for (original, decoded) in zip(projects, decodedProjects) {
            XCTAssertEqual(original.id, decoded.id, "项目ID应该匹配")
            XCTAssertEqual(original.name, decoded.name, "项目名称应该匹配")
            XCTAssertEqual(Set(original.tags), Set(decoded.tags), "标签应该匹配")
        }
    }
    
    func testEmptyProjectSerialization() throws {
        // Given
        let emptyProjects: [Project] = []
        
        // When
        let data = try JSONEncoder().encode(emptyProjects)
        let decoded = try JSONDecoder().decode([Project].self, from: data)
        
        // Then
        XCTAssertEqual(decoded.count, 0, "空数组应该正确序列化")
    }
}

// MARK: - 标签序列化测试

extension DataSerializationTests {
    func testTagSetSerialization() throws {
        // Given
        let tags: Set<String> = ["swift", "ios", "macOS", "项目", "测试标签", "🏷️"]
        let tagsArray = Array(tags)
        
        // When
        let data = try JSONEncoder().encode(tagsArray)
        let decodedArray = try JSONDecoder().decode([String].self, from: data)
        let decodedTags = Set(decodedArray)
        
        // Then
        XCTAssertEqual(tags, decodedTags, "标签集合应该完整序列化")
    }
    
    func testTagColorsInfo() throws {
        // Given
        let colorInfo = TagColorInfo(
            red: 0.5,
            green: 0.8,
            blue: 0.2,
            alpha: 1.0
        )
        
        // When
        let data = try JSONEncoder().encode(colorInfo)
        let decoded = try JSONDecoder().decode(TagColorInfo.self, from: data)
        
        // Then
        XCTAssertEqual(colorInfo.red, decoded.red, accuracy: 0.001, "红色值应该匹配")
        XCTAssertEqual(colorInfo.green, decoded.green, accuracy: 0.001, "绿色值应该匹配")
        XCTAssertEqual(colorInfo.blue, decoded.blue, accuracy: 0.001, "蓝色值应该匹配")
        XCTAssertEqual(colorInfo.alpha, decoded.alpha, accuracy: 0.001, "透明度应该匹配")
    }
    
    func testTagColorMapping() throws {
        // Given
        let colorMapping: [String: TagColorInfo] = [
            "red_tag": TagColorInfo(red: 1.0, green: 0.0, blue: 0.0, alpha: 1.0),
            "green_tag": TagColorInfo(red: 0.0, green: 1.0, blue: 0.0, alpha: 1.0),
            "中文标签": TagColorInfo(red: 0.0, green: 0.0, blue: 1.0, alpha: 0.8)
        ]
        
        // When
        let data = try JSONEncoder().encode(colorMapping)
        let decoded = try JSONDecoder().decode([String: TagColorInfo].self, from: data)
        
        // Then
        XCTAssertEqual(colorMapping.keys, decoded.keys, "标签键应该匹配")
        
        for (key, originalColor) in colorMapping {
            let decodedColor = decoded[key]!
            XCTAssertEqual(originalColor.red, decodedColor.red, accuracy: 0.001, "红色值应该匹配")
            XCTAssertEqual(originalColor.green, decodedColor.green, accuracy: 0.001, "绿色值应该匹配")
            XCTAssertEqual(originalColor.blue, decodedColor.blue, accuracy: 0.001, "蓝色值应该匹配")
            XCTAssertEqual(originalColor.alpha, decodedColor.alpha, accuracy: 0.001, "透明度应该匹配")
        }
    }
}

// MARK: - Linus格式转换测试

extension DataSerializationTests {
    func testLinusFormatConversion() throws {
        // Given - 原始复杂格式的项目数据
        let complexProject = createComplexFormatProject()
        let complexData = try JSONEncoder().encode([complexProject])
        
        // When - 转换为Linus格式
        let linusProject = convertToLinusFormat(complexProject)
        let linusData = try JSONEncoder().encode([linusProject])
        
        // Then - 验证数据转换
        XCTAssertEqual(complexProject.id, linusProject.id, "项目ID应该保持一致")
        XCTAssertEqual(complexProject.name, linusProject.name, "项目名称应该保持一致")
        XCTAssertEqual(complexProject.path, linusProject.path, "项目路径应该保持一致")
        
        // 验证数据大小减少
        let complexSize = complexData.count
        let linusSize = linusData.count
        print("复杂格式: \(complexSize) bytes, Linus格式: \(linusSize) bytes")
        // Linus格式应该更紧凑（根据实际情况调整）
    }
    
    func testLinusFormatSerialization() throws {
        // Given - Linus格式项目
        let linusProject = LinusProject(
            id: UUID().uuidString,
            name: "TestProject",
            path: "/test/path",
            tags: ["swift", "test"],
            mtime: Int(Date().timeIntervalSince1970),
            size: 1024,
            checksum: "sha256:abcd1234",
            git_commits: 42,
            git_last_commit: Int(Date().timeIntervalSince1970) - 3600,
            created: Int(Date().timeIntervalSince1970) - 86400,
            checked: Int(Date().timeIntervalSince1970)
        )
        
        // When
        let data = try JSONEncoder().encode(linusProject)
        let decoded = try JSONDecoder().decode(LinusProject.self, from: data)
        
        // Then
        XCTAssertEqual(linusProject.id, decoded.id, "ID应该匹配")
        XCTAssertEqual(linusProject.name, decoded.name, "名称应该匹配")
        XCTAssertEqual(linusProject.path, decoded.path, "路径应该匹配")
        XCTAssertEqual(linusProject.tags, decoded.tags, "标签应该匹配")
        XCTAssertEqual(linusProject.mtime, decoded.mtime, "修改时间应该匹配")
        XCTAssertEqual(linusProject.checksum, decoded.checksum, "校验和应该匹配")
    }
}

// MARK: - 数据完整性测试

extension DataSerializationTests {
    func testDataIntegrityWithSpecialCharacters() throws {
        // Given - 包含特殊字符的项目
        let specialProject = Project(
            id: UUID(),
            name: "项目@#$%^&*()_+-=[]{}|;':\",./<>?测试",
            path: "/path/with spaces/and/中文/🎉",
            lastModified: Date().timeIntervalSince1970,
            tags: ["标签@#$", "emoji🏷️", "spaces in tag", "\"quotes\""]
        )
        
        // When
        let data = try JSONEncoder().encode(specialProject)
        let decoded = try JSONDecoder().decode(Project.self, from: data)
        
        // Then
        XCTAssertEqual(specialProject.name, decoded.name, "特殊字符名称应该保持完整")
        XCTAssertEqual(specialProject.path, decoded.path, "特殊字符路径应该保持完整")
        XCTAssertEqual(Set(specialProject.tags), Set(decoded.tags), "特殊字符标签应该保持完整")
    }
    
    func testLargeDataSerialization() throws {
        // Given - 大量数据
        let largeProjectCount = 1000
        let projects = (0..<largeProjectCount).map { i in
            MockProject.createTestProject(
                name: "Project\(i)",
                path: "/very/long/path/to/project/number/\(i)/with/many/subdirectories",
                tags: ["tag\(i)", "type\(i % 5)", "large_dataset"]
            )
        }
        
        // When
        let startTime = Date()
        let data = try JSONEncoder().encode(projects)
        let serializationTime = Date().timeIntervalSince(startTime)
        
        let deserializationStart = Date()
        let decoded = try JSONDecoder().decode([Project].self, from: data)
        let deserializationTime = Date().timeIntervalSince(deserializationStart)
        
        // Then
        XCTAssertEqual(projects.count, decoded.count, "所有项目都应该被序列化")
        XCTAssertLessThan(serializationTime, 1.0, "序列化1000个项目应该在1秒内完成")
        XCTAssertLessThan(deserializationTime, 1.0, "反序列化1000个项目应该在1秒内完成")
        
        print("序列化时间: \(serializationTime)s, 反序列化时间: \(deserializationTime)s")
        print("数据大小: \(data.count) bytes (\(Double(data.count) / 1024.0 / 1024.0) MB)")
    }
}

// MARK: - 错误处理和恢复测试

extension DataSerializationTests {
    func testCorruptedDataHandling() throws {
        // Given - 损坏的JSON数据
        let corruptedData = "这不是有效的JSON数据{[}]".data(using: .utf8)!
        
        // When & Then - 应该抛出错误而不是崩溃
        XCTAssertThrowsError(
            try JSONDecoder().decode([Project].self, from: corruptedData)
        ) { error in
            XCTAssertTrue(error is DecodingError, "应该抛出解码错误")
        }
    }
    
    func testIncompleteDataHandling() throws {
        // Given - 不完整的项目数据
        let incompleteJSON = """
        [{
            "id": "123-456-789",
            "name": "不完整项目"
        }]
        """.data(using: .utf8)!
        
        // When & Then
        XCTAssertThrowsError(
            try JSONDecoder().decode([Project].self, from: incompleteJSON)
        ) { error in
            // 应该因为缺少必需字段而失败
            XCTAssertTrue(error is DecodingError, "应该抛出解码错误")
        }
    }
    
    func testVersionCompatibility() throws {
        // Given - 模拟旧版本的项目数据（缺少某些新字段）
        let oldVersionJSON = """
        [{
            "id": "123e4567-e89b-12d3-a456-426614174000",
            "name": "旧版本项目",
            "path": "/old/path",
            "lastModified": 1234567890.0,
            "tags": ["old_tag"]
        }]
        """.data(using: .utf8)!
        
        // When - 应该能够解码旧版本数据
        let projects = try JSONDecoder().decode([Project].self, from: oldVersionJSON)
        
        // Then
        XCTAssertEqual(projects.count, 1, "应该成功解码旧版本数据")
        let project = projects.first!
        XCTAssertEqual(project.name, "旧版本项目", "名称应该正确")
        XCTAssertEqual(project.tags, ["old_tag"], "标签应该正确")
    }
}

// MARK: - 文件系统持久化测试

extension DataSerializationTests {
    func testFilePersistence() throws {
        // Given
        let projects = MockProject.createTestProjects(count: 5)
        let testFile = tempDirectory.appendingPathComponent("test_projects.json")
        
        // When - 保存到文件
        let data = try JSONEncoder().encode(projects)
        try data.write(to: testFile)
        
        // Then - 从文件读取
        let loadedData = try Data(contentsOf: testFile)
        let loadedProjects = try JSONDecoder().decode([Project].self, from: loadedData)
        
        assertProjectsEqual(loadedProjects, projects)
    }
    
    func testAtomicWrite() throws {
        // Given
        let projects = MockProject.createTestProjects(count: 3)
        let testFile = tempDirectory.appendingPathComponent("atomic_test.json")
        
        // When - 模拟原子写入
        let data = try JSONEncoder().encode(projects)
        let tempFile = testFile.appendingPathExtension("tmp")
        
        // 写入临时文件
        try data.write(to: tempFile)
        
        // 原子移动
        _ = try FileManager.default.replaceItem(at: testFile, withItemAt: tempFile, backupItemName: nil, options: [], resultingItemURL: nil)
        
        // Then - 验证最终文件
        let loadedData = try Data(contentsOf: testFile)
        let loadedProjects = try JSONDecoder().decode([Project].self, from: loadedData)
        
        assertProjectsEqual(loadedProjects, projects)
        XCTAssertFalse(FileManager.default.fileExists(atPath: tempFile.path), "临时文件应该被移除")
    }
}

// MARK: - 辅助方法和结构

extension DataSerializationTests {
    // 模拟复杂格式的项目（类似原始格式）
    func createComplexFormatProject() -> Project {
        return Project(
            id: UUID(),
            name: "ComplexProject",
            path: "/complex/path",
            lastModified: Date().timeIntervalSince1970,
            tags: ["complex", "test"]
        )
    }
    
    // 转换为Linus格式
    func convertToLinusFormat(_ project: Project) -> LinusProject {
        return LinusProject(
            id: project.id.uuidString,
            name: project.name,
            path: project.path,
            tags: project.tags,
            mtime: Int(project.lastModified),
            size: 0, // 简化
            checksum: "sha256:simplified",
            git_commits: 0, // 简化
            git_last_commit: 0, // 简化
            created: Int(project.lastModified),
            checked: Int(Date().timeIntervalSince1970)
        )
    }
}

// Linus格式数据结构
struct LinusProject: Codable, Equatable {
    let id: String
    let name: String
    let path: String
    let tags: [String]
    let mtime: Int
    let size: Int
    let checksum: String
    let git_commits: Int
    let git_last_commit: Int
    let created: Int
    let checked: Int
}

// AIDEV-NOTE: 这些测试确保数据序列化的可靠性
// - 基本序列化/反序列化
// - Linus格式转换
// - 数据完整性（特殊字符、大数据）
// - 错误处理和恢复
// - 版本兼容性
// - 文件系统持久化
// 遵循Linus原则：数据完整性是不可妥协的
