#!/bin/bash

# 为分支创建符号链接，让IDE显示更友好的名称
create_branch_link() {
    local branch_name="$1"
    local link_name="ProjectManager-$branch_name"
    
    if [ -L "$link_name" ]; then
        rm "$link_name"
    fi
    
    ln -s ".trees/$branch_name" "$link_name"
    echo "创建链接: $link_name -> .trees/$branch_name"
}

# 使用方式: ./create-branch-link.sh dash
if [ -n "$1" ]; then
    create_branch_link "$1"
else
    echo "使用方式: $0 <branch_name>"
fi