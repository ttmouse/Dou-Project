#!/bin/bash

# 检查输入文件
if [ ! -f "icon.png" ]; then
    echo "错误: 未找到 icon.png 文件"
    exit 1
fi

# 创建图标集目录
mkdir -p ProjectManager.iconset

# 生成不同尺寸的图标
sips -z 16 16     icon.png --out ProjectManager.iconset/icon_16x16.png
sips -z 32 32     icon.png --out ProjectManager.iconset/icon_16x16@2x.png
sips -z 32 32     icon.png --out ProjectManager.iconset/icon_32x32.png
sips -z 64 64     icon.png --out ProjectManager.iconset/icon_32x32@2x.png
sips -z 128 128   icon.png --out ProjectManager.iconset/icon_128x128.png
sips -z 256 256   icon.png --out ProjectManager.iconset/icon_128x128@2x.png
sips -z 256 256   icon.png --out ProjectManager.iconset/icon_256x256.png
sips -z 512 512   icon.png --out ProjectManager.iconset/icon_256x256@2x.png
sips -z 512 512   icon.png --out ProjectManager.iconset/icon_512x512.png
sips -z 1024 1024 icon.png --out ProjectManager.iconset/icon_512x512@2x.png

# 转换为 icns 文件
iconutil -c icns ProjectManager.iconset

# 清理临时文件
rm -rf ProjectManager.iconset

echo "图标已生成: ProjectManager.icns" 