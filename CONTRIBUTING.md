# 贡献指南

感谢您对 ProjectManager 的兴趣！我们欢迎各种形式的贡献，无论是错误报告、功能请求、文档改进还是代码贡献。

## 🚀 开始之前

请确保您已经：
1. 阅读了 [README.md](README.md) 了解项目基本信息
2. 查看了现有的 [Issues](https://github.com/your-username/project-list/issues) 避免重复
3. 了解了项目的 [架构设计](README.md#架构设计)

## 🐛 报告问题

发现 Bug？请创建一个 Issue 并包含以下信息：

### Bug 报告模板
```
**问题描述**
简洁清晰地描述问题是什么。

**重现步骤**
1. 执行 '...'
2. 点击 '....'
3. 滚动到 '....'
4. 看到错误

**预期行为**
描述您期望发生的行为。

**实际行为**
描述实际发生的行为。

**环境信息**
- macOS 版本: [例如 macOS 13.0]
- ProjectManager 版本: [例如 v1.0.0]
- 其他相关信息

**屏幕截图**
如果适用，添加屏幕截图来帮助解释问题。

**附加信息**
其他有助于理解问题的上下文。
```

## ✨ 功能请求

有好的想法？我们很乐意听到！请创建一个 Issue 描述：

1. **问题描述**: 您试图解决什么问题？
2. **建议解决方案**: 您认为如何解决这个问题？
3. **可选方案**: 是否考虑过其他解决方案？
4. **使用场景**: 谁会使用这个功能？如何使用？

## 🛠️ 代码贡献

### 开发环境设置

1. Fork 仓库到您的 GitHub 账户
2. 克隆您的 Fork：
   ```bash
   git clone https://github.com/your-username/project-list.git
   cd project-list
   ```

3. 创建开发分支：
   ```bash
   git checkout -b feature/your-feature-name
   ```

4. 构建项目确保环境正常：
   ```bash
   swift build
   ./build.sh
   ```

### 代码规范

请遵循以下编码规范：

#### Swift 代码风格
- 使用 4 个空格缩进（不使用 Tab）
- 函数和类名使用 PascalCase
- 变量和属性使用 camelCase
- 常量使用 UPPERCASE_WITH_UNDERSCORES
- 每行最大长度 100 字符

#### 注释规范
```swift
/// 计算项目的 Git 提交统计信息
/// - Parameter projectPath: 项目路径
/// - Returns: Git 信息结构体，包含提交次数等
func calculateGitInfo(for projectPath: String) -> GitInfo? {
    // 实现逻辑...
}
```

#### SwiftUI 最佳实践
- 优先使用 SwiftUI 原生组件
- 保持视图组件小而专注
- 使用 @StateObject 和 @ObservedObject 适当管理状态
- 遵循单一职责原则

### 重要开发注意事项

⚠️ **标签系统安全**

在修改涉及标签系统的代码时，请特别注意：

1. **核心文件**: 修改这些文件时需要格外小心
   - `TagSystemSync.swift`
   - `TagManager.swift`
   - `Project.swift` 中的标签相关方法

2. **测试要求**: 确保标签操作的原子性
   - 测试应用重启后标签持久性
   - 测试系统重启后标签持久性
   - 测试批量操作的数据一致性

3. **数据备份**: 在测试标签功能前备份测试数据

### 提交规范

使用约定式提交格式：

```
<类型>[可选的作用域]: <描述>

[可选的正文]

[可选的脚注]
```

#### 提交类型
- `feat`: 新功能
- `fix`: 错误修复
- `docs`: 文档更新
- `style`: 代码格式修改（不影响功能）
- `refactor`: 重构（既不修复错误也不添加功能）
- `test`: 添加或修改测试
- `chore`: 构建过程或辅助工具的变动

#### 示例
```
feat(tags): 实现项目卡片标签点击筛选功能

- 添加标签点击事件处理
- 实现与侧边栏标签一致的筛选逻辑
- 增强用户交互体验

Closes #123
```

### Pull Request 流程

1. **准备工作**
   - 确保代码通过所有测试
   - 更新相关文档
   - 添加必要的测试用例

2. **创建 PR**
   - 使用清晰的标题描述变更
   - 在描述中说明：
     - 解决了什么问题
     - 如何解决的
     - 是否有破坏性变更
     - 测试步骤

3. **代码审查**
   - 响应审查意见
   - 根据反馈进行调整
   - 保持分支更新

### 测试

在提交 PR 前，请确保：

```bash
# 运行测试套件
swift test

# 构建发布版本
swift build -c release

# 手动测试核心功能
./build.sh && open ProjectManager.app
```

## 📚 文档贡献

文档改进同样重要！您可以：

- 改进现有文档的清晰度
- 添加使用示例
- 翻译文档到其他语言
- 修复文档中的错误或过时信息

## 🎨 设计贡献

如果您有设计背景，我们也欢迎：

- UI/UX 改进建议
- 图标设计
- 用户体验优化方案
- 无障碍功能改进

## 📞 联系方式

如有任何问题，请通过以下方式联系：

- 创建 [Issue](https://github.com/your-username/project-list/issues)
- 参与 [Discussions](https://github.com/your-username/project-list/discussions)

## 🙏 致谢

感谢每一位贡献者！您的贡献使 ProjectManager 变得更好。

---

再次感谢您考虑为 ProjectManager 做出贡献！🎉