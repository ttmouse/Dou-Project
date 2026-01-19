# .trees 简单使用指南

## 🎯 你想要的效果

```bash
./trees-manager.sh switch dashboard
# 等价于
cd .trees/dashboard
```

但更智能：会创建独立的工作环境，终端提示符显示当前分支。

## 🚀 快速上手

### 1. 创建分支
```bash
# 创建一个名为 dashboard 的分支
./trees-manager.sh create dashboard

# 输出：
# 创建分支工作区: dashboard
# 正在复制项目文件...
# 成功创建分支: dashboard
```

### 2. 切换到分支
```bash
# 切换到 dashboard 分支（相当于 cd .trees/dashboard）
./trees-manager.sh switch dashboard

# 输出：
# 切换到分支: dashboard
# 目录: .trees/dashboard
# 当前分支: dashboard
# 工作目录: /Users/douba/Projects/project-list/.trees/dashboard
# 使用 exit 返回主目录

# 注意：终端提示符现在变为：
# [dashboard] douba …/project-list/.trees/dashboard ❯
```

### 3. 在分支中工作
现在你在独立的工作环境中：
```bash
# 查看文件（独立副本）
ls Sources/

# 编辑代码
nano Sources/ProjectManager/Views/DashboardView.swift

# 编译（不影响主分支）
swift build

# Git提交（在分支中）
git add .
git commit -m "添加仪表盘功能"
```

### 4. 返回主目录
```bash
# 方法1：使用便捷脚本
./back-to-main.sh

# 方法2：直接退出
exit

# 现在回到主项目目录
# douba …/project-list   main ✘!?⇡   base   15:38  ❯
```

## 📋 基本命令

```bash
# 查看所有分支
./trees-manager.sh list

# 查看当前状态  
./trees-manager.sh status

# 删除分支
./trees-manager.sh delete dashboard
```

## 🔥 核心优势

### 真正的隔离
```bash
# 在主目录
douba …/project-list ❯ swift build
# 编译主分支代码

# 在dashboard分支  
[dashboard] douba …/.trees/dashboard ❯ swift build
# 编译dashboard分支代码
```

### 同时开发多个功能
```bash
# 终端窗口1：开发仪表盘
./trees-manager.sh switch dashboard
[dashboard] douba …/.trees/dashboard ❯

# 终端窗口2：修复bug  
./trees-manager.sh switch bugfix
[bugfix] douba …/.trees/bugfix ❯
```

## 🎯 实际使用场景

### 场景1：紧急bug修复
```bash
# 正在开发新功能 dashboard
./trees-manager.sh switch dashboard
[dashboard] # 编码中...

# 发现紧急bug，新建修复分支
# 打开新终端
./trees-manager.sh create urgent_fix
./trees-manager.sh switch urgent_fix
[urgent_fix] # 修复bug

# 修复完成，回到dashboard继续开发
./trees-manager.sh switch dashboard
[dashboard] # 继续编码
```

### 场景2：尝试不同方案
```bash
# 尝试方案A
./trees-manager.sh create approach_A
./trees-manager.sh switch approach_A
[approach_A] # 实现方案A

# 尝试方案B
./trees-manager.sh create approach_B  
./trees-manager.sh switch approach_B
[approach_B] # 实现方案B

# 对比两种方案，选择更好的
```

就这么简单！现在 `./trees-manager.sh switch dashboard` 真的等于 `cd .trees/dashboard`，但功能更强大！ 🎉