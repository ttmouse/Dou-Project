import Foundation

/// 子进程输出读取顺序的唯一实现：先把 stdout/stderr 排空，再等进程退出。
///
/// 管道缓冲区只有 64KB。子进程写满后会在 write() 上阻塞，父进程若先
/// `waitUntilExit()` 就永远等不到退出，形同死锁 —— `git status/diff` 在大仓库、
/// `lsof` 在大量连接上都会踩到（性能审计后续 #5，对齐 GitDailyCollector.runGit）。
/// 两路管道必须并发读取：只读一路时，另一路写满同样会把子进程卡住。
enum ProcessPipeDrain {

    struct Result {
        let standardOutput: Data
        let standardError: Data
        let terminationStatus: Int32
    }

    /// 运行子进程并收集全部输出。launch 失败时抛错，由调用方保留各自的错误文案。
    static func run(
        executable: URL,
        arguments: [String],
        currentDirectoryURL: URL? = nil
    ) throws -> Result {
        let process = Process()
        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()

        process.executableURL = executable
        process.arguments = arguments
        process.currentDirectoryURL = currentDirectoryURL
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        try process.run()

        let collector = OutputCollector()
        let group = DispatchGroup()
        for (index, handle) in [stdoutPipe.fileHandleForReading, stderrPipe.fileHandleForReading].enumerated() {
            group.enter()
            DispatchQueue.global(qos: .userInitiated).async {
                collector.store(handle.readDataToEndOfFile(), at: index)
                group.leave()
            }
        }

        // readDataToEndOfFile 在写端全部关闭（即进程退出）时返回，此时再等退出是即时的。
        group.wait()
        process.waitUntilExit()

        return Result(
            standardOutput: collector.data(at: 0),
            standardError: collector.data(at: 1),
            terminationStatus: process.terminationStatus
        )
    }

    /// 两个读取线程各自写一个槽位，用锁隔开，避免依赖调用线程的隔离域。
    private final class OutputCollector: @unchecked Sendable {
        private let lock = NSLock()
        private var storage: [Int: Data] = [:]

        func store(_ data: Data, at index: Int) {
            lock.lock()
            storage[index] = data
            lock.unlock()
        }

        func data(at index: Int) -> Data {
            lock.lock()
            defer { lock.unlock() }
            return storage[index] ?? Data()
        }
    }
}
