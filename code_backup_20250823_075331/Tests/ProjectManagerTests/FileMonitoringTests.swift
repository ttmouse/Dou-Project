// Linus风格文件系统监控测试 - 测试目录监视和项目自动发现

import XCTest
import Foundation
@testable import ProjectManager

// AIDEV-NOTE: 文件系统监控是应用的核心功能之一
// 必须测试目录监视、项目自动发现、增量更新等关键功能

class FileMonitoringTests: XCTestCase {
    var tempDirectory: URL!
    var mockStorage: MockTagStorage!
    var tagManager: SimpleTagManager!
    
    override func setUp() {
        super.setUp()
        tempDirectory = TestHelper.createTempDirectory()
        mockStorage = MockTagStorage()
        tagManager = SimpleTagManager(storage: mockStorage)
    }
    
    override func tearDown() {
        TestHelper.cleanupTempDirectory(tempDirectory)
        mockStorage.clear()
        tagManager = nil
        mockStorage = nil
        tempDirectory = nil
        super.tearDown()
    }
}

// MARK: - 目录监视基础功能测试

extension FileMonitoringTests {
    func testWatchDirectory() {
        // Given
        let watchPath = tempDirectory.path
        
        // When
        tagManager.watch(watchPath)
        
        // Then
        let watchingPaths = tagManager.watching()
        XCTAssertTrue(watchingPaths.contains(watchPath), "目录应该被添加到监视列表")
        XCTAssertEqual(watchingPaths.count, 1, "应该只有一个监视目录")
    }
    
    func testUnwatchDirectory() {
        // Given
        let watchPath = tempDirectory.path
        tagManager.watch(watchPath)
        
        // When
        tagManager.unwatch(watchPath)
        
        // Then
        let watchingPaths = tagManager.watching()
        XCTAssertFalse(watchingPaths.contains(watchPath), "目录应该从监视列表中移除")
        XCTAssertEqual(watchingPaths.count, 0, "监视列表应该为空")
    }
    
    func testWatchDuplicateDirectory() {
        // Given
        let watchPath = tempDirectory.path
        tagManager.watch(watchPath)
        
        // When
        tagManager.watch(watchPath) // 重复添加
        
        // Then
        let watchingPaths = tagManager.watching()
        XCTAssertEqual(watchingPaths.filter { $0 == watchPath }.count, 1, "重复目录不应该被添加")
    }
    
    func testWatchNonexistentDirectory() {
        // Given
        let nonexistentPath = "/nonexistent/path/that/does/not/exist"
        
        // When
        tagManager.watch(nonexistentPath)
        
        // Then - 应该能够添加，但不会找到项目
        let watchingPaths = tagManager.watching()
        XCTAssertTrue(watchingPaths.contains(nonexistentPath), "不存在的路径也应该能被监视")
    }
}

// MARK: - 项目自动发现测试

extension FileMonitoringTests {
    func testDiscoverGitProject() throws {
        // Given - 创建一个Git项目
        let gitProjectDir = tempDirectory.appendingPathComponent("TestGitProject")
        try FileManager.default.createDirectory(at: gitProjectDir, withIntermediateDirectories: true)
        
        let gitDir = gitProjectDir.appendingPathComponent(".git")
        try FileManager.default.createDirectory(at: gitDir, withIntermediateDirectories: true)
        
        // When
        tagManager.watch(tempDirectory.path)
        tagManager.refresh()
        
        // Then
        let projects = tagManager.all()
        let gitProject = projects.first { $0.name == "TestGitProject" }
        
        XCTAssertNotNil(gitProject, "应该发现Git项目")
        XCTAssertEqual(gitProject?.path, gitProjectDir.path, "项目路径应该正确")
    }
    
    func testDiscoverNodeProject() throws {
        // Given - 创建一个Node.js项目
        let nodeProjectDir = tempDirectory.appendingPathComponent("TestNodeProject")
        try FileManager.default.createDirectory(at: nodeProjectDir, withIntermediateDirectories: true)
        
        let packageJson = nodeProjectDir.appendingPathComponent("package.json")
        let packageContent = """
        {
            "name": "test-node-project",
            "version": "1.0.0"
        }
        """.data(using: .utf8)!
        try packageContent.write(to: packageJson)
        
        // When
        tagManager.watch(tempDirectory.path)
        tagManager.refresh()
        
        // Then
        let projects = tagManager.all()
        let nodeProject = projects.first { $0.name == "TestNodeProject" }
        
        XCTAssertNotNil(nodeProject, "应该发现Node.js项目")
        XCTAssertEqual(nodeProject?.path, nodeProjectDir.path, "项目路径应该正确")
    }
    
    func testDiscoverSwiftProject() throws {
        // Given - 创建一个Swift项目
        let swiftProjectDir = tempDirectory.appendingPathComponent("TestSwiftProject")
        try FileManager.default.createDirectory(at: swiftProjectDir, withIntermediateDirectories: true)
        
        let packageSwift = swiftProjectDir.appendingPathComponent("Package.swift")
        let packageContent = """
        // swift-tools-version:5.7
        import PackageDescription
        
        let package = Package(
            name: "TestSwiftProject"
        )
        """.data(using: .utf8)!
        try packageContent.write(to: packageSwift)
        
        // When
        tagManager.watch(tempDirectory.path)
        tagManager.refresh()
        
        // Then
        let projects = tagManager.all()
        let swiftProject = projects.first { $0.name == "TestSwiftProject" }
        
        XCTAssertNotNil(swiftProject, "应该发现Swift项目")
        XCTAssertEqual(swiftProject?.path, swiftProjectDir.path, "项目路径应该正确")
    }
    
    func testDiscoverMultipleProjectTypes() throws {
        // Given - 创建多种类型的项目
        try createTestProject(name: "GitProject", type: .git)
        try createTestProject(name: "NodeProject", type: .node)
        try createTestProject(name: "PythonProject", type: .python)
        try createTestProject(name: "RustProject", type: .rust)
        
        // When
        tagManager.watch(tempDirectory.path)
        tagManager.refresh()
        
        // Then
        let projects = tagManager.all()
        XCTAssertEqual(projects.count, 4, "应该发现4个不同类型的项目")
        
        let projectNames = Set(projects.map(\.name))
        XCTAssertTrue(projectNames.contains("GitProject"), "应该发现Git项目")
        XCTAssertTrue(projectNames.contains("NodeProject"), "应该发现Node项目")
        XCTAssertTrue(projectNames.contains("PythonProject"), "应该发现Python项目")
        XCTAssertTrue(projectNames.contains("RustProject"), "应该发现Rust项目")
    }
}

// MARK: - 增量更新测试

extension FileMonitoringTests {
    func testIncrementalProjectUpdate() throws {
        // Given - 初始状态有一个项目
        try createTestProject(name: "ExistingProject", type: .git)
        tagManager.watch(tempDirectory.path)
        tagManager.refresh()
        
        let initialProjects = tagManager.all()
        XCTAssertEqual(initialProjects.count, 1, "初始应该有1个项目")
        
        // When - 添加新项目
        try createTestProject(name: "NewProject", type: .node)
        tagManager.refresh()
        
        // Then - 应该检测到新项目
        let updatedProjects = tagManager.all()
        XCTAssertEqual(updatedProjects.count, 2, "应该检测到新增项目")
        
        let projectNames = Set(updatedProjects.map(\.name))
        XCTAssertTrue(projectNames.contains("ExistingProject"), "原有项目应该保留")
        XCTAssertTrue(projectNames.contains("NewProject"), "新项目应该被发现")
    }
    
    func testProjectDeletion() throws {
        // Given - 创建两个项目
        let project1Dir = try createTestProject(name: "Project1", type: .git)
        try createTestProject(name: "Project2", type: .node)
        
        tagManager.watch(tempDirectory.path)
        tagManager.refresh()
        XCTAssertEqual(tagManager.all().count, 2, "初始应该有2个项目")
        
        // When - 删除一个项目目录
        try FileManager.default.removeItem(at: project1Dir)
        tagManager.refresh()
        
        // Then - 应该检测到项目被删除
        let remainingProjects = tagManager.all()
        XCTAssertEqual(remainingProjects.count, 1, "应该只剩1个项目")
        XCTAssertEqual(remainingProjects.first?.name, "Project2", "Project2应该被保留")
    }
}

// MARK: - 监视目录持久化测试

extension FileMonitoringTests {
    func testWatchedDirectoriesPersistence() {
        // Given
        let paths = [
            tempDirectory.appendingPathComponent("dir1").path,
            tempDirectory.appendingPathComponent("dir2").path,
            tempDirectory.appendingPathComponent("dir3").path
        ]
        
        paths.forEach { tagManager.watch($0) }
        
        // When - 保存并重新加载
        tagManager.save()
        let newTagManager = SimpleTagManager(storage: mockStorage)
        
        // Then
        let loadedPaths = newTagManager.watching()
        XCTAssertEqual(Set(loadedPaths), Set(paths), "监视目录应该被持久化")
    }
    
    func testEmptyWatchedDirectoriesPersistence() {
        // Given - 没有监视目录
        
        // When
        tagManager.save()
        let newTagManager = SimpleTagManager(storage: mockStorage)
        
        // Then
        XCTAssertEqual(newTagManager.watching().count, 0, "空监视列表应该被正确加载")
    }
}

// MARK: - 性能测试

extension FileMonitoringTests {
    func testLargeDirectoryScanning() throws {
        // Given - 创建大量项目目录
        let projectCount = 100
        for i in 0..<projectCount {
            try createTestProject(name: "Project\(i)", type: .git)
        }
        
        // When
        let startTime = Date()
        tagManager.watch(tempDirectory.path)
        tagManager.refresh()
        let scanTime = Date().timeIntervalSince(startTime)
        
        // Then
        let projects = tagManager.all()
        XCTAssertEqual(projects.count, projectCount, "应该发现所有项目")
        XCTAssertLessThan(scanTime, 5.0, "扫描100个项目应该在5秒内完成")
    }
    
    func testDeepDirectoryStructure() throws {
        // Given - 创建深层目录结构
        var currentDir = tempDirectory!
        for i in 0..<10 {
            currentDir = currentDir.appendingPathComponent("level\(i)")
            try FileManager.default.createDirectory(at: currentDir, withIntermediateDirectories: true)
        }
        
        // 在最深层创建一个项目
        let deepProjectDir = currentDir.appendingPathComponent("DeepProject")
        try FileManager.default.createDirectory(at: deepProjectDir, withIntermediateDirectories: true)
        let gitDir = deepProjectDir.appendingPathComponent(".git")
        try FileManager.default.createDirectory(at: gitDir, withIntermediateDirectories: true)
        
        // When
        tagManager.watch(tempDirectory.path)
        tagManager.refresh()
        
        // Then
        let projects = tagManager.all()
        let deepProject = projects.first { $0.name == "DeepProject" }
        XCTAssertNotNil(deepProject, "应该能发现深层目录中的项目")
    }
}

// MARK: - 错误处理测试

extension FileMonitoringTests {
    func testPermissionDeniedDirectory() {
        // Given - 模拟权限被拒绝的目录
        let restrictedPath = "/System/Library/PrivateFrameworks"
        
        // When - 不应该崩溃
        tagManager.watch(restrictedPath)
        tagManager.refresh()
        
        // Then - 应该优雅地处理权限错误
        XCTAssertTrue(tagManager.watching().contains(restrictedPath), "路径应该被添加到监视列表")
        // 不应该发现任何项目，但也不应该崩溃
    }
    
    func testSymbolicLinkHandling() throws {
        // Given - 创建一个符号链接项目
        let realProjectDir = try createTestProject(name: "RealProject", type: .git)
        let linkPath = tempDirectory.appendingPathComponent("LinkProject")
        
        try FileManager.default.createSymbolicLink(at: linkPath, withDestinationURL: realProjectDir)
        
        // When
        tagManager.watch(tempDirectory.path)
        tagManager.refresh()
        
        // Then - 应该正确处理符号链接
        let projects = tagManager.all()
        // 根据实际需求决定是否应该发现符号链接项目
        // 这里假设应该发现真实项目，但不重复发现符号链接
        XCTAssertEqual(projects.filter { $0.name == "RealProject" }.count, 1, "真实项目应该被发现一次")
    }
}

// MARK: - 辅助方法

extension FileMonitoringTests {
    enum ProjectType {
        case git
        case node
        case python
        case rust
        case swift
        case go
    }
    
    @discardableResult
    func createTestProject(name: String, type: ProjectType) throws -> URL {
        let projectDir = tempDirectory.appendingPathComponent(name)
        try FileManager.default.createDirectory(at: projectDir, withIntermediateDirectories: true)
        
        switch type {
        case .git:
            let gitDir = projectDir.appendingPathComponent(".git")
            try FileManager.default.createDirectory(at: gitDir, withIntermediateDirectories: true)
            
        case .node:
            let packageJson = projectDir.appendingPathComponent("package.json")
            let content = """
            {
                "name": "\(name.lowercased())",
                "version": "1.0.0"
            }
            """.data(using: .utf8)!
            try content.write(to: packageJson)
            
        case .python:
            let requirementsTxt = projectDir.appendingPathComponent("requirements.txt")
            let content = "flask==2.0.0\nrequests==2.25.1\n".data(using: .utf8)!
            try content.write(to: requirementsTxt)
            
        case .rust:
            let cargoToml = projectDir.appendingPathComponent("Cargo.toml")
            let content = """
            [package]
            name = "\(name.lowercased())"
            version = "0.1.0"
            edition = "2021"
            """.data(using: .utf8)!
            try content.write(to: cargoToml)
            
        case .swift:
            let packageSwift = projectDir.appendingPathComponent("Package.swift")
            let content = """
            // swift-tools-version:5.7
            import PackageDescription
            
            let package = Package(name: "\(name)")
            """.data(using: .utf8)!
            try content.write(to: packageSwift)
            
        case .go:
            let goMod = projectDir.appendingPathComponent("go.mod")
            let content = """
            module \(name.lowercased())
            
            go 1.19
            """.data(using: .utf8)!
            try content.write(to: goMod)
        }
        
        return projectDir
    }
}

// AIDEV-NOTE: 这些测试覆盖了文件系统监控的关键功能
// - 目录监视的基础操作
// - 多种项目类型的自动发现
// - 增量更新和变化检测
// - 持久化功能
// - 性能考虑
// - 错误处理和边界情况
// 遵循Linus原则：全面测试确保可靠性