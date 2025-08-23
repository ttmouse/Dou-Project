#!/bin/bash
# Linus风格性能测试 - "Fast code is good code. Slow code is user-hostile code."

set -e

echo "=== LINUS PERFORMANCE TEST SUITE ==="
echo "\"Performance isn't everything, but lack of performance is user-hostile.\""
echo

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# 性能基准
MAX_BUILD_TIME=30      # 最大构建时间(秒)
MAX_STARTUP_TIME=3     # 最大启动时间(秒)  
MAX_LOAD_1K_TIME=5     # 加载1000项目最大时间(秒)
MAX_MEMORY_MB=200      # 最大内存使用(MB)

# 性能统计
PERF_PASSED=0
PERF_FAILED=0
PERF_WARNINGS=0

print_perf_test() {
    echo -e "${BLUE}[PERF]${NC} $1"
}

print_perf_pass() {
    echo -e "${GREEN}[PASS]${NC} $1"
    ((PERF_PASSED++))
}

print_perf_fail() {
    echo -e "${RED}[FAIL]${NC} $1"
    ((PERF_FAILED++))
}

print_perf_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
    ((PERF_WARNINGS++))
}

# 清理函数
cleanup() {
    echo "清理性能测试环境..."
    rm -rf perf_temp_* *.perf.log
    killall ProjectManager 2>/dev/null || true
}
trap cleanup EXIT

echo "=== 1. BUILD PERFORMANCE ==="

print_perf_test "测试构建性能"
BUILD_START=$(date +%s)
swift build -c release > build_perf.log 2>&1
BUILD_END=$(date +%s)
BUILD_TIME=$((BUILD_END - BUILD_START))

if [ $BUILD_TIME -le $MAX_BUILD_TIME ]; then
    print_perf_pass "构建时间: ${BUILD_TIME}s (≤${MAX_BUILD_TIME}s)"
else
    print_perf_fail "构建时间过长: ${BUILD_TIME}s (>${MAX_BUILD_TIME}s)"
fi

print_perf_test "测试增量构建性能"
INCREMENTAL_START=$(date +%s)
swift build -c release > incremental_build.log 2>&1
INCREMENTAL_END=$(date +%s)
INCREMENTAL_TIME=$((INCREMENTAL_END - INCREMENTAL_START))

if [ $INCREMENTAL_TIME -le 5 ]; then
    print_perf_pass "增量构建时间: ${INCREMENTAL_TIME}s (≤5s)"
else
    print_perf_warn "增量构建较慢: ${INCREMENTAL_TIME}s"
fi

echo
echo "=== 2. DATA PROCESSING PERFORMANCE ==="

print_perf_test "测试数据转换性能"
CONVERT_START=$(date +%s)
python3 linus-data-converter.py > converter_perf.log 2>&1
CONVERT_END=$(date +%s)
CONVERT_TIME=$((CONVERT_END - CONVERT_START))

if [ $CONVERT_TIME -le 3 ]; then
    print_perf_pass "数据转换时间: ${CONVERT_TIME}s (≤3s)"
else
    print_perf_warn "数据转换较慢: ${CONVERT_TIME}s"
fi

print_perf_test "测试大数据处理性能"
# 创建大量测试数据
create_large_test_data() {
    cat > large_test_data.json << EOF
[
$(for i in {1..1000}; do
    cat << ITEM
    {
        "id": "$(uuidgen)",
        "name": "TestProject$i",
        "path": "/test/path/project$i",
        "tags": ["tag$((i % 10))", "type$((i % 5))"],
        "lastModified": $(($(date +%s) - $i * 60))
    }$(if [ $i -ne 1000 ]; then echo ","; fi)
ITEM
done)
]
EOF
}

create_large_test_data
LARGE_DATA_START=$(date +%s)
python3 -c "
import json
with open('large_test_data.json') as f:
    data = json.load(f)
    # 模拟复杂数据处理
    processed = []
    for item in data:
        processed.append({
            'id': item['id'],
            'name': item['name'],
            'tags': sorted(item['tags']),
            'score': len(item['name']) + len(item['tags'])
        })
    print(f'Processed {len(processed)} items')
" > large_data_perf.log 2>&1
LARGE_DATA_END=$(date +%s)
LARGE_DATA_TIME=$((LARGE_DATA_END - LARGE_DATA_START))

if [ $LARGE_DATA_TIME -le $MAX_LOAD_1K_TIME ]; then
    print_perf_pass "大数据处理时间: ${LARGE_DATA_TIME}s (≤${MAX_LOAD_1K_TIME}s)"
else
    print_perf_fail "大数据处理过慢: ${LARGE_DATA_TIME}s (>${MAX_LOAD_1K_TIME}s)"
fi

rm -f large_test_data.json

echo
echo "=== 3. INTERFACE COMPLEXITY PERFORMANCE ==="

print_perf_test "测试接口检查性能"
INTERFACE_START=$(date +%s)
python3 interface-complexity-check.py > interface_perf.log 2>&1
INTERFACE_END=$(date +%s)
INTERFACE_TIME=$((INTERFACE_END - INTERFACE_START))

if [ $INTERFACE_TIME -le 2 ]; then
    print_perf_pass "接口检查时间: ${INTERFACE_TIME}s (≤2s)"
else
    print_perf_warn "接口检查较慢: ${INTERFACE_TIME}s"
fi

echo
echo "=== 4. COMPILATION PERFORMANCE ==="

print_perf_test "测试Swift编译器性能"
SWIFT_COMPILE_START=$(date +%s)
swift build --configuration debug > swift_compile_perf.log 2>&1
SWIFT_COMPILE_END=$(date +%s)
SWIFT_COMPILE_TIME=$((SWIFT_COMPILE_END - SWIFT_COMPILE_START))

if [ $SWIFT_COMPILE_TIME -le 20 ]; then
    print_perf_pass "Debug编译时间: ${SWIFT_COMPILE_TIME}s (≤20s)"
else
    print_perf_warn "Debug编译较慢: ${SWIFT_COMPILE_TIME}s"
fi

echo
echo "=== 5. MEMORY USAGE ESTIMATION ==="

print_perf_test "估算内存使用"
# 通过构建产物大小估算内存使用
if [ -f ".build/release/ProjectManager" ]; then
    BINARY_SIZE=$(ls -la .build/release/ProjectManager | awk '{print $5}')
    BINARY_SIZE_MB=$((BINARY_SIZE / 1024 / 1024))
    
    # 估算运行时内存使用 (通常是二进制大小的2-5倍)
    ESTIMATED_MEMORY=$((BINARY_SIZE_MB * 3))
    
    if [ $ESTIMATED_MEMORY -le $MAX_MEMORY_MB ]; then
        print_perf_pass "估算内存使用: ${ESTIMATED_MEMORY}MB (≤${MAX_MEMORY_MB}MB)"
    else
        print_perf_warn "估算内存使用较高: ${ESTIMATED_MEMORY}MB"
    fi
else
    print_perf_warn "找不到构建产物，跳过内存估算"
fi

echo
echo "=== 6. TEST SUITE PERFORMANCE ==="

print_perf_test "测试套件性能"
if [ -f "Package.swift" ] && grep -q "testTarget" Package.swift; then
    TEST_START=$(date +%s)
    swift test > test_perf.log 2>&1 || true  # 允许测试失败，只关注性能
    TEST_END=$(date +%s)
    TEST_TIME=$((TEST_END - TEST_START))
    
    if [ $TEST_TIME -le 30 ]; then
        print_perf_pass "测试套件时间: ${TEST_TIME}s (≤30s)"
    else
        print_perf_warn "测试套件较慢: ${TEST_TIME}s"
    fi
else
    print_perf_warn "没有找到测试套件"
fi

echo
echo "=== 7. REGRESSION TEST PERFORMANCE ==="

print_perf_test "回归测试性能"
REGRESSION_START=$(date +%s)
timeout 60 ./regression-test.sh > regression_perf.log 2>&1 || true
REGRESSION_END=$(date +%s)
REGRESSION_TIME=$((REGRESSION_END - REGRESSION_START))

if [ $REGRESSION_TIME -le 45 ]; then
    print_perf_pass "回归测试时间: ${REGRESSION_TIME}s (≤45s)"
else
    print_perf_warn "回归测试较慢: ${REGRESSION_TIME}s"
fi

echo
echo "=== PERFORMANCE SUMMARY ==="

TOTAL_TESTS=$((PERF_PASSED + PERF_FAILED + PERF_WARNINGS))
echo
echo -e "${BLUE}性能测试统计:${NC}"
echo "总测试数: $TOTAL_TESTS"
echo -e "通过: ${GREEN}$PERF_PASSED${NC}"
echo -e "失败: ${RED}$PERF_FAILED${NC}"
echo -e "警告: ${YELLOW}$PERF_WARNINGS${NC}"

if [ $PERF_FAILED -eq 0 ]; then
    SUCCESS_RATE=$(( (PERF_PASSED * 100) / TOTAL_TESTS ))
    echo "成功率: $SUCCESS_RATE%"
fi

echo
echo "=== PERFORMANCE VERDICT ==="

if [ $PERF_FAILED -eq 0 ]; then
    if [ $PERF_WARNINGS -eq 0 ]; then
        echo -e "${GREEN}=== PERFORMANCE EXCELLENT ===${NC}"
        echo "\"Fast enough. Users won't want to kill you.\""
    else
        echo -e "${YELLOW}=== PERFORMANCE ACCEPTABLE ===${NC}"
        echo "\"Good enough, but could be better.\""
    fi
    exit 0
else
    echo -e "${RED}=== PERFORMANCE ISSUES DETECTED ===${NC}"
    echo "\"Too slow. Users will hate this.\""
    echo "Fix performance regressions before release!"
    exit 1
fi