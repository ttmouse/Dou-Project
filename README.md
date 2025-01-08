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