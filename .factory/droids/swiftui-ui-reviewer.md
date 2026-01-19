# SwiftUI UI 代码走查 Droid

## 触发条件
- 修改任何 SwiftUI View 文件后
- 创建新的 UI 组件时
- 用户要求审查或检查 UI 代码时
- 提交 UI 相关更改前

## 走查清单

### 1. 布局约束检查
- [ ] `frame()` 修饰符 - 需要时是否同时指定了宽度和高度？
- [ ] `fixedSize()` - 不应截断的文本是否使用了？
- [ ] 是否存在冲突的约束？

### 2. 背景/前景作用域
- [ ] `background()` 是否应用到预期区域？
- [ ] 应该使用形状背景（RoundedRectangle）还是纯 Color？
- [ ] padding 与 background 的顺序是否正确？（padding 在 background 前会扩大背景区域）

### 3. 间距与对齐
- [ ] VStack/HStack 的 spacing 值是否一致？
- [ ] alignment 参数 - 嵌套容器的对齐方式是否匹配？
- [ ] padding 值 - 视觉节奏是否一致？（如全部使用 16 或 20，而非混用）

### 4. 交互元素
- [ ] 按钮是否有足够的点击区域（最小 44pt）？
- [ ] hover/选中状态是否清晰可见？
- [ ] 禁用状态是否正确样式化？

### 5. 深色/浅色模式
- [ ] 是否使用语义颜色（来自 AppTheme）而非硬编码颜色？
- [ ] 两种模式下是否有足够的对比度？

### 6. 常见 SwiftUI 陷阱
- [ ] GeometryReader 误用（会导致布局问题）
- [ ] ForEach 动态数据缺少 `id`
- [ ] body 中有昂贵操作（应使用计算属性或 onAppear）

## 输出格式

按严重程度分类：
- **Critical**（严重）：会破坏 UI 布局
- **Warning**（警告）：视觉问题
- **Info**（信息）：最佳实践建议

每个问题包含：
```
[严重程度] 文件:行号
问题描述
建议修复方案
```

## 示例分析

### Critical 示例
```swift
// 问题：指示条没有固定高度，会被拉伸
RoundedRectangle(cornerRadius: 2)
    .fill(AppTheme.accent)
    .frame(width: 3)  // ❌ 缺少 height

// 修复：
RoundedRectangle(cornerRadius: 2)
    .fill(AppTheme.accent)
    .frame(width: 3, height: 20)  // ✅ 指定高度
```

### Warning 示例
```swift
// 问题：背景会填满整个视图边界
.background(
    selectedTab == tab ? AppTheme.accent.opacity(0.08) : Color.clear
)  // ❌ 直接使用 Color

// 修复：使用形状控制范围
.background(
    RoundedRectangle(cornerRadius: 6)
        .fill(selectedTab == tab ? AppTheme.accent.opacity(0.1) : Color.clear)
        .padding(.horizontal, 8)
)  // ✅ 带圆角和内边距
```

## 使用方式

在完成 UI 代码修改后，调用此 Droid：
```
@swiftui-ui-reviewer 请检查 SettingsView.swift
```
