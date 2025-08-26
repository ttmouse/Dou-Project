#!/bin/bash

# 测试Git多天历史记录脚本
PROJECT_PATH="/Users/douba/Projects/project-list"

echo "=== Git多天历史测试 ==="
echo "项目路径: $PROJECT_PATH"
echo ""

cd "$PROJECT_PATH"

# 检查是否是Git仓库
if [ ! -d ".git" ]; then
    echo "❌ 不是Git仓库"
    exit 1
fi

echo "✅ 是Git仓库"
echo ""

# 获取最近30天的每日提交统计
echo "=== 最近30天每日提交统计 ==="
for i in {0..29}; do
    # 计算日期
    if [[ "$OSTYPE" == "darwin"* ]]; then
        # macOS
        target_date=$(date -v-${i}d +%Y-%m-%d)
        next_date=$(date -v-$((i-1))d +%Y-%m-%d)
    else
        # Linux
        target_date=$(date -d "-${i} days" +%Y-%m-%d)
        next_date=$(date -d "-$((i-1)) days" +%Y-%m-%d)
    fi
    
    # 获取该日期的提交数
    commit_count=$(git log --oneline --since="$target_date" --until="$next_date" 2>/dev/null | wc -l | tr -d ' ')
    
    if [ "$commit_count" -gt 0 ]; then
        echo "$target_date: $commit_count 个提交"
        
        # 显示该日期的提交详情
        echo "  提交详情:"
        git log --oneline --since="$target_date" --until="$next_date" 2>/dev/null | head -3 | sed 's/^/    /'
        echo ""
    fi
done

echo ""
echo "=== 总体统计 ==="
total_commits=$(git rev-list --count HEAD 2>/dev/null)
echo "总提交数: $total_commits"

recent_commits=$(git log --oneline --since="30 days ago" 2>/dev/null | wc -l | tr -d ' ')
echo "最近30天提交数: $recent_commits"

first_commit=$(git log --reverse --pretty=format:"%cd" --date=short 2>/dev/null | head -1)
last_commit=$(git log -1 --pretty=format:"%cd" --date=short 2>/dev/null)
echo "第一次提交: $first_commit"
echo "最后一次提交: $last_commit"