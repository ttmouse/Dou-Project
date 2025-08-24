#!/bin/bash

# ProjectManager .trees 交互式菜单管理工具
# 使用 Git Worktree 实现分支管理

TREES_DIR=".trees"
CURRENT_BRANCH_FILE="$TREES_DIR/.current"

# 颜色定义
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m' # No Color

# 确保在Git仓库中
ensure_git_repo() {
    if [ ! -d ".git" ]; then
        echo -e "${RED}❌ 错误: 当前目录不是Git仓库${NC}"
        echo -e "${YELLOW}请在项目根目录运行此脚本${NC}"
        exit 1
    fi
}

# 确保 .trees 目录存在
ensure_trees_dir() {
    if [ ! -d "$TREES_DIR" ]; then
        mkdir -p "$TREES_DIR"
    fi
}

# 显示标题
show_header() {
    clear
    echo -e "${BOLD}${CYAN}╔══════════════════════════════════════════╗${NC}"
    echo -e "${BOLD}${CYAN}║           🌲 Trees 分支管理器             ║${NC}"
    echo -e "${BOLD}${CYAN}║         Git Worktree 交互式工具          ║${NC}"
    echo -e "${BOLD}${CYAN}╚══════════════════════════════════════════╝${NC}"
    echo ""
    
    # 显示当前状态
    local current_git_branch=$(git branch --show-current 2>/dev/null || echo "unknown")
    echo -e "${BLUE}📁 项目: ${BOLD}$(basename "$PWD")${NC}"
    echo -e "${BLUE}🌿 主分支: ${BOLD}$current_git_branch${NC}"
    
    # 显示最后使用的分支
    if [ -f "$CURRENT_BRANCH_FILE" ]; then
        local last_branch=$(cat "$CURRENT_BRANCH_FILE")
        echo -e "${BLUE}⏱️  最后使用: ${BOLD}$last_branch${NC}"
    fi
    
    echo ""
}

# 获取所有工作树分支
get_worktree_branches() {
    local branches=()
    if [ -d "$TREES_DIR" ]; then
        for branch_dir in "$TREES_DIR"/*/; do
            if [ -d "$branch_dir" ]; then
                local branch_name=$(basename "$branch_dir")
                branches+=("$branch_name")
            fi
        done
    fi
    echo "${branches[@]}"
}

# 显示主菜单
show_main_menu() {
    echo -e "${BOLD}🎯 请选择操作:${NC}"
    echo ""
    echo -e "${GREEN}1.${NC} 🆕 创建新分支"
    echo -e "${GREEN}2.${NC} 🔄 切换到分支"
    echo -e "${GREEN}3.${NC} 📋 查看所有分支"
    echo -e "${GREEN}4.${NC} 🗑️  删除分支"
    echo -e "${GREEN}5.${NC} 📊 显示状态"
    echo -e "${GREEN}0.${NC} 🚪 退出"
    echo ""
}

# 创建新分支
create_branch_interactive() {
    echo -e "${BOLD}${CYAN}🆕 创建新分支${NC}"
    echo ""
    
    read -p "请输入分支名称: " branch_name
    
    if [ -z "$branch_name" ]; then
        echo -e "${RED}❌ 分支名不能为空${NC}"
        read -p "按回车继续..."
        return
    fi
    
    local branch_dir="$TREES_DIR/$branch_name"
    if [ -d "$branch_dir" ]; then
        echo -e "${RED}❌ 分支 '$branch_name' 已存在${NC}"
        read -p "按回车继续..."
        return
    fi
    
    echo -e "${YELLOW}🔨 正在创建Git分支和工作树...${NC}"
    
    ensure_trees_dir
    
    # 检查分支是否已存在
    if git branch | grep -q "\\b$branch_name\\b"; then
        git worktree add "$branch_dir" "$branch_name"
    else
        git worktree add -b "$branch_name" "$branch_dir"
    fi
    
    if [ $? -eq 0 ]; then
        # 创建分支信息文件
        cat > "$branch_dir/.branch_info" << EOF
{
    "name": "$branch_name",
    "created": "$(date -Iseconds)",
    "description": "",
    "type": "git-worktree"
}
EOF
        
        # 创建返回主目录的便捷脚本
        cat > "$branch_dir/back-to-main.sh" << 'EOF'
#!/bin/bash
cd ../..
echo "🏠 已返回主项目目录"
exec bash
EOF
        chmod +x "$branch_dir/back-to-main.sh"
        
        echo -e "${GREEN}✅ 成功创建分支: $branch_name${NC}"
        echo ""
        
        read -p "是否立即切换到新分支? (y/N): " switch_now
        if [[ "$switch_now" =~ ^[Yy]$ ]]; then
            switch_to_branch "$branch_name"
            return
        fi
    else
        echo -e "${RED}❌ 创建工作树失败${NC}"
    fi
    
    read -p "按回车继续..."
}

# 切换分支交互式选择
switch_branch_interactive() {
    echo -e "${BOLD}${CYAN}🔄 切换到分支${NC}"
    echo ""
    
    local branches=($(get_worktree_branches))
    
    if [ ${#branches[@]} -eq 0 ]; then
        echo -e "${YELLOW}📭 没有找到可用的分支${NC}"
        echo -e "${BLUE}💡 请先创建一个分支${NC}"
        read -p "按回车继续..."
        return
    fi
    
    echo -e "${BLUE}可用的分支:${NC}"
    echo ""
    
    for i in "${!branches[@]}"; do
        local branch_name="${branches[$i]}"
        local branch_dir="$TREES_DIR/$branch_name"
        
        # 检查Git状态
        local status_info=""
        if [ -d "$branch_dir" ]; then
            cd "$branch_dir" 2>/dev/null
            local uncommitted=$(git status --porcelain 2>/dev/null | wc -l)
            if [ "$uncommitted" -gt 0 ]; then
                status_info=" ${YELLOW}($uncommitted 个更改)${NC}"
            else
                status_info=" ${GREEN}(干净)${NC}"
            fi
            cd ../.. > /dev/null
        fi
        
        echo -e "${GREEN}$((i+1)).${NC} $branch_name$status_info"
    done
    
    echo ""
    read -p "请选择分支编号 (1-${#branches[@]}): " choice
    
    if [[ "$choice" =~ ^[0-9]+$ ]] && [ "$choice" -ge 1 ] && [ "$choice" -le "${#branches[@]}" ]; then
        local selected_branch="${branches[$((choice-1))]}"
        switch_to_branch "$selected_branch"
    else
        echo -e "${RED}❌ 无效选择${NC}"
        read -p "按回车继续..."
    fi
}

# 切换到指定分支
switch_to_branch() {
    local branch_name="$1"
    local branch_dir="$TREES_DIR/$branch_name"
    local project_name=$(basename "$PWD")
    
    echo "$branch_name" > "$CURRENT_BRANCH_FILE"
    
    echo -e "${GREEN}🔄 切换到分支: $branch_name${NC}"
    echo -e "${BLUE}📂 工作目录: $branch_dir${NC}"
    echo ""
    
    # 显示分支信息
    if [ -f "$branch_dir/.branch_info" ]; then
        local description=$(grep '"description"' "$branch_dir/.branch_info" | sed 's/.*"description": *"\([^"]*\)".*/\1/')
        if [ -n "$description" ] && [ "$description" != "" ]; then
            echo -e "${BLUE}📝 描述: $description${NC}"
        fi
    fi
    
    echo -e "${CYAN}🚀 启动分支环境...${NC}"
    echo -e "${YELLOW}💡 使用 'exit' 或 '..' 返回主目录${NC}"
    echo -e "${YELLOW}💡 使用 'ts' 查看当前环境状态${NC}"
    echo ""
    
    # 切换到分支目录
    cd "$branch_dir"
    
    # 启动新的shell会话，设置提示符
    export TREES_BRANCH="$branch_name"
    
    # 创建临时的rcfile
    local temp_rcfile="/tmp/trees_rcfile_$$"
    cat > "$temp_rcfile" << EOF
# 加载用户的bashrc (如果存在)
[ -f ~/.bashrc ] && source ~/.bashrc
[ -f ~/.bash_profile ] && source ~/.bash_profile

# 设置更明显的终端标题：项目名-分支名
export PROMPT_COMMAND="echo -ne '\033]0;$project_name-$branch_name | \$(basename \\\$PWD)\007'"

# 设置彩色提示符，包含项目名和分支名
PS1='\[\e[1;36m\][$project_name:\[\e[1;32m\]$branch_name\[\e[1;36m\]]\[\e[0m\] \[\e[1;34m\]\u\[\e[0m\] \[\e[1;33m\]\W\[\e[0m\] \$ '

# 导出环境变量
export TREES_BRANCH='$branch_name'
export TREES_PROJECT='$project_name'

# 添加分支状态函数
trees_status() {
    echo -e '\033[1;32m当前 Trees 环境:\033[0m'
    echo -e '  项目: \033[1;34m$project_name\033[0m'
    echo -e '  分支: \033[1;32m$branch_name\033[0m'
    echo -e '  路径: \033[1;33m'\$(pwd)'\033[0m'
    echo -e '  Git: \033[0;36m'\$(git branch --show-current 2>/dev/null || echo "未知")'\033[0m'
}

# 添加快速返回函数  
back() {
    cd ../..
    echo -e '\033[1;36m🏠 已返回主项目目录\033[0m'
    rm -f "$temp_rcfile" 2>/dev/null
    exec bash
}

# 添加别名
alias ts='trees_status'
alias ..='back'

# 欢迎信息
echo -e '\033[1;36m╔══════════════════════════════════════════╗\033[0m'
echo -e '\033[1;36m║          🌲 Trees 分支环境               ║\033[0m'
echo -e '\033[1;36m╚══════════════════════════════════════════╝\033[0m'
echo -e '\033[1;32m🌿 当前分支: $branch_name\033[0m'
echo -e '\033[1;33m📁 工作目录: '\$(pwd)'\033[0m'
echo -e '\033[1;34m🏗️  项目名称: $project_name\033[0m'
echo ''
echo -e '\033[0;36m💡 提示: 终端标题显示 "$project_name-$branch_name"\033[0m'
echo -e '\033[0;35m💡 便捷命令: ts (状态) | .. (返回) | exit (退出)\033[0m'
echo ''
EOF
    
    # 增强的终端标题和提示符设置
    exec bash --rcfile "$temp_rcfile"
}

# 查看所有分支
list_branches_interactive() {
    echo -e "${BOLD}${CYAN}📋 所有分支列表${NC}"
    echo ""
    
    # 显示Git Worktree官方信息
    echo -e "${BLUE}🔗 Git Worktree 列表:${NC}"
    git worktree list
    echo ""
    
    local branches=($(get_worktree_branches))
    
    if [ ${#branches[@]} -eq 0 ]; then
        echo -e "${YELLOW}📭 没有找到Trees管理的分支${NC}"
    else
        echo -e "${BLUE}🌲 Trees 分支详情:${NC}"
        echo ""
        
        local current_branch=""
        if [ -f "$CURRENT_BRANCH_FILE" ]; then
            current_branch=$(cat "$CURRENT_BRANCH_FILE")
        fi
        
        for branch_name in "${branches[@]}"; do
            local branch_dir="$TREES_DIR/$branch_name"
            local marker="  "
            
            if [ "$branch_name" = "$current_branch" ]; then
                marker="👉"
                echo -e "${GREEN}$marker $branch_name (最后使用)${NC}"
            else
                echo -e "$marker $branch_name"
            fi
            
            # 显示详细信息
            if [ -f "$branch_dir/.branch_info" ]; then
                local created=$(grep '"created"' "$branch_dir/.branch_info" | sed 's/.*"created": *"\([^"]*\)".*/\1/' | cut -d'T' -f1)
                echo "     📅 创建: $created"
                
                # Git状态
                cd "$branch_dir" 2>/dev/null
                local uncommitted=$(git status --porcelain 2>/dev/null | wc -l)
                if [ "$uncommitted" -gt 0 ]; then
                    echo -e "     📊 状态: ${YELLOW}$uncommitted 个未提交更改${NC}"
                else
                    echo -e "     📊 状态: ${GREEN}干净${NC}"
                fi
                cd ../.. > /dev/null
            fi
            echo ""
        done
    fi
    
    read -p "按回车继续..."
}


# 删除分支交互式选择
delete_branch_interactive() {
    echo -e "${BOLD}${CYAN}🗑️ 删除分支${NC}"
    echo ""
    
    local branches=($(get_worktree_branches))
    
    if [ ${#branches[@]} -eq 0 ]; then
        echo -e "${YELLOW}📭 没有找到可删除的分支${NC}"
        read -p "按回车继续..."
        return
    fi
    
    echo -e "${RED}⚠️ 警告: 删除操作不可恢复!${NC}"
    echo ""
    echo -e "${BLUE}可删除的分支:${NC}"
    echo ""
    
    for i in "${!branches[@]}"; do
        local branch_name="${branches[$i]}"
        local branch_dir="$TREES_DIR/$branch_name"
        
        # 显示状态
        cd "$branch_dir" 2>/dev/null
        local uncommitted=$(git status --porcelain 2>/dev/null | wc -l)
        local status_info=""
        if [ "$uncommitted" -gt 0 ]; then
            status_info=" ${RED}($uncommitted 个未提交更改)${NC}"
        else
            status_info=" ${GREEN}(干净)${NC}"
        fi
        cd ../.. > /dev/null
        
        echo -e "${GREEN}$((i+1)).${NC} $branch_name$status_info"
    done
    
    echo ""
    read -p "请选择要删除的分支编号 (1-${#branches[@]}): " choice
    
    if [[ "$choice" =~ ^[0-9]+$ ]] && [ "$choice" -ge 1 ] && [ "$choice" -le "${#branches[@]}" ]; then
        local selected_branch="${branches[$((choice-1))]}"
        delete_branch "$selected_branch"
    else
        echo -e "${RED}❌ 无效选择${NC}"
        read -p "按回车继续..."
    fi
}

# 删除分支
delete_branch() {
    local branch_name="$1"
    local force_mode="$2"
    local branch_dir="$TREES_DIR/$branch_name"
    
    if [ "$force_mode" != "force" ]; then
        echo -e "${RED}⚠️ 即将删除分支 '$branch_name' 和所有相关数据${NC}"
        
        # 检查未提交更改
        cd "$branch_dir" 2>/dev/null
        local uncommitted=$(git status --porcelain 2>/dev/null | wc -l)
        if [ "$uncommitted" -gt 0 ]; then
            echo -e "${YELLOW}🔍 发现 $uncommitted 个未提交的更改:${NC}"
            git status --short
            echo ""
        fi
        cd ../.. > /dev/null
        
        read -p "确认删除分支 '$branch_name'? (y/N): " confirm
        
        if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
            echo -e "${YELLOW}🚫 删除已取消${NC}"
            read -p "按回车继续..."
            return
        fi
    fi
    
    echo -e "${YELLOW}🗑️ 正在删除...${NC}"
    
    # 删除Git工作树和分支
    git worktree remove "$branch_dir" --force
    git branch -D "$branch_name" 2>/dev/null
    
    # 清除当前分支记录
    if [ -f "$CURRENT_BRANCH_FILE" ]; then
        local current_branch=$(cat "$CURRENT_BRANCH_FILE")
        if [ "$current_branch" = "$branch_name" ]; then
            rm -f "$CURRENT_BRANCH_FILE"
        fi
    fi
    
    echo -e "${GREEN}✅ 分支 '$branch_name' 已删除${NC}"
    
    if [ "$force_mode" != "force" ]; then
        read -p "按回车继续..."
    fi
}

# 显示状态
show_status_interactive() {
    echo -e "${BOLD}${CYAN}📊 系统状态${NC}"
    echo ""
    
    # Git状态
    local current_git_branch=$(git branch --show-current)
    echo -e "${BLUE}🌿 当前Git分支: ${BOLD}$current_git_branch${NC}"
    
    local git_status=$(git status --porcelain | wc -l)
    if [ "$git_status" -gt 0 ]; then
        echo -e "${YELLOW}📝 主分支状态: $git_status 个更改${NC}"
    else
        echo -e "${GREEN}📝 主分支状态: 干净${NC}"
    fi
    
    echo ""
    
    # 工作树统计
    local branches=($(get_worktree_branches))
    echo -e "${BLUE}🌲 工作树统计:${NC}"
    echo "   📊 总分支数: ${#branches[@]}"
    
    if [ ${#branches[@]} -gt 0 ]; then
        local clean_count=0
        local dirty_count=0
        
        for branch_name in "${branches[@]}"; do
            local branch_dir="$TREES_DIR/$branch_name"
            cd "$branch_dir" 2>/dev/null
            local uncommitted=$(git status --porcelain 2>/dev/null | wc -l)
            if [ "$uncommitted" -gt 0 ]; then
                ((dirty_count++))
            else
                ((clean_count++))
            fi
            cd ../.. > /dev/null
        done
        
        echo -e "   ${GREEN}✅ 干净分支: $clean_count${NC}"
        echo -e "   ${YELLOW}📝 有更改分支: $dirty_count${NC}"
    fi
    
    echo ""
    echo -e "${BLUE}💾 磁盘使用:${NC}"
    if [ -d "$TREES_DIR" ]; then
        local size=$(du -sh "$TREES_DIR" 2>/dev/null | cut -f1)
        echo "   📁 .trees 目录: $size"
    fi
    
    echo ""
    read -p "按回车继续..."
}

# 主循环
main_loop() {
    ensure_git_repo
    ensure_trees_dir
    
    while true; do
        show_header
        show_main_menu
        
        read -p "请选择 (0-5): " choice
        echo ""
        
        case "$choice" in
            "1")
                create_branch_interactive
                ;;
            "2")
                switch_branch_interactive
                ;;
            "3")
                list_branches_interactive
                ;;
            "4")
                delete_branch_interactive
                ;;
            "5")
                show_status_interactive
                ;;
            "0")
                echo -e "${GREEN}👋 再见!${NC}"
                exit 0
                ;;
            *)
                echo -e "${RED}❌ 无效选择，请重新输入${NC}"
                read -p "按回车继续..."
                ;;
        esac
    done
}

# 启动程序
main_loop