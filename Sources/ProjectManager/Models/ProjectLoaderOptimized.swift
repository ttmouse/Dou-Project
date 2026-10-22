import Foundation

/// Linus式优化项目加载器
/// 
/// 核心理念：
/// 1. "Do it right the first time" - 第一次就做对
/// 2. "Don't be stupid" - 批量处理，不要逐个处理
/// 3. "Performance matters" - 性能很重要
class ProjectLoaderOptimized {
    private let cache = TagCache.shared
    private let batchLoader = BatchTagLoader()
    
    /// 批量创建项目，优化版本
    func createProjectsBatch(
        paths: [String], 
        existingProjects: [UUID: Project] = [:]
    ) -> [Project] {
        
        return PerformanceTimer.measure("Create projects batch (\(paths.count) paths)") {
            // 1. 批量加载标签
            let tagMap = PerformanceTimer.measure("Batch load tags") {
                return batchLoader.loadTagsBatch(paths: paths)
            }
            
            // 2. 并发创建项目对象
            return PerformanceTimer.measure("Create project objects") {
                return createProjectsConcurrently(
                    paths: paths, 
                    tagMap: tagMap, 
                    existingProjects: existingProjects
                )
            }
        }
    }
    
    /// 并发创建项目对象
    private func createProjectsConcurrently(
        paths: [String],
        tagMap: [String: Set<String>],
        existingProjects: [UUID: Project]
    ) -> [Project] {
        
        let chunks = paths.chunked(into: 50)
        var allProjects: [Project] = []
        let lock = NSLock()
        let group = DispatchGroup()
        let queue = DispatchQueue(label: "project.creation", qos: .utility, attributes: .concurrent)
        
        for chunk in chunks {
            group.enter()
            queue.async {
                let chunkProjects = chunk.compactMap { path -> Project? in
                    guard FileManager.default.fileExists(atPath: path) else {
                        return nil
                    }
                    
                    let name = URL(fileURLWithPath: path).lastPathComponent
                    let attributes = try? FileManager.default.attributesOfItem(atPath: path)
                    let modificationDate = attributes?[.modificationDate] as? Date ?? Date()
                    let tags = tagMap[path] ?? []
                    
                    // 检查是否有现有项目
                    if let existingProject = existingProjects.values.first(where: { $0.path == path }) {
                        return Project(
                            id: existingProject.id,
                            name: name,
                            path: path,
                            lastModified: modificationDate,
                            tags: tags
                        )
                    } else {
                        return Project(
                            id: UUID(),
                            name: name,
                            path: path,
                            lastModified: modificationDate,
                            tags: tags
                        )
                    }
                }
                
                lock.lock()
                allProjects.append(contentsOf: chunkProjects)
                lock.unlock()
                
                group.leave()
            }
        }
        
        group.wait()
        return allProjects
    }
    
    /// 智能项目发现 - 只扫描必要的目录
    func discoverProjectsSmart(from watchedDirectories: [String]) -> [String] {
        return PerformanceTimer.measure("Smart project discovery") {
            var projectPaths: [String] = []
            let lock = NSLock()
            let group = DispatchGroup()
            let queue = DispatchQueue(label: "project.discovery", qos: .utility, attributes: .concurrent)
            
            for directory in watchedDirectories {
                group.enter()
                queue.async {
                    let foundPaths = self.scanDirectoryTwoLevels(directory)
                    
                    lock.lock()
                    projectPaths.append(contentsOf: foundPaths)
                    lock.unlock()
                    
                    group.leave()
                }
            }
            
            group.wait()
            
            // 去重
            return Array(Set(projectPaths))
        }
    }
    
    /// 扫描目录的两层结构
    private func scanDirectoryTwoLevels(_ path: String) -> [String] {
        var results: [String] = []
        
        guard FileManager.default.fileExists(atPath: path) else {
            return results
        }

        // 监视目录是容器，不是项目；只收录一级子目录
        // 扫描子目录
        do {
            let contents = try FileManager.default.contentsOfDirectory(atPath: path)
            for item in contents {
                guard ProjectDiscoveryPolicy.isEligibleChildDirectory(named: item) else {
                    continue
                }

                let itemPath = (path as NSString).appendingPathComponent(item)
                var isDirectory: ObjCBool = false
                
                if FileManager.default.fileExists(atPath: itemPath, isDirectory: &isDirectory),
                   isDirectory.boolValue {
                    results.append(itemPath)
                }
            }
        } catch {
            print("扫描目录失败 \(path): \(error)")
        }
        
        return results
    }
    
    /// 增量更新项目
    func updateProjectsIncremental(
        currentProjects: [UUID: Project],
        watchedDirectories: [String]
    ) -> [Project] {
        
        return PerformanceTimer.measure("Incremental project update") {
            // 1. 发现所有项目路径
            let allPaths = discoverProjectsSmart(from: watchedDirectories)
            
            // 2. 找出需要更新的路径
            let currentPaths = Set(currentProjects.values.map { $0.path })
            let newPaths = Set(allPaths)
            
            let addedPaths = Array(newPaths.subtracting(currentPaths))
            let removedPaths = Array(currentPaths.subtracting(newPaths))
            
            print("增量更新: 新增 \(addedPaths.count), 移除 \(removedPaths.count)")
            
            if addedPaths.isEmpty && removedPaths.isEmpty {
                return Array(currentProjects.values)
            }
            
            // 3. 创建新项目
            let newProjects = addedPaths.isEmpty ? [] : 
                createProjectsBatch(paths: addedPaths, existingProjects: currentProjects)
            
            // 4. 合并结果
            var updatedProjects = currentProjects
            
            // 移除已删除的项目
            for path in removedPaths {
                if let project = updatedProjects.values.first(where: { $0.path == path }) {
                    updatedProjects.removeValue(forKey: project.id)
                }
            }
            
            // 添加新项目
            for project in newProjects {
                updatedProjects[project.id] = project
            }
            
            return Array(updatedProjects.values)
        }
    }
    
    /// 获取性能统计
    func getPerformanceStats() -> String {
        let cacheStats = cache.getCacheStats()
        return """
        📊 项目加载器性能统计:
        - 缓存条目: \(cacheStats.count)
        - 缓存命中率: \(String(format: "%.1f", cacheStats.hitRate * 100))%
        """
    }
}
