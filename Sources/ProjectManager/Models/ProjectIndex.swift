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
    private let semaphore = DispatchSemaphore(value: 1)  // 添加信号量

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
            self?.saveIndex()  // 每次扫描后保存
        }
    }

    // 同步扫描所有目录
    func scanDirectoriesSync(_ paths: [String], force: Bool = false) {
        print("开始同步扫描 \(paths.count) 个目录")
        for path in paths {
            performScan(path, force: force)
        }
        saveIndex()
        print("同步扫描完成并保存索引")
    }

    // 同步扫描方法，直接在当前线程执行
    func performScanSync(_ path: String, force: Bool = false) {
        performScan(path, force: force)
        saveIndex()
    }

    private func performScan(_ path: String, force: Bool) {
        let fileManager = FileManager.default
        
        // 使用信号量保护索引访问
        semaphore.wait()
        defer { semaphore.signal() }
        
        do {
            let contents = try fileManager.contentsOfDirectory(
                at: URL(fileURLWithPath: path),
                includingPropertiesForKeys: [.isDirectoryKey, .contentModificationDateKey],
                options: [.skipsHiddenFiles]
            )
            
            var childPaths: [String] = []
            
            // 处理子目录 - 只扫描一级
            for url in contents {
                let resourceValues = try url.resourceValues(forKeys: [
                    .isDirectoryKey, .contentModificationDateKey,
                ])
                guard let isDirectory = resourceValues.isDirectory, isDirectory else { continue }
                
                let itemPath = url.path
                childPaths.append(itemPath)
                
                // 所有目录都当作项目
                let lastModified = resourceValues.contentModificationDate ?? Date()
                
                // 更新或创建索引条目
                let entry = ProjectIndexEntry(
                    path: itemPath,
                    lastScan: Date(),
                    isProject: true, // 所有目录都是项目
                    lastModified: lastModified,
                    children: []
                )
                indexEntries[itemPath] = entry
            }
            
            // 更新父目录
            indexEntries[path] = ProjectIndexEntry(
                path: path,
                lastScan: Date(),
                isProject: true, // 父目录也是项目
                lastModified: Date(),
                children: childPaths
            )
            
        } catch {
            print("扫描目录失败: \(error)")
        }
    }

    // 添加二级扫描功能
    func scanDirectoryTwoLevels(_ path: String, force: Bool = false) {
        // 扫描父目录
        performScanSync(path, force: force)
        
        // 获取子目录并扫描
        if let children = indexEntries[path]?.children {
            for childPath in children {
                performScanSync(childPath, force: force)
            }
        }
        
        // 保存索引
        saveIndex()
    }

    // MARK: - 项目加载

    func loadProjects(existingProjects: [UUID: Project] = [:], fromWatchedDirectories watchedDirectories: Set<String> = []) -> [Project] {
        var projects: [Project] = []
        var processedPaths = Set<String>()
        
        print("开始加载项目，监视目录数量: \(watchedDirectories.count)")
        
        // 使用信号量保护索引访问
        semaphore.wait()
        defer { semaphore.signal() }
        
        // 对每个监视目录进行扫描
        for watchedDir in watchedDirectories {
            print("处理监视目录: \(watchedDir)")
            
            // 检查监视目录本身是否是项目
            if let entry = indexEntries[watchedDir], entry.isProject, !processedPaths.contains(watchedDir) {
                if let project = Project.createProject(at: watchedDir, existingProjects: existingProjects) {
                    projects.append(project)
                    processedPaths.insert(watchedDir)
                    print("添加项目: \(watchedDir)")
                }
            }
            
            // 获取并处理子目录
            if let children = indexEntries[watchedDir]?.children {
                for childPath in children {
                    if !processedPaths.contains(childPath),
                       let entry = indexEntries[childPath],
                       entry.isProject
                    {
                        if let project = Project.createProject(at: childPath, existingProjects: existingProjects) {
                            projects.append(project)
                            processedPaths.insert(childPath)
                            print("添加子项目: \(childPath)")
                        }
                    }
                }
            }
        }
        
        print("完成加载，共找到 \(projects.count) 个项目")
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
