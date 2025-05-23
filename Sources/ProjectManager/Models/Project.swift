import AppKit
import Foundation
import SwiftUI

/// 项目模型，代表文件系统中的一个项目目录
///
/// ⚠️ 标签系统警告：
/// 1. 项目的标签信息直接存储在文件系统的元数据中
/// 2. 标签的加载和保存操作需要特别注意数据完整性
/// 3. 在修改标签相关代码时，请参考 README.md 中的警告说明
///
/// 标签处理流程：
/// 1. `loadTagsFromSystem`: 从文件系统加载标签
/// 2. 标签修改后需要确保同步回系统
/// 3. 避免在未同步完成前执行其他标签操作
struct Project: Identifiable, Equatable, Codable {
    let id: UUID
    let name: String
    let path: String
    let lastModified: Date
    private(set) var tags: Set<String>
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
        self.fileSystemInfo = Self.loadFileSystemInfo(path: path)
        self.gitInfo = Self.loadGitInfo(path: path)
        
        // 总是从系统加载标签
        let systemTags = Self.loadTagsFromSystem(path: path)
        if !systemTags.isEmpty {
            // 如果系统有标签，优先使用系统标签
            self.tags = systemTags
            // 不要在这里保存标签，避免覆盖系统标签
        } else if !tags.isEmpty {
            // 如果系统没有标签，但提供了标签，则使用提供的标签并保存到系统
            self.tags = tags
            // 直接调用静态方法保存标签
            let finalTags = tags
            DispatchQueue.main.async {
                Self.saveTagsToSystem(path: path, tags: finalTags)
            }
        } else {
            // 都没有标签，使用空集合
            self.tags = []
        }
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

    mutating func addTag(_ tag: String) {
        print("添加标签到项目 '\(name)': \(tag)")
        print("原有标签: \(tags)")
        tags.insert(tag)
        print("更新后标签: \(tags)")
        // 不在这里保存，由上层统一处理
    }

    mutating func removeTag(_ tag: String) {
        print("从项目 '\(name)' 移除标签: \(tag)")
        print("原有标签: \(tags)")
        tags.remove(tag)
        print("更新后标签: \(tags)")
        // 不在这里保存，由上层统一处理
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

    // 从系统加载标签
    static func loadTagsFromSystem(path: String) -> Set<String> {
        // 使用 TagSystemSync 加载标签
        let tags = TagSystemSync.loadTagsFromFile(at: path)
        print("从系统加载标签: \(path) -> \(tags)")
        return tags
    }

    // 系统标准标签映射
    private static let systemTagMapping: [String: String] = [
        "green": "绿色",
        "绿色": "绿色",
        "red": "红色",
        "红色": "红色",
        "orange": "橙色",
        "橙色": "橙色",
        "yellow": "黄色",
        "黄色": "黄色",
        "blue": "蓝色",
        "蓝色": "蓝色",
        "purple": "紫色",
        "紫色": "紫色",
        "gray": "灰色",
        "grey": "灰色",
        "灰色": "灰色"
    ]

    // 保存标签到系统（改为静态方法）
    static func saveTagsToSystem(path: String, tags: Set<String>) {
        // 获取当前系统标签
        let currentTags = loadTagsFromSystem(path: path)
        
        // 如果当前有系统标签，不要覆盖它们
        if !currentTags.isEmpty {
            print("文件已有系统标签，不覆盖: \(currentTags)")
            return
        }
        
        // 保存标签到系统
        print("保存标签到系统: \(path) -> \(tags)")
        TagSystemSync.saveTagsToFile(tags, at: path)
    }

    // 实例方法调用静态方法
    func saveTagsToSystem() {
        // 获取当前系统标签
        let currentTags = Self.loadTagsFromSystem(path: path)
        
        // 合并标签，确保不会删除系统标签
        var mergedTags = currentTags
        mergedTags.formUnion(tags)
        
        // 保存合并后的标签
        Self.saveTagsToSystem(path: path, tags: mergedTags)
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
            // 使用现有项目的ID，但重新从系统加载标签
            return Project(
                id: existingProject.id,
                name: name,
                path: path,
                lastModified: modificationDate
            )
        }
        
        // 创建新项目
        return Project(
            id: UUID(),
            name: name,
            path: path,
            lastModified: modificationDate
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
