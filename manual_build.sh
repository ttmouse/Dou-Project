#!/bin/bash

# 手动打包脚本 - 用于验证增强的自动打标功能

cd /Users/douba/Projects/project-list

echo "1. 清理旧文件..."
rm -rf ProjectManager.app ProjectManager.dmg

echo "2. 创建应用包结构..."
mkdir -p ProjectManager.app/Contents/MacOS
mkdir -p ProjectManager.app/Contents/Resources

echo "3. 复制可执行文件..."
cp .build/release/ProjectManager ProjectManager.app/Contents/MacOS/

echo "4. 复制资源文件..."
cp -r Sources/ProjectManager/Resources/* ProjectManager.app/Contents/Resources/ 2>/dev/null || true

echo "5. 复制图标..."
if [ -f "ProjectManager.icns" ]; then
    cp ProjectManager.icns ProjectManager.app/Contents/Resources/

    echo "6. 创建 Info.plist..."
    cat > ProjectManager.app/Contents/Info.plist << 'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleIconFile</key>
    <string>ProjectManager.icns</string>
    <key>CFBundleIdentifier</key>
    <string>com.projectmanager.app</string>
    <key>CFBundleName</key>
    <string>项目管理器</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>1.0</string>
    <key>LSMinimumSystemVersion</key>
    <string>12.0</string>
    <key>CFBundleExecutable</key>
    <string>ProjectManager</string>
</dict>
</plist>
EOF
fi

echo "7. 创建 DMG..."
hdiutil create -volname "项目管理器" -srcfolder ProjectManager.app -ov -format UDZO ProjectManager.dmg

echo ""
echo "✅ 打包完成！"
echo "应用位置: /Users/douba/Projects/project-list/ProjectManager.app"
echo "DMG 位置: /Users/douba/Projects/project-list/ProjectManager.dmg"
echo ""
echo "本次更新内容:"
echo "1. ✅ 增强了 AutoTagger 的项目名称匹配逻辑"
echo "2. ✅ 支持更多技术栈关键词识别（node, js, npm, py, ts, go, rust 等）"
echo "3. ✅ 打标完成后的结果提示功能已存在"
echo ""
echo "测试建议:"
echo "1. 启动应用后，进入设置 > 自动标签"
echo "2. 点击'立即运行打标'按钮"
echo "3. 观察是否显示'打标完成：更新了 X 个项目'的提示"
echo "4. 检查主界面，验证标签是否立即更新"
