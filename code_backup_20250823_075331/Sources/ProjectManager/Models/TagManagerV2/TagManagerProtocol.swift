import Foundation
import SwiftUI

/// TagManagerProtocol - 定义TagManager的接口契约
/// 这个协议允许我们使用依赖注入而不是单例
protocol TagManagerProtocol: AnyObject, ObservableObject {
    // MARK: - 核心数据
    var allTags: Set<String> { get set }
    var projects: [UUID: Project] { get set }
    var watchedDirectories: Set<String> { get set }
    
    // MARK: - 标签操作
    func getColor(for tag: String) -> Color
    func setColor(_ color: Color, for tag: String)
    func getUsageCount(for tag: String) -> Int
    func invalidateTagUsageCache()
    
    // MARK: - 项目操作
    func registerProject(_ project: Project)
    func removeProject(_ id: UUID)
    func getSortedProjects() -> [Project]
    
    // MARK: - 排序
    func setSortCriteria(_ criteria: TagManager.SortCriteria, ascending: Bool)
    
    // MARK: - 数据保存
    func saveAll(force: Bool)
}

// MARK: - 让TagManagerCore遵守协议
extension TagManagerCore: TagManagerProtocol {
    // 协议要求的所有方法已经在TagManagerCore中实现
}