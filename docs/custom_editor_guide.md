# 如何添加自定义编辑器

本指南将帮助您将自定义编辑器添加到 Project Manager 中。

## 1. 了解编辑器配置

Project Manager 支持通过两种方式启动编辑器：
1. **Bundle ID** (推荐): 使用 macOS 的 `open -a` 命令或 `NSWorkspace` API 启动应用。
2. **命令行路径**: 直接执行编辑器的命令行工具。

## 2. 获取必要信息

### 获取 Bundle ID

Bundle ID 是 macOS 应用的唯一标识符。您可以通过以下方式获取：

**方法一：使用终端命令**
打开终端，运行以下命令（将 "App Name" 替换为应用名称）：
```bash
osascript -e 'id of app "App Name"'
```
例如：
```bash
osascript -e 'id of app "Visual Studio Code"'
# 输出: com.microsoft.VSCode
```

**方法二：查看 Info.plist**
1. 在 Finder 中找到应用程序。
2. 右键点击 -> "显示包内容"。
3. 打开 `Contents/Info.plist` 文件。
4. 查找 `CFBundleIdentifier` 对应的值。

### 获取命令行路径

如果您希望通过命令行启动编辑器（例如支持打开特定文件或文件夹），需要找到其可执行文件路径。

常见的命令行工具路径：
- `/usr/local/bin/code` (VS Code)
- `/usr/local/bin/subl` (Sublime Text)
- `/usr/local/bin/cursor` (Cursor)

您可以在终端中使用 `which` 命令查找：
```bash
which code
```

## 3. 添加编辑器

在 `Sources/ProjectManager/Models/EditorConfig.swift` 文件中，找到 `defaultEditors` 数组，并添加新的 `EditorConfig` 对象：

```swift
EditorConfig(
    name: "您的编辑器名称",
    bundleId: "com.example.editor", // 您的编辑器 Bundle ID
    commandPath: "/path/to/cli",    // 可选：命令行路径
    arguments: [],                  // 可选：启动参数
    displayOrder: 10                // 显示顺序
)
```

### 示例：添加 TRAE

```swift
EditorConfig(
    name: "TRAE",
    bundleId: "com.trae.app",
    commandPath: nil,
    arguments: [],
    displayOrder: 3
)
```

## 4. 验证

1. 重新编译并运行 Project Manager。
2. 进入 "设置" -> "编辑器"。
3. 点击 "重置为默认" 或检查列表是否包含新添加的编辑器。
