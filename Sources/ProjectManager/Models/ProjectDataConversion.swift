import Foundation
import SwiftUI

// MARK: - Project <-> ProjectData 转换扩展
// Linus式设计：简单的数据转换，无副作用，便于BusinessLogic处理

extension Project {
    /// 转换为纯数据模型，用于BusinessLogic处理（扁平结构）
    func toProjectData() -> ProjectData {
        return ProjectData(from: self)
    }
    
    /// 从纯数据模型创建Project实例（扁平结构）
    static func fromProjectData(_ data: ProjectData) -> Project {
        return Project(
            id: data.id,
            name: data.name,
            path: data.path,
            tags: data.tags,
            mtime: data.mtime,
            size: data.size,
            checksum: data.checksum,
            git_commits: data.git_commits,
            git_last_commit: data.git_last_commit,
            git_daily: data.git_daily,
            created: data.created,
            checked: data.checked
        )
    }
}

extension Project.GitInfo {
    /// 转换为纯数据模型
    func toProjectDataGitInfo() -> ProjectData.GitInfoData {
        return ProjectData.GitInfoData(
            commitCount: self.commitCount,
            lastCommitDate: self.lastCommitDate
        )
    }
}

extension Project.FileSystemInfo {
    /// 转换为纯数据模型
    func toProjectDataFileSystemInfo() -> ProjectData.FileSystemInfoData {
        return ProjectData.FileSystemInfoData(
            modificationDate: self.modificationDate,
            size: self.size,
            checksum: self.checksum,
            lastCheckTime: self.lastCheckTime
        )
    }
}

extension ProjectData.GitInfoData {
    /// 转换为Project的GitInfo
    func toProjectGitInfo() -> Project.GitInfo {
        return Project.GitInfo(
            commitCount: self.commitCount,
            lastCommitDate: self.lastCommitDate
        )
    }
}

extension ProjectData.FileSystemInfoData {
    /// 转换为Project的FileSystemInfo
    func toProjectFileSystemInfo() -> Project.FileSystemInfo {
        return Project.FileSystemInfo(
            modificationDate: self.modificationDate,
            size: self.size,
            checksum: self.checksum,
            lastCheckTime: self.lastCheckTime
        )
    }
}

// MARK: - TagColorData <-> SwiftUI.Color 转换

// MARK: - TagColorData扩展已在DataModels.swift中定义，避免重复

extension Color {
    /// 从TagColorData创建Color
    init(from tagColorData: TagColorData) {
        self.init(red: tagColorData.red, 
                 green: tagColorData.green, 
                 blue: tagColorData.blue, 
                 opacity: tagColorData.alpha)
    }
}

// MARK: - 批量转换工具

extension Array where Element == Project {
    /// 批量转换为ProjectData数组
    func toProjectDataArray() -> [ProjectData] {
        return self.map { $0.toProjectData() }
    }
}

extension Array where Element == ProjectData {
    /// 批量转换为Project数组
    func toProjectArray() -> [Project] {
        return self.map { Project.fromProjectData($0) }
    }
}

extension Dictionary where Key == UUID, Value == Project {
    /// 转换为ProjectData字典
    func toProjectDataDictionary() -> [UUID: ProjectData] {
        return self.mapValues { $0.toProjectData() }
    }
}

extension Dictionary where Key == UUID, Value == ProjectData {
    /// 转换为Project字典
    func toProjectDictionary() -> [UUID: Project] {
        return self.mapValues { Project.fromProjectData($0) }
    }
}