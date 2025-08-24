#!/bin/bash

# ProjectManager .trees 工作区管理工具
# 通过创建独立工作目录实现真正的分支隔离

TREES_DIR=".trees"
PROJECT_ROOT=$(pwd)
CURRENT_BRANCH_FILE="$TREES_DIR/.current"

# 颜色定义
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# 确保在项目根目录
ensure_project_root() {
    if [ ! -f "Package.swift" ] || [ ! -d "Sources" ]; then
        echo -e "${RED}错误: 请在 ProjectManager 项目根目录运行此脚本${NC}"
        exit 1
    fi
}

# 确保 .trees 目录存在
ensure_trees_dir() {
    if [ ! -d "$TREES_DIR" ]; then
        mkdir -p "$TREES_DIR"
        echo -e "${GREEN}创建 $TREES_DIR 目录${NC}"
    fi
}

# 显示帮助信息
show_help() {
    echo "ProjectManager Trees 工作区管理工具"
    echo ""
    echo "用法: ./trees-workspace.sh [命令] [选项]"
    echo ""
    echo "命令:"
    echo "  create <分支名>     创建新的工作区分支"
    echo "  enter <分支名>      进入指定分支工作区（新终端窗口）"
    echo "  list               列出所有分支工作区"
    echo "  status             显示当前分支状态"
    echo "  sync <分支名>      将主分支更新同步到指定分支"
    echo "  merge <分支名>     将分支更改合并回主分支"
    echo "  delete <分支名>     删除指定分支工作区"
    echo "  help               显示此帮助信息"
    echo ""
    echo "注意: 分支工作区位于 .trees/<分支名>/ 目录中"
    echo ""
}

# 创建新的分支工作区
create_branch() {
    local branch_name="$1"
    if [ -z "$branch_name" ]; then
        echo -e "${RED}错误: 请提供分支名${NC}"
        return 1
    fi
    
    ensure_project_root
    ensure_trees_dir
    
    local branch_dir="$TREES_DIR/$branch_name"
    if [ -d "$branch_dir" ]; then
        echo -e "${RED}错误: 分支工作区 '$branch_name' 已存在${NC}"
        return 1
    fi
    
    echo -e "${YELLOW}创建分支工作区: $branch_name${NC}"
    echo "正在复制项目文件..."
    
    # 创建分支目录
    mkdir -p "$branch_dir"
    
    # 复制项目文件（排除 .trees 和 .git）
    rsync -av --progress \
        --exclude='.trees/' \
        --exclude='.git/' \
        --exclude='build/' \
        --exclude='.build/' \
        --exclude='*.dmg' \
        --exclude='ProjectManager.app' \
        --exclude='*.log' \
        . "$branch_dir/"
    
    # 创建分支信息文件
    cat > "$branch_dir/.branch_info" << EOF
{
    "name": "$branch_name",
    "created": "$(date -Iseconds)",
    "description": "",
    "parent": "$PROJECT_ROOT",
    "last_sync": "$(date -Iseconds)"
}
EOF
    
    # 创建变更记录文件
    touch "$branch_dir/.changes.log"
    
    # 创建工作区标识文件
    echo "$branch_name" > "$branch_dir/.trees_branch"
    
    # 创建便捷脚本
    cat > "$branch_dir/back-to-main.sh" << 'EOF'
#!/bin/bash
# 返回主项目目录
cd "$(cat .branch_info | grep '"parent"' | sed 's/.*"parent": *"\([^"]*\)".*/\1/')"
echo "已返回主项目目录"
exec bash
EOF
    chmod +x "$branch_dir/back-to-main.sh"
    
    echo -e "${GREEN}成功创建分支工作区: $branch_name${NC}"
    echo -e "${YELLOW}使用 './trees-workspace.sh enter $branch_name' 进入工作区${NC}"
}

# 进入分支工作区
enter_branch() {
    local branch_name="$1"
    if [ -z "$branch_name" ]; then
        echo -e "${RED}错误: 请提供分支名${NC}"
        return 1
    fi
    
    local branch_dir="$TREES_DIR/$branch_name"
    if [ ! -d "$branch_dir" ]; then
        echo -e "${RED}错误: 分支工作区 '$branch_name' 不存在${NC}"
        return 1
    fi
    
    echo -e "${GREEN}进入分支工作区: $branch_name${NC}"
    echo -e "${BLUE}提示: 使用 './back-to-main.sh' 返回主项目目录${NC}"
    echo -e "${BLUE}提示: 使用 'exit' 退出当前分支工作区${NC}"
    echo ""
    
    # 记录当前分支
    echo "$branch_name" > "$CURRENT_BRANCH_FILE"
    
    # 切换到分支目录并启动新的shell会话
    cd "$branch_dir"
    
    # 设置环境变量，让shell提示符显示分支信息
    export TREES_BRANCH="$branch_name"
    export PS1="[\e[32m$branch_name\e[0m] $PS1"
    
    # 启动新的bash会话
    exec bash --rcfile <(echo "
        PS1='[\[\e[32m\]$branch_name\[\e[0m\]] \u \[\e[33m\]\w\[\e[0m\] \$ '
        export TREES_BRANCH='$branch_name'
        echo -e '\e[32m当前工作区: $branch_name\e[0m'
        echo -e '\e[33m工作目录: $(pwd)\e[0m'
        echo ''
    ")
}

# 列出所有分支工作区
list_branches() {
    ensure_trees_dir
    
    echo -e "${BLUE}所有分支工作区:${NC}"
    echo ""
    
    local current_branch=""
    if [ -f "$CURRENT_BRANCH_FILE" ]; then
        current_branch=$(cat "$CURRENT_BRANCH_FILE")
    fi
    
    local found_branches=false
    for branch_dir in "$TREES_DIR"/*/; do
        if [ -d "$branch_dir" ] && [ -f "$branch_dir/.trees_branch" ]; then
            found_branches=true
            local branch_name=$(basename "$branch_dir")
            local marker=" "
            
            if [ "$branch_name" = "$current_branch" ]; then
                marker="*"
                echo -e "  ${GREEN}$marker $branch_name (当前分支)${NC}"
            else
                echo "  $marker $branch_name"
            fi
            
            # 显示分支信息
            local info_file="$branch_dir/.branch_info"
            if [ -f "$info_file" ]; then
                local created=$(grep '"created"' "$info_file" | sed 's/.*"created": *"\([^"]*\)".*/\1/')
                local description=$(grep '"description"' "$info_file" | sed 's/.*"description": *"\([^"]*\)".*/\1/')
                
                echo "    创建时间: $created"
                echo "    工作目录: $(realpath "$branch_dir")"
                if [ -n "$description" ] && [ "$description" != "" ]; then
                    echo "    描述: $description"
                fi
            fi
            
            # 显示磁盘使用情况
            local size=$(du -sh "$branch_dir" | cut -f1)
            echo "    磁盘占用: $size"
            echo ""
        fi
    done
    
    if [ "$found_branches" = false ]; then
        echo "  没有找到分支工作区"
        echo "  使用 './trees-workspace.sh create <分支名>' 创建第一个分支"
    fi
}

# 显示当前状态
show_status() {
    echo -e "${BLUE}项目根目录:${NC} $PROJECT_ROOT"
    
    local current_branch=""
    if [ -f "$CURRENT_BRANCH_FILE" ]; then
        current_branch=$(cat "$CURRENT_BRANCH_FILE")
        echo -e "${GREEN}最后使用分支: $current_branch${NC}"
        
        local branch_dir="$TREES_DIR/$current_branch"
        if [ -f "$branch_dir/.changes.log" ] && [ -s "$branch_dir/.changes.log" ]; then
            echo -e "${BLUE}最近变更:${NC}"
            tail -3 "$branch_dir/.changes.log" | sed 's/^/  /'
        fi
    else
        echo -e "${YELLOW}没有使用过分支工作区${NC}"
    fi
    
    # 检查当前是否在分支工作区中
    if [ -f ".trees_branch" ]; then
        local current_workspace_branch=$(cat ".trees_branch")
        echo -e "${GREEN}当前位置: 分支工作区 '$current_workspace_branch'${NC}"
    else
        echo -e "${BLUE}当前位置: 主项目目录${NC}"
    fi
    
    echo ""
    echo -e "${BLUE}Git 状态:${NC}"
    git status --short 2>/dev/null || echo "  (无Git信息)"
}

# 同步主分支到指定分支
sync_branch() {
    local branch_name="$1"
    if [ -z "$branch_name" ]; then
        echo -e "${RED}错误: 请提供分支名${NC}"
        return 1
    fi
    
    local branch_dir="$TREES_DIR/$branch_name"
    if [ ! -d "$branch_dir" ]; then
        echo -e "${RED}错误: 分支工作区 '$branch_name' 不存在${NC}"
        return 1
    fi
    
    echo -e "${YELLOW}同步主分支更新到: $branch_name${NC}"
    echo -e "${RED}警告: 这将覆盖分支中与主分支冲突的文件${NC}"
    read -p "确认同步? (y/N): " confirm
    
    if [[ "$confirm" =~ ^[Yy]$ ]]; then
        echo "正在同步..."
        
        # 备份分支的当前状态
        local backup_dir="$branch_dir/.sync_backup_$(date +%Y%m%d_%H%M%S)"
        mkdir -p "$backup_dir"
        
        # 复制主分支更新（排除特定目录和文件）
        rsync -av --progress \
            --exclude='.trees/' \
            --exclude='.git/' \
            --exclude='build/' \
            --exclude='.build/' \
            --exclude='*.dmg' \
            --exclude='ProjectManager.app' \
            --exclude='*.log' \
            --exclude='.branch_info' \
            --exclude='.changes.log' \
            --exclude='.trees_branch' \
            --exclude='back-to-main.sh' \
            . "$branch_dir/"
        
        # 更新同步时间
        if [ -f "$branch_dir/.branch_info" ]; then
            local temp_file=$(mktemp)
            sed "s/\"last_sync\": \".*\"/\"last_sync\": \"$(date -Iseconds)\"/" "$branch_dir/.branch_info" > "$temp_file"
            mv "$temp_file" "$branch_dir/.branch_info"
        fi
        
        echo -e "${GREEN}同步完成${NC}"
        echo -e "${BLUE}备份创建于: $backup_dir${NC}"
    else
        echo -e "${YELLOW}同步已取消${NC}"
    fi
}

# 合并分支更改回主分支
merge_branch() {
    local branch_name="$1"
    if [ -z "$branch_name" ]; then
        echo -e "${RED}错误: 请提供要合并的分支名${NC}"
        return 1
    fi
    
    local branch_dir="$TREES_DIR/$branch_name"
    if [ ! -d "$branch_dir" ]; then
        echo -e "${RED}错误: 分支工作区 '$branch_name' 不存在${NC}"
        return 1
    fi
    
    echo -e "${YELLOW}准备将分支 '$branch_name' 合并到主分支${NC}"
    echo -e "${RED}警告: 这将覆盖主分支中与分支冲突的文件${NC}"
    
    # 显示分支变更历史
    if [ -f "$branch_dir/.changes.log" ] && [ -s "$branch_dir/.changes.log" ]; then
        echo -e "${BLUE}分支变更历史:${NC}"
        cat "$branch_dir/.changes.log" | sed 's/^/  /'
        echo ""
    fi
    
    read -p "确认合并? (y/N): " confirm
    if [[ "$confirm" =~ ^[Yy]$ ]]; then
        echo "正在合并..."
        
        # 备份主分支当前状态
        local backup_dir=".merge_backup_$(date +%Y%m%d_%H%M%S)"
        mkdir -p "$backup_dir"
        
        # 复制分支更改到主分支（排除分支特有文件）
        rsync -av --progress \
            --exclude='.branch_info' \
            --exclude='.changes.log' \
            --exclude='.trees_branch' \
            --exclude='back-to-main.sh' \
            --exclude='.sync_backup_*' \
            "$branch_dir/" .
        
        echo -e "${GREEN}合并完成${NC}"
        echo -e "${BLUE}主分支备份创建于: $backup_dir${NC}"
        echo -e "${YELLOW}建议现在提交更改到Git${NC}"
    else
        echo -e "${YELLOW}合并已取消${NC}"
    fi
}

# 删除分支工作区
delete_branch() {
    local branch_name="$1"
    if [ -z "$branch_name" ]; then
        echo -e "${RED}错误: 请提供分支名${NC}"
        return 1
    fi
    
    local branch_dir="$TREES_DIR/$branch_name"
    if [ ! -d "$branch_dir" ]; then
        echo -e "${RED}错误: 分支工作区 '$branch_name' 不存在${NC}"
        return 1
    fi
    
    # 显示分支信息
    local size=$(du -sh "$branch_dir" | cut -f1)
    echo -e "${RED}警告: 将删除分支工作区 '$branch_name' 及其所有数据 ($size)${NC}"
    
    if [ -f "$branch_dir/.changes.log" ] && [ -s "$branch_dir/.changes.log" ]; then
        echo -e "${YELLOW}分支包含以下变更记录:${NC}"
        cat "$branch_dir/.changes.log" | sed 's/^/  /'
        echo ""
    fi
    
    read -p "确认删除? (输入分支名确认): " confirm
    
    if [ "$confirm" = "$branch_name" ]; then
        rm -rf "$branch_dir"
        
        # 如果是当前分支，清除当前分支记录
        local current_branch=""
        if [ -f "$CURRENT_BRANCH_FILE" ]; then
            current_branch=$(cat "$CURRENT_BRANCH_FILE")
            if [ "$current_branch" = "$branch_name" ]; then
                rm -f "$CURRENT_BRANCH_FILE"
            fi
        fi
        
        echo -e "${GREEN}分支工作区 '$branch_name' 已删除${NC}"
    else
        echo -e "${YELLOW}删除已取消${NC}"
    fi
}

# 主函数
main() {
    case "$1" in
        "create")
            create_branch "$2"
            ;;
        "enter")
            enter_branch "$2"
            ;;
        "list")
            list_branches
            ;;
        "status")
            show_status
            ;;
        "sync")
            sync_branch "$2"
            ;;
        "merge")
            merge_branch "$2"
            ;;
        "delete")
            delete_branch "$2"
            ;;
        "help"|"")
            show_help
            ;;
        *)
            echo -e "${RED}错误: 未知命令 '$1'${NC}"
            show_help
            return 1
            ;;
    esac
}

main "$@"