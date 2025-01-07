import Foundation
import AppKit

struct Project: Identifiable, Equatable {
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
    }
    
    mutating func addTag(_ tag: String) {
        tags.insert(tag)
    }
    
    mutating func removeTag(_ tag: String) {
        tags.remove(tag)
    }
    
    func copyWith(tags newTags: Set<String>) -> Project {
        Project(
            id: self.id,
            name: self.name,
            path: self.path,
            lastModified: self.lastModified,
            tags: newTags
        )
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
        let fileManager = FileManager.default
        let directoryURL = URL(fileURLWithPath: directory)
        
        guard let contents = try? fileManager.contentsOfDirectory(
            at: directoryURL,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles]
        ) else { return [] }
        
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        
        return contents
            .filter { $0.hasDirectoryPath }
            .map { url in
                let modDate = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? Date()
                return Project(
                    name: url.lastPathComponent,
                    path: url.path,
                    lastModified: dateFormatter.string(from: modDate),
                    tags: []
                )
            }
            .sorted { $0.lastModified > $1.lastModified }
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