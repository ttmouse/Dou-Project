#!/bin/bash

# ProjectManager .trees 管理工具
# 用于管理并行开发分支的脚本

TREES_DIR=".trees"
CURRENT_BRANCH_FILE="$TREES_DIR/.current"

# 颜色定义
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# 确保 .trees 目录存在
ensure_trees_dir() {
    if [ ! -d "$TREES_DIR" ]; then
        mkdir -p "$TREES_DIR"
        echo -e "${GREEN}创建 $TREES_DIR 目录${NC}"
    fi
}

# 显示帮助信息
show_help() {
    echo "ProjectManager Trees 管理工具"
    echo ""
    echo "用法: ./trees-manager.sh [命令] [选项]"
    echo ""
    echo "命令:"
    echo "  create <分支名>     创建新的开发分支"
    echo "  switch <分支名>     切换到指定分支"
    echo "  list               列出所有分支"
    echo "  status             显示当前分支状态"
    echo "  save <消息>        保存当前进度"
    echo "  merge <分支名>     合并指定分支到主分支"
    echo "  delete <分支名>     删除指定分支"
    echo "  backup             备份所有分支数据"
    echo "  help               显示此帮助信息"
    echo ""
}

# 创建新分支（使用 Git Worktree）
create_branch() {
    local branch_name="$1"
    if [ -z "$branch_name" ]; then
        echo -e "${RED}错误: 请提供分支名${NC}"
        return 1
    fi
    
    # 确保在Git仓库中
    if [ ! -d ".git" ]; then
        echo -e "${RED}错误: 当前目录不是Git仓库${NC}"
        return 1
    fi
    
    ensure_trees_dir
    
    local branch_dir="$TREES_DIR/$branch_name"
    if [ -d "$branch_dir" ]; then
        echo -e "${RED}错误: 分支 '$branch_name' 已存在${NC}"
        return 1
    fi
    
    echo -e "${GREEN}创建Git分支和工作树: $branch_name${NC}"
    
    # 检查分支是否已存在
    if git branch | grep -q "\\b$branch_name\\b"; then
        echo -e "${YELLOW}Git分支 '$branch_name' 已存在，创建工作树...${NC}"
        git worktree add "$branch_dir" "$branch_name"
    else
        echo -e "${BLUE}创建新的Git分支和工作树...${NC}"
        # 从当前分支创建新分支和工作树
        git worktree add -b "$branch_name" "$branch_dir"
    fi
    
    if [ $? -eq 0 ]; then
        # 创建分支信息文件
        cat > "$branch_dir/info.json" << EOF
{
    "name": "$branch_name",
    "created": "$(date -Iseconds)",
    "description": "",
    "status": "active",
    "type": "git-worktree"
}
EOF
        
        # 创建返回主目录的便捷脚本
        cat > "$branch_dir/back-to-main.sh" << 'EOF'
#!/bin/bash
cd ../..
echo "已返回主项目目录"
exec bash
EOF
        chmod +x "$branch_dir/back-to-main.sh"
        
        echo -e "${GREEN}成功创建Git工作树: $branch_name${NC}"
        echo -e "${BLUE}位置: $branch_dir${NC}"
        echo -e "${YELLOW}使用 './trees-manager.sh switch $branch_name' 切换到此分支${NC}"
    else
        echo -e "${RED}创建工作树失败${NC}"
        return 1
    fi
}

# 切换分支（实际切换目录）
switch_branch() {
    local branch_name="$1"
    if [ -z "$branch_name" ]; then
        echo -e "${RED}错误: 请提供分支名${NC}"
        return 1
    fi
    
    local branch_dir="$TREES_DIR/$branch_name"
    if [ ! -d "$branch_dir" ]; then
        echo -e "${RED}错误: 分支 '$branch_name' 不存在${NC}"
        return 1
    fi
    
    # 保存当前分支信息
    echo "$branch_name" > "$CURRENT_BRANCH_FILE"
    
    echo -e "${GREEN}切换到分支: $branch_name${NC}"
    echo -e "${BLUE}目录: $branch_dir${NC}"
    
    # 显示分支信息
    if [ -f "$branch_dir/info.json" ]; then
        local description=$(grep '"description"' "$branch_dir/info.json" | sed 's/.*"description": *"\([^"]*\)".*/\1/')
        if [ -n "$description" ]; then
            echo -e "${BLUE}描述: $description${NC}"
        fi
    fi
    
    # 切换到分支目录
    cd "$branch_dir"
    
    # 启动新的shell会话，设置提示符
    export TREES_BRANCH="$branch_name"
    exec bash --rcfile <(echo "
        PS1='[\[\e[32m\]$branch_name\[\e[0m\]] \u \[\e[33m\]\w\[\e[0m\] \$ '
        export TREES_BRANCH='$branch_name'
        echo -e '\033[32m🌿 当前分支: $branch_name\033[0m'
        echo -e '\033[33m📁 工作目录: '\$(pwd)'\033[0m'
        echo -e '\033[36m💡 使用 exit 返回主目录\033[0m'
        echo ''
    ")
}

# 列出所有分支
list_branches() {
    ensure_trees_dir
    
    echo -e "${BLUE}所有开发分支:${NC}"
    echo ""
    
    local current_branch=""
    if [ -f "$CURRENT_BRANCH_FILE" ]; then
        current_branch=$(cat "$CURRENT_BRANCH_FILE")
    fi
    
    for branch_dir in "$TREES_DIR"/*/; do
        if [ -d "$branch_dir" ]; then
            local branch_name=$(basename "$branch_dir")
            local marker=" "
            
            if [ "$branch_name" = "$current_branch" ]; then
                marker="*"
                echo -e "  ${GREEN}$marker $branch_name (当前分支)${NC}"
            else
                echo "  $marker $branch_name"
            fi
            
            # 显示分支信息
            local info_file="$branch_dir/info.json"
            if [ -f "$info_file" ]; then
                local created=$(grep '"created"' "$info_file" | sed 's/.*"created": *"\([^"]*\)".*/\1/')
                local description=$(grep '"description"' "$info_file" | sed 's/.*"description": *"\([^"]*\)".*/\1/')
                
                echo "    创建时间: $created"
                if [ -n "$description" ]; then
                    echo "    描述: $description"
                fi
            fi
            echo ""
        fi
    done
}

# 显示当前状态
show_status() {
    ensure_trees_dir
    
    local current_branch=""
    if [ -f "$CURRENT_BRANCH_FILE" ]; then
        current_branch=$(cat "$CURRENT_BRANCH_FILE")
        echo -e "${GREEN}当前分支: $current_branch${NC}"
        
        local branch_dir="$TREES_DIR/$current_branch"
        if [ -f "$branch_dir/changes.log" ]; then
            echo -e "${BLUE}最近变更:${NC}"
            tail -5 "$branch_dir/changes.log" | sed 's/^/  /'
        fi
    else
        echo -e "${YELLOW}没有活动分支${NC}"
    fi
    
    echo ""
    echo -e "${BLUE}Git 状态:${NC}"
    git status --short
}

# 保存进度
save_progress() {
    local message="$1"
    if [ -z "$message" ]; then
        echo -e "${RED}错误: 请提供保存消息${NC}"
        return 1
    fi
    
    local current_branch=""
    if [ -f "$CURRENT_BRANCH_FILE" ]; then
        current_branch=$(cat "$CURRENT_BRANCH_FILE")
    else
        echo -e "${RED}错误: 没有活动分支${NC}"
        return 1
    fi
    
    local branch_dir="$TREES_DIR/$current_branch"
    local timestamp=$(date -Iseconds)
    
    # 记录变更
    echo "[$timestamp] $message" >> "$branch_dir/changes.log"
    
    # 备份当前修改的文件
    local backup_dir="$branch_dir/modified_files/$(date +%Y%m%d_%H%M%S)"
    mkdir -p "$backup_dir"
    
    # 查找修改的文件并备份
    git status --porcelain | while read line; do
        local status="${line:0:2}"
        local file="${line:3}"
        
        if [[ "$status" =~ [MAD] ]]; then
            if [ -f "$file" ]; then
                local file_dir=$(dirname "$backup_dir/$file")
                mkdir -p "$file_dir"
                cp "$file" "$backup_dir/$file"
            fi
        fi
    done
    
    echo -e "${GREEN}进度已保存: $message${NC}"
}

# 合并分支
merge_branch() {
    local branch_name="$1"
    if [ -z "$branch_name" ]; then
        echo -e "${RED}错误: 请提供要合并的分支名${NC}"
        return 1
    fi
    
    local branch_dir="$TREES_DIR/$branch_name"
    if [ ! -d "$branch_dir" ]; then
        echo -e "${RED}错误: 分支 '$branch_name' 不存在${NC}"
        return 1
    fi
    
    echo -e "${YELLOW}准备合并分支: $branch_name${NC}"
    echo -e "${YELLOW}请确保已提交所有更改到 git${NC}"
    echo ""
    
    # 显示分支变更历史
    if [ -f "$branch_dir/changes.log" ]; then
        echo -e "${BLUE}分支变更历史:${NC}"
        cat "$branch_dir/changes.log" | sed 's/^/  /'
        echo ""
    fi
    
    read -p "确认合并? (y/N): " confirm
    if [[ "$confirm" =~ ^[Yy]$ ]]; then
        # 标记分支为已合并
        if [ -f "$branch_dir/info.json" ]; then
            sed -i '' 's/"status": "active"/"status": "merged"/' "$branch_dir/info.json"
        fi
        
        echo -e "${GREEN}分支 '$branch_name' 已标记为已合并${NC}"
        echo -e "${YELLOW}请手动执行 git 合并操作${NC}"
    else
        echo -e "${YELLOW}合并已取消${NC}"
    fi
}

# 删除分支和Git工作树
delete_branch() {
    local branch_name="$1"
    if [ -z "$branch_name" ]; then
        echo -e "${RED}错误: 请提供分支名${NC}"
        return 1
    fi
    
    local branch_dir="$TREES_DIR/$branch_name"
    if [ ! -d "$branch_dir" ]; then
        echo -e "${RED}错误: 分支 '$branch_name' 不存在${NC}"
        return 1
    fi
    
    echo -e "${RED}警告: 将删除Git分支 '$branch_name' 和工作树${NC}"
    
    # 检查是否有未提交的更改
    cd "$branch_dir" 2>/dev/null
    if [ $? -eq 0 ]; then
        local uncommitted=$(git status --porcelain 2>/dev/null | wc -l)
        if [ "$uncommitted" -gt 0 ]; then
            echo -e "${YELLOW}分支有 $uncommitted 个未提交的更改:${NC}"
            git status --short
            echo ""
        fi
        cd ../..
    fi
    
    read -p "确认删除分支 '$branch_name'? (y/N): " confirm
    
    if [[ "$confirm" =~ ^[Yy]$ ]]; then
        # 删除Git工作树
        git worktree remove "$branch_dir" --force
        
        # 删除Git分支
        git branch -D "$branch_name" 2>/dev/null
        
        # 清除当前分支记录
        local current_branch=""
        if [ -f "$CURRENT_BRANCH_FILE" ]; then
            current_branch=$(cat "$CURRENT_BRANCH_FILE")
            if [ "$current_branch" = "$branch_name" ]; then
                rm -f "$CURRENT_BRANCH_FILE"
            fi
        fi
        
        echo -e "${GREEN}Git分支和工作树 '$branch_name' 已删除${NC}"
    else
        echo -e "${YELLOW}删除已取消${NC}"
    fi
}

# 备份所有分支
backup_trees() {
    ensure_trees_dir
    
    local backup_file="trees-backup-$(date +%Y%m%d_%H%M%S).tar.gz"
    
    tar -czf "$backup_file" "$TREES_DIR"
    
    echo -e "${GREEN}已创建备份文件: $backup_file${NC}"
}

# 主函数
main() {
    case "$1" in
        "create")
            create_branch "$2"
            ;;
        "switch")
            switch_branch "$2"
            ;;
        "list")
            list_branches
            ;;
        "status")
            show_status
            ;;
        "save")
            save_progress "$2"
            ;;
        "merge")
            merge_branch "$2"
            ;;
        "delete")
            delete_branch "$2"
            ;;
        "backup")
            backup_trees
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