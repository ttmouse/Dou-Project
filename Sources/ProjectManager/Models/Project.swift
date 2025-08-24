import AppKit
import Foundation
import SwiftUI

/// 项目模型，代表文件系统中的一个项目目录
/// 
/// Linus式重构后的简单设计：
/// 1. 去掉所有延迟加载 - "Premature optimization is the root of all evil"
/// 2. 去掉所有缓存逻辑 - 先让它工作，再优化
/// 3. 标签就是简单的Set<String> - 不搞花里胡哨
/// 4. 需要业务逻辑？去BusinessLogic.swift找
struct Project: Identifiable, Equatable, Codable {
    let id: UUID
    let name: String
    let path: String
    let lastModified: Date
    let tags: Set<String>  // 简单直接，不搞延迟加载
    let gitInfo: GitInfo?
    let fileSystemInfo: FileSystemInfo

    struct GitInfo: Codable, Equatable {
        let commitCount: Int
        let lastCommitDate: Date
    }

    struct FileSystemInfo: Codable, Equatable {
        let modificationDate: Date
        let size: UInt64
        let checksum: String
        let lastCheckTime: Date

        static let checkInterval: TimeInterval = 300  // 5分钟检查间隔
    }

    /// Linus式简单初始化器 - 无花里胡哨，直接赋值
    init(
        id: UUID = UUID(),
        name: String,
        path: String,
        lastModified: Date = Date(),
        tags: Set<String> = []
    ) {
        self.id = id
        self.name = name
        self.path = path
        self.lastModified = lastModified
        self.tags = tags  // 直接赋值，不搞缓存
        self.fileSystemInfo = Self.loadFileSystemInfo(path: path)
        self.gitInfo = Self.loadGitInfo(path: path)
    }
    
    // MARK: - Codable Support
    
    enum CodingKeys: String, CodingKey {
        case id, name, path, lastModified, tags, gitInfo, fileSystemInfo
    }
    
    /// Linus式简单解码 - 直接解码，无缓存逻辑
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        
        id = try container.decode(UUID.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        path = try container.decode(String.self, forKey: .path)
        lastModified = try container.decode(Date.self, forKey: .lastModified)
        tags = try container.decodeIfPresent(Set<String>.self, forKey: .tags) ?? []
        gitInfo = try container.decodeIfPresent(GitInfo.self, forKey: .gitInfo)
        fileSystemInfo = try container.decode(FileSystemInfo.self, forKey: .fileSystemInfo)
    }
    
    /// Linus式简单编码 - 直接编码，无缓存逻辑
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        
        try container.encode(id, forKey: .id)
        try container.encode(name, forKey: .name)
        try container.encode(path, forKey: .path)
        try container.encode(lastModified, forKey: .lastModified)
        try container.encode(tags, forKey: .tags)
        try container.encodeIfPresent(gitInfo, forKey: .gitInfo)
        try container.encode(fileSystemInfo, forKey: .fileSystemInfo)
    }

    private static func loadFileSystemInfo(path: String) -> FileSystemInfo {
        let url = URL(fileURLWithPath: path)
        do {
            let resourceValues = try url.resourceValues(forKeys: [
                .contentModificationDateKey, .fileSizeKey,
            ])
            let modDate = resourceValues.contentModificationDate ?? Date()
            let size = UInt64(resourceValues.fileSize ?? 0)
            let checksum = "\(modDate.timeIntervalSince1970)_\(size)"
            return FileSystemInfo(
                modificationDate: modDate,
                size: size,
                checksum: checksum,
                lastCheckTime: Date()
            )
        } catch {
            return FileSystemInfo(
                modificationDate: Date(),
                size: 0,
                checksum: "",
                lastCheckTime: Date()
            )
        }
    }

    private static func loadGitInfo(path: String) -> GitInfo? {
        // 检查是否是 Git 仓库
        let gitPath = "\(path)/.git"
        guard FileManager.default.fileExists(atPath: gitPath) else {
            return nil
        }

        let process = Process()
        process.currentDirectoryURL = URL(fileURLWithPath: path)
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")

        // 获取提交次数和最后提交时间
        let pipe = Pipe()
        process.standardOutput = pipe
        process.arguments = ["log", "--format=%ct", "-n", "1"]

        do {
            try process.run()
            process.waitUntilExit()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            if let timestamp = Double(
                String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
                    ?? "0")
            {
                let lastCommitDate = Date(timeIntervalSince1970: timestamp)

                // 获取提交次数
                let countProcess = Process()
                countProcess.currentDirectoryURL = URL(fileURLWithPath: path)
                countProcess.executableURL = URL(fileURLWithPath: "/usr/bin/git")
                countProcess.arguments = ["rev-list", "--count", "HEAD"]

                let countPipe = Pipe()
                countProcess.standardOutput = countPipe
                try countProcess.run()
                countProcess.waitUntilExit()

                let countData = countPipe.fileHandleForReading.readDataToEndOfFile()
                if let commitCount = Int(
                    String(data: countData, encoding: .utf8)?.trimmingCharacters(
                        in: .whitespacesAndNewlines) ?? "0")
                {
                    return GitInfo(commitCount: commitCount, lastCommitDate: lastCommitDate)
                }
            }
        } catch {
            print("获取 Git 信息失败: \(error)")
        }
        return nil
    }

    // 检查项目是否需要更新
    func needsUpdate() -> Bool {
        // 如果距离上次检查时间不足5分钟，直接返回 false
        if Date().timeIntervalSince(fileSystemInfo.lastCheckTime) < FileSystemInfo.checkInterval {
            return false
        }

        let currentInfo = Self.loadFileSystemInfo(path: path)
        return currentInfo.checksum != fileSystemInfo.checksum
    }

    // 更新项目信息
    func updated() -> Project {
        return Project(id: id, name: name, path: path, tags: tags)
    }

    /// Linus式标签操作 - 返回新实例，不修改自身（函数式编程风格）
    /// 业务逻辑请使用BusinessLogic中的ProjectOperations和TagLogic
    func withAddedTag(_ tag: String) -> Project {
        var newTags = tags
        newTags.insert(tag)
        return Project(id: id, name: name, path: path, lastModified: lastModified, tags: newTags)
    }

    func withRemovedTag(_ tag: String) -> Project {
        var newTags = tags
        newTags.remove(tag)
        return Project(id: id, name: name, path: path, lastModified: lastModified, tags: newTags)
    }

    func copyWith(tags newTags: Set<String>) -> Project {
        let project = Project(
            id: self.id,
            name: self.name,
            path: self.path,
            lastModified: self.lastModified,
            tags: newTags
        )
        return project
    }

    // 系统标签读写（启用）：使用 URLResourceValues(.tagNamesKey) 的方式
    // 参考 /tmp/tag_test_tool.swift 的实现
    static func loadTagsFromSystem(path: String) -> Set<String> {
        return TagSystemSyncOptimized.loadTagsFromFile(at: path)
    }

    static func saveTagsToSystem(path: String, tags: Set<String>) {
        TagSystemSync.saveTagsToFile(tags, at: path)
    }

    /// 将当前项目的标签保存到系统文件标签
    func saveTagsToSystem() {
        Self.saveTagsToSystem(path: path, tags: tags)
    }

    private var projectType: ProjectType {
        if FileManager.default.fileExists(atPath: "\(path)/package.json") {
            return .node
        } else if FileManager.default.fileExists(atPath: "\(path)/Package.swift") {
            return .swift
        } else {
            return .unknown
        }
    }

    func runProject() {
        let process = Process()
        process.currentDirectoryURL = URL(fileURLWithPath: path)

        switch projectType {
        case .node:
            process.executableURL = URL(fileURLWithPath: "/usr/local/bin/npm")
            process.arguments = ["start"]
        case .swift:
            process.executableURL = URL(fileURLWithPath: "/usr/bin/swift")
            process.arguments = ["run"]
        case .unknown:
            return
        }

        do {
            try process.run()
        } catch {
            print("运行项目失败: \(error)")
        }
    }

    func openInVSCode() {
        let process = Process()
        process.executableURL = URL(
            fileURLWithPath: "/Applications/Cursor.app/Contents/MacOS/Cursor")
        process.arguments = [path]

        do {
            try process.run()
        } catch {
            print("打开 Cursor 失败: \(error)")
            let fallbackProcess = Process()
            fallbackProcess.executableURL = URL(fileURLWithPath: "/usr/bin/open")
            fallbackProcess.arguments = ["-a", "Cursor", path]
            try? fallbackProcess.run()
        }
    }

    func openInFinder() {
        NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: path)
    }

    // 检查项目是否已存在
    static func isProjectExists(path: String, in projects: [UUID: Project]) -> Bool {
        return projects.values.contains { $0.path == path }
    }

    // 静态方法：创建项目
    static func createProject(at path: String, existingProjects: [UUID: Project] = [:]) -> Project? {
        // 检查路径是否存在
        guard FileManager.default.fileExists(atPath: path) else {
            return nil
        }
        
        // 获取目录名作为项目名
        let url = URL(fileURLWithPath: path)
        let name = url.lastPathComponent
        
        // 获取目录修改时间
        let attributes = try? FileManager.default.attributesOfItem(atPath: path)
        let modificationDate = attributes?[.modificationDate] as? Date ?? Date()
        
        // 检查是否已有现有项目
        if let existingProject = existingProjects.values.first(where: { $0.path == path }) {
            // 🛡️ 安全修复：保持现有项目的标签，避免数据丢失
            return Project(
                id: existingProject.id,
                name: name,
                path: path,
                lastModified: modificationDate,
                tags: existingProject.tags  // 🔧 修复：保持现有标签
            )
        }
        
        // 创建新项目，从系统加载标签
        let systemTags = loadTagsFromSystem(path: path)
        return Project(
            id: UUID(),
            name: name,
            path: path,
            lastModified: modificationDate,
            tags: systemTags  // 🔧 修复：加载系统标签
        )
    }

    // 检查是否是项目目录 - 简化版本，所有目录都是项目
    static func isProjectDirectory(at path: String) -> Bool {
        return FileManager.default.fileExists(atPath: path)
    }
}

private enum ProjectType {
    case node
    case swift
    case unknown
}
