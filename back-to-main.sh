#!/bin/bash
# 自动生成的返回主项目脚本
cd "/Users/douba/Projects/project-list"
if command -v cursor > /dev/null 2>&1; then
    cursor .
elif command -v code > /dev/null 2>&1; then
    code .
else
    open .
fi