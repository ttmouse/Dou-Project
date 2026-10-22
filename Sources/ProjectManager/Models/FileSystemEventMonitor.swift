import CoreServices
import Foundation

/// 监听监视目录的文件系统事件，并将短时间内的多个事件合并成一次刷新。
final class FileSystemEventMonitor {
    private let queue = DispatchQueue(
        label: "com.projectmanager.filesystem-events",
        qos: .utility
    )
    private let debounceInterval: TimeInterval = 0.8
    private var stream: FSEventStreamRef?
    private var pendingPaths = Set<String>()
    private var debounceWorkItem: DispatchWorkItem?
    private var eventHandler: ((Set<String>) -> Void)?

    init(eventHandler: @escaping (Set<String>) -> Void) {
        self.eventHandler = eventHandler
    }

    deinit {
        stop()
    }

    func start(paths: Set<String>) {
        queue.async { [weak self] in
            guard let self = self else { return }
            self.stopOnQueue()

            let watchedPaths = Array(paths) as CFArray
            var context = FSEventStreamContext(
                version: 0,
                info: Unmanaged.passUnretained(self).toOpaque(),
                retain: nil,
                release: nil,
                copyDescription: nil
            )

            let callback: FSEventStreamCallback = { _, info, count, rawPaths, _, _ in
                guard let info = info, count > 0 else { return }
                let monitor = Unmanaged<FileSystemEventMonitor>
                    .fromOpaque(info)
                    .takeUnretainedValue()
                let paths = rawPaths.assumingMemoryBound(to: UnsafePointer<CChar>.self)
                var changedPaths = Set<String>()
                for index in 0..<count {
                    changedPaths.insert(String(cString: paths[index]))
                }
                monitor.enqueue(changedPaths)
            }

            guard let stream = FSEventStreamCreate(
                kCFAllocatorDefault,
                callback,
                &context,
                watchedPaths,
                FSEventStreamEventId(kFSEventStreamEventIdSinceNow),
                0.2,
                FSEventStreamCreateFlags(
                    kFSEventStreamCreateFlagFileEvents | kFSEventStreamCreateFlagNoDefer
                )
            ) else {
                return
            }

            self.stream = stream
            FSEventStreamSetDispatchQueue(stream, self.queue)
            FSEventStreamStart(stream)
        }
    }

    func stop() {
        queue.sync {
            stopOnQueue()
        }
    }

    private func stopOnQueue() {
        debounceWorkItem?.cancel()
        debounceWorkItem = nil
        pendingPaths.removeAll()

        if let stream = stream {
            FSEventStreamStop(stream)
            FSEventStreamInvalidate(stream)
            FSEventStreamRelease(stream)
            self.stream = nil
        }
    }

    private func enqueue(_ paths: Set<String>) {
        queue.async { [weak self] in
            guard let self = self else { return }
            self.pendingPaths.formUnion(paths)
            self.debounceWorkItem?.cancel()

            let workItem = DispatchWorkItem { [weak self] in
                guard let self = self else { return }
                let changedPaths = self.pendingPaths
                self.pendingPaths.removeAll()
                guard !changedPaths.isEmpty else { return }
                self.eventHandler?(changedPaths)
            }
            self.debounceWorkItem = workItem
            self.queue.asyncAfter(deadline: .now() + self.debounceInterval, execute: workItem)
        }
    }
}
