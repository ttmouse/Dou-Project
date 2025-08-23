// Linus风格标签系统测试 - 简单、直接、全覆盖

import XCTest
import SwiftUI
@testable import ProjectManager

// AIDEV-NOTE: 标签系统是应用的核心，必须有100%的测试覆盖
// 这些测试验证标签的添加、删除、持久化、同步等所有功能

class TagSystemTests: XCTestCase {
    var mockStorage: MockTagStorage!
    var tagManager: SimpleTagManager!
    
    override func setUp() {
        super.setUp()
        mockStorage = MockTagStorage()
        tagManager = SimpleTagManager(storage: mockStorage)
    }
    
    override func tearDown() {
        mockStorage.clear()
        tagManager = nil
        mockStorage = nil
        super.tearDown()
    }
}

// MARK: - Tags协议基础功能测试

extension TagSystemTests {
    func testAddTag() {
        // Given
        let tagName = "新标签"
        
        // When
        tagManager.add(tagName)
        
        // Then
        let allTags = tagManager.all()
        XCTAssertTrue(allTags.contains(tagName), "标签应该被添加到列表中")
        XCTAssertEqual(allTags.count, 1, "应该只有一个标签")
    }
    
    func testAddDuplicateTag() {
        // Given
        let tagName = "重复标签"
        tagManager.add(tagName)
        let initialCount = tagManager.all().count
        
        // When
        tagManager.add(tagName) // 重复添加
        
        // Then
        let allTags = tagManager.all()
        XCTAssertEqual(allTags.count, initialCount, "重复标签不应该被添加")
        XCTAssertTrue(allTags.contains(tagName), "原标签应该还在")
    }
    
    func testRemoveTag() {
        // Given
        let tagName = "待删除标签"
        tagManager.add(tagName)
        XCTAssertTrue(tagManager.all().contains(tagName), "标签应该存在")
        
        // When
        tagManager.remove(tagName)
        
        // Then
        let allTags = tagManager.all()
        XCTAssertFalse(allTags.contains(tagName), "标签应该被删除")
    }
    
    func testRemoveNonexistentTag() {
        // Given
        let existingTag = "存在的标签"
        let nonexistentTag = "不存在的标签"
        tagManager.add(existingTag)
        
        // When
        tagManager.remove(nonexistentTag)
        
        // Then
        let allTags = tagManager.all()
        XCTAssertTrue(allTags.contains(existingTag), "存在的标签不应该被影响")
        XCTAssertEqual(allTags.count, 1, "标签数量不应该变化")
    }
    
    func testAllTags() {
        // Given
        let tags = ["标签1", "标签2", "标签3"]
        tags.forEach { tagManager.add($0) }
        
        // When
        let allTags = tagManager.all()
        
        // Then
        XCTAssertEqual(Set(allTags), Set(tags), "所有标签都应该被返回")
        XCTAssertEqual(allTags.count, 3, "应该返回3个标签")
    }
}

// MARK: - TagColors协议功能测试

extension TagSystemTests {
    func testGetDefaultColor() {
        // Given
        let tagName = "颜色测试标签"
        
        // When
        let color = tagManager.get(tagName)
        
        // Then
        XCTAssertNotNil(color, "应该返回默认颜色")
        // 颜色应该是基于标签名哈希的确定性颜色
        let color2 = tagManager.get(tagName)
        XCTAssertEqual(color, color2, "同一标签的颜色应该一致")
    }
    
    func testSetAndGetColor() {
        // Given
        let tagName = "自定义颜色标签"
        let customColor = Color.red
        
        // When
        tagManager.set(tagName, customColor)
        let retrievedColor = tagManager.get(tagName)
        
        // Then
        XCTAssertEqual(retrievedColor, customColor, "应该返回设置的自定义颜色")
    }
    
    func testColorPersistence() {
        // Given
        let tagName = "持久化颜色标签"
        let customColor = Color.blue
        tagManager.set(tagName, customColor)
        
        // When - 创建新的manager实例模拟重启
        let newTagManager = SimpleTagManager(storage: mockStorage)
        let retrievedColor = newTagManager.get(tagName)
        
        // Then
        XCTAssertEqual(retrievedColor, customColor, "颜色应该持久化")
    }
}

// MARK: - Projects协议功能测试

extension TagSystemTests {
    func testAddProject() {
        // Given
        let project = MockProject.createTestProject()
        
        // When
        tagManager.add(project)
        
        // Then
        let allProjects = tagManager.all()
        XCTAssertEqual(allProjects.count, 1, "应该有一个项目")
        XCTAssertEqual(allProjects.first?.id, project.id, "项目ID应该匹配")
    }
    
    func testRemoveProject() {
        // Given
        let project = MockProject.createTestProject()
        tagManager.add(project)
        
        // When
        tagManager.remove(project.id)
        
        // Then
        let allProjects = tagManager.all()
        XCTAssertEqual(allProjects.count, 0, "项目应该被删除")
    }
    
    func testAddDuplicateProject() {
        // Given
        let project = MockProject.createTestProject()
        tagManager.add(project)
        
        // When
        tagManager.add(project) // 重复添加同一项目
        
        // Then
        let allProjects = tagManager.all()
        XCTAssertEqual(allProjects.count, 1, "重复项目不应该被添加")
    }
}

// MARK: - ProjectTags协议功能测试

extension TagSystemTests {
    func testTagProject() {
        // Given
        let project = MockProject.createTestProject()
        let tagName = "项目标签"
        tagManager.add(project)
        
        // When
        tagManager.tag(project.id, tagName)
        
        // Then
        let allProjects = tagManager.all()
        let taggedProject = allProjects.first { $0.id == project.id }
        XCTAssertNotNil(taggedProject, "项目应该存在")
        XCTAssertTrue(taggedProject!.tags.contains(tagName), "项目应该包含标签")
        
        // 标签也应该被添加到全局标签列表
        let allTags = tagManager.all()
        XCTAssertTrue(allTags.contains(tagName), "标签应该被添加到全局列表")
    }
    
    func testUntagProject() {
        // Given
        let project = MockProject.createTestProject(tags: ["现有标签"])
        tagManager.add(project)
        
        // When
        tagManager.untag(project.id, "现有标签")
        
        // Then
        let allProjects = tagManager.all()
        let untaggedProject = allProjects.first { $0.id == project.id }
        XCTAssertNotNil(untaggedProject, "项目应该存在")
        XCTAssertFalse(untaggedProject!.tags.contains("现有标签"), "标签应该被移除")
    }
    
    func testTagNonexistentProject() {
        // Given
        let nonexistentId = UUID()
        
        // When
        tagManager.tag(nonexistentId, "测试标签")
        
        // Then
        // 不应该崩溃，优雅处理
        XCTAssertEqual(tagManager.all().count, 0, "不应该创建项目")
    }
}

// MARK: - Data协议功能测试

extension TagSystemTests {
    func testDataPersistence() {
        // Given
        let tags = ["标签1", "标签2"]
        let projects = MockProject.createTestProjects(count: 2)
        
        tags.forEach { tagManager.add($0) }
        projects.forEach { tagManager.add($0) }
        
        // When - 保存数据
        tagManager.save()
        
        // Then - 创建新实例验证数据持久化
        let newTagManager = SimpleTagManager(storage: mockStorage)
        
        assertTagsEqual(Set(newTagManager.all()), Set(tags))
        XCTAssertEqual(newTagManager.all().count, projects.count, "项目应该被持久化")
    }
    
    func testLoadEmptyData() {
        // Given - 空的存储
        let emptyStorage = MockTagStorage()
        
        // When
        let emptyTagManager = SimpleTagManager(storage: emptyStorage)
        
        // Then
        XCTAssertEqual(emptyTagManager.all().count, 0, "应该加载空标签列表")
        XCTAssertEqual(emptyTagManager.all().count, 0, "应该加载空项目列表")
    }
}

// MARK: - 便利方法测试

extension TagSystemTests {
    func testFindProjects() {
        // Given
        let projects = [
            MockProject.createTestProject(name: "ProjectA", path: "/path/a"),
            MockProject.createTestProject(name: "ProjectB", path: "/path/b"),
            MockProject.createTestProject(name: "TestProject", path: "/other/path")
        ]
        projects.forEach { tagManager.add($0) }
        
        // When
        let foundProjects = tagManager.find("Project")
        
        // Then
        XCTAssertEqual(foundProjects.count, 3, "应该找到3个包含'Project'的项目")
        
        // When - 更具体的搜索
        let foundA = tagManager.find("ProjectA")
        
        // Then
        XCTAssertEqual(foundA.count, 1, "应该找到1个ProjectA")
        XCTAssertEqual(foundA.first?.name, "ProjectA", "找到的项目名应该匹配")
    }
    
    func testProjectsWithTag() {
        // Given
        let tag = "特定标签"
        let taggedProject = MockProject.createTestProject(name: "Tagged", tags: [tag])
        let untaggedProject = MockProject.createTestProject(name: "Untagged")
        
        tagManager.add(taggedProject)
        tagManager.add(untaggedProject)
        
        // When
        let projectsWithTag = tagManager.projects(with: tag)
        
        // Then
        XCTAssertEqual(projectsWithTag.count, 1, "应该找到1个有特定标签的项目")
        XCTAssertEqual(projectsWithTag.first?.name, "Tagged", "找到的应该是Tagged项目")
    }
    
    func testUntaggedProjects() {
        // Given
        let taggedProject = MockProject.createTestProject(name: "Tagged", tags: ["标签"])
        let untaggedProject = MockProject.createTestProject(name: "Untagged")
        
        tagManager.add(taggedProject)
        tagManager.add(untaggedProject)
        
        // When
        let untaggedProjects = tagManager.untaggedProjects()
        
        // Then
        XCTAssertEqual(untaggedProjects.count, 1, "应该找到1个无标签项目")
        XCTAssertEqual(untaggedProjects.first?.name, "Untagged", "找到的应该是Untagged项目")
    }
}

// MARK: - 边界条件和错误处理测试

extension TagSystemTests {
    func testEmptyTagName() {
        // Given
        let emptyTag = ""
        
        // When
        tagManager.add(emptyTag)
        
        // Then
        let allTags = tagManager.all()
        // 根据实际需求决定是否允许空标签名
        // 这里假设不允许空标签
        XCTAssertFalse(allTags.contains(emptyTag), "空标签名不应该被添加")
    }
    
    func testVeryLongTagName() {
        // Given
        let longTag = String(repeating: "很长的标签", count: 100)
        
        // When
        tagManager.add(longTag)
        
        // Then
        let allTags = tagManager.all()
        XCTAssertTrue(allTags.contains(longTag), "长标签名应该被支持")
    }
    
    func testSpecialCharactersInTagName() {
        // Given
        let specialTag = "标签@#$%^&*()_+-=[]{}|;:,.<>?"
        
        // When
        tagManager.add(specialTag)
        
        // Then
        let allTags = tagManager.all()
        XCTAssertTrue(allTags.contains(specialTag), "特殊字符标签应该被支持")
    }
}

// AIDEV-NOTE: 这些测试覆盖了标签系统的所有核心功能
// 包括基础操作、持久化、边界条件、错误处理
// 遵循Linus原则：测试要全面、清晰、可靠
// 每个测试都有明确的Given-When-Then结构