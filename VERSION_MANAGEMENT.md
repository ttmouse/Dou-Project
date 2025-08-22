# 版本管理系统使用指南

本项目集成了完整的版本管理系统，支持自动版本递增、版本显示和发布构建。

## 功能特性

### 1. 版本显示
- 在应用侧边栏底部显示当前版本信息
- 支持紧凑、详细和徽章三种显示样式
- 自动从版本配置文件读取版本信息

### 2. 版本管理
- 集中式版本配置文件 (`Sources/ProjectManager/Resources/Version.plist`)
- 包含版本号、构建号、构建日期等信息
- 支持语义化版本控制 (Semantic Versioning)

### 3. 自动版本递增
- 支持 patch、minor、major 三种递增类型
- 自动更新构建日期和构建序号
- 可选的 Git 集成（自动提交和标签）

## 使用方法

### 1. 标准打包构建（推荐）

```bash
# 运行标准打包流程，可选择是否递增版本
./build.sh
```

这个脚本会：
- 询问是否需要递增版本号
- 如果选择递增，可以选择递增类型（patch/minor/major）
- 自动构建应用
- 从版本文件读取版本信息并嵌入到应用包
- 创建 DMG 安装镜像
- 显示构建结果和版本信息

### 2. 手动递增版本

```bash
# 递增修复版本 (1.0.0 -> 1.0.1)
./Scripts/increment_version.sh patch

# 递增功能版本 (1.0.0 -> 1.1.0)
./Scripts/increment_version.sh minor

# 递增主要版本 (1.0.0 -> 2.0.0)
./Scripts/increment_version.sh major
```

### 3. 高级发布构建

```bash
# 运行完整的发布构建流程（包含测试）
./Scripts/build_release.sh
```

## 版本号规则

遵循语义化版本控制 (SemVer)：

- **MAJOR**: 不兼容的 API 修改
- **MINOR**: 向后兼容的功能性新增
- **PATCH**: 向后兼容的问题修正

示例：`1.2.3` → `1.2.4` (patch) → `1.3.0` (minor) → `2.0.0` (major)

## Git 集成

版本递增脚本支持自动 Git 操作：

1. 自动提交版本文件更改
2. 创建版本标签 (如 `v1.0.1`)
3. 可选择是否推送到远程仓库

## 文件结构

```
project-root/
├── Sources/ProjectManager/Resources/
│   └── Version.plist              # 版本配置文件
├── Sources/ProjectManager/
│   ├── VersionManager.swift       # 版本管理器
│   └── Views/VersionDisplay.swift # 版本显示组件
├── Scripts/
│   ├── increment_version.sh       # 版本递增脚本
│   └── build_release.sh          # 发布构建脚本
├── build.sh                      # 标准打包脚本
└── VERSION_MANAGEMENT.md         # 本文档
```

## 组件样式

`VersionDisplay` 组件支持三种显示样式：

- **compact**: 紧凑显示 (如 "v1.0.1")
- **detailed**: 详细显示 (包含构建日期)
- **badge**: 徽章样式显示

## 自定义配置

### 修改版本显示样式

在 `SidebarView.swift` 中修改 `VersionDisplay` 的样式参数：

```swift
VersionDisplay(style: .compact) // 或 .detailed, .badge
```

### 修改版本文件位置

如需更改版本文件位置，需要同时更新：
1. `VersionManager.swift` 中的文件路径
2. `increment_version.sh` 中的 `VERSION_FILE` 变量
3. `build.sh` 中的 `VERSION_FILE` 变量

## 故障排除

### 版本信息不显示
1. 检查 `Version.plist` 文件是否存在
2. 确认文件格式正确
3. 检查 `VersionManager` 是否正确加载

### 脚本执行权限问题
```bash
chmod +x Scripts/increment_version.sh
chmod +x Scripts/build_release.sh
chmod +x build.sh
```

### Git 操作失败
确保当前目录是 Git 仓库，且有适当的提交权限。

## 最佳实践

1. **发布前**: 使用 `./build.sh` 进行标准打包，选择合适的版本递增类型
2. **开发中**: 使用手动版本递增进行测试
3. **重要发布**: 使用 `./Scripts/build_release.sh` 进行完整的发布流程
4. **版本控制**: 确保版本更改被正确提交到 Git
5. **文档更新**: 重要版本发布时更新 CHANGELOG 或发布说明

## 版本历史查看

```bash
# 查看当前版本
plutil -p Sources/ProjectManager/Resources/Version.plist

# 查看 Git 标签历史
git tag -l

# 查看版本提交历史
git log --oneline --grep="版本"
```