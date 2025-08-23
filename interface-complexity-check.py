#!/usr/bin/env python3
# Linus风格接口复杂度检查器
# 验证接口是否符合≤5方法≤3参数的要求

import os
import re
from pathlib import Path

def check_protocol_complexity():
    """检查协议接口复杂度"""
    
    protocols_file = "./Sources/ProjectManager/Protocols/LinusProtocols.swift"
    
    if not os.path.exists(protocols_file):
        print("❌ 协议文件不存在")
        return
    
    with open(protocols_file, 'r', encoding='utf-8') as f:
        content = f.read()
    
    print("=== Linus协议复杂度检查 ===\n")
    
    # 提取所有协议
    protocol_pattern = r'protocol\s+(\w+)[^{]*\{([^}]*)\}'
    protocols = re.findall(protocol_pattern, content, re.DOTALL)
    
    all_passed = True
    
    for protocol_name, protocol_body in protocols:
        print(f"协议: {protocol_name}")
        
        # 提取方法
        method_pattern = r'func\s+(\w+)\s*\([^)]*\)'
        methods = re.findall(method_pattern, protocol_body)
        
        method_count = len(methods)
        print(f"  方法数量: {method_count}")
        
        # 检查方法数量
        if method_count > 5:
            print(f"  ❌ 方法过多! 超过5个限制 ({method_count} > 5)")
            all_passed = False
        else:
            print(f"  ✅ 方法数量符合要求 ({method_count} ≤ 5)")
        
        # 检查每个方法的参数
        for method in methods:
            # 提取完整方法定义以检查参数
            method_def_pattern = rf'func\s+{method}\s*\(([^)]*)\)'
            method_match = re.search(method_def_pattern, protocol_body)
            if method_match:
                params_str = method_match.group(1).strip()
                if not params_str:
                    param_count = 0
                else:
                    # 简单计算参数数量（按逗号分割）
                    param_count = len([p for p in params_str.split(',') if p.strip()])
                
                print(f"    {method}(): {param_count} 参数", end="")
                if param_count > 3:
                    print(" ❌ 参数过多!")
                    all_passed = False
                else:
                    print(" ✅")
        
        print()
    
    print("=== 接口简化验证结果 ===")
    if all_passed:
        print("✅ 所有协议都符合Linus标准!")
        print("✅ 每个协议 ≤ 5个方法")
        print("✅ 每个方法 ≤ 3个参数")
        print("\n\"Good. At least you didn't make it worse.\"")
    else:
        print("❌ 部分协议不符合要求，需要进一步简化")
        print("\n\"This still looks like enterprise Java bullshit.\"")

def check_method_naming():
    """检查方法命名是否简单"""
    protocols_file = "./Sources/ProjectManager/Protocols/LinusProtocols.swift"
    
    if not os.path.exists(protocols_file):
        return
    
    with open(protocols_file, 'r', encoding='utf-8') as f:
        content = f.read()
    
    print("\n=== 方法命名简化检查 ===")
    
    # 提取所有方法名
    method_pattern = r'func\s+(\w+)'
    methods = re.findall(method_pattern, content)
    
    simple_methods = []
    complex_methods = []
    
    for method in methods:
        # 简单判断：短的方法名通常更简单
        if len(method) <= 6 and not '_' in method:
            simple_methods.append(method)
        else:
            complex_methods.append(method)
    
    print(f"简单方法名 ({len(simple_methods)}): {simple_methods}")
    if complex_methods:
        print(f"复杂方法名 ({len(complex_methods)}): {complex_methods}")
    else:
        print("✅ 所有方法名都够简单!")
    
    print(f"\n简化率: {len(simple_methods)}/{len(methods)} = {len(simple_methods)/len(methods)*100:.1f}%")

def check_implementation_complexity():
    """检查实现复杂度"""
    impl_files = [
        "./Sources/ProjectManager/Models/SimpleTagManager.swift",
        "./Sources/ProjectManager/Models/SimpleProjectManager.swift"
    ]
    
    print("\n=== 实现复杂度检查 ===")
    
    for file_path in impl_files:
        if not os.path.exists(file_path):
            continue
            
        print(f"\n文件: {os.path.basename(file_path)}")
        
        with open(file_path, 'r', encoding='utf-8') as f:
            content = f.read()
        
        # 统计方法数量
        method_pattern = r'func\s+\w+'
        methods = re.findall(method_pattern, content)
        print(f"  实现方法: {len(methods)}")
        
        # 统计行数
        lines = len(content.split('\n'))
        print(f"  代码行数: {lines}")
        
        # 统计复杂度指标
        if_count = len(re.findall(r'\bif\b', content))
        for_count = len(re.findall(r'\bfor\b', content))
        guard_count = len(re.findall(r'\bguard\b', content))
        
        complexity_score = if_count + for_count + guard_count
        print(f"  复杂度分数: {complexity_score} (if:{if_count} for:{for_count} guard:{guard_count})")
        
        if complexity_score < 20:
            print("  ✅ 复杂度合理")
        else:
            print("  ⚠️ 复杂度偏高，考虑进一步简化")

if __name__ == '__main__':
    check_protocol_complexity()
    check_method_naming()
    check_implementation_complexity()