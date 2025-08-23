# CLAUDE.md

本文档为 Claude Code (claude.ai/code) 在此代码仓库中工作时提供指导。

## 项目概述

ProjectManager（项目管理器）是一个 macOS SwiftUI 应用程序，用于管理开发项目。它提供项目发现、标签管理、目录监控，并集成了各种编辑器，如 Cursor、VSCode 和 Trae AI。

## 构建和开发命令

### 主要构建命令
```bash
# 快速构建和打包
./build.sh

# 手动构建流程
swift build -c release

# 版本管理
./scripts/increment_version.sh [patch|minor|major]
```

### 图标生成
```bash
# 从 icon.png 生成应用图标（如果存在）
./make_icon.sh
```

### 包结构
- **平台**: macOS 12+
- **Swift 工具版本**: 5.7
- **目标**: 带捆绑资源的可执行文件
- **依赖**: 无（仅使用系统框架）

## 架构概述

### 当前架构（重构后）

代码库经过大幅重构，遵循清洁架构原则，职责分离清晰：

1. **核心数据模型**
   - `Project.swift` - 带 Git 集成的核心项目数据结构
   - `ProjectData.swift` - 业务逻辑层的纯数据表示

2. **业务逻辑层（纯函数）**
   - `BusinessLogic.swift` - 包含 `ProjectLogic` 和 `TagLogic` 枚举及纯函数
   - 所有业务操作都是无状态且无副作用的
   - 便于测试和代码推理

3. **管理器组件（单一职责）**
   - `TagManager.swift` - 中央协调器（相比之前版本已简化）
   - `TagManagerComponents.swift` - 包含 4 个专注的组件：
     - `ProjectSortManager` - 二分搜索优化的排序
     - `ProjectOperationManager` - 带批处理的项目 CRUD 操作
     - `DirectoryWatcher` - 带增量更新的文件系统监控
     - 依赖注入的协议定义

4. **视图模型层**
   - `ViewModels.swift` - MVVM 模式实现
   - 将 UI 状态与业务逻辑分离
   - 与 SwiftUI 视图的清洁数据绑定

5. **UI 架构**
   - **ProjectListView**: 带 HSplitView 布局的主界面
   - **SidebarView**: 标签过滤和目录管理
   - **MainContentView**: 带搜索和排序的项目网格
   - **ProjectCard**: 带上下文菜单的单个项目显示

### 标签系统集成 - ⚠️ **关键系统**

**警告**: 标签系统直接与 macOS 文件系统元数据集成：
- 使用 `com.apple.metadata:_kMDItemUserTags` 进行持久标签存储
- **数据安全**: 标签操作必须是原子的且经过仔细测试
- **风险**: 重新加载或刷新操作可能导致标签信息丢失
- 修改前务必备份项目标签数据

### 数据流

1. **启动**: 加载缓存项目 → 立即显示 → 后台刷新
2. **项目变更**: 增量检测 → 缓存更新 → 通过 ViewModels 刷新 UI
3. **标签操作**: UI 操作 → BusinessLogic → TagManager → 系统同步 → 缓存保存
4. **搜索/过滤**: BusinessLogic 中的纯函数处理缓存数据

### 文件系统集成

- **标签存储**: macOS 扩展属性（`xattr`）
- **项目缓存**: Application Support 中的 JSON 文件
- **偏好设置**: UserDefaults + 自定义编辑器设置
- **Git 集成**: 基于进程的 git 命令执行

### 编辑器集成

应用支持多个编辑器，具有智能回退机制：
1. **支持的编辑器**: Cursor（默认）、Visual Studio Code、Trae AI、自定义编辑器
2. **检测**: 自动检测，带可视化指示器（绿色 ✓ = 可用，橙色 ⚠ = 缺失）
3. **打开策略**:
   - 首先尝试命令行工具（`cursor`、`code`、`trae`）
   - 回退到直接应用启动
   - 最终回退到 macOS `open` 命令

## 开发指南

### 代码风格（来自 .cursorrules）
- **专注于 SwiftUI 最佳实践** - 使用最新的 SwiftUI 和 Swift 功能
- **可读性优于性能** - 优先考虑清晰、可读的代码
- **完整实现** - 不允许 TODO、占位符或缺失部分
- **分步规划** - 实现前先思考伪代码

### 🔥 重构核心原则（关键）
**重构此项目中任何代码时：**
1. **UI功能完整性** - 所有现有的UI交互功能必须100%保留
2. **零功能丢失** - 用户能做的每一个操作都必须在重构后继续可用
3. **向后兼容** - 用户数据、偏好设置、标签等必须完全兼容
4. **渐进式重构** - 重构必须是增量的，不能破坏现有功能
5. **测试验证** - 每个重构步骤都要验证功能完整性

### 标签系统安全（⚠️ 关键）
修改标签相关代码时：
1. **首先阅读 README.md 中的标签系统警告**
2. 仅在备份数据上测试
3. 验证应用重启后的标签持久性
4. 检查 `TagSystemSync.swift` 的实现细节
5. 确保标签保存/加载的原子操作
6. 测试标签在以下场景的持久性：应用重启、项目重新加载、系统重启

### 架构原则
- **纯函数**: `BusinessLogic.swift` 中的业务逻辑必须保持无状态
- **单一职责**: 每个管理器组件都有明确的单一目的
- **依赖注入**: 使用协议打破循环依赖
- **性能优化**: 
  - 排序插入使用二分搜索
  - 批量操作最小化 I/O
  - 增量更新避免 UI 阻塞
  - 防抖保存（1秒延迟）

### 需要了解的关键文件
- `Sources/ProjectManager/Models/TagSystemSync.swift` - 标签系统集成
- `Sources/ProjectManager/Models/BusinessLogic.swift` - 纯业务逻辑函数
- `Sources/ProjectManager/Models/TagManagerComponents.swift` - 核心管理器组件
- `Sources/ProjectManager/Models/Project.swift` - 核心项目模型
- `Sources/ProjectManager/ViewModels/ViewModels.swift` - MVVM 层
- `Sources/ProjectManager/ProjectManagerApp.swift` - 应用生命周期和偏好设置

### 性能考虑
- 项目加载使用增量更新避免 UI 阻塞
- 标签操作使用防抖（1秒延迟保存）
- 文件系统检查针对性能进行了优化
- 使用二分搜索维护排序项目列表
- 批量操作防止过度 I/O 操作

### 已知问题（来自 README.md TODO）
- 文件修改时间可能不会正确更新，影响基于时间的排序
- 嵌套监视目录的目录监控可能需要优化

## 常见开发任务

### 添加新编辑器支持
1. 在 `AppOpenHelper.swift` 中更新新编辑器检测逻辑
2. 在偏好设置系统中添加命令行工具映射
3. 实现回退应用启动机制
4. 测试编辑器可用性检测和可视化指示器

### 修改项目发现
1. 审查 `ProjectIndex.swift` 中的扫描逻辑
2. 考虑 `DirectoryWatcher` 中的缓存失效
3. 测试 `ProjectOperationManager` 中的增量更新行为
4. 验证项目去重逻辑

### 标签系统变更（⚠️ 高风险）
1. **必须**: 审查 README.md 中关于数据丢失风险的警告
2. 首先在备份项目数据上测试
3. 验证 `TagSystemSync.swift` 中的系统标签同步
4. 检查跨会话持久性
5. 仔细测试批量操作
6. 确保操作是原子的

### 添加业务逻辑
1. 在 `BusinessLogic.swift` 的适当枚举中添加纯函数
2. 确保函数无状态且无副作用
3. 为纯函数编写对应的测试
4. 更新 ViewModels 以使用新的业务逻辑函数

## 文件结构
```
Sources/ProjectManager/
├── Models/
│   ├── TagManager.swift              # 中央协调器
│   ├── TagManagerComponents.swift    # 核心管理器组件
│   ├── BusinessLogic.swift          # 纯业务逻辑函数
│   ├── Project.swift               # 核心项目模型
│   ├── TagSystemSync.swift         # macOS 标签系统集成
│   └── ProjectIndex.swift          # 项目发现和缓存
├── ViewModels/
│   └── ViewModels.swift            # UI 状态的 MVVM 层
├── Views/
│   ├── ProjectListView.swift       # 主应用视图
│   ├── Components/
│   │   ├── SidebarView.swift      # 标签过滤和目录
│   │   └── MainContentView.swift   # 项目网格显示
│   └── ProjectCard.swift          # 单个项目显示
├── Utilities/
│   └── AppOpenHelper.swift        # 编辑器集成
├── Theme/
│   └── AppTheme.swift             # UI 样式常量
└── Resources/                     # 资源和配置文件

build.sh                          # 主要构建脚本
scripts/                          # 版本管理和构建工具
```

此应用程序与 macOS 文件系统功能深度集成，在进行修改时需要仔细考虑数据持久性和系统集成。最近的重构显著改善了代码组织，在数据、业务逻辑和表示层之间实现了清晰的分离。