# ProjectManager

<div align="center">

![ProjectManager Icon](icon.png)

**一个强大的 macOS 项目管理工具**

[![Swift](https://img.shields.io/badge/Swift-5.7+-orange.svg)](https://swift.org)
[![macOS](https://img.shields.io/badge/macOS-12.0+-blue.svg)](https://www.apple.com/macos/)
[![License](https://img.shields.io/badge/License-MIT-green.svg)](LICENSE)

</div>

ProjectManager 是一个专为开发者设计的 macOS 原生项目管理应用，提供直观的项目发现、标签管理、编辑器集成和 Git 信息展示功能。

## ✨ 主要特性

### 📁 智能项目发现
- 自动扫描指定目录下的项目
- 支持多个工作目录监控
- 实时检测项目变更
- 增量更新，性能优化

### 🏷️ 强大的标签系统
- **深度系统集成**：直接使用 macOS 文件标签系统
- **可视化管理**：彩色标签，直观分类
- **智能筛选**：支持标签组合筛选
- **快速操作**：点击项目卡片标签即可筛选

### 🔧 多编辑器支持
- **Cursor** - AI 驱动的代码编辑器（默认）
- **Visual Studio Code** - 流行的开发环境
- **Trae AI** - AI 增强的 IDE
- **自定义编辑器** - 支持任意编辑器配置
- **智能检测** - 自动识别已安装的编辑器

### 📊 Git 集成
- 显示提交次数统计
- 最后提交时间信息
- 分支管理支持
- 项目状态概览

### 🎨 现代化界面
- SwiftUI 原生设计
- 响应式网格布局
- 暗色模式支持
- 平滑动画效果

## 🚀 快速开始

### 系统要求
- macOS 12.0 或更高版本
- Swift 5.7+

### 从源码构建

```bash
# 克隆仓库
git clone https://github.com/your-username/project-list.git
cd project-list

# 快速构建和打包
./build.sh
```

### 安装

1. 运行 `./build.sh` 构建应用
2. 打开生成的 `ProjectManager.dmg` 文件
3. 将 ProjectManager.app 拖拽到应用程序文件夹

## 📖 使用指南

### 首次设置

1. 启动 ProjectManager
2. 点击侧边栏的"管理目录"
3. 选择"添加工作目录（扫描项目）"来添加你的项目目录
4. 应用将自动扫描并发现项目

### 标签管理

- **创建标签**：点击侧边栏的 + 按钮
- **应用标签**：右键点击项目卡片，选择标签
- **筛选项目**：点击侧边栏标签或项目卡片上的标签
- **删除标签**：右键点击标签选择删除

### 编辑器配置

1. 按 `⌘ + ,` 打开偏好设置
2. 选择你的首选编辑器
3. 对于自定义编辑器，提供名称和可执行文件路径

### 项目操作

- **打开项目**：双击项目卡片
- **在编辑器中打开**：右键选择编辑器
- **在 Finder 中显示**：右键选择"在Finder中显示"
- **复制路径**：右键选择"复制路径"

## 🏗️ 架构设计

ProjectManager 采用现代 SwiftUI 架构，遵循 MVVM 模式：

```
Sources/ProjectManager/
├── Models/              # 数据模型和业务逻辑
│   ├── Project.swift    # 核心项目模型
│   ├── TagManager.swift # 标签管理器
│   └── BusinessLogic.swift # 纯函数业务逻辑
├── Views/               # 用户界面
│   ├── ProjectListView.swift # 主界面
│   ├── ProjectCard.swift     # 项目卡片
│   └── Components/          # 可复用组件
├── ViewModels/          # 视图模型
└── Utilities/          # 工具类
```

### 核心组件

- **TagManager**: 中央协调器，管理项目和标签
- **BusinessLogic**: 纯函数业务逻辑，易于测试
- **TagSystemSync**: 与 macOS 文件标签系统的集成
- **ProjectIndex**: 项目发现和缓存机制

## ⚠️ 重要提醒

### 标签系统安全

ProjectManager 深度集成 macOS 文件标签系统，标签数据直接存储在文件系统元数据中：

- 使用 `com.apple.metadata:_kMDItemUserTags` 扩展属性
- 标签操作需要谨慎处理，避免数据丢失
- 修改标签相关代码前请备份数据
- 涉及 `TagSystemSync.swift` 的更改需要特别小心

## 🛠️ 开发

### 构建配置

```bash
# 开发构建
swift build

# 发布构建
swift build -c release

# 运行测试
swift test
```

### 代码风格

- 遵循 Swift 最佳实践
- 优先使用 SwiftUI 和 Combine
- 保持函数纯净，便于测试
- 详细的中文注释

### 项目脚本

- `build.sh` - 完整构建和打包
- `make_icon.sh` - 生成应用图标
- `scripts/increment_version.sh` - 版本管理

## 🤝 贡献指南

我们欢迎社区贡献！请遵循以下步骤：

1. Fork 本仓库
2. 创建功能分支 (`git checkout -b feature/amazing-feature`)
3. 提交更改 (`git commit -m 'Add some amazing feature'`)
4. 推送到分支 (`git push origin feature/amazing-feature`)
5. 开启 Pull Request

### 贡献类型

- 🐛 Bug 修复
- ✨ 新功能开发
- 📚 文档改进
- 🎨 UI/UX 优化
- ⚡ 性能改进
- 🧪 测试覆盖

## 📄 许可证

本项目采用 MIT 许可证 - 查看 [LICENSE](LICENSE) 文件了解详情。

## 🙏 致谢

- [SwiftUI](https://developer.apple.com/xcode/swiftui/) - Apple 的声明式 UI 框架
- macOS 文件系统 API - 强大的元数据支持
- 开源社区的灵感和支持

## 📞 联系方式

- 提交 Issue：[GitHub Issues](https://github.com/your-username/project-list/issues)
- 讨论功能：[GitHub Discussions](https://github.com/your-username/project-list/discussions)

---

<div align="center">
Made with ❤️ for developers by developers
</div>