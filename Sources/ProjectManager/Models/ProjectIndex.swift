import Foundation

struct ProjectIndexEntry: Codable {
    let path: String
    var lastScan: Date
    var isProject: Bool
    var lastModified: Date
    var children: [String]  // 子目录路径

    static let scanInterval: TimeInterval = 3600  // 1小时重新扫描
}

class ProjectIndex {
    private let storage: TagStorage
    private var indexEntries: [String: ProjectIndexEntry] = [:]
    private let indexFileName = "project_index.json"
    private let queue = DispatchQueue(label: "com.projectmanager.indexing", qos: .utility)

    init(storage: TagStorage) {
        self.storage = storage
        loadIndex()
    }

    // MARK: - 索引文件操作

    private var indexFileURL: URL {
        return storage.appSupportURL.appendingPathComponent(indexFileName)
    }

    private func loadIndex() {
        do {
            let data = try Data(contentsOf: indexFileURL)
            let decoder = JSONDecoder()
            indexEntries = try decoder.decode([String: ProjectIndexEntry].self, from: data)
            print("加载项目索引: \(indexEntries.count) 个条目")
        } catch {
            print("加载项目索引失败（可能是首次运行）: \(error)")
            indexEntries = [:]
        }
    }

    private func saveIndex() {
        do {
            let encoder = JSONEncoder()
            let data = try encoder.encode(indexEntries)
            try data.write(to: indexFileURL)
            print("保存项目索引: \(indexEntries.count) 个条目")
        } catch {
            print("保存项目索引失败: \(error)")
        }
    }
    
    // 清除索引缓存
    func clearIndexCache() {
        indexEntries.removeAll()
        do {
            try FileManager.default.removeItem(at: indexFileURL)
            print("已清除项目索引缓存")
        } catch {
            print("清除项目索引缓存失败，可能不存在: \(error)")
        }
        saveIndex()
    }

    // MARK: - 索引扫描

    func scanDirectory(_ path: String, force: Bool = false) {
        queue.async { [weak self] in
            self?.performScan(path, force: force)
        }
    }
    
    // 同步扫描方法，直接在当前线程执行
    func performScanSync(_ path: String, force: Bool = false) {
        performScan(path, force: force)
    }

    private func performScan(_ path: String, force: Bool) {
        let fileManager = FileManager.default
        
        // 只扫描第一级目录
        do {
            let contents = try fileManager.contentsOfDirectory(
                at: URL(fileURLWithPath: path),
                includingPropertiesForKeys: [.isDirectoryKey, .contentModificationDateKey],
                options: [.skipsHiddenFiles]
            )
            
            // 创建全新的索引条目集合，而不是修改现有的
            var newIndexEntries: [String: ProjectIndexEntry] = [:]
            let parentPath = path
            var childPaths: [String] = []
            
            // 只处理第一级目录
            for url in contents {
                let resourceValues = try url.resourceValues(forKeys: [
                    .isDirectoryKey, .contentModificationDateKey,
                ])
                guard let isDirectory = resourceValues.isDirectory else { continue }
                
                let itemPath = url.path
                
                // 只记录目录
                if isDirectory {
                    childPaths.append(itemPath)
                    
                    // 检查是否为项目目录
                    let isProject = Project.isProjectDirectory(at: itemPath)
                    let lastModified = resourceValues.contentModificationDate ?? Date()
                    
                    // 创建新的索引条目
                    let entry = ProjectIndexEntry(
                        path: itemPath,
                        lastScan: Date(),
                        isProject: isProject,
                        lastModified: lastModified,
                        children: []
                    )
                    newIndexEntries[itemPath] = entry
                }
            }
            
            // 更新父目录
            let entry = ProjectIndexEntry(
                path: parentPath,
                lastScan: Date(),
                isProject: Project.isProjectDirectory(at: parentPath),
                lastModified: Date(),
                children: childPaths
            )
            newIndexEntries[parentPath] = entry
            
            // 从现有索引中只保留不相关的目录（不是当前扫描目录及其子目录的条目）
            for (entryPath, entry) in indexEntries {
                if !entryPath.hasPrefix(parentPath) && newIndexEntries[entryPath] == nil {
                    newIndexEntries[entryPath] = entry
                }
            }
            
            // 完全替换索引
            indexEntries = newIndexEntries
            
            saveIndex()
            
        } catch {
            print("扫描目录失败: \(error)")
        }
    }

    // MARK: - 项目加载

    func loadProjects(existingProjects: [UUID: Project] = [:], fromWatchedDirectories watchedDirectories: Set<String> = []) -> [Project] {
        var projects: [Project] = []
        var processedPaths = Set<String>() // 用于跟踪已处理的路径，避免重复
        
        print("加载项目开始，监视目录数量: \(watchedDirectories.count)")
        
        // 如果提供了监视目录集合，只处理这些目录
        let directoriesToProcess = watchedDirectories.isEmpty ? 
            Array(indexEntries.keys) : Array(watchedDirectories)
        
        print("需要处理的目录: \(directoriesToProcess)")
        
        for watchedDir in directoriesToProcess {
            print("处理目录: \(watchedDir)")
            
            // 检查监视目录本身是否是项目
            if let entry = indexEntries[watchedDir], entry.isProject, !processedPaths.contains(watchedDir) {
                print("监视目录自身是项目: \(watchedDir)")
                if let project = Project.createProject(at: watchedDir, existingProjects: existingProjects) {
                    projects.append(project)
                    processedPaths.insert(watchedDir)
                }
            }
            
            // 获取监视目录的直接子目录
            let children = indexEntries[watchedDir]?.children ?? []
            print("目录 \(watchedDir) 的子目录数量: \(children.count)")
            
            // 记录被识别为项目的子目录数量
            var projectDirCount = 0
            
            // 只处理第一级子目录中的项目
            for childPath in children {
                // 确保只考虑第一级子目录且未处理过
                guard (childPath as NSString).deletingLastPathComponent == watchedDir 
                    && !processedPaths.contains(childPath) else {
                    if processedPaths.contains(childPath) {
                        print("跳过已处理的目录: \(childPath)")
                    } else {
                        print("跳过非第一级子目录: \(childPath)")
                    }
                    continue
                }
                
                if let childEntry = indexEntries[childPath], childEntry.isProject {
                    print("子目录是项目: \(childPath)")
                    projectDirCount += 1
                    if let project = Project.createProject(at: childPath, existingProjects: existingProjects) {
                        projects.append(project)
                        processedPaths.insert(childPath)
                    }
                }
            }
            
            print("目录 \(watchedDir) 中找到 \(projectDirCount) 个项目目录")
        }
        
        print("项目加载完成，总共找到 \(projects.count) 个项目")
        return projects
    }

    // MARK: - 索引查询

    func isProjectDirectory(_ path: String) -> Bool {
        return indexEntries[path]?.isProject ?? false
    }

    func getSubdirectories(_ path: String) -> [String] {
        return indexEntries[path]?.children ?? []
    }

    func needsRescan(_ path: String) -> Bool {
        guard let entry = indexEntries[path] else { return true }
        return Date().timeIntervalSince(entry.lastScan) >= ProjectIndexEntry.scanInterval
    }
}

// MARK: - Project 扩展
extension Project {
    static func isProjectDirectory(at path: String) -> Bool {
        // 重要项目指示器 - 这些文件或目录存在时，一定是项目
        let strongIndicators = [
            "Package.swift",
            "package.json",
            ".git",
            "Podfile",
            "Cargo.toml",
            "go.mod",
            "pom.xml",
        ]
        
        // 弱项目指示器 - 这些文件可能表示项目，但需要更多验证
        let weakIndicators = [
            "*.xcodeproj",
            "*.xcworkspace",
            "Cartfile",
            "build.gradle",
            "requirements.txt",
            "setup.py",
            "composer.json",
            "Gemfile",
        ]

        let fileManager = FileManager.default
        
        // 检查路径是否存在并且是一个目录
        var isDir: ObjCBool = false
        guard fileManager.fileExists(atPath: path, isDirectory: &isDir) && isDir.boolValue else {
            print("路径不存在或不是目录: \(path)")
            return false
        }
        
        // 检查是否是系统目录或隐藏目录
        let lastComponent = (path as NSString).lastPathComponent
        if lastComponent.hasPrefix(".") && lastComponent != ".git" {
            return false
        }
        
        // 如果目录名是明显的非项目名称，则跳过
        let systemDirectories = [
            "Library", "Documents", "Downloads", "Pictures", "Music", "Movies", 
            "Applications", "Desktop", "Library", "Public"
        ]
        if systemDirectories.contains(lastComponent) {
            return false
        }

        // 检查强项目指示器
        for indicator in strongIndicators {
            let fullPath = (path as NSString).appendingPathComponent(indicator)
            if fileManager.fileExists(atPath: fullPath) {
                print("强项目指示器匹配: \(path) 包含 \(indicator)")
                return true
            }
        }

        // 检查弱项目指示器的通配符模式
        var foundWeakIndicator = false
        for indicator in weakIndicators where indicator.contains("*") {
            let pattern = indicator.replacingOccurrences(of: ".", with: "\\.")
                .replacingOccurrences(of: "*", with: ".*")
            do {
                let regex = try NSRegularExpression(pattern: pattern, options: [])
                if let contents = try? fileManager.contentsOfDirectory(atPath: path) {
                    for item in contents {
                        let range = NSRange(location: 0, length: item.utf16.count)
                        if regex.firstMatch(in: item, options: [], range: range) != nil {
                            print("弱项目指示器匹配: \(path) 包含匹配 \(indicator) 的文件 \(item)")
                            foundWeakIndicator = true
                            break
                        }
                    }
                }
            } catch {
                print("正则表达式错误: \(error)")
            }
        }
        
        // 检查非通配符的弱项目指示器
        for indicator in weakIndicators where !indicator.contains("*") {
            let fullPath = (path as NSString).appendingPathComponent(indicator)
            if fileManager.fileExists(atPath: fullPath) {
                print("弱项目指示器匹配: \(path) 包含 \(indicator)")
                foundWeakIndicator = true
                break
            }
        }
        
        // 如果有弱指示器匹配，再做额外验证
        if foundWeakIndicator {
            // 检查是否包含源代码文件
            let sourceCodeExtensions = ["swift", "java", "kt", "py", "js", "ts", "go", "rs", "c", "cpp", "h", "m", "rb", "php"]
            
            // 尝试找源代码文件
            do {
                if let contents = try? fileManager.contentsOfDirectory(atPath: path) {
                    for item in contents {
                        let ext = (item as NSString).pathExtension.lowercased()
                        if sourceCodeExtensions.contains(ext) {
                            print("找到源代码文件: \(path)/\(item)")
                            return true
                        }
                    }
                }
                
                // 检查子目录中是否有源代码文件
                if let subDirs = try? fileManager.contentsOfDirectory(at: URL(fileURLWithPath: path), includingPropertiesForKeys: [.isDirectoryKey]) {
                    for subDir in subDirs.prefix(3) { // 只检查前3个子目录
                        if let isDirectory = try? subDir.resourceValues(forKeys: [.isDirectoryKey]).isDirectory, isDirectory {
                            if let contents = try? fileManager.contentsOfDirectory(atPath: subDir.path) {
                                for item in contents {
                                    let ext = (item as NSString).pathExtension.lowercased()
                                    if sourceCodeExtensions.contains(ext) {
                                        print("在子目录中找到源代码文件: \(subDir.path)/\(item)")
                                        return true
                                    }
                                }
                            }
                        }
                    }
                }
            } catch {
                print("检查源代码文件时出错: \(error)")
            }
        }
        
        print("未识别为项目目录: \(path)")
        return false
    }

    static func createProject(at path: String, existingProjects: [UUID: Project] = [:]) -> Project?
    {
        // 检查是否存在缓存的项目
        if let existingProject = existingProjects.values.first(where: { $0.path == path }) {
            // 如果存在且不需要更新，直接使用缓存
            if !existingProject.needsUpdate() {
                return existingProject
            }
            // 需要更新，返回更新后的项目
            return existingProject.updated()
        }

        // 新项目，创建新实例
        guard
            let modDate = try? URL(fileURLWithPath: path).resourceValues(
                forKeys: [.contentModificationDateKey]
            ).contentModificationDate
        else {
            return nil
        }

        let tags = loadTagsFromSystem(path: path)
        return Project(
            name: (path as NSString).lastPathComponent,
            path: path,
            lastModified: modDate,
            tags: tags
        )
    }
}
