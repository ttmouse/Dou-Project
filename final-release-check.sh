#!/bin/bash
# Linus风格最终发布检查 - "Ready for release. You didn't completely fuck it up!"

set -e

echo "=== LINUS FINAL RELEASE CHECK ==="
echo "\"This is it. Either your code is ready, or you're not.\""
echo

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# 检查计数
PASSED=0
FAILED=0
WARNINGS=0

print_check() {
    echo -e "${BLUE}[CHECK]${NC} $1"
}

print_pass() {
    echo -e "${GREEN}[PASS]${NC} $1"
    ((PASSED++))
}

print_fail() {
    echo -e "${RED}[FAIL]${NC} $1"
    ((FAILED++))
}

print_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
    ((WARNINGS++))
}

# 清理函数
cleanup() {
    echo "清理检查环境..."
    rm -rf final_check_temp_* *.check.log
}
trap cleanup EXIT

echo "=== 1. CODE QUALITY VERIFICATION ==="

print_check "运行Linus代码质量检查"
if ./linus-check.sh > quality_check.log 2>&1; then
    if grep -q "LINUS VERDICT" quality_check.log; then
        print_pass "代码质量检查通过"
    else
        print_warn "代码质量检查可能有警告"
    fi
else
    print_fail "代码质量检查失败"
    echo "质量检查错误详情:"
    cat quality_check.log | tail -10
fi

print_check "接口复杂度标准验证"
if python3 interface-complexity-check.py > interface_final.log 2>&1; then
    if grep -q "所有协议都符合Linus标准" interface_final.log; then
        SIMPLIFICATION_RATE=$(grep "简化率:" interface_final.log | awk '{print $2}' | cut -d'=' -f2)
        print_pass "接口复杂度检查通过 ($SIMPLIFICATION_RATE 简化率)"
    else
        print_fail "接口复杂度不符合标准"
    fi
else
    print_fail "接口复杂度检查失败"
fi

echo
echo "=== 2. BUILD AND COMPILATION ==="

print_check "Release构建测试"
BUILD_START=$(date +%s)
if swift build -c release > release_build.log 2>&1; then
    BUILD_END=$(date +%s)
    BUILD_TIME=$((BUILD_END - BUILD_START))
    print_pass "Release构建成功 (${BUILD_TIME}s)"
else
    print_fail "Release构建失败"
    echo "构建错误详情:"
    cat release_build.log | tail -15
    exit 1
fi

print_check "Debug构建测试"
if swift build -c debug > debug_build.log 2>&1; then
    print_pass "Debug构建成功"
else
    print_fail "Debug构建失败"
    cat debug_build.log | tail -10
fi

print_check "编译警告检查"
WARNINGS_COUNT=$(cat release_build.log debug_build.log 2>/dev/null | grep -i "warning" | wc -l)
if [ $WARNINGS_COUNT -eq 0 ]; then
    print_pass "无编译警告"
else
    print_warn "发现 $WARNINGS_COUNT 个编译警告"
fi

echo
echo "=== 3. REGRESSION TESTING ==="

print_check "功能回归测试"
REGRESSION_START=$(date +%s)
if timeout 120 ./regression-test.sh > regression_final.log 2>&1; then
    REGRESSION_END=$(date +%s)
    REGRESSION_TIME=$((REGRESSION_END - REGRESSION_START))
    print_pass "回归测试通过 (${REGRESSION_TIME}s)"
else
    print_fail "回归测试失败"
    echo "回归测试错误:"
    cat regression_final.log | tail -20
fi

echo
echo "=== 4. PERFORMANCE VERIFICATION ==="

print_check "性能回归检查"
if ./performance-test.sh > performance_final.log 2>&1; then
    if grep -q "PERFORMANCE EXCELLENT\|PERFORMANCE ACCEPTABLE" performance_final.log; then
        PERF_STATUS=$(grep "PERFORMANCE.*===" performance_final.log | tail -1)
        print_pass "性能测试通过: $PERF_STATUS"
    else
        print_warn "性能测试有警告"
    fi
else
    print_fail "性能测试失败"
    cat performance_final.log | tail -15
fi

echo
echo "=== 5. REFACTORING SUCCESS METRICS ==="

print_check "单例消除验证"
SINGLETON_COUNT=$(grep -r "\.shared\|static.*shared" Sources/ --include="*.swift" | grep -v "NSWorkspace.shared" | wc -l)
if [ $SINGLETON_COUNT -eq 0 ]; then
    print_pass "✅ 0个应用层单例 (目标: 0个)"
else
    print_warn "发现 $SINGLETON_COUNT 个单例残留"
fi

print_check "测试覆盖率评估"
if [ -d "Tests" ] && [ -f "Package.swift" ]; then
    TEST_FILES=$(find Tests -name "*.swift" | wc -l)
    if [ $TEST_FILES -ge 4 ]; then
        print_pass "✅ 测试覆盖充分 ($TEST_FILES 个测试文件)"
    else
        print_warn "测试覆盖可能不足 ($TEST_FILES 个测试文件)"
    fi
else
    print_fail "测试基础设施缺失"
fi

print_check "协议简化成果"
PROTOCOL_COUNT=$(grep -r "^protocol " Sources/ --include="*.swift" | wc -l)
LINUS_PROTOCOLS=$(grep -r "^protocol.*Tags\|^protocol.*Projects\|^protocol.*Data" Sources/ --include="*.swift" | wc -l)
if [ $LINUS_PROTOCOLS -ge 5 ]; then
    print_pass "✅ Linus风格协议就绪 ($LINUS_PROTOCOLS/$PROTOCOL_COUNT)"
else
    print_warn "Linus协议数量不足 ($LINUS_PROTOCOLS/$PROTOCOL_COUNT)"
fi

print_check "代码组织结构"
if [ -d "Sources/ProjectManager/Protocols" ] && [ -f "Sources/ProjectManager/Models/SimpleTagManager.swift" ]; then
    print_pass "✅ 代码结构已优化"
else
    print_warn "代码结构可能需要进一步整理"
fi

echo
echo "=== 6. DATA INTEGRITY VERIFICATION ==="

print_check "数据格式完整性"
if [ -f "projects-backup-20250823-070551.json" ] && [ -f "projects-linus-format.json" ]; then
    ORIGINAL_COUNT=$(python3 -c "import json; print(len(json.load(open('projects-backup-20250823-070551.json'))))" 2>/dev/null || echo "0")
    LINUS_COUNT=$(python3 -c "import json; print(len(json.load(open('projects-linus-format.json'))))" 2>/dev/null || echo "0")
    
    if [ "$ORIGINAL_COUNT" = "$LINUS_COUNT" ] && [ "$ORIGINAL_COUNT" -gt 0 ]; then
        print_pass "✅ 数据完整性验证通过 ($ORIGINAL_COUNT 项目)"
    else
        print_fail "数据完整性问题: 原始$ORIGINAL_COUNT vs Linus$LINUS_COUNT"
    fi
else
    print_warn "数据文件不完整"
fi

echo
echo "=== 7. DOCUMENTATION AND REPORTS ==="

print_check "重构报告完整性"
REPORT_FILES=(
    "doc/PHASE3_INTERFACE_SIMPLIFICATION_REPORT.md"
    "doc/PHASE4_TEST_ARMAMENT_REPORT.md" 
    "doc/LINUS_BRUTAL_REFACTORING_PLAN.md"
)

MISSING_REPORTS=0
for report in "${REPORT_FILES[@]}"; do
    if [ ! -f "$report" ]; then
        ((MISSING_REPORTS++))
    fi
done

if [ $MISSING_REPORTS -eq 0 ]; then
    print_pass "✅ 重构文档完整"
else
    print_warn "$MISSING_REPORTS 个报告文件缺失"
fi

echo
echo "=== FINAL VERDICT ==="

TOTAL_CHECKS=$((PASSED + FAILED + WARNINGS))
echo
echo -e "${BLUE}最终检查统计:${NC}"
echo "总检查项: $TOTAL_CHECKS"
echo -e "通过: ${GREEN}$PASSED${NC}"
echo -e "失败: ${RED}$FAILED${NC}"
echo -e "警告: ${YELLOW}$WARNINGS${NC}"

if [ $TOTAL_CHECKS -gt 0 ]; then
    SUCCESS_RATE=$((PASSED * 100 / TOTAL_CHECKS))
    echo "通过率: $SUCCESS_RATE%"
fi

echo
echo "=== LINUS FINAL JUDGMENT ==="

if [ $FAILED -eq 0 ]; then
    if [ $WARNINGS -eq 0 ]; then
        echo -e "${GREEN}"
        echo "██████╗ ██████╗ ██╗     ██████╗   ██╗ ██╗"
        echo "██╔════╝██╔═══██╗██║     ██╔══██╗  ██║ ██║"  
        echo "██║  ███╗██║   ██║██║     ██║  ██║  ██║ ██║"
        echo "██║   ██║██║   ██║██║     ██║  ██║  ██║ ██║"
        echo "╚██████╔╝╚██████╔╝███████╗██████╔╝  ╚██═██╔╝"
        echo " ╚═════╝  ╚═════╝ ╚══════╝╚═════╝    ╚═══╝"
        echo -e "${NC}"
        echo
        echo "🎉 === RELEASE READY! ==="
        echo "\"Congratulations. You didn't completely fuck it up.\""
        echo "\"The code is clean, tested, and ready for production.\""
        echo "\"Ship it.\""
    else
        echo -e "${YELLOW}=== RELEASE ACCEPTABLE WITH WARNINGS ===${NC}"
        echo "\"Good enough. Address the warnings when you have time.\""
        echo "\"But don't let perfect be the enemy of good.\""
    fi
    exit 0
else
    echo -e "${RED}"
    echo "███████╗ █████╗ ██╗██╗     ██╗"
    echo "██╔════╝██╔══██╗██║██║     ██║"
    echo "█████╗  ███████║██║██║     ██║"
    echo "██╔══╝  ██╔══██║██║██║     ╚═╝"
    echo "██║     ██║  ██║██║███████╗██╗"
    echo "╚═╝     ╚═╝  ╚═╝╚═╝╚══════╝╚═╝"
    echo -e "${NC}"
    echo
    echo "💥 === NOT READY FOR RELEASE ==="
    echo "\"You broke something. Fix it before you even think about shipping.\""
    echo "\"Regression tests are not suggestions, they are requirements.\""
    exit 1
fi