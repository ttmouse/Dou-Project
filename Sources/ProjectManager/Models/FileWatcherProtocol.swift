import SwiftUI
import Combine

// MARK: - FileWatcher协议 - 统一文件监视接口
protocol FileWatcher: ObservableObject {
    var watchedDirectories: Set<String> { get }
    
    func loadWatchedDirectories()
    func addWatchedDirectory(_ path: String)
    func removeWatchedDirectory(_ path: String)
    func saveWatchedDirectories()
    func clearCacheAndReloadProjects()
    func incrementallyReloadProjects()
}

// MARK: - DirectoryWatcher协议包装器
class DirectoryWatcherAdapter: FileWatcher, ObservableObject {
    
    @Published private(set) var watchedDirectories: Set<String> = []
    
    private let directoryWatcher: DirectoryWatcher
    private var cancellables = Set<AnyCancellable>()
    
    init(directoryWatcher: DirectoryWatcher) {
        self.directoryWatcher = directoryWatcher
        
        // 监听delegate的变化来更新watchedDirectories
        setupObservers()
    }
    
    private func setupObservers() {
        // 由于DirectoryWatcher使用delegate模式，我们需要手动同步状态
        // 这里可以通过观察者模式或通知来实现状态同步
    }
    
    // MARK: - FileWatcher协议实现
    func loadWatchedDirectories() {
        directoryWatcher.loadWatchedDirectories()
        syncWatchedDirectories()
    }
    
    func addWatchedDirectory(_ path: String) {
        directoryWatcher.addWatchedDirectory(path)
        watchedDirectories.insert(path)
    }
    
    func removeWatchedDirectory(_ path: String) {
        directoryWatcher.removeWatchedDirectory(path)
        watchedDirectories.remove(path)
    }
    
    func saveWatchedDirectories() {
        directoryWatcher.saveWatchedDirectories()
    }
    
    func clearCacheAndReloadProjects() {
        directoryWatcher.clearCacheAndReloadProjects()
    }
    
    func incrementallyReloadProjects() {
        directoryWatcher.incrementallyReloadProjects()
    }
    
    // 同步监视目录状态
    private func syncWatchedDirectories() {
        if let delegate = directoryWatcher.delegate {
            watchedDirectories = delegate.watchedDirectories
        }
    }
}