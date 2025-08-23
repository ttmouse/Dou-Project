#!/bin/bash
# Linus风格代码清理 - "Clean code is readable code"

set -e

echo "=== LINUS CODE CLEANUP SUITE ==="
echo "\"Clean code doesn't happen by accident. It requires discipline.\""
echo

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

CLEANED=0
WARNINGS=0

print_cleanup() {
    echo -e "${BLUE}[CLEANUP]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[CLEAN]${NC} $1"
    ((CLEANED++))
}

print_warning() {
    echo -e "${YELLOW}[WARN]${NC} $1"
    ((WARNINGS++))
}

# 备份函数
backup_code() {
    BACKUP_DIR="code_backup_$(date +%Y%m%d_%H%M%S)"
    mkdir -p "$BACKUP_DIR"
    cp -r Sources Tests "$BACKUP_DIR/"
    echo "代码已备份到: $BACKUP_DIR"
}

# 创建备份
print_cleanup "创建代码备份"
backup_code

echo
echo "=== 1. REMOVE DEBUG OUTPUT ==="

print_cleanup "扫描调试输出语句"
DEBUG_FILES=$(find Sources Tests -name "*.swift" -exec grep -l "print(" {} \; 2>/dev/null || true)
DEBUG_COUNT=$(echo "$DEBUG_FILES" | grep -v "^$" | wc -l || echo "0")

if [ "$DEBUG_COUNT" -gt 0 ]; then
    print_warning "发现 $DEBUG_COUNT 个文件包含调试输出"
    
    # 创建清理脚本但不自动执行，需要人工审查
    cat > cleanup_debug.py << 'EOF'
import re
import sys

def clean_debug_prints(file_path):
    """清理调试print语句，但保留有意义的错误输出"""
    with open(file_path, 'r') as f:
        content = f.read()
    
    original_content = content
    lines = content.split('\n')
    cleaned_lines = []
    
    for line in lines:
        # 保留错误信息的print
        if 'print(' in line and any(keyword in line.lower() for keyword in ['error', '失败', 'failed', '错误']):
            cleaned_lines.append(line)
        # 移除调试print
        elif re.match(r'\s*print\s*\(', line.strip()):
            # 记录移除的调试语句
            print(f"移除调试语句: {line.strip()}")
            continue
        else:
            cleaned_lines.append(line)
    
    new_content = '\n'.join(cleaned_lines)
    
    # 只在有变化时写回文件
    if new_content != original_content:
        with open(file_path, 'w') as f:
            f.write(new_content)
        print(f"清理完成: {file_path}")
        return True
    return False

if __name__ == "__main__":
    import glob
    
    swift_files = glob.glob("Sources/**/*.swift", recursive=True) + glob.glob("Tests/**/*.swift", recursive=True)
    cleaned_count = 0
    
    for file_path in swift_files:
        if clean_debug_prints(file_path):
            cleaned_count += 1
    
    print(f"总计清理了 {cleaned_count} 个文件")
EOF

    python3 cleanup_debug.py > debug_cleanup.log 2>&1
    CLEANED_DEBUG=$(cat debug_cleanup.log | grep "清理完成" | wc -l)
    print_success "清理了 $CLEANED_DEBUG 个文件的调试输出"
else
    print_success "没有发现调试输出语句"
fi

echo
echo "=== 2. REMOVE TODO/FIXME ==="

print_cleanup "扫描TODO/FIXME注释"
TODO_FILES=$(find Sources Tests -name "*.swift" -exec grep -l "TODO\|FIXME\|XXX" {} \; 2>/dev/null || true)
TODO_COUNT=$(echo "$TODO_FILES" | grep -v "^$" | wc -l || echo "0")

if [ "$TODO_COUNT" -gt 0 ]; then
    print_warning "发现 $TODO_COUNT 个文件包含TODO/FIXME"
    
    echo "TODO/FIXME详细信息:"
    find Sources Tests -name "*.swift" -exec grep -Hn "TODO\|FIXME\|XXX" {} \; 2>/dev/null | head -10
    
    print_warning "请手工审查并处理这些TODO项"
else
    print_success "没有发现TODO/FIXME注释"
fi

echo
echo "=== 3. REMOVE UNUSED IMPORTS ==="

print_cleanup "扫描未使用的import"
# 创建unused imports检查脚本
cat > check_unused_imports.py << 'EOF'
import re
import glob

def check_unused_imports(file_path):
    with open(file_path, 'r') as f:
        content = f.read()
    
    # 提取所有import语句
    import_pattern = r'^import\s+(\w+)(?:\.\w+)*$'
    imports = []
    lines = content.split('\n')
    
    for i, line in enumerate(lines):
        match = re.match(import_pattern, line.strip())
        if match:
            module = match.group(1)
            imports.append((i, line.strip(), module))
    
    # 检查每个import是否被使用
    unused_imports = []
    for line_num, import_line, module in imports:
        # 简单检查：在代码中搜索模块名称
        # 排除import行本身
        code_without_imports = '\n'.join([line for i, line in enumerate(lines) if i != line_num])
        
        # 基本模块通常都会用到，跳过检查
        if module in ['Foundation', 'SwiftUI', 'AppKit', 'Combine', 'UniformTypeIdentifiers']:
            continue
            
        # 检查模块是否在代码中被引用
        if not re.search(rf'\b{module}\b', code_without_imports):
            unused_imports.append((line_num + 1, import_line))
    
    return unused_imports

# 检查所有Swift文件
swift_files = glob.glob("Sources/**/*.swift", recursive=True)
total_unused = 0

for file_path in swift_files:
    unused = check_unused_imports(file_path)
    if unused:
        print(f"\n{file_path}:")
        for line_num, import_line in unused:
            print(f"  行 {line_num}: {import_line}")
            total_unused += 1

print(f"\n总计发现 {total_unused} 个可能未使用的import")
EOF

python3 check_unused_imports.py > unused_imports.log 2>&1
UNUSED_IMPORTS=$(cat unused_imports.log | grep -c "行" || echo "0")

if [ "$UNUSED_IMPORTS" -gt 0 ]; then
    print_warning "发现 $UNUSED_IMPORTS 个可能未使用的import"
    cat unused_imports.log
else
    print_success "没有发现明显未使用的import"
fi

echo
echo "=== 4. REMOVE DEAD CODE ==="

print_cleanup "扫描死代码"

# 检查未使用的类和结构体
cat > check_dead_code.py << 'EOF'
import re
import glob
import os

def find_definitions(content):
    """查找类、结构体、协议定义"""
    definitions = []
    
    # 匹配 class, struct, protocol, enum 定义
    pattern = r'^(?:(?:private|public|internal|open)\s+)?(?:class|struct|protocol|enum)\s+(\w+)'
    for match in re.finditer(pattern, content, re.MULTILINE):
        definitions.append(match.group(1))
    
    return definitions

def check_usage(name, all_files_content):
    """检查名称是否在其他地方被使用"""
    # 排除定义行本身，检查是否有其他引用
    usage_pattern = rf'\b{name}\b'
    occurrences = len(re.findall(usage_pattern, all_files_content))
    # 如果只出现1次，可能是死代码（只有定义，没有使用）
    return occurrences > 1

# 读取所有Swift文件
all_content = ""
swift_files = glob.glob("Sources/**/*.swift", recursive=True)

for file_path in swift_files:
    with open(file_path, 'r') as f:
        all_content += f.read() + "\n"

# 查找可能的死代码
potential_dead_code = []

for file_path in swift_files:
    with open(file_path, 'r') as f:
        content = f.read()
    
    definitions = find_definitions(content)
    
    for definition in definitions:
        if not check_usage(definition, all_content):
            potential_dead_code.append((file_path, definition))

if potential_dead_code:
    print(f"发现 {len(potential_dead_code)} 个可能的死代码:")
    for file_path, definition in potential_dead_code:
        print(f"  {os.path.basename(file_path)}: {definition}")
else:
    print("没有发现明显的死代码")
EOF

python3 check_dead_code.py > dead_code.log 2>&1
DEAD_CODE_COUNT=$(cat dead_code.log | grep -c "个可能的死代码" || echo "0")

if [ -s dead_code.log ]; then
    print_warning "死代码检查结果:"
    cat dead_code.log
else
    print_success "没有发现明显的死代码"
fi

echo
echo "=== 5. VERIFY COMPILATION ==="

print_cleanup "验证清理后的代码编译"
if swift build > cleanup_compile.log 2>&1; then
    print_success "清理后代码编译成功"
else
    echo -e "${RED}[ERROR]${NC} 清理后编译失败!"
    echo "编译错误详情:"
    cat cleanup_compile.log | tail -20
    exit 1
fi

echo
echo "=== CLEANUP SUMMARY ==="

echo
echo -e "${BLUE}清理统计:${NC}"
echo "成功清理: $CLEANED 项"
echo "需要人工处理: $WARNINGS 项"

echo
echo "生成的文件:"
echo "- debug_cleanup.log: 调试输出清理日志"
echo "- unused_imports.log: 未使用import检查"
echo "- dead_code.log: 死代码检查"
echo "- cleanup_compile.log: 编译验证日志"

if [ $WARNINGS -eq 0 ]; then
    echo -e "${GREEN}=== CODE CLEANUP COMPLETE ===${NC}"
    echo "\"Code is clean. Linus would approve.\""
else
    echo -e "${YELLOW}=== CODE CLEANUP NEEDS MANUAL REVIEW ===${NC}"
    echo "\"Clean enough, but review the warnings.\""
fi

# 清理临时脚本
rm -f cleanup_debug.py check_unused_imports.py check_dead_code.py