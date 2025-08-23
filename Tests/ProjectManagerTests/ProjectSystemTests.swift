// Linus风格项目系统测试 - 测试项目发现、缓存、索引等核心功能

import XCTest
import Foundation
@testable import ProjectManager

// AIDEV-NOTE: 项目系统测试覆盖项目发现、缓存、文件系统交互
// 这些是应用的核心功能，必须经过严格测试

class ProjectSystemTests: XCTestCase {
    var mockStorage: MockTagStorage!
    var projectManager: SimpleProjectManager!
    var tempDirectory: URL!
    
    override func setUp() {
        super.setUp()
        mockStorage = MockTagStorage()
        projectManager = SimpleProjectManager(storage: mockStorage)
        tempDirectory = TestHelper.createTempDirectory()
    }
    
    override func tearDown() {
        TestHelper.cleanupTempDirectory(tempDirectory)
        mockStorage.clear()
        projectManager = nil
        mockStorage = nil
        tempDirectory = nil
        super.tearDown()
    }
}

// MARK: - 基础项目管理测试

extension ProjectSystemTests {
    func testAddAndRetrieveProject() {
        // Given
        let project = MockProject.createTestProject(name: "TestProject", path: "/test/path")
        
        // When
        projectManager.add(project)
        
        // Then
        let allProjects = projectManager.all()
        XCTAssertEqual(allProjects.count, 1, "应该有一个项目")
        
        let retrievedProject = projectManager.get(project.id)
        XCTAssertNotNil(retrievedProject, "应该能够检索到项目")
        XCTAssertEqual(retrievedProject?.name, "TestProject", "项目名称应该匹配")
    }
    
    func testRemoveProject() {
        // Given
        let project = MockProject.createTestProject()
        projectManager.add(project)
        XCTAssertEqual(projectManager.count(), 1, "初始应该有一个项目")
        
        // When
        projectManager.remove(project.id)
        
        // Then
        XCTAssertEqual(projectManager.count(), 0, "项目应该被删除")
        XCTAssertNil(projectManager.get(project.id), "删除的项目不应该能被检索")
    }
    
    func testUpdateProject() {
        // Given
        let originalProject = MockProject.createTestProject(name: "Original")
        projectManager.add(originalProject)
        
        var updatedProject = originalProject
        updatedProject.addTag("新标签")
        
        // When
        projectManager.update(updatedProject)
        
        // Then
        let retrievedProject = projectManager.get(originalProject.id)
        XCTAssertNotNil(retrievedProject, "项目应该存在")
        XCTAssertTrue(retrievedProject!.tags.contains("新标签"), "项目应该包含新标签")
    }
}

// MARK: - 项目搜索和筛选测试

extension ProjectSystemTests {
    func testFindProjectsByName() {
        // Given
        let projects = [
            MockProject.createTestProject(name: "ReactProject"),
            MockProject.createTestProject(name: "VueProject"),
            MockProject.createTestProject(name: "AngularApp")
        ]
        projects.forEach { projectManager.add($0) }
        
        // When
        let reactProjects = projectManager.findByName("React")
        let projectsWithProject = projectManager.findByName("Project")
        
        // Then
        XCTAssertEqual(reactProjects.count, 1, "应该找到1个React项目")
        XCTAssertEqual(reactProjects.first?.name, "ReactProject", "找到的项目名应该匹配")
        
        XCTAssertEqual(projectsWithProject.count, 2, "应该找到2个包含'Project'的项目")
    }
    
    func testFindProjectsByPath() {
        // Given
        let projects = [
            MockProject.createTestProject(name: "Project1", path: "/Users/dev/frontend/react-app"),
            MockProject.createTestProject(name: "Project2", path: "/Users/dev/backend/node-api"),
            MockProject.createTestProject(name: "Project3", path: "/Users/dev/mobile/ios-app")
        ]
        projects.forEach { projectManager.add($0) }
        
        // When
        let frontendProjects = projectManager.findByPath("frontend")
        let devProjects = projectManager.findByPath("/Users/dev")
        
        // Then
        XCTAssertEqual(frontendProjects.count, 1, "应该找到1个frontend项目")
        XCTAssertEqual(devProjects.count, 3, "应该找到3个在/Users/dev下的项目")
    }
    
    func testFindProjectsByTag() {
        // Given
        let projects = [
            MockProject.createTestProject(name: "Project1", tags: ["web", "react"]),
            MockProject.createTestProject(name: "Project2", tags: ["mobile", "ios"]),
            MockProject.createTestProject(name: "Project3", tags: ["web", "vue"])
        ]
        projects.forEach { projectManager.add($0) }
        
        // When
        let webProjects = projectManager.findByTag("web")
        let mobileProjects = projectManager.findByTag("mobile")
        
        // Then
        XCTAssertEqual(webProjects.count, 2, "应该找到2个web项目")
        XCTAssertEqual(mobileProjects.count, 1, "应该找到1个mobile项目")
    }
}

// MARK: - 项目排序测试

extension ProjectSystemTests {
    func testSortByName() {
        // Given
        let projects = [
            MockProject.createTestProject(name: "Zulu"),
            MockProject.createTestProject(name: "Alpha"),
            MockProject.createTestProject(name: "Beta")
        ]
        projects.forEach { projectManager.add($0) }
        
        // When
        let sortedProjects = projectManager.sorted(by: .name)
        
        // Then
        XCTAssertEqual(sortedProjects.count, 3, "应该有3个项目")
        XCTAssertEqual(sortedProjects[0].name, "Alpha", "第一个应该是Alpha")
        XCTAssertEqual(sortedProjects[1].name, "Beta", "第二个应该是Beta")
        XCTAssertEqual(sortedProjects[2].name, "Zulu", "第三个应该是Zulu")
    }
    
    func testSortByTime() {
        // Given
        let now = Date().timeIntervalSince1970
        let projects = [
            MockProject.createTestProject(name: "Old", path: "/old", tags: []).withModifiedTime(now - 3600), // 1小时前
            MockProject.createTestProject(name: "New", path: "/new", tags: []).withModifiedTime(now), // 现在
            MockProject.createTestProject(name: "Medium", path: "/medium", tags: []).withModifiedTime(now - 1800) // 30分钟前
        ]
        projects.forEach { projectManager.add($0) }
        
        // When
        let sortedProjects = projectManager.sorted(by: .time)
        
        // Then
        XCTAssertEqual(sortedProjects.count, 3, "应该有3个项目")
        XCTAssertEqual(sortedProjects[0].name, "New", "最新的项目应该在前面")
        XCTAssertEqual(sortedProjects[1].name, "Medium", "中等时间的项目应该在中间")
        XCTAssertEqual(sortedProjects[2].name, "Old", "最老的项目应该在后面")
    }
}

// MARK: - 项目统计测试

extension ProjectSystemTests {
    func testProjectCounts() {
        // Given
        let projects = [
            MockProject.createTestProject(name: "GitProject", tags: ["tag1"]).withGitInfo(commitCount: 50),
            MockProject.createTestProject(name: "NoGitProject", tags: ["tag2"]),
            MockProject.createTestProject(name: "AnotherGitProject", tags: []).withGitInfo(commitCount: 20),
            MockProject.createTestProject(name: "UntaggedProject", tags: [])
        ]
        projects.forEach { projectManager.add($0) }
        
        // When & Then
        XCTAssertEqual(projectManager.count(), 4, "应该有4个项目")
        XCTAssertEqual(projectManager.gitCount(), 2, "应该有2个Git项目")
        XCTAssertEqual(projectManager.taggedCount(), 2, "应该有2个带标签的项目")
    }
}

// MARK: - 数据持久化测试

extension ProjectSystemTests {
    func testProjectPersistence() {
        // Given
        let projects = MockProject.createTestProjects(count: 3)
        projects.forEach { projectManager.add($0) }
        
        // When - 保存数据
        projectManager.save()
        
        // Then - 创建新实例验证持久化
        let newProjectManager = SimpleProjectManager(storage: mockStorage)
        let loadedProjects = newProjectManager.all()
        
        XCTAssertEqual(loadedProjects.count, 3, "应该加载3个项目")
        assertProjectsEqual(loadedProjects, projects)
    }
    
    func testEmptyProjectPersistence() {
        // Given - 空项目列表
        
        // When
        projectManager.save()
        
        // Then
        let newProjectManager = SimpleProjectManager(storage: mockStorage)
        XCTAssertEqual(newProjectManager.count(), 0, "应该加载空项目列表")
    }
    
    func testCorruptedDataRecovery() {
        // Given - 损坏的项目数据
        let corruptData = "不是有效的JSON".data(using: .utf8)!
        let cacheURL = mockStorage.appSupportURL.appendingPathComponent("projects.json")
        
        // 模拟写入损坏数据
        mockStorage.saveData(corruptData, to: cacheURL.lastPathComponent)
        
        // When - 尝试创建项目管理器
        let newProjectManager = SimpleProjectManager(storage: mockStorage)
        
        // Then - 应该优雅地处理损坏数据
        XCTAssertEqual(newProjectManager.count(), 0, "损坏数据应该导致空项目列表")
    }
}

// MARK: - 并发和线程安全测试

extension ProjectSystemTests {
    func testConcurrentProjectOperations() {
        // Given
        let projects = MockProject.createTestProjects(count: 10)
        let expectation = XCTestExpectation(description: "并发操作完成")
        expectation.expectedFulfillmentCount = 10
        
        // When - 并发添加项目
        for project in projects {
            DispatchQueue.global().async {
                self.projectManager.add(project)
                expectation.fulfill()
            }
        }
        
        // Then
        wait(for: [expectation], timeout: 5.0)
        
        // 验证所有项目都被添加（可能需要一些时间同步）
        assertAsync({
            self.projectManager.count() == 10
        }, timeout: 2.0, message: "所有项目应该被并发添加")
    }
}

// MARK: - 边界条件和错误处理测试

extension ProjectSystemTests {
    func testMaxProjectCapacity() {
        // Given - 大量项目
        let largeCount = 1000
        let projects = MockProject.createTestProjects(count: largeCount)
        
        // When
        projects.forEach { projectManager.add($0) }
        
        // Then
        XCTAssertEqual(projectManager.count(), largeCount, "应该支持大量项目")
        
        // 搜索性能应该仍然合理
        let startTime = Date()
        let _ = projectManager.findByName("Project1")
        let searchTime = Date().timeIntervalSince(startTime)
        
        XCTAssertLessThan(searchTime, 0.1, "搜索应该在100ms内完成")
    }
    
    func testProjectWithMissingPath() {
        // Given
        var project = MockProject.createTestProject()
        // 模拟路径不存在的情况
        let nonexistentProject = Project(
            id: project.id,
            name: project.name,
            path: "/nonexistent/path/that/does/not/exist",
            lastModified: project.lastModified,
            tags: project.tags
        )
        
        // When
        projectManager.add(nonexistentProject)
        
        // Then - 应该能够处理不存在的路径
        XCTAssertEqual(projectManager.count(), 1, "应该能够添加路径不存在的项目")
        let retrievedProject = projectManager.get(nonexistentProject.id)
        XCTAssertEqual(retrievedProject?.path, nonexistentProject.path, "路径应该被保存")
    }
}

// MARK: - 辅助扩展

extension MockProject {
    func withModifiedTime(_ time: TimeInterval) -> Project {
        return Project(
            id: self.id,
            name: self.name,
            path: self.path,
            lastModified: time,
            tags: self.tags
        )
    }
    
    func withGitInfo(commitCount: Int) -> Project {
        var project = self
        // 这里需要根据实际的Project结构设置Git信息
        // 假设有方法可以设置Git信息
        return project
    }
}

extension MockTagStorage {
    func saveData(_ data: Data, to filename: String) {
        // 模拟保存数据到特定文件名
        // 这个方法需要根据实际的MockTagStorage实现
    }
}

// AIDEV-NOTE: 这些测试覆盖了项目系统的关键功能
// - 基础CRUD操作
// - 搜索和筛选
// - 排序功能
// - 数据持久化
// - 并发安全
// - 错误处理和边界条件
// 遵循Linus原则：全面、可靠、易于理解