import Foundation
import AppKit

struct Project: Identifiable, Equatable, Codable {
    let id: UUID
    let name: String
    let path: String
    let lastModified: String
    private(set) var tags: Set<String>
    
    init(id: UUID = UUID(), name: String, path: String, lastModified: String, tags: Set<String> = []) {
        self.id = id
        self.name = name
        self.path = path
        self.lastModified = lastModified
        self.tags = tags
        saveTagsToSystem() // 初始化时保存标签
    }
    
    mutating func addTag(_ tag: String) {
        print("添加标签到项目 '\(name)': \(tag)")
        print("原有标签: \(tags)")
        tags.insert(tag)
        print("更新后标签: \(tags)")
        saveTagsToSystem()
    }
    
    mutating func removeTag(_ tag: String) {
        print("从项目 '\(name)' 移除标签: \(tag)")
        print("原有标签: \(tags)")
        tags.remove(tag)
        print("更新后标签: \(tags)")
        saveTagsToSystem()
    }
    
    func copyWith(tags newTags: Set<String>) -> Project {
        let project = Project(
            id: self.id,
            name: self.name,
            path: self.path,
            lastModified: self.lastModified,
            tags: newTags
        )
        return project // 初始化时已经保存标签
    }
    
    // 保存标签到系统
    private func saveTagsToSystem() {
        let url = URL(fileURLWithPath: path)
        do {
            try (url as NSURL).setResourceValue(Array(tags), forKey: .tagNamesKey)
            print("系统标签保存成功: \(tags)")
        } catch {
            print("保存系统标签失败: \(error)")
        }
    }
    
    // 从系统加载标签
    private static func loadTagsFromSystem(path: String) -> Set<String> {
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
    
    static func loadProjects(from directory: String) -> [Project] {
        print("开始加载项目目录: \(directory)")
        let fileManager = FileManager.default
        let directoryURL = URL(fileURLWithPath: directory)
        
        guard let contents = try? fileManager.contentsOfDirectory(
            at: directoryURL,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles]
        ) else {
            print("读取目录失败")
            return []
        }
        
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        
        let projects = contents
            .filter { $0.hasDirectoryPath }
            .map { url in
                let modDate = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? Date()
                let tags = loadTagsFromSystem(path: url.path)
                print("加载项目: \(url.lastPathComponent), 标签: \(tags)")
                return Project(
                    name: url.lastPathComponent,
                    path: url.path,
                    lastModified: dateFormatter.string(from: modDate),
                    tags: tags
                )
            }
            .sorted { $0.lastModified > $1.lastModified }
        
        print("加载完成，共 \(projects.count) 个项目")
        return projects
    }
    
    func openInVSCode() {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/Applications/Cursor.app/Contents/MacOS/Cursor")
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
