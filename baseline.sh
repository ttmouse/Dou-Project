#!/bin/bash
# baseline.sh - 记录当前的烂摊子状态

echo "📊 Current Codebase Baseline:"
echo "================================"

# 基本统计
total_files=$(find Sources -name "*.swift" | wc -l | tr -d ' ')
echo "- Total Swift files: $total_files"

# 最大的文件
echo "- Largest files:"
find Sources -name "*.swift" -exec wc -l {} \; | sort -nr | head -5 | while read line; do
    echo "  $line"
done

# 单例统计
singleton_count=$(grep -r "\.shared" Sources/ 2>/dev/null | wc -l | tr -d ' ')
echo "- Singleton instances: $singleton_count"

# 总行数
total_lines=$(find Sources -name "*.swift" -exec wc -l {} \; | awk '{sum+=$1} END {print sum}')
echo "- Total lines of code: $total_lines"

# God Objects (>15 methods)
echo "- God objects (>15 methods):"
god_count=0
for file in $(find Sources -name "*.swift"); do
    method_count=$(grep -c "func " "$file")
    if [ $method_count -gt 15 ]; then
        echo "  $(basename "$file"): $method_count methods"
        god_count=$((god_count + 1))
    fi
done
if [ $god_count -eq 0 ]; then
    echo "  None found"
fi

# 测试统计
if [ -d "Tests" ]; then
    test_files=$(find Tests -name "*.swift" | wc -l | tr -d ' ')
    echo "- Test files: $test_files"
else
    echo "- Test files: 0 (NO TESTS DIRECTORY)"
fi

echo ""
echo "🎯 Functional Baseline:"
echo "======================"

# 编译测试
echo "- Build test:"
if ./build.sh > /dev/null 2>&1; then
    echo "  ✅ Build works"
else
    echo "  ❌ Build fails"
fi

# 记录到文件
echo ""
echo "💾 Saving baseline to baseline-$(date +%Y%m%d-%H%M%S).txt..."
{
    echo "ProjectManager Baseline - $(date)"
    echo "================================"
    echo "Total Swift files: $total_files"
    echo "Singleton instances: $singleton_count"
    echo "God objects: $god_count"
    echo "Total lines: $total_lines"
    echo "Test files: $([ -d "Tests" ] && find Tests -name "*.swift" | wc -l | tr -d ' ' || echo "0")"
    echo ""
    echo "Largest files:"
    find Sources -name "*.swift" -exec wc -l {} \; | sort -nr | head -10
} > "baseline-$(date +%Y%m%d-%H%M%S).txt"

echo "✅ Baseline recorded!"
echo ""
echo "🔍 Key Issues Identified:"
if [ $singleton_count -gt 0 ]; then
    echo "❌ $singleton_count singleton instances need elimination"
fi
if [ $god_count -gt 0 ]; then
    echo "❌ $god_count god objects need refactoring"
fi
if [ ! -d "Tests" ] || [ $(find Tests -name "*.swift" 2>/dev/null | wc -l) -eq 0 ]; then
    echo "❌ No tests - need comprehensive test suite"
fi

echo ""
echo "🚀 Ready to start the brutal refactoring!"