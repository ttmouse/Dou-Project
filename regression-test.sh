#!/bin/bash
# regression-test.sh - 确保我们没搞砸任何东西

echo "🔬 Running Regression Tests..."

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# 测试结果跟踪
tests_passed=0
tests_failed=0

function test_result() {
    if [ $1 -eq 0 ]; then
        echo -e "${GREEN}✅ PASS${NC}: $2"
        tests_passed=$((tests_passed + 1))
    else
        echo -e "${RED}❌ FAIL${NC}: $2"
        tests_failed=$((tests_failed + 1))
    fi
}

echo "🏗️  Testing build process..."

# 1. 编译测试
echo ""
echo "1️⃣  Build Test"
echo "============="
./build.sh > build_output.tmp 2>&1
build_result=$?
if [ $build_result -eq 0 ]; then
    test_result 0 "Project builds successfully"
else
    test_result 1 "Project build failed"
    echo "Build output:"
    cat build_output.tmp | tail -20
fi
rm -f build_output.tmp

# 2. 代码质量检查
echo ""
echo "2️⃣  Code Quality Check"
echo "==================="
./linus-check.sh > quality_output.tmp 2>&1
quality_result=$?
if [ $quality_result -eq 0 ]; then
    test_result 0 "Code quality standards met"
else
    test_result 1 "Code quality issues found"
    echo "Quality issues:"
    cat quality_output.tmp | grep "❌"
fi
rm -f quality_output.tmp

# 3. 基本文件结构检查
echo ""
echo "3️⃣  File Structure Check"
echo "====================="

# 检查关键文件存在
critical_files=(
    "Sources/ProjectManager/ProjectManagerApp.swift"
    "Sources/ProjectManager/Models/TagManager.swift" 
    "Sources/ProjectManager/Models/Project.swift"
    "Sources/ProjectManager/Views/ProjectListView.swift"
    "Package.swift"
    "build.sh"
)

for file in "${critical_files[@]}"; do
    if [ -f "$file" ]; then
        test_result 0 "Critical file exists: $file"
    else
        test_result 1 "Critical file missing: $file"
    fi
done

# 4. 基本语法检查 (编译检查)
echo ""
echo "4️⃣  Syntax Check"
echo "============="
swift build --configuration debug > syntax_check.tmp 2>&1
syntax_result=$?
if [ $syntax_result -eq 0 ]; then
    test_result 0 "No syntax errors found"
else
    test_result 1 "Syntax errors detected"
    echo "Syntax errors:"
    cat syntax_check.tmp | grep "error:"
fi
rm -f syntax_check.tmp

# 5. 手动功能测试清单
echo ""
echo "📋 Manual Test Checklist:"
echo "========================"
echo -e "${YELLOW}Please manually verify these after running the app:${NC}"
echo "- [ ] App 启动无崩溃"
echo "- [ ] 项目列表正常显示"  
echo "- [ ] 标签添加/删除正常"
echo "- [ ] 搜索功能工作"
echo "- [ ] 编辑器集成正常"
echo "- [ ] 设置保存/加载正常"
echo "- [ ] 项目卡片显示正常"
echo "- [ ] 侧边栏标签过滤工作"
echo "- [ ] 拖拽操作正常"
echo "- [ ] 上下文菜单功能正常"

echo ""
echo "📊 Test Results Summary:"
echo "======================="
total_tests=$((tests_passed + tests_failed))
echo "Total tests: $total_tests"
echo -e "Passed: ${GREEN}$tests_passed${NC}"
echo -e "Failed: ${RED}$tests_failed${NC}"

if [ $tests_failed -eq 0 ]; then
    echo -e "${GREEN}"
    echo "🎉 ALL AUTOMATED TESTS PASSED!"
    echo "Ready for manual testing."
    echo -e "${NC}"
    echo ""
    echo "Next steps:"
    echo "1. Run the app and verify manual checklist"
    echo "2. Test all user interactions"
    echo "3. Verify no functionality regression"
    exit 0
else
    echo -e "${RED}"
    echo "💥 SOME TESTS FAILED!"
    echo "Fix the issues before proceeding!"
    echo -e "${NC}"
    exit 1
fi