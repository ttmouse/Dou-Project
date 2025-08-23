// Linus风格简单接口协议
// 原则：每个协议≤5方法，每个方法≤3参数，名称简单到5岁小孩都懂

import Foundation
import SwiftUI

// AIDEV-NOTE: 这些协议遵循Linus Torvalds的接口设计原则
// - 最多5个方法
// - 每个方法最多3个参数  
// - 方法名简单到5岁小孩都能理解
// - 无需文档就知道做什么

// MARK: - 标签简单操作

protocol TagOps {
    /// 添加标签
    func add(_ tag: String)
    
    /// 删除标签
    func remove(_ tag: String)
    
    /// 获取所有标签
    func all() -> [String]
    
    /// 获取标签颜色
    func color(_ tag: String) -> Color
    
    /// 设置标签颜色
    func setColor(_ tag: String, _ color: Color)
}

// MARK: - 项目简单操作

protocol ProjectOps {
    /// 添加项目
    func add(_ project: Project)
    
    /// 删除项目
    func remove(_ id: UUID)
    
    /// 获取所有项目
    func all() -> [Project]
    
    /// 查找项目
    func find(_ text: String) -> [Project]
    
    /// 给项目打标签
    func tag(_ projectId: UUID, _ tag: String)
}

// MARK: - 数据保存简单操作

protocol DataOps {
    /// 加载数据
    func load()
    
    /// 保存数据
    func save()
    
    /// 清理数据
    func clean()
}

// MARK: - 目录监视简单操作

protocol WatchOps {
    /// 监视目录
    func watch(_ path: String)
    
    /// 停止监视
    func unwatch(_ path: String)
    
    /// 获取监视的目录
    func watching() -> [String]
    
    /// 刷新项目
    func refresh()
}

// MARK: - Linus风格的TagManager简化接口

protocol LinusTagManager: TagOps, ProjectOps, DataOps {
    // 继承所有基础操作，无额外方法
    // 总共13个方法，需要进一步分解为更小的协议
}

// MARK: - 更激进的简化 - 每个协议最多3个方法

protocol Tags {
    func add(_ name: String)
    func remove(_ name: String)  
    func all() -> [String]
}

protocol TagColors {
    func get(_ tag: String) -> Color
    func set(_ tag: String, _ color: Color)
}

protocol Projects {
    func add(_ project: Project)
    func remove(_ id: UUID)
    func all() -> [Project]
}

protocol ProjectTags {
    func tag(_ projectId: UUID, _ tag: String)
    func untag(_ projectId: UUID, _ tag: String)
}

protocol DataStorage {
    func load()
    func save()
}

// AIDEV-NOTE: 这种极简设计让接口职责单一，易于理解和测试
// 符合Linus "boring is beautiful" 的设计理念