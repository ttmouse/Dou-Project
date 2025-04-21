import AppKit
import Foundation

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
        id: UUID = UUID(), name: String, path: String, lastModified: Date = Date(),
        tags: Set<String> = []
    ) {
        self.id = id
        self.name = name
        self.path = path
        self.lastModified = lastModified
        self.tags = tags
        self.fileSystemInfo = Self.loadFileSystemInfo(path: path)
        self.gitInfo = Self.loadGitInfo(path: path)
        saveTagsToSystem()
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

    // 保存标签到系统
    func saveTagsToSystem() {
        let url = URL(fileURLWithPath: path)
        do {
            // 获取当前系统标签
            let currentTags = Self.loadTagsFromSystem(path: path)
            // 如果标签没有变化，不需要保存
            if currentTags == tags {
                return
            }

            try (url as NSURL).setResourceValue(Array(tags), forKey: .tagNamesKey)
            print("系统标签保存成功: \(tags)")
        } catch {
            print("保存系统标签失败: \(error)")
        }
    }

    // 从系统加载标签
    static func loadTagsFromSystem(path: String) -> Set<String> {
        let url = URL(fileURLWithPath: path)
        do {
            let resourceValues = try url.resourceValues(forKeys: Set([.tagNamesKey]))
            if let tags = resourceValues.tagNames {
                print("从系统加载标签: \(tags)")
                return Set(tags)
            }
        } catch {
            print("加载系统标签失败: \(error)")
        }
        return []
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
}

private enum ProjectType {
    case node
    case swift
    case unknown
}
