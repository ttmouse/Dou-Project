# AGENTS.md: ProjectManager 开发者指导原则

本文件为在 ProjectManager macOS SwiftUI 应用程序上工作的 AI 编码代理提供权威指导原则。请严格遵守这些说明，以保持代码质量、架构完整性和开发效率。

## 1. 项目概览
ProjectManager 是一个基于 SwiftUI 的 macOS 应用程序，用于项目管理、目录监控和编辑器集成。它采用简洁架构（Clean Architecture），并明确区分模型（Models）、视图模型（ViewModels）、视图（Views）和专用管理器（Managers）。

## 2. 命令参考

### 构建
- **构建发布版:** `swift build -c release`
- **构建脚本:** `./build.sh`
- **体验交付:** 当改动完成后需要用户亲自体验或验收时，构建可运行版本并安装或更新到 `/Applications/ProjectManager.app`，再告知用户如何启动和体验。

### 测试
- **运行所有测试:** `swift test`
- **运行特定测试:** `swift test --filter <TestName>`
  - 示例: `swift test --filter TagManagerTests`
- **确保测试覆盖率:** 在创建新功能之前，务必检查 `Tests/ProjectManagerTests/` 中是否存在相关测试。

### 版本控制
- **增加版本号:** `./scripts/increment_version.sh [patch|minor|major]`

## 3. 代码风格与架构

### 架构原则
- **简洁架构 (Clean Architecture):** 严格遵守关注点分离原则。
  - **模型 (Models):** 纯数据结构。
  - **业务逻辑 (Business Logic):** 纯函数（无状态、无副作用）。
  - **管理器 (Managers):** 单一职责组件（例如 `TagManager`、`ProjectSortManager`）。
  - **视图模型 (ViewModels):** 用于 UI 数据绑定的 MVVM 模式实现。
  - **视图 (Views):** 基于 SwiftUI 的组件，使用现有的 UI 模式。
- **依赖注入:** 为管理器依赖使用协议，以便于测试和模块化。
- **性能:**
  - 最小化 I/O 操作（使用批处理）。
  - 使用二分查找进行排序（如 `ProjectSortManager` 中所实现）。
  - 使用防抖（Debounce）处理文件系统/偏好设置写入（通常为 1 秒）。
  - 避免阻塞主线程进行繁重的处理。

### 编码风格 (Swift/SwiftUI)
- 使用最新的 Swift/SwiftUI 特性 (Swift 5.7+)。
- **可读性 > 性能:** 代码必须清晰且易于维护。
- **禁止占位符:** 代码必须是生产就绪的。禁止 `TODO` 注释或临时占位符。
- **注释:** 简洁添加，重点关注复杂逻辑背后的“为什么”，避免注释“是什么”。
- **命名规范:**
  - `CamelCase` 用于类型（类、结构体、协议、枚举）。
  - `camelCase` 用于函数、变量和属性。
  - 协议应根据其能力命名（例如 `ProjectSyncing`）。

### 导入与格式化
- 遵循标准 Swift 格式化约定。
- 合理组织导入（先项目框架，后 Apple 框架）。
- 强制严格类型化。除非绝对必要，避免使用 `Any` 或隐式的 `AnyObject`。

### 错误处理
- 在适当的地方使用 Swift 的 `Error` 协议和 `Result` 类型。
- 妥善处理文件系统和 git 命令失败。
- 将严重错误记录到控制台，而不导致应用程序崩溃。
- 在 UI 中为可操作的错误提供用户友好的反馈。

## 4. Git 与协作
- **约定式提交 (Conventional Commits):** 使用 `type(scope): description` 格式。
- **小功能提交:** 每个独立的小功能完成并验证后，单独创建一次 Git 提交；不要把多个互不相关的小功能合并到同一个提交中。提交信息遵循约定式提交格式。
- **分支:** 除非明确授权，否则不得删除分支。
- **合并:** 合并分支后必须进行构建和测试。
- **冲突:** 如果发生冲突，请向开发者提供清晰的解决选项。

## 5. 安全与稳健性
- **系统完整性:** 此应用程序与 macOS 文件系统交互。未经明确的用户确认和健壮的错误检查，不得引入执行破坏性文件操作的代码。
- **数据持久化:** 尊重现有的 JSON 缓存和 `UserDefaults` 机制。
- **无敏感数据:** 绝不提交秘密、密钥或特定于用户的路径。

## 6. 主动行为
- **三思而后行:** 在创建新文件或修改现有文件之前，分析现有的模式（`BusinessLogic.swift`, `TagManager.swift`）。
- **验证循环:** 在修复 bug 或添加功能时，编写单元测试以验证修复，运行测试并确认修复后再继续。
- **设计走查:** 涉及界面设计或布局调整时，交付前对相关界面做设计走查，检查图标风格与尺寸的一致性、元素间距和对齐、视觉层级，以及不同内容和交互状态下的呈现；发现问题应先修正再交付。
