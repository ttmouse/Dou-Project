# Frontend Changes

## 修改日期
2025-08-24

## 修改内容
移除设置面板中的通用选项

## 修改的文件

### 1. `/Sources/ProjectManager/Views/Settings/SettingsView.swift`
- 移除了 `@State private var selectedTab: SettingsTab = .editors` 状态变量
- 移除了标签选择器 (Picker) 组件
- 简化了内容区域，直接显示 `EditorSettingsView` 而不是使用 switch 语句
- 移除了 `SettingsTab` 枚举定义
- 移除了对 `GeneralSettingsView` 的引用

### 2. `/Sources/ProjectManager/Views/Settings/AddEditorView.swift`
- 移除了 `GeneralSettingsView` 结构体定义（该结构体仅显示"暂无通用设置项"的占位符内容）

## 修改原因
根据用户需求，设置面板中目前没有通用选项，因此移除相关的 UI 元素和代码，简化设置面板界面。

## 修改后的效果
- 设置面板现在只显示编辑器设置
- 移除了标签选择器，界面更加简洁
- 减少了不必要的代码复杂度
- 用户体验更加直接，避免了无用的选项卡