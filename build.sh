#!/bin/bash

# 清理旧的构建文件
rm -rf .build/release
rm -rf ProjectManager.app
rm -f ProjectManager.dmg

# 如果存在 icon.png，则生成图标
if [ -f "icon.png" ]; then
    echo "生成应用图标..."
    ./make_icon.sh
fi

echo "开始构建..."
# 构建发布版本
swift build -c release

echo "创建应用包..."
# 创建应用包结构
mkdir -p ProjectManager.app/Contents/MacOS
mkdir -p ProjectManager.app/Contents/Resources

# 复制文件
cp .build/release/ProjectManager ProjectManager.app/Contents/MacOS/
cp -r Sources/ProjectManager/Resources/* ProjectManager.app/Contents/Resources/ 2>/dev/null || true

# 复制图标
if [ -f "ProjectManager.icns" ]; then
    cp ProjectManager.icns ProjectManager.app/Contents/Resources/
    # 创建 Info.plist
    cat > ProjectManager.app/Contents/Info.plist << EOF
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

echo "创建 DMG..."
# 创建 DMG
hdiutil create -volname "项目管理器" -srcfolder ProjectManager.app -ov -format UDZO ProjectManager.dmg

echo "打包完成！" 

# 一个命令就可以完成打包： ./build.sh