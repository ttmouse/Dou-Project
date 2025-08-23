import Foundation

/// 标签缓存系统 - Linus式高性能缓存
/// 
/// 设计原则：
/// 1. "Don't be stupid" - 避免重复的系统调用
/// 2. "Cache everything sensibly" - 基于文件修改时间的智能缓存
/// 3. "Keep it simple" - 简单直接的API
class TagCache {
    static let shared = TagCache()
    
    private struct CacheEntry {
        let tags: Set<String>
        let mtime: Date
        let fileSize: UInt64
        let cacheTime: Date
        
        init(tags: Set<String>, mtime: Date, fileSize: UInt64) {
            self.tags = tags
            self.mtime = mtime
            self.fileSize = fileSize
            self.cacheTime = Date()
        }
    }
    
    private var cache = [String: CacheEntry]()
    private let lock = NSLock()
    private let maxCacheAge: TimeInterval = 3600 // 1小时最大缓存时间
    
    private init() {
        // 启动缓存清理定时器
        startCacheCleanupTimer()
    }
    
    /// 获取缓存的标签，如果缓存失效返回nil
    func getTags(for path: String) -> Set<String>? {
        lock.lock()
        defer { lock.unlock() }
        
        guard let cached = cache[path] else {
            return nil
        }
        
        // 检查缓存是否过期
        if Date().timeIntervalSince(cached.cacheTime) > maxCacheAge {
            cache.removeValue(forKey: path)
            return nil
        }
        
        // 检查文件是否被修改
        if let currentInfo = getFileInfo(path: path) {
            if currentInfo.mtime <= cached.mtime && currentInfo.fileSize == cached.fileSize {
                return cached.tags // 缓存有效
            }
            
            // 文件已修改，移除缓存
            cache.removeValue(forKey: path)
        }
        
        return nil
    }
    
    /// 设置标签到缓存
    func setTags(_ tags: Set<String>, for path: String) {
        guard let fileInfo = getFileInfo(path: path) else { return }
        
        lock.lock()
        defer { lock.unlock() }
        
        cache[path] = CacheEntry(
            tags: tags,
            mtime: fileInfo.mtime,
            fileSize: fileInfo.fileSize
        )
    }
    
    /// 批量设置标签到缓存
    func setTagsBatch(_ tagMap: [String: Set<String>]) {
        lock.lock()
        defer { lock.unlock() }
        
        for (path, tags) in tagMap {
            if let fileInfo = getFileInfo(path: path) {
                cache[path] = CacheEntry(
                    tags: tags,
                    mtime: fileInfo.mtime,
                    fileSize: fileInfo.fileSize
                )
            }
        }
    }
    
    /// 获取文件信息（修改时间和大小）
    private func getFileInfo(path: String) -> (mtime: Date, fileSize: UInt64)? {
        do {
            let attrs = try FileManager.default.attributesOfItem(atPath: path)
            let mtime = attrs[.modificationDate] as? Date ?? Date()
            let fileSize = (attrs[.size] as? NSNumber)?.uint64Value ?? 0
            return (mtime, fileSize)
        } catch {
            return nil
        }
    }
    
    /// 清除缓存
    func clearCache() {
        lock.lock()
        defer { lock.unlock() }
        cache.removeAll()
    }
    
    /// 获取缓存统计信息
    func getCacheStats() -> (count: Int, hitRate: Double) {
        lock.lock()
        defer { lock.unlock() }
        return (cache.count, 0.0) // 简化版本，后续可扩展统计功能
    }
    
    /// 启动缓存清理定时器
    private func startCacheCleanupTimer() {
        Timer.scheduledTimer(withTimeInterval: 1800, repeats: true) { [weak self] _ in
            self?.cleanupExpiredEntries()
        }
    }
    
    /// 清理过期缓存条目
    private func cleanupExpiredEntries() {
        lock.lock()
        defer { lock.unlock() }
        
        let now = Date()
        let expiredKeys = cache.compactMap { (key, value) in
            now.timeIntervalSince(value.cacheTime) > maxCacheAge ? key : nil
        }
        
        for key in expiredKeys {
            cache.removeValue(forKey: key)
        }
        
        if !expiredKeys.isEmpty {
            print("TagCache: 清理了 \(expiredKeys.count) 个过期缓存条目")
        }
    }
}

/// 数组分块扩展
extension Array {
    func chunked(into size: Int) -> [[Element]] {
        return stride(from: 0, to: count, by: size).map {
            Array(self[$0..<Swift.min($0 + size, count)])
        }
    }
}