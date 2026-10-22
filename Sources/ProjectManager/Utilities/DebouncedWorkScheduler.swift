import Foundation

/// 与 RunLoop 无关的合并触发调度器（防抖）。
///
/// 背景：两处防抖保存原先都用 `Timer.scheduledTimer`，而它挂在「调用线程」的
/// RunLoop 上。生产路径多数在主线程序列里调用，所以碰巧能跑；一旦从后台队列
/// （目录扫描、Git 回填、测试夹具）触发，那个线程没有 RunLoop 在跑，回调
/// 永远不会来 —— 保存被静默丢掉，还留下一个永远不会清的待写状态。
///
/// 这里用串行队列 + `DispatchWorkItem` 实现同样的「静默 N 秒后执行一次」：
/// 任意线程都能安全调用，重复调用只保留最后一次，取消是幂等的。
final class DebouncedWorkScheduler {

    private let queue: DispatchQueue
    private let lock = NSLock()
    private var pending: DispatchWorkItem?
    private var generation: UInt64 = 0

    init(label: String) {
        queue = DispatchQueue(label: label, qos: .utility)
    }

    /// 是否还有未触发的任务。诊断与测试用，调用方不需要关心。
    var hasPendingWork: Bool {
        lock.lock()
        defer { lock.unlock() }
        return pending != nil
    }

    /// 约在 `delay` 秒后执行 `work`。前一次尚未触发的调用会被丢弃。
    func schedule(after delay: TimeInterval, _ work: @escaping () -> Void) {
        lock.lock()
        pending?.cancel()
        generation &+= 1
        let token = generation
        let item = DispatchWorkItem { [weak self] in
            guard let self = self else { return }
            self.lock.lock()
            // 只有仍是最新一次调度才执行：被替换的旧任务直接退出，
            // 避免取消与触发之间的竞态造成重复写盘。
            guard self.generation == token else {
                self.lock.unlock()
                return
            }
            self.pending = nil
            self.lock.unlock()
            work()
        }
        pending = item
        lock.unlock()

        queue.asyncAfter(deadline: .now() + delay, execute: item)
    }

    /// 丢弃尚未触发的任务。已开始执行的任务不受影响。
    func cancel() {
        lock.lock()
        pending?.cancel()
        pending = nil
        generation &+= 1
        lock.unlock()
    }

    deinit {
        pending?.cancel()
    }
}
