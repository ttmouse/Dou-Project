#!/bin/bash

# 性能测试脚本
# 用于自动化测试应用的性能指标

set -e

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# 配置
APP_NAME="ProjectManager"
BUILD_DIR=".build/release"
APP_PATH="${BUILD_DIR}/${APP_NAME}.app"
LOG_FILE="performance_test_$(date +%Y%m%d_%H%M%S).log"

# 测试配置
PROJECT_COUNTS=(10 50 100 200)
TEST_ITERATIONS=5

echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}   ProjectManager 性能测试工具${NC}"
echo -e "${BLUE}========================================${NC}"
echo ""

# 检查构建
if [ ! -d "$APP_PATH" ]; then
    echo -e "${YELLOW}⚠️  应用未构建，开始构建...${NC}"
    swift build -c release
    echo -e "${GREEN}✅ 构建完成${NC}"
else
    echo -e "${GREEN}✅ 找到已构建的应用${NC}"
fi

# 启动应用
echo ""
echo -e "${BLUE}🚀 启动应用...${NC}"
open "$APP_PATH"

# 等待应用启动
echo -e "${YELLOW}⏳ 等待应用启动 (10秒)...${NC}"
sleep 10

# 检查应用是否运行
APP_PID=$(pgrep -x "$APP_NAME" || true)
if [ -z "$APP_PID" ]; then
    echo -e "${RED}❌ 应用启动失败${NC}"
    exit 1
fi

echo -e "${GREEN}✅ 应用已启动 (PID: $APP_PID)${NC}"
echo ""

# 性能测试函数
run_test() {
    local test_name=$1
    local description=$2

    echo -e "${BLUE}📊 测试: ${test_name}${NC}"
    echo -e "   ${description}"

    # 这里可以添加 AppleScript 或其他自动化工具来执行特定操作
    # 例如：点击按钮、输入文本等
}

# 测试用例
run_test "启动时间" "测量应用冷启动时间"
run_test "搜索响应" "测试搜索输入的响应速度"
run_test "标签切换" "测试标签筛选的性能"
run_test "列表滚动" "测试项目列表滚动的流畅度"
run_test "内存占用" "测量应用的内存使用情况"
run_test "CPU使用率" "测量应用的CPU负载"

# 使用 Instruments 进行性能分析（需要安装 Xcode）
if command -v xcrun &> /dev/null; then
    echo ""
    echo -e "${BLUE}🔍 启动 Instruments 性能分析...${NC}"

    # Time Profiler
    xcrun xctrace record \
        --template "Time Profiler" \
        --launch "$APP_PATH" \
        --output "time_profile.trace" \
        --autolaunch \
        &

    INSTRUMENTS_PID=$!
    sleep 60  # 运行 60 秒

    # 停止 Instruments
    kill $INSTRUMENTS_PID 2>/dev/null || true

    echo -e "${GREEN}✅ Time Profiler 数据已保存到: time_profile.trace${NC}"
fi

# 生成测试报告
echo ""
echo -e "${BLUE}📋 生成测试报告...${NC}"
cat > "$LOG_FILE" << EOF
========================================
  ProjectManager 性能测试报告
========================================
测试时间: $(date)
测试环境: macOS $(sw_vers -productVersion)

测试结果:
---------

1. 启动时间: 待测量
2. 搜索响应: 待测量
3. 标签切换: 待测量
4. 列表滚动: 待测量
5. 内存占用: 待测量
6. CPU使用率: 待测量

优化建议:
---------

1. 使用性能监控面板查看实时指标
2. 对比优化前后的性能数据
3. 重点关注响应时间超过 100ms 的操作
4. 监控内存使用是否存在泄漏
5. 使用 Instruments 分析 CPU 热点

EOF

echo -e "${GREEN}✅ 测试报告已保存到: $LOG_FILE${NC}"
echo ""

# 显示性能面板使用说明
echo -e "${BLUE}💡 使用提示:${NC}"
echo "   1. 在应用中按 ⌘⌥P 打开性能监控面板"
echo "   2. 执行各种操作（搜索、切换标签等）"
echo "   3. 查看面板中的实时性能指标"
echo "   4. 点击\"复制报告\"按钮导出详细数据"
echo ""

# 清理
echo -e "${YELLOW}🧹 清理测试资源...${NC}"
kill $APP_PID 2>/dev/null || true

echo -e "${GREEN}✅ 测试完成${NC}"
echo ""
echo -e "${BLUE}📊 后续步骤:${NC}"
echo "   1. 查看 $LOG_FILE 文件"
echo "   2. 在应用中使用性能监控面板进行手动测试"
echo "   3. 对比优化前后的性能数据"
echo ""
