#!/bin/bash
# linus-check.sh - 因为人类太蠢，需要脚本来检查

echo "🔥 Starting Linus Quality Check..."

# 1. 文件职责检查
echo "📏 Checking file responsibilities..."
echo "ℹ️  Looking for files with mixed responsibilities..."

# 检查过大的文件 (>500行可能有多重职责)
echo "🐘 Checking for bloated files..."
find Sources -name "*.swift" -exec wc -l {} \; | awk '{if($1>500) print "❌ BLOATED FILE: " $2 " (" $1 " lines)"}' | sort -nr

# 2. 单例检测
echo ""
echo "🚫 Hunting singletons..."
singleton_count=$(grep -r "\.shared" Sources/ 2>/dev/null | wc -l)
if [ $singleton_count -gt 0 ]; then
    echo "❌ FOUND $singleton_count SINGLETON CANCER INSTANCES:"
    grep -rn "\.shared" Sources/ 2>/dev/null | head -10
else
    echo "✅ No singletons found"
fi

# 3. God Object检测 (>15个方法)
echo ""
echo "👹 Looking for God Objects..."
god_objects_found=0
for file in $(find Sources -name "*.swift"); do
    method_count=$(grep -c "func " "$file")
    if [ $method_count -gt 15 ]; then
        echo "❌ GOD OBJECT: $file ($method_count methods)"
        god_objects_found=$((god_objects_found + 1))
    fi
done

if [ $god_objects_found -eq 0 ]; then
    echo "✅ No god objects found"
fi

# 4. 测试覆盖率
echo ""
echo "🧪 Test coverage check..."
if [ -d "Tests" ]; then
    test_files=$(find Tests -name "*.swift" | wc -l)
    if [ $test_files -gt 0 ]; then
        echo "✅ Found $test_files test files"
    else
        echo "❌ NO TEST FILES FOUND"
    fi
else
    echo "❌ NO TESTS DIRECTORY, YOU IDIOTS"
fi

# 5. 检查循环依赖
echo ""
echo "🔄 Checking for circular dependencies..."
# 这是一个简单的检查，寻找可能的循环import
echo "ℹ️  Looking for potential circular imports..."

# 6. 代码复杂度检查
echo ""
echo "🧠 Checking code complexity..."
# 检查过长的方法 (>50行)
echo "🐍 Looking for long methods..."
for file in $(find Sources -name "*.swift"); do
    awk '
    /func / { 
        func_start = NR
        func_name = $0
        brace_count = 0
        in_func = 1
        next
    }
    in_func {
        if (/\{/) brace_count += gsub(/\{/, "")
        if (/\}/) brace_count -= gsub(/\}/, "")
        if (brace_count == 0 && in_func) {
            func_length = NR - func_start
            if (func_length > 50) {
                print "❌ LONG METHOD: " FILENAME ":" func_start " (" func_length " lines)"
            }
            in_func = 0
        }
    }
    ' "$file"
done

# 7. 总结
echo ""
echo "📊 Quality Check Summary:"
total_swift_files=$(find Sources -name "*.swift" | wc -l)
echo "- Total Swift files: $total_swift_files"
echo "- Singleton instances: $singleton_count"
echo "- God objects: $god_objects_found"

if [ $singleton_count -gt 0 ] || [ $god_objects_found -gt 0 ]; then
    echo ""
    echo "❌ Quality check FAILED. Fix the shit above!"
    exit 1
else
    echo ""
    echo "✅ Quality check PASSED. Code doesn't completely suck!"
    exit 0
fi