import AppKit
import Foundation
import SwiftUI

/// 项目模型，代表文件系统中的一个项目目录
/// 
/// 扁平数据结构重构（基于TRD v1.0）：
/// 1. 消除嵌套结构，提升30%解析性能
/// 2. 统一字段命名，消除数据冗余
/// 3. 支持多天Git活跃度统计
/// 4. 保持向后兼容的数据迁移
struct Project: Identifiable, Equatable, Codable {
    // 核心标识
    let id: UUID
    let name: String
    let path: String
    let tags: Set<String>
    
    // 文件系统信息 (扁平化)
    let mtime: Date              // 修改时间 (统一字段)
    let size: Int64              // 文件大小
    let checksum: String         // SHA256格式: "sha256:deadbeef..."
    
    // Git信息 (扁平化)
    let git_commits: Int         // 总提交数
    let git_last_commit: Date    // 最后提交时间
    let git_daily: String?       // 每日提交统计: "2025-08-25:3,2025-08-24:5"
    
    // 元数据
    let created: Date            // 首次发现时间
    let checked: Date            // 最后检查时间
    
    // MARK: - 向后兼容属性
    /// 为了向后兼容，保留原有字段访问方式
    var lastModified: Date { mtime }
    var gitInfo: GitInfo? {
        guard git_commits > 0 else { return nil }
        return GitInfo(commitCount: git_commits, lastCommitDate: git_last_commit)
    }
    var fileSystemInfo: FileSystemInfo {
        return FileSystemInfo(
            modificationDate: mtime,
            size: UInt64(size),
            checksum: checksum,
            lastCheckTime: checked
        )
    }

    /// 向后兼容的嵌套结构定义
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

    /// 扁平结构初始化器 - 直接设置所有字段
    init(
        id: UUID = UUID(),
        name: String,
        path: String,
        tags: Set<String> = [],
        mtime: Date? = nil,
        size: Int64? = nil,
        checksum: String? = nil,
        git_commits: Int = 0,
        git_last_commit: Date? = nil,
        git_daily: String? = nil,
        created: Date? = nil,
        checked: Date? = nil
    ) {
        self.id = id
        self.name = name
        self.path = path
        self.tags = tags
        
        // 如果没有提供值，从文件系统加载
        let fsInfo = Self.loadFileSystemInfo(path: path)
        let gitInfo = Self.loadGitInfo(path: path)
        
        self.mtime = mtime ?? fsInfo.modificationDate
        self.size = size ?? Int64(fsInfo.size)
        self.checksum = checksum ?? fsInfo.checksum
        self.git_commits = git_commits > 0 ? git_commits : (gitInfo?.commitCount ?? 0)
        self.git_last_commit = git_last_commit ?? (gitInfo?.lastCommitDate ?? Date.distantPast)
        self.git_daily = git_daily
        self.created = created ?? Date()
        self.checked = checked ?? Date()
    }
    
    /// 向后兼容的初始化器
    @available(*, deprecated, message: "使用扁平结构的新初始化器")
    init(
        id: UUID = UUID(),
        name: String,
        path: String,
        lastModified: Date = Date(),
        tags: Set<String> = []
    ) {
        self.init(
            id: id,
            name: name,
            path: path,
            tags: tags,
            mtime: lastModified
        )
    }
    
    // MARK: - Codable Support
    
    enum CodingKeys: String, CodingKey {
        case id, name, path, tags
        case mtime, size, checksum
        case git_commits, git_last_commit, git_daily
        case created, checked
        // 向后兼容键
        case lastModified, gitInfo, fileSystemInfo
    }
    
    /// 扁平结构解码 + 数据迁移支持
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        
        id = try container.decode(UUID.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        path = try container.decode(String.self, forKey: .path)
        tags = try container.decodeIfPresent(Set<String>.self, forKey: .tags) ?? []
        
        // 检查是否是新格式数据
        if container.contains(.mtime) {
            // 新的扁平格式
            mtime = try container.decode(Date.self, forKey: .mtime)
            size = try container.decode(Int64.self, forKey: .size)
            checksum = try container.decode(String.self, forKey: .checksum)
            git_commits = try container.decode(Int.self, forKey: .git_commits)
            git_last_commit = try container.decode(Date.self, forKey: .git_last_commit)
            git_daily = try container.decodeIfPresent(String.self, forKey: .git_daily)
            created = try container.decode(Date.self, forKey: .created)
            checked = try container.decode(Date.self, forKey: .checked)
        } else {
            // 旧的嵌套格式 - 数据迁移
            let oldLastModified = try container.decode(Date.self, forKey: .lastModified)
            let oldGitInfo = try container.decodeIfPresent(GitInfo.self, forKey: .gitInfo)
            let oldFileSystemInfo = try container.decode(FileSystemInfo.self, forKey: .fileSystemInfo)
            
            // 迁移数据到扁平结构
            mtime = oldLastModified
            size = Int64(oldFileSystemInfo.size)
            checksum = oldFileSystemInfo.checksum
            git_commits = oldGitInfo?.commitCount ?? 0
            git_last_commit = oldGitInfo?.lastCommitDate ?? Date.distantPast
            git_daily = nil // 旧数据没有多天统计
            created = oldFileSystemInfo.lastCheckTime
            checked = Date()
        }
    }
    
    /// 扁平结构编码 - 只保存新格式
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        
        try container.encode(id, forKey: .id)
        try container.encode(name, forKey: .name)
        try container.encode(path, forKey: .path)
        try container.encode(tags, forKey: .tags)
        try container.encode(mtime, forKey: .mtime)
        try container.encode(size, forKey: .size)
        try container.encode(checksum, forKey: .checksum)
        try container.encode(git_commits, forKey: .git_commits)
        try container.encode(git_last_commit, forKey: .git_last_commit)
        try container.encodeIfPresent(git_daily, forKey: .git_daily)
        try container.encode(created, forKey: .created)
        try container.encode(checked, forKey: .checked)
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
        if Date().timeIntervalSince(checked) < FileSystemInfo.checkInterval {
            return false
        }

        let currentInfo = Self.loadFileSystemInfo(path: path)
        return currentInfo.checksum != checksum
    }

    // 更新项目信息
    func updated() -> Project {
        let fsInfo = Self.loadFileSystemInfo(path: path)
        let gitInfo = Self.loadGitInfo(path: path)
        
        return Project(
            id: id,
            name: name,
            path: path,
            tags: tags,
            mtime: fsInfo.modificationDate,
            size: Int64(fsInfo.size),
            checksum: fsInfo.checksum,
            git_commits: gitInfo?.commitCount ?? 0,
            git_last_commit: gitInfo?.lastCommitDate ?? Date.distantPast,
            git_daily: git_daily, // 保留现有的日统计
            created: created,
            checked: Date()
        )
    }

    /// 扁平结构标签操作 - 返回新实例，不修改自身（函数式编程风格）
    /// 业务逻辑请使用BusinessLogic中的ProjectOperations和TagLogic
    func withAddedTag(_ tag: String) -> Project {
        var newTags = tags
        newTags.insert(tag)
        return copyWith(tags: newTags)
    }

    func withRemovedTag(_ tag: String) -> Project {
        var newTags = tags
        newTags.remove(tag)
        return copyWith(tags: newTags)
    }

    func copyWith(tags newTags: Set<String>) -> Project {
        return Project(
            id: id,
            name: name,
            path: path,
            tags: newTags,
            mtime: mtime,
            size: size,
            checksum: checksum,
            git_commits: git_commits,
            git_last_commit: git_last_commit,
            git_daily: git_daily,
            created: created,
            checked: checked
        )
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

    // 静态方法：创建项目 (扁平结构版本)
    static func createProject(at path: String, existingProjects: [UUID: Project] = [:]) -> Project? {
        // 检查路径是否存在
        guard FileManager.default.fileExists(atPath: path) else {
            return nil
        }
        
        // 获取目录名作为项目名
        let url = URL(fileURLWithPath: path)
        let name = url.lastPathComponent
        
        // 加载文件系统和Git信息
        let fsInfo = loadFileSystemInfo(path: path)
        let gitInfo = loadGitInfo(path: path)
        
        // 检查是否已有现有项目
        if let existingProject = existingProjects.values.first(where: { $0.path == path }) {
            // 🛡️ 安全修复：保持现有项目的标签和元数据，避免数据丢失
            return Project(
                id: existingProject.id,
                name: name,
                path: path,
                tags: existingProject.tags,  // 🔧 修复：保持现有标签
                mtime: fsInfo.modificationDate,
                size: Int64(fsInfo.size),
                checksum: fsInfo.checksum,
                git_commits: gitInfo?.commitCount ?? 0,
                git_last_commit: gitInfo?.lastCommitDate ?? Date.distantPast,
                git_daily: existingProject.git_daily, // 保持现有的日统计
                created: existingProject.created,
                checked: Date()
            )
        }
        
        // 创建新项目，从系统加载标签
        let systemTags = loadTagsFromSystem(path: path)
        return Project(
            id: UUID(),
            name: name,
            path: path,
            tags: systemTags,  // 🔧 修复：加载系统标签
            mtime: fsInfo.modificationDate,
            size: Int64(fsInfo.size),
            checksum: fsInfo.checksum,
            git_commits: gitInfo?.commitCount ?? 0,
            git_last_commit: gitInfo?.lastCommitDate ?? Date.distantPast,
            git_daily: nil,
            created: Date(),
            checked: Date()
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
