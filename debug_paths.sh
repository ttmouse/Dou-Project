#!/bin/bash

echo "=== 调试项目路径 ==="

# 测试具体路径
TEST_PATH="/Users/douba/Projects/project-list"
echo "测试路径: $TEST_PATH"

# 检查.git目录
if [ -d "$TEST_PATH/.git" ]; then
    echo "✅ .git 目录存在"
else
    echo "❌ .git 目录不存在"
fi

# 测试Git命令
echo ""
echo "=== 测试Git命令 ==="
cd "$TEST_PATH"

echo "当前目录: $(pwd)"
echo "Git仓库状态: $(git status --porcelain 2>/dev/null && echo '✅ Git正常' || echo '❌ Git错误')"

# 测试具体的日期查询
echo ""
echo "=== 测试2025-08-25的提交 ==="
commits=$(git log --oneline --since='2025-08-25' --until='2025-08-26' 2>/dev/null | wc -l | tr -d ' ')
echo "2025-08-25的提交数: $commits"

if [ "$commits" -gt 0 ]; then
    echo "✅ 能正确获取提交记录"
    echo "具体提交:"
    git log --oneline --since='2025-08-25' --until='2025-08-26' 2>/dev/null | head -3
else
    echo "❌ 无法获取提交记录"
fi