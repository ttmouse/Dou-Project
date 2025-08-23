#!/bin/bash
# Linus风格回归测试 - 验证重构没有破坏任何功能
# "If your refactoring breaks existing functionality, you're not refactoring, you're just breaking shit."

set -e  # 遇到错误立即退出

echo "=== LINUS REGRESSION TEST SUITE ==="
echo "\"Untested code is buggy code. Buggy code is shit code.\""
echo

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# 测试结果跟踪
tests_passed=0
tests_failed=0
tests_total=0

function print_test() {
    echo -e "${BLUE}[TEST]${NC} $1"
    ((tests_total++))
}

function print_success() {
    echo -e "${GREEN}[PASS]${NC} $1"
    ((tests_passed++))
}

function print_failure() {
    echo -e "${RED}[FAIL]${NC} $1"
    ((tests_failed++))
}

function print_warning() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

function test_result() {
    if [ $1 -eq 0 ]; then
        print_success "$2"
    else
        print_failure "$2"
    fi
}

# 清理函数
cleanup() {
    echo "清理测试环境..."
    rm -rf test_temp_* *.tmp *.log
}
trap cleanup EXIT

echo "=== 1. BUILD VERIFICATION ==="

print_test "编译项目"
./build.sh > build_output.tmp 2>&1
build_result=$?
test_result $build_result "Project builds successfully"
if [ $build_result -ne 0 ]; then
    echo "Build output:"
    cat build_output.tmp | tail -20
fi

print_test "Swift编译检查"
swift build > swift_build.tmp 2>&1
swift_result=$?
test_result $swift_result "Swift compilation successful"

echo
echo "=== 2. FUNCTIONALITY TESTS ==="

print_test "数据格式转换功能"
python3 linus-data-converter.py > converter.tmp 2>&1
converter_result=$?
test_result $converter_result "Data converter works"

print_test "Linus数据结构检查"
./linus-check.sh > linus_check.tmp 2>&1
linus_result=$?
test_result $linus_result "Linus data structure validation"

print_test "接口复杂度验证"
python3 interface-complexity-check.py > interface_check.tmp 2>&1
interface_result=$?
test_result $interface_result "Interface complexity check"

echo
echo "=== 3. CRITICAL FILES CHECK ==="

# 检查关键文件存在
critical_files=(
    "Sources/ProjectManager/ProjectManagerApp.swift"
    "Sources/ProjectManager/Models/TagManager.swift" 
    "Sources/ProjectManager/Models/SimpleTagManager.swift"
    "Sources/ProjectManager/Models/SimpleProjectManager.swift"
    "Sources/ProjectManager/Protocols/LinusProtocols.swift"
    "Sources/ProjectManager/Models/Project.swift"
    "Sources/ProjectManager/Views/ProjectListView.swift"
    "Package.swift"
    "build.sh"
    "Tests/ProjectManagerTests/MockSystem.swift"
    "Tests/ProjectManagerTests/TagSystemTests.swift"
)

for file in "${critical_files[@]}"; do
    print_test "检查关键文件: $(basename $file)"
    if [ -f "$file" ]; then
        print_success "文件存在: $file"
    else
        print_failure "文件缺失: $file"
    fi
done

echo
echo "=== 4. LINUS STANDARDS VERIFICATION ==="

print_test "验证协议定义"
if grep -r "protocol.*Tags\|protocol.*Projects" Sources/ > /dev/null 2>&1; then
    print_success "发现Linus协议定义"
else
    print_failure "Linus协议定义缺失"
fi

print_test "验证AIDEV注释"
AIDEV_COUNT=$(find Sources Tests -name "*.swift" -exec grep -l "AIDEV-" {} \; 2>/dev/null | wc -l)
if [ $AIDEV_COUNT -gt 0 ]; then
    print_success "发现 $AIDEV_COUNT 个文件包含AIDEV注释"
else
    print_warning "缺少AIDEV锚点注释"
fi

echo
echo "=== 5. DATA INTEGRITY TESTS ==="

print_test "验证备份数据完整性"
if [ -f "projects-backup-20250823-070551.json" ]; then
    BACKUP_COUNT=$(python3 -c "import json; print(len(json.load(open('projects-backup-20250823-070551.json'))))" 2>/dev/null || echo "0")
    if [ "$BACKUP_COUNT" -gt 0 ]; then
        print_success "备份数据包含 $BACKUP_COUNT 个项目"
    else
        print_failure "备份数据为空"
    fi
else
    print_warning "找不到备份数据文件"
fi

print_test "验证Linus格式数据"
if [ -f "projects-linus-format.json" ]; then
    LINUS_COUNT=$(python3 -c "import json; print(len(json.load(open('projects-linus-format.json'))))" 2>/dev/null || echo "0")
    if [ "$LINUS_COUNT" -gt 0 ]; then
        print_success "Linus格式数据包含 $LINUS_COUNT 个项目"
    else
        print_failure "Linus格式数据为空"
    fi
else
    print_warning "找不到Linus格式数据文件"
fi

echo
echo "=== MANUAL VERIFICATION CHECKLIST ==="
echo -e "${YELLOW}请手动验证以下功能:${NC}"
echo "- [ ] 应用启动无崩溃"
echo "- [ ] 项目列表正常显示"  
echo "- [ ] 标签添加/删除正常"
echo "- [ ] 搜索功能工作正常"
echo "- [ ] 编辑器集成正常"
echo "- [ ] 数据持久化正常"
echo "- [ ] 项目卡片显示正确"
echo "- [ ] 侧边栏过滤功能正常"
echo "- [ ] 所有UI交互正常"
echo "- [ ] 无功能回归"

echo
echo "=== FINAL REGRESSION REPORT ==="

echo
echo -e "${BLUE}测试统计:${NC}"
echo "总测试数: $tests_total"
echo -e "通过: ${GREEN}$tests_passed${NC}"
echo -e "失败: ${RED}$tests_failed${NC}"

if [ $tests_total -gt 0 ]; then
    SUCCESS_RATE=$((tests_passed * 100 / tests_total))
    echo "成功率: $SUCCESS_RATE%"
fi

echo
if [ $tests_failed -eq 0 ]; then
    echo -e "${GREEN}=== REGRESSION TEST PASSED ===${NC}"
    echo "\"Good. Your refactoring didn't break anything.\""
    echo "\"Now go make it even better.\""
    exit 0
else
    echo -e "${RED}=== REGRESSION TEST FAILED ===${NC}"
    echo "\"You broke something. Fix it before proceeding.\""
    echo "\"Regression tests are not suggestions, they are requirements.\""
    exit 1
fi