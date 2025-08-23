#!/bin/bash
# Linus审查数据结构 - 直接、残酷、准确

echo "=== Linus对projects.json数据结构的审查 ==="

python3 -c "
import json
import os

# 读取数据
with open('./projects-backup-20250823-070551.json') as f:
    projects = json.load(f)

print('=== LINUS TORVALDS DATA STRUCTURE REVIEW ===')
print()

print('GOOD SHIT:')
print('- JSON格式: 可读、可解析、不是XML垃圾')
print('- 扁平数组结构: 简单直接，不搞嵌套地狱')
print('- 每个项目有UUID: 好，至少不是靠路径做主键')
print('- Git信息分离: commitCount, lastCommitDate - 清晰')
print()

print('QUESTIONABLE CHOICES:')
print('- fileSystemInfo嵌套: 为什么不直接放在顶层?')
print('- checksum格式奇怪: \"timestamp_counter\" - 能用但不优雅')
print('- 路径用绝对路径: 不便携，但至少明确')
print()

print('STATISTICS:')
print(f'总项目数: {len(projects)}')

# 统计标签
all_tags = set()
tagged_projects = 0
for p in projects:
    if p.get('tags'):
        tagged_projects += 1
        all_tags.update(p['tags'])

print(f'有标签项目: {tagged_projects}/{len(projects)} ({tagged_projects/len(projects)*100:.1f}%)')
print(f'不同标签: {len(all_tags)}')

# 检查数据一致性
print()
print('DATA CONSISTENCY CHECK:')
required_fields = ['id', 'name', 'path', 'tags', 'lastModified']
inconsistent = 0
for i, p in enumerate(projects):
    missing = [f for f in required_fields if f not in p]
    if missing:
        inconsistent += 1
        if inconsistent <= 3:  # 只显示前3个
            print(f'项目 {i}: 缺少字段 {missing}')

if inconsistent == 0:
    print('✓ 所有项目都有必需字段')
else:
    print(f'⚠ {inconsistent}个项目有字段缺失')

print()
print('LINUS VERDICT: \"This is actually not completely braindead.\"')
print('\"At least you stored the fucking data instead of losing it.\"')
"
