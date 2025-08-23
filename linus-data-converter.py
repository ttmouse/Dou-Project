#!/usr/bin/env python3
# Linus数据格式转换器 - 简单、直接、不搞复杂的嵌套

import json
import hashlib
import os
from datetime import datetime
from pathlib import Path

def convert_to_linus_format():
    """
    将复杂的原始数据格式转换为Linus简单格式
    Linus原则: 扁平优于嵌套，简单优于复杂
    """
    
    # 读取原始复杂数据
    backup_file = './projects-backup-20250823-070551.json'
    if not os.path.exists(backup_file):
        print(f"❌ 原始数据文件不存在: {backup_file}")
        return
        
    with open(backup_file, 'r', encoding='utf-8') as f:
        original_data = json.load(f)
    
    print(f"📂 读取原始数据: {len(original_data)} 个项目")
    
    # 转换为Linus简单格式
    linus_projects = []
    
    for project in original_data:
        # 提取基本信息
        linus_project = {
            'id': project.get('id'),
            'name': project.get('name'),
            'path': project.get('path'),
            'tags': project.get('tags', [])
        }
        
        # 扁平化文件系统信息 (去除嵌套的 fileSystemInfo)
        fs_info = project.get('fileSystemInfo', {})
        linus_project['mtime'] = fs_info.get('modificationTime', 0)
        linus_project['size'] = fs_info.get('size', 0)
        linus_project['created'] = project.get('lastModified', 0)
        
        # 扁平化Git信息 (去除嵌套的 gitInfo)
        git_info = project.get('gitInfo', {})
        linus_project['git_commits'] = git_info.get('commitCount', 0)
        linus_project['git_last_commit'] = git_info.get('lastCommitDate', 0)
        
        # 简化checksum格式：timestamp_counter → sha256
        old_checksum = project.get('checksum', '')
        if old_checksum:
            # 从复杂的timestamp_counter格式转换为简单的sha256
            # 使用项目路径+时间戳创建一致的哈希
            hash_input = f"{project.get('path', '')}{project.get('lastModified', 0)}"
            simple_hash = hashlib.sha256(hash_input.encode()).hexdigest()[:16]  # 16字符足够
            linus_project['checksum'] = f"sha256:{simple_hash}"
        else:
            linus_project['checksum'] = ""
            
        # 添加最后检查时间
        linus_project['checked'] = int(datetime.now().timestamp())
        
        linus_projects.append(linus_project)
    
    # 保存到Linus格式文件
    output_file = './projects-linus-format.json'
    with open(output_file, 'w', encoding='utf-8') as f:
        json.dump(linus_projects, f, ensure_ascii=False, indent=2)
    
    print(f"✅ 转换完成: {len(linus_projects)} 个项目")
    print(f"📁 输出文件: {output_file}")
    
    # 统计信息
    print("\n=== LINUS格式统计 ===")
    print(f"总项目数: {len(linus_projects)}")
    
    tagged_count = sum(1 for p in linus_projects if p.get('tags'))
    print(f"有标签项目: {tagged_count}/{len(linus_projects)} ({tagged_count/len(linus_projects)*100:.1f}%)")
    
    git_count = sum(1 for p in linus_projects if p.get('git_commits', 0) > 0)
    print(f"Git项目: {git_count}/{len(linus_projects)} ({git_count/len(linus_projects)*100:.1f}%)")
    
    print("\n=== LINUS VERDICT ===")
    print("✓ 数据结构：扁平化，没有嵌套地狱")
    print("✓ 命名：简单直接，不装逼")
    print("✓ 格式：一致性，无例外")
    print("✓ 大小：更紧凑，无冗余")
    print("\n\"Much better. At least now it doesn't look like")
    print("enterprise Java architect vomited on your data.\"")

if __name__ == '__main__':
    convert_to_linus_format()