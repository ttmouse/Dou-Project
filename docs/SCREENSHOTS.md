# 项目截图指南

这个文档说明如何为 ProjectManager 准备高质量的项目截图。

## 推荐的截图内容

### 1. 主界面截图
- **文件名**: `main-interface.png`
- **内容**: 显示项目列表、标签筛选和搜索功能的主界面
- **建议尺寸**: 1920x1080 或更高
- **要点**: 展示多个项目卡片和标签系统

### 2. 标签管理截图
- **文件名**: `tag-management.png` 
- **内容**: 显示标签创建、编辑和颜色设置
- **要点**: 突出标签的可视化管理功能

### 3. 编辑器集成截图
- **文件名**: `editor-integration.png`
- **内容**: 显示多编辑器支持和智能检测
- **要点**: 展示右键菜单中的编辑器选择

### 4. 项目详情截图
- **文件名**: `project-details.png`
- **内容**: 显示 Git 信息、分支管理和项目统计
- **要点**: 突出 Git 集成功能

### 5. 偏好设置截图
- **文件名**: `preferences.png`
- **内容**: 显示编辑器配置和自定义设置
- **要点**: 展示应用的可配置性

## 截图规范

### 技术要求
- **格式**: PNG（推荐）或 JPG
- **分辨率**: 至少 1920x1080，推荐 2K 或 4K
- **DPI**: 144 DPI 或更高（Retina 显示器效果）
- **颜色**: RGB 色彩模式

### 内容要求
- 使用真实的项目数据，避免空白状态
- 确保界面元素清晰可见
- 包含有意义的项目名称和标签
- 避免包含个人敏感信息

### 美观建议
- 使用统一的 macOS 主题（浅色或深色）
- 保持窗口大小一致
- 截图时隐藏无关的 Dock 和菜单栏元素
- 使用整洁的桌面背景

## 制作流程

1. **准备测试数据**
   ```bash
   # 创建一些示例项目目录
   mkdir -p ~/示例项目/{ProjectManager,SwiftUI-Demo,iOS-App}
   ```

2. **配置应用状态**
   - 添加一些标签（如：Swift, iOS, macOS, 开源）
   - 设置不同颜色的标签
   - 确保有足够的项目数据展示

3. **截图工具推荐**
   - macOS 自带截图工具（Shift+Cmd+4）
   - CleanMyMac X 截图功能
   - Snagit（专业截图工具）

4. **后期处理**
   - 调整亮度和对比度
   - 添加阴影效果（可选）
   - 压缩文件大小但保持质量

## 存储位置

截图文件应存储在以下位置：

```
docs/
├── screenshots/
│   ├── main-interface.png
│   ├── tag-management.png  
│   ├── editor-integration.png
│   ├── project-details.png
│   └── preferences.png
└── SCREENSHOTS.md (本文件)
```

## 在 README 中使用

将截图添加到 README.md 中：

```markdown
## 🖼️ 应用截图

### 主界面
![主界面](docs/screenshots/main-interface.png)

### 标签管理
![标签管理](docs/screenshots/tag-management.png)

### 编辑器集成  
![编辑器集成](docs/screenshots/editor-integration.png)
```

## 维护更新

- 重要功能更新时重新截图
- 保持截图与最新版本一致
- 定期检查截图链接的有效性

---

高质量的截图能显著提升项目的专业形象和用户理解度。