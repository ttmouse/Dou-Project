# Trees分支管理功能规格文档

## 项目概述

本文档描述了将Trees分支管理功能集成到ProjectManager SwiftUI应用中的完整功能规格。该集成基于现有的trees.sh脚本，提供Git worktree的图形化管理界面。

## 设计原则

- **零破坏性** - 完全保持现有功能不变
- **Linus式简洁** - 直接复用Git worktree，不重新发明轮子  
- **渐进集成** - 可分阶段实现，降低风险
- **用户友好** - 通过详情面板自然集成，学习成本低

## 技术架构

### 数据层设计
```swift
// BranchModels.swift - 新增文件
- BranchInfo: 分支基本信息（名称、路径、状态、描述）
- WorktreeInfo: Git worktree 详细信息
- BranchStatus: 分支状态枚举（干净/有更改/未知）
- BranchOperation: 操作类型枚举
- BranchOperationResult: 操作结果封装
```

### 业务逻辑层增强
```swift
// BusinessLogic.swift - 修改现有文件，新增BranchLogic枚举
enum BranchLogic {
    - createBranch(name: String, basePath: String) -> BranchOperationResult
    - deleteBranch(name: String, path: String) -> BranchOperationResult
    - getBranchStatus(path: String) -> BranchStatus
    - listWorktrees(projectPath: String) -> [WorktreeInfo]
    - mergeBranch(source: String, target: String) -> BranchOperationResult
    - validateBranchName(name: String) -> Bool
    - getBranchInfo(path: String) -> BranchInfo?
}
```

### Shell执行工具
```swift
// ShellExecutor.swift - 新增文件
class ShellExecutor {
    - executeGitCommand(args: [String], workingDir: String) -> (output: String, success: Bool)
    - createWorktree(branchName: String, targetPath: String, basePath: String) -> Bool
    - removeWorktree(path: String) -> Bool
    - getGitStatus(path: String) -> (clean: Bool, changes: Int)
    - getWorktreeList(basePath: String) -> [WorktreeInfo]
}
```

## 完整功能清单

### 1. 分支管理功能
- **创建分支**
  - 基于当前分支创建新的Git worktree分支
  - 支持分支名称和描述设置
  - 自动创建.trees/分支名目录结构
  - 生成分支信息文件(.branch_info)
  - 创建返回主目录的便捷脚本(back-to-main.sh)

- **分支列表显示**
  - 显示所有现有分支
  - 实时状态指示器（干净/有更改/未知）
  - 分支创建时间
  - 最后使用时间跟踪
  - 未提交更改数量统计

- **分支切换**
  - 一键切换到任意分支
  - 在选定编辑器中打开分支目录
  - 支持所有已配置的编辑器（Cursor、VSCode、Trae AI等）
  - 自动设置工作目录

- **分支删除**
  - 安全删除分支（带确认）
  - 检测未提交更改并警告
  - 自动清理Git worktree和本地分支
  - 清理相关目录和文件

- **分支合并**
  - 将分支合并回主分支
  - 合并前检查状态
  - 冲突检测和处理提示
  - 合并后可选择删除源分支

### 2. 状态管理功能
- **实时状态监控**
  - Git状态检查（干净/有更改）
  - 未提交文件数量统计
  - 分支同步状态
  - 磁盘使用情况统计

- **可视化指示器**
  - 绿色圆点：分支干净
  - 橙色圆点：有未提交更改
  - 灰色圆点：状态未知
  - 数字徽章显示更改数量

### 3. UI/UX功能
- **项目详情面板**
  - 侧边栏滑出式详情面板
  - 项目基本信息显示
  - 分支管理区域集成
  - 可折叠/展开界面

- **分支操作界面**
  - 分支卡片式显示
  - 右键上下文菜单
  - 快速操作按钮
  - 创建分支对话框
  - 操作确认对话框

- **键盘快捷键支持**
  - 快速打开详情面板
  - 分支间快速切换
  - 创建分支快捷键

### 4. 编辑器集成功能
- **多编辑器支持**
  - 完全复用现有编辑器配置
  - 支持Cursor、VSCode、Trae AI等所有已配置编辑器
  - 编辑器可用性检测和状态显示
  - 智能回退机制

- **工作目录管理**
  - 自动切换到正确的分支目录
  - 保持编辑器工作空间一致性
  - 支持相对路径解析

### 5. 数据持久化功能
- **分支信息存储**
  - 分支元数据持久化
  - 使用历史记录
  - 用户偏好设置
  - 缓存管理

- **系统集成**
  - 完全兼容现有trees.sh脚本
  - .trees目录结构保持一致
  - 分支信息文件格式兼容

### 6. 错误处理和安全功能
- **操作安全**
  - 分支删除前检查未提交更改
  - 合并冲突检测
  - 磁盘空间检查
  - 权限验证

- **错误恢复**
  - Git操作失败处理
  - 用户友好的错误消息
  - 操作回滚机制
  - 日志记录

### 7. 性能优化功能
- **后台处理**
  - Git命令异步执行
  - UI更新不阻塞主线程
  - 状态检查缓存机制
  - 增量更新

- **资源管理**
  - 内存使用优化
  - Git进程管理
  - 文件系统监控优化

### 8. 用户体验增强
- **智能提示**
  - 分支命名建议
  - 操作状态反馈
  - 进度指示器
  - 成功/失败通知

- **工作流优化**
  - 最近使用分支快速访问
  - 批量操作支持
  - 操作历史记录
  - 自定义工作流程

## UI组件设计

### 新增UI组件
```swift
// ProjectDetailView.swift - 项目详情面板
- 显示项目基本信息
- 集成分支管理面板
- 支持侧边栏显示/隐藏

// BranchManagementPanel.swift - 分支管理主面板  
- 分支列表显示
- 创建分支按钮
- 分支操作菜单

// BranchListView.swift - 分支列表
- 分支卡片显示
- 状态指示器
- 右键菜单操作

// BranchCard.swift - 单个分支卡片
- 分支名称和描述
- 状态可视化（干净/有更改）
- 快速操作按钮（打开、删除）

// CreateBranchView.swift - 创建分支对话框
- 分支名称输入
- 描述输入
- 基于分支选择
```

### 现有组件修改
```swift
// ProjectCard.swift - 修改现有文件
- 添加"详情"按钮（齿轮图标）
- 保持现有所有功能不变

// ProjectListView.swift - 修改现有文件  
- 添加详情面板状态管理
- 支持HSplitView三分栏布局（侧边栏 + 主内容 + 详情面板）
- 添加详情面板显示/隐藏逻辑

// MainContentView.swift - 修改现有文件
- 传递选中项目到详情面板
- 处理详情面板打开/关闭事件
```

## 文件结构规划
```
Sources/ProjectManager/
├── Models/
│   ├── BranchModels.swift          # 新增 - 分支数据模型
│   ├── WorktreeManager.swift       # 新增 - 分支管理器
│   ├── BusinessLogic.swift         # 修改 - 添加BranchLogic
│   └── ...
├── Utilities/
│   ├── ShellExecutor.swift         # 新增 - Shell命令执行
│   ├── WorktreePathManager.swift   # 新增 - .trees目录管理
│   └── ...
├── Views/
│   ├── Branch/                     # 新增目录
│   │   ├── ProjectDetailView.swift
│   │   ├── BranchManagementPanel.swift
│   │   ├── BranchListView.swift
│   │   ├── BranchCard.swift
│   │   └── CreateBranchView.swift
│   ├── ProjectCard.swift           # 修改 - 添加详情按钮
│   ├── ProjectListView.swift       # 修改 - 三分栏布局
│   └── ...
```

## 用户操作流程

### 基础操作流程
1. 用户点击项目卡片的"详情"按钮
2. 右侧滑出详情面板，显示项目信息和分支列表
3. 用户可以：
   - 查看现有分支状态
   - 创建新分支
   - 切换分支（在新窗口打开编辑器）
   - 删除分支
   - 合并分支到主分支

### 界面布局
- 保持现有卡片网格布局
- 右侧滑出详情面板（类似Xcode导航器）
- 详情面板可折叠/展开
- 支持键盘快捷键控制

## 实现策略

### 渐进式集成
- **第一阶段**：添加基础数据模型和Shell执行工具
- **第二阶段**：实现基础UI组件
- **第三阶段**：集成到现有界面
- **第四阶段**：添加高级功能（合并、状态同步）

### 零破坏性原则
- 所有新功能都是可选的
- 现有用户工作流程完全不变
- 新功能通过"详情"按钮访问
- 保持向后兼容

## 技术细节

### Git Worktree集成
- 完全兼容现有trees.sh脚本的.trees目录结构
- 使用相同的.branch_info文件格式
- 生成相同的back-to-main.sh脚本

### 编辑器集成
- 复用现有AppOpenHelper.swift的编辑器检测和启动逻辑
- 支持在分支目录中打开所有配置的编辑器
- 自动传递正确的工作目录路径

### 性能考虑
- Git命令执行使用后台队列
- 分支状态缓存（避免频繁Git调用）
- UI更新使用@MainActor确保线程安全
- 大项目的worktree列表分页加载

### 错误处理
- Git命令失败的友好提示
- 分支名称冲突检测
- 磁盘空间不足警告
- 权限问题处理

## 总结

这个设计方案将Trees脚本的强大分支管理能力完整地集成到SwiftUI应用中，为用户提供了一个现代化、直观的Git worktree管理界面。通过遵循Linus式简洁设计原则，保持了代码的可维护性和用户体验的一致性。

---
*文档版本: 1.0*  
*创建日期: 2024-08-24*  
*最后更新: 2024-08-24*