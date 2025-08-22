# ProjectManager 重构计划

## 概述

基于代码评审发现的架构问题，本文档提供一个分阶段的重构计划，以解决"大泥球"架构模式，提高代码质量和可维护性。

## 问题总结

### 架构债务
1. **单例反模式**: `TagManager.shared` 使用 weak 引用，可能随机释放
2. **上帝对象**: TagManager 承担过多职责（465行）
3. **循环依赖**: TagManager ↔ ProjectOperationManager 相互引用
4. **初始化器副作用**: 在 init 中执行异步 I/O 操作
5. **混合职责**: Project 结构体既是数据模型又处理业务逻辑
6. **全局可变状态**: 静态变量导致测试和并发问题
7. **缺乏抽象**: 直接依赖文件系统，难以测试

### 影响
- 代码难以测试
- 组件耦合过紧
- 错误处理不一致
- 并发安全问题
- 维护成本高

## 重构目标

### 架构目标
- **单一职责**: 每个类只有一个变更理由
- **依赖倒置**: 依赖抽象而非具体实现
- **接口隔离**: 提供最小必要的接口
- **开闭原则**: 对扩展开放，对修改关闭

### 质量目标
- **可测试性**: 100% 业务逻辑可单元测试
- **错误处理**: 一致的错误处理策略
- **线程安全**: 明确的并发模型
- **性能**: 保持现有性能特性

## 分阶段重构计划

### 阶段 1: 基础设施重构 (2-3周)

#### 1.1 定义核心抽象
```swift
// 领域模型
struct Project {
    let id: UUID
    let name: String
    let path: URL
    let lastModified: Date
    let tags: Set<String>
    let gitInfo: GitInfo?
    let fileSystemInfo: FileSystemInfo
}

// 仓储协议
protocol ProjectRepository {
    func loadProjects(from paths: [URL]) async throws -> [Project]
    func saveProject(_ project: Project) async throws
    func deleteProject(id: UUID) async throws
}

protocol TagRepository {
    func loadTags(for path: URL) async throws -> Set<String>
    func saveTags(_ tags: Set<String>, for path: URL) async throws
    func deleteTags(for path: URL) async throws
}

protocol DirectoryWatcher {
    func startWatching(paths: [URL]) async throws
    func stopWatching()
    var changes: AsyncStream<DirectoryChange> { get }
}
```

#### 1.2 错误处理系统
```swift
enum ProjectManagerError: Error {
    case pathNotFound(URL)
    case permissionDenied(URL)
    case corruptedMetadata(URL)
    case gitNotAvailable
    case tagSyncFailed(String)
    case cacheCorrupted
}

protocol ErrorHandler {
    func handle(_ error: ProjectManagerError) async
    func shouldRetry(_ error: ProjectManagerError) -> Bool
}
```

#### 1.3 配置系统
```swift
struct AppConfiguration {
    let cacheDirectory: URL
    let syncInterval: TimeInterval
    let supportedEditors: [EditorType]
    let tagTranslations: [String: String]
}

protocol ConfigurationProvider {
    func loadConfiguration() async throws -> AppConfiguration
}
```

### 阶段 2: 服务层重构 (3-4周)

#### 2.1 项目服务
```swift
protocol ProjectService {
    func loadProjects(from directories: [URL]) async throws -> [Project]
    func updateProject(_ project: Project) async throws
    func searchProjects(query: String, tags: Set<String>) async -> [Project]
    func refreshProject(at path: URL) async throws -> Project?
}

class DefaultProjectService: ProjectService {
    private let repository: ProjectRepository
    private let gitService: GitService
    private let fileSystemService: FileSystemService
    private let cache: ProjectCache
    
    init(
        repository: ProjectRepository,
        gitService: GitService,
        fileSystemService: FileSystemService,
        cache: ProjectCache
    ) {
        self.repository = repository
        self.gitService = gitService
        self.fileSystemService = fileSystemService
        self.cache = cache
    }
}
```

#### 2.2 标签服务
```swift
protocol TagService {
    func loadTags(for project: Project) async throws -> Set<String>
    func saveTags(_ tags: Set<String>, for project: Project) async throws
    func getAllTags() async -> Set<String>
    func getTagColors() async -> [String: Color]
    func updateTagColor(_ tag: String, color: Color) async throws
}

class DefaultTagService: TagService {
    private let repository: TagRepository
    private let systemSync: TagSystemSync
    private let colorManager: TagColorManager
    
    // 实现去抖保存
    private let saveDebouncer = Debouncer(delay: 1.0)
}
```

#### 2.3 目录监控服务
```swift
protocol DirectoryMonitoringService {
    func startMonitoring(directories: [URL]) async throws
    func stopMonitoring()
    var projectChanges: AsyncStream<ProjectChange> { get }
}

class DefaultDirectoryMonitoringService: DirectoryMonitoringService {
    private let watcher: DirectoryWatcher
    private let projectService: ProjectService
    private let changeProcessor: ChangeProcessor
}
```

### 阶段 3: 应用状态管理 (2-3周)

#### 3.1 应用状态
```swift
@MainActor
class AppState: ObservableObject {
    @Published var projects: [Project] = []
    @Published var filteredProjects: [Project] = []
    @Published var selectedTags: Set<String> = []
    @Published var searchQuery: String = ""
    @Published var isLoading: Bool = false
    @Published var error: ProjectManagerError?
    
    private let projectService: ProjectService
    private let tagService: TagService
    private let directoryService: DirectoryMonitoringService
    
    init(
        projectService: ProjectService,
        tagService: TagService,
        directoryService: DirectoryMonitoringService
    ) {
        self.projectService = projectService
        self.tagService = tagService
        self.directoryService = directoryService
        
        setupMonitoring()
    }
}
```

#### 3.2 依赖注入容器
```swift
class DIContainer {
    private var services: [String: Any] = [:]
    
    func register<T>(_ type: T.Type, instance: T) {
        services[String(describing: type)] = instance
    }
    
    func resolve<T>(_ type: T.Type) -> T {
        guard let service = services[String(describing: type)] as? T else {
            fatalError("Service not registered: \(type)")
        }
        return service
    }
}

extension DIContainer {
    static func createDefault() -> DIContainer {
        let container = DIContainer()
        
        // 注册核心服务
        let fileSystemRepo = FileSystemProjectRepository()
        let tagRepo = MacOSTagRepository()
        let gitService = DefaultGitService()
        
        container.register(ProjectRepository.self, instance: fileSystemRepo)
        container.register(TagRepository.self, instance: tagRepo)
        container.register(GitService.self, instance: gitService)
        
        // 注册应用服务
        let projectService = DefaultProjectService(
            repository: container.resolve(ProjectRepository.self),
            gitService: container.resolve(GitService.self),
            fileSystemService: DefaultFileSystemService(),
            cache: InMemoryProjectCache()
        )
        container.register(ProjectService.self, instance: projectService)
        
        return container
    }
}
```

### 阶段 4: UI 层重构 (2-3周)

#### 4.1 视图模型模式
```swift
@MainActor
class ProjectListViewModel: ObservableObject {
    @Published var projects: [Project] = []
    @Published var isLoading = false
    @Published var error: ProjectManagerError?
    
    private let projectService: ProjectService
    private let tagService: TagService
    
    init(projectService: ProjectService, tagService: TagService) {
        self.projectService = projectService
        self.tagService = tagService
    }
    
    func loadProjects() async {
        isLoading = true
        defer { isLoading = false }
        
        do {
            projects = try await projectService.loadProjects(from: watchedDirectories)
        } catch {
            self.error = error as? ProjectManagerError
        }
    }
}
```

#### 4.2 视图依赖注入
```swift
struct ProjectManagerApp: App {
    private let container = DIContainer.createDefault()
    
    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(container.resolve(AppState.self))
                .environmentObject(container.resolve(ProjectService.self))
                .environmentObject(container.resolve(TagService.self))
        }
    }
}
```

### 阶段 5: 测试基础设施 (1-2周)

#### 5.1 模拟实现
```swift
class MockProjectRepository: ProjectRepository {
    var projects: [Project] = []
    var shouldThrowError = false
    
    func loadProjects(from paths: [URL]) async throws -> [Project] {
        if shouldThrowError {
            throw ProjectManagerError.pathNotFound(paths.first!)
        }
        return projects
    }
}

class MockTagRepository: TagRepository {
    var tags: [URL: Set<String>] = [:]
    
    func loadTags(for path: URL) async throws -> Set<String> {
        return tags[path] ?? []
    }
}
```

#### 5.2 测试工具
```swift
class TestContainer {
    static func create() -> DIContainer {
        let container = DIContainer()
        
        container.register(ProjectRepository.self, instance: MockProjectRepository())
        container.register(TagRepository.self, instance: MockTagRepository())
        
        return container
    }
}
```

## 实施策略

### 渐进式重构
1. **保持功能**: 每个阶段都要保持应用可运行
2. **并行开发**: 新架构与旧代码并存
3. **特性切换**: 使用特性开关逐步迁移
4. **回滚计划**: 每个阶段都有回滚策略

### 迁移步骤
1. **第一步**: 创建新的抽象接口，旧代码实现接口
2. **第二步**: 创建新的服务实现
3. **第三步**: 逐步替换旧的直接调用
4. **第四步**: 删除旧代码

### 风险缓解
- **标签系统**: 特别小心，先在副本上测试
- **数据迁移**: 提供迁移脚本和验证工具
- **性能监控**: 监控重构对性能的影响
- **用户测试**: 每个阶段都进行用户验收测试

## 成功指标

### 代码质量
- [ ] 单元测试覆盖率 > 80%
- [ ] 集成测试覆盖率 > 60%
- [ ] 代码复杂度 < 10 (平均)
- [ ] 依赖循环 = 0

### 架构质量
- [ ] 单一职责原则违规 = 0
- [ ] 单例模式使用 = 0 (除了真正需要的)
- [ ] 全局可变状态 = 0
- [ ] 抽象层级清晰

### 性能
- [ ] 启动时间 ≤ 当前
- [ ] 项目加载时间 ≤ 当前
- [ ] 内存使用 ≤ 当前 + 10%
- [ ] UI 响应时间 ≤ 当前

## 资源估算

### 开发时间
- **总工期**: 10-13周
- **开发人员**: 1-2人
- **测试时间**: 30% 额外时间

### 风险时间
- **学习曲线**: 1周
- **意外问题**: 2-3周
- **集成问题**: 1-2周

### 推荐的实施顺序
1. **阶段1 + 阶段5**: 建立基础设施和测试框架
2. **阶段2**: 实现核心服务
3. **阶段3**: 重构状态管理
4. **阶段4**: 更新UI层

## 结论

这个重构计划虽然工期较长，但会显著改善代码质量和可维护性。通过分阶段实施和渐进式迁移，可以最小化风险并保持产品稳定性。

重构完成后，代码将具有：
- 清晰的架构边界
- 高度的可测试性
- 强大的错误处理
- 良好的扩展性
- 更好的性能监控能力

这项投资将为未来的功能开发和维护节省大量时间和成本。