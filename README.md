可以整合项目内的gathhup的一些提交信息。

## 打包应用

### 快速打包
使用打包脚本一键完成：
```bash
./build.sh
```

### 自定义应用图标
1. 准备一个高质量的 PNG 图片（建议尺寸 1024x1024），命名为 `icon.png`
2. 将 `icon.png` 放在项目根目录
3. 运行打包脚本，会自动生成并使用图标

### 手动打包流程
如果需要手动打包，可以按以下步骤执行：

## 打包流程

### 1. 构建发布版本
```bash
swift build -c release
```

### 2. 创建应用包结构
```bash
mkdir -p ProjectManager.app/Contents/MacOS
mkdir -p ProjectManager.app/Contents/Resources
```

### 3. 复制构建文件
```bash
# 复制可执行文件
cp .build/release/ProjectManager ProjectManager.app/Contents/MacOS/

# 复制资源文件
cp -r Sources/ProjectManager/Resources/* ProjectManager.app/Contents/Resources/
```

### 4. 创建 DMG 安装包
```bash
hdiutil create -volname "项目管理器" -srcfolder ProjectManager.app -ov -format UDZO ProjectManager.dmg
```

### 注意事项
1. 由于应用未签名，首次运行时需要在系统偏好设置中允许运行
2. 应用的数据会保存在用户目录下
3. 如需应用图标，需要添加 .icns 文件到 Contents/Resources 目录

### 运行方式
- 直接运行 ProjectManager.app
- 或打开 ProjectManager.dmg 进行安装

## ⚠️ 重要警告：标签系统

### 数据安全
项目使用了 macOS 的文件标签系统进行标签管理。这涉及到以下关键点：

1. **标签数据存储**
   - 项目标签直接存储在 macOS 文件系统的元数据中
   - 使用 `com.apple.metadata:_kMDItemUserTags` 扩展属性存储
   - 标签信息与文件系统深度集成

2. **数据完整性风险**
   - ⚠️ 重新加载或刷新操作可能导致标签信息丢失
   - 修改标签相关代码时需要特别谨慎
   - 建议在修改前备份项目的标签数据

3. **开发注意事项**
   - 修改 `TagSystemSync.swift` 时需要特别小心
   - 确保 `loadTagsFromSystem` 和 `syncTagsToSystem` 的操作是原子的
   - 在实现新功能时，优先考虑标签数据的安全性

4. **代码审查要求**
   - 涉及标签系统的修改必须经过严格的代码审查
   - 需要测试标签在各种操作后的持久性
   - 包括但不限于：重启应用、重新加载项目、系统重启等场景

### 相关文件
- `TagSystemSync.swift`: 负责与系统标签的同步
- `Project.swift`: 项目标签的加载和保存
- `ProjectOperationManager.swift`: 项目操作中的标签处理

### todo
* 文件夹时间没有更新。按时间排序展示的不是真实的效果。
* 


### 监视目录设置
- 用户可以设置多个监视目录
- 每个监视目录都会被独立扫描
- 如果一个目录是另一个监视目录的子目录，它们会被分别扫描
  - 例如：如果同时监视 `/path/A` 和 `/path/A/B`
  - `/path/A` 的扫描只会处理其直接子目录
  - `/path/A/B` 对子目录也会被添加。



# 
添加工作目录（扫描项目）  预期就是添加目录下的一级子目录作为入口。
直接添加为项目，将选中的 文件夹作为入口。
扫描子目录并添加  不需单独一个菜单，可以不要了。


