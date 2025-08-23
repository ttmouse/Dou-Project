import Foundation

/// Linus式性能监控工具
/// 
/// 核心思想：
/// 1. "Measure, don't guess" - 测量，不要猜测
/// 2. "Performance matters" - 性能至关重要
/// 3. "Profile the slow stuff" - 找出慢的部分
struct PerformanceTimer {
    
    /// 测量代码块执行时间
    /// - Parameters:
    ///   - operation: 操作描述
    ///   - threshold: 警告阈值（秒），超过此值会打印警告
    ///   - block: 要测量的代码块
    /// - Returns: 代码块的返回值
    static func measure<T>(
        _ operation: String,
        threshold: Double = 0.1,
        block: () throws -> T
    ) rethrows -> T {
        let start = CFAbsoluteTimeGetCurrent()
        let result = try block()
        let time = CFAbsoluteTimeGetCurrent() - start
        
        if time > threshold {
            let emoji = time > 1.0 ? "🐌" : "⚠️"
            print("\(emoji) SLOW: \(operation) took \(String(format: "%.3f", time))s")
        } else if time > 0.01 {
            print("⏱️  \(operation) took \(String(format: "%.3f", time))s")
        }
        
        return result
    }
    
    /// 异步版本的性能测量
    static func measureAsync<T>(
        _ operation: String,
        threshold: Double = 0.1,
        block: () async throws -> T
    ) async rethrows -> T {
        let start = CFAbsoluteTimeGetCurrent()
        let result = try await block()
        let time = CFAbsoluteTimeGetCurrent() - start
        
        if time > threshold {
            let emoji = time > 1.0 ? "🐌" : "⚠️"
            print("\(emoji) ASYNC SLOW: \(operation) took \(String(format: "%.3f", time))s")
        } else if time > 0.01 {
            print("⏱️  ASYNC: \(operation) took \(String(format: "%.3f", time))s")
        }
        
        return result
    }
    
    /// 批量操作性能统计
    static func measureBatch<T>(
        _ operation: String,
        items: [T],
        threshold: Double = 0.001,
        block: (T) throws -> Void
    ) rethrows {
        let start = CFAbsoluteTimeGetCurrent()
        var slowItems = 0
        
        for item in items {
            let itemStart = CFAbsoluteTimeGetCurrent()
            try block(item)
            let itemTime = CFAbsoluteTimeGetCurrent() - itemStart
            
            if itemTime > threshold {
                slowItems += 1
            }
        }
        
        let totalTime = CFAbsoluteTimeGetCurrent() - start
        let averageTime = totalTime / Double(items.count)
        
        print("📊 BATCH: \(operation)")
        print("   - Total: \(String(format: "%.3f", totalTime))s")
        print("   - Items: \(items.count)")
        print("   - Average: \(String(format: "%.4f", averageTime))s/item")
        print("   - Slow items: \(slowItems)/\(items.count)")
    }
    
    /// 内存使用监控
    static func logMemoryUsage(_ context: String) {
        var info = mach_task_basic_info()
        var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size)/4
        
        let result: kern_return_t = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: 1) {
                task_info(mach_task_self_,
                         task_flavor_t(MACH_TASK_BASIC_INFO),
                         $0,
                         &count)
            }
        }
        
        if result == KERN_SUCCESS {
            let usedMemoryMB = Double(info.resident_size) / (1024 * 1024)
            print("💾 MEMORY: \(context) - \(String(format: "%.1f", usedMemoryMB)) MB")
        }
    }
    
    /// 性能基准测试
    static func benchmark<T>(
        _ operation: String,
        iterations: Int = 1000,
        block: () throws -> T
    ) rethrows -> (average: Double, min: Double, max: Double) {
        var times: [Double] = []
        times.reserveCapacity(iterations)
        
        print("🏁 BENCHMARK: Starting \(operation) with \(iterations) iterations...")
        
        for _ in 0..<iterations {
            let start = CFAbsoluteTimeGetCurrent()
            _ = try block()
            let time = CFAbsoluteTimeGetCurrent() - start
            times.append(time)
        }
        
        let average = times.reduce(0, +) / Double(iterations)
        let min = times.min() ?? 0
        let max = times.max() ?? 0
        
        print("📈 BENCHMARK RESULTS: \(operation)")
        print("   - Average: \(String(format: "%.6f", average))s")
        print("   - Min: \(String(format: "%.6f", min))s") 
        print("   - Max: \(String(format: "%.6f", max))s")
        
        return (average, min, max)
    }
}

/// 性能计数器 - 用于累积统计
class PerformanceCounter {
    private var counts: [String: Int] = [:]
    private var times: [String: Double] = [:]
    private let lock = NSLock()
    
    func increment(_ key: String, time: Double = 0) {
        lock.lock()
        defer { lock.unlock() }
        
        counts[key] = (counts[key] ?? 0) + 1
        times[key] = (times[key] ?? 0) + time
    }
    
    func report() {
        lock.lock()
        defer { lock.unlock() }
        
        print("📊 PERFORMANCE COUNTER REPORT:")
        for key in counts.keys.sorted() {
            let count = counts[key] ?? 0
            let totalTime = times[key] ?? 0
            let avgTime = count > 0 ? totalTime / Double(count) : 0
            
            print("   - \(key): \(count) calls, total \(String(format: "%.3f", totalTime))s, avg \(String(format: "%.4f", avgTime))s")
        }
    }
    
    func reset() {
        lock.lock()
        defer { lock.unlock() }
        
        counts.removeAll()
        times.removeAll()
    }
}

/// 全局性能计数器实例
let globalPerformanceCounter = PerformanceCounter()