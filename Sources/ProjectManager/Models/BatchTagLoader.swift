import Foundation

/// 批量标签加载器 - Linus式高性能批量处理
///
/// 核心思想：
/// 1. "Don't be stupid" - 批量处理而不是逐个处理
/// 2. "Performance matters" - 并发加载，减少等待时间
/// 3. "Do one thing well" - 专门负责批量标签加载
class BatchTagLoader {
    private let cache = TagCache.shared
    private let batchSize = 50
    private let maxConcurrentOperations = 4
    
    /// 批量加载标签，返回路径到标签的映射
    func loadTagsBatch(paths: [String]) -> [String: Set<String>] {
        var results = [String: Set<String>]()
        let lock = NSLock()
        
        // 1. 先从缓存获取
        let (cachedResults, uncachedPaths) = getCachedAndUncachedPaths(paths)
        results.merge(cachedResults) { _, new in new }
        
        print("TagLoader: 缓存命中 \(cachedResults.count)/\(paths.count), 需要加载 \(uncachedPaths.count) 个")
        
        if uncachedPaths.isEmpty {
            return results
        }
        
        // 2. 并发批量加载未缓存的路径
        let chunks = uncachedPaths.chunked(into: batchSize)
        let dispatchGroup = DispatchGroup()
        let concurrentQueue = DispatchQueue(label: "batch.tag.loader", qos: .utility, attributes: .concurrent)
        let semaphore = DispatchSemaphore(value: maxConcurrentOperations)
        
        for chunk in chunks {
            dispatchGroup.enter()
            concurrentQueue.async {
                semaphore.wait() // 限制并发数
                defer { 
                    semaphore.signal()
                    dispatchGroup.leave() 
                }
                
                let chunkResults = self.loadTagsChunk(chunk)
                
                lock.lock()
                results.merge(chunkResults) { _, new in new }
                lock.unlock()
                
                // 批量更新缓存
                self.cache.setTagsBatch(chunkResults)
            }
        }
        
        dispatchGroup.wait()
        
        print("BatchTagLoader: 完成加载 \(results.count) 个项目的标签")
        return results
    }
    
    /// 获取缓存和未缓存的路径
    private func getCachedAndUncachedPaths(_ paths: [String]) -> (cached: [String: Set<String>], uncached: [String]) {
        var cached = [String: Set<String>]()
        var uncached = [String]()
        
        for path in paths {
            if let cachedTags = cache.getTags(for: path) {
                cached[path] = cachedTags
            } else {
                uncached.append(path)
            }
        }
        
        return (cached, uncached)
    }
    
    /// 加载一批路径的标签
    private func loadTagsChunk(_ paths: [String]) -> [String: Set<String>] {
        var results = [String: Set<String>]()
        
        for path in paths {
            let tags = TagSystemSyncOptimized.loadTagsFromFile(at: path)
            if !tags.isEmpty {
                results[path] = tags
            }
        }
        
        return results
    }
}

/// 优化版TagSystemSync - Linus式系统调用优化
///
/// 原则：
/// 1. "Minimize syscalls" - 最小化系统调用
/// 2. "Fail fast" - 快速失败，不浪费时间
/// 3. "Cache wisely" - 合理缓存
class TagSystemSyncOptimized {
    
    /// 优化版标签加载 - 一次性获取所有需要的资源值
    static func loadTagsFromFile(at path: String) -> Set<String> {
        let url = URL(fileURLWithPath: path)
        
        do {
            // 一次性获取所有需要的资源值，减少系统调用
            let resourceValues = try url.resourceValues(forKeys: [
                .tagNamesKey,
                .contentModificationDateKey,
                .fileSizeKey
            ])
            
            guard let systemTags = resourceValues.tagNames, !systemTags.isEmpty else {
                return []
            }
            
            // 内联标签标准化，避免额外的字典查找
            let standardizedTags = systemTags.map { standardizeTagInline($0) }
            return Set(standardizedTags)
            
        } catch {
            // Fail fast - 直接返回空集合
            return []
        }
    }
    
    /// 内联标签标准化 - 避免字典查找开销
    private static func standardizeTagInline(_ tag: String) -> String {
        let lowercased = tag.lowercased()
        
        // 使用 switch 而不是字典查找，编译器会优化为跳转表
        switch lowercased {
        case "green", "绿色":
            return "绿色"
        case "red", "红色":
            return "红色"
        case "orange", "橙色":
            return "橙色"
        case "yellow", "黄色":
            return "黄色"
        case "blue", "蓝色":
            return "蓝色"
        case "purple", "紫色":
            return "紫色"
        case "gray", "grey", "灰色":
            return "灰色"
        default:
            return tag
        }
    }
    
    /// 保存标签到文件 - 优化版本
    static func saveTagsToFile(_ tags: Set<String>, at path: String) {
        // 直接调用原来的TagSystemSync方法
        TagSystemSync.saveTagsToFile(tags, at: path)
    }
}