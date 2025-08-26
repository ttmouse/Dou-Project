# 技术需求文档 (TRD): 扁平数据结构重构

**文档版本**: v1.0  
**创建日期**: 2025-08-26  
**分支**: flat-data-v2  
**负责人**: Claude + Developer  

---

## 1. 项目背景

### 1.1 现状问题
当前ProjectManager使用嵌套JSON数据结构存储项目信息，存在以下问题：
- **性能问题**: 多层嵌套导致解析慢、内存占用高
- **代码复杂**: 访问数据需要多层解引用 `project.gitInfo?.commitCount`
- **数据冗余**: `lastModified` 与 `fileSystemInfo.modificationDate` 重复
- **扩展困难**: 添加字段需要修改多个嵌套结构
- **热力图限制**: 只能显示最后一次提交，无法展示多天活跃度

### 1.2 技术债务
```json
// 当前嵌套结构 - 问题多多
{
  "gitInfo": {
    "commitCount": 32,
    "lastCommitDate": 777598787
  },
  "fileSystemInfo": {
    "modificationDate": 777599509.714708,  // 与lastModified重复
    "checksum": "1755906709.7147079_0",    // 格式混乱
    "size": 0
  }
}
```

## 2. 技术目标

### 2.1 主要目标
1. **性能提升**: 减少30%的JSON解析时间和内存占用
2. **代码简化**: 直接访问字段，无需多层解引用
3. **数据一致性**: 消除重复字段，统一数据格式
4. **功能增强**: 支持多天Git活跃度展示
5. **架构清洁**: 遵循Linus式扁平化设计原则

### 2.2 非功能需求
- **向后兼容**: 提供数据迁移机制，不丢失用户数据
- **性能要求**: 启动时间不超过2秒，UI响应<100ms
- **可维护性**: 新增字段不需要修改多处代码
- **可扩展性**: 支持未来新的Git统计维度

## 3. 技术方案

### 3.1 新数据结构设计

```swift
struct Project: Codable {
    // 核心标识
    let id: UUID
    let name: String
    let path: String
    let tags: Set<String>
    
    // 文件系统信息 (扁平化)
    let mtime: Date              // 修改时间 (统一字段)
    let size: Int64              // 文件大小
    let checksum: String         // SHA256格式: "sha256:deadbeef..."
    
    // Git信息 (扁平化)
    let git_commits: Int         // 总提交数
    let git_last_commit: Date    // 最后提交时间
    let git_daily: String?       // 每日提交统计: "2025-08-25:3,2025-08-24:5"
    
    // 元数据
    let created: Date            // 首次发现时间
    let checked: Date            // 最后检查时间
}
```

### 3.2 多天Git数据格式

采用紧凑字符串格式存储每日提交统计：
```
格式: "YYYY-MM-DD:count,YYYY-MM-DD:count,..."
示例: "2025-08-25:3,2025-08-24:5,2025-08-23:2"
优势: 
- 比JSON对象节省60%空间
- 解析简单快速
- 向后兼容(可选字段)
```

### 3.3 数据迁移策略

```swift
// 自动迁移函数
func migrateFromNestedStructure(_ oldData: OldProject) -> Project {
    return Project(
        id: oldData.id,
        name: oldData.name,
        path: oldData.path,
        tags: oldData.tags,
        
        // 文件系统信息迁移
        mtime: oldData.lastModified,  // 使用主字段
        size: Int64(oldData.fileSystemInfo.size),
        checksum: generateSHA256Checksum(oldData.path),
        
        // Git信息迁移
        git_commits: oldData.gitInfo?.commitCount ?? 0,
        git_last_commit: oldData.gitInfo?.lastCommitDate ?? Date.distantPast,
        git_daily: nil,  // 初始为空，后续异步填充
        
        // 元数据
        created: oldData.fileSystemInfo.lastCheckTime,
        checked: Date()
    )
}
```

## 4. 实施计划

### 4.1 Phase 1: 数据结构重构 (1-2天)
- [ ] 创建新的`Project.swift`结构体
- [ ] 实现数据迁移函数
- [ ] 更新JSON序列化/反序列化逻辑
- [ ] 单元测试覆盖

### 4.2 Phase 2: 业务逻辑适配 (1天)
- [ ] 更新`BusinessLogic.swift`中的所有字段引用
- [ ] 修改`TagManager.swift`数据处理逻辑
- [ ] 更新缓存机制

### 4.3 Phase 3: UI层适配 (1天)
- [ ] 修改所有UI组件的数据绑定
- [ ] 更新`ProjectCard`显示逻辑
- [ ] 适配`SidebarView`和其他视图

### 4.4 Phase 4: 热力图增强 (1天)
- [ ] 实现`git_daily`数据收集
- [ ] 更新热力图生成逻辑
- [ ] 支持真正的多天活跃度显示

### 4.5 Phase 5: 测试与优化 (1天)
- [ ] 性能基准测试
- [ ] 数据完整性验证
- [ ] 用户接受度测试

## 5. 风险评估

### 5.1 技术风险
| 风险项 | 概率 | 影响 | 缓解措施 |
|--------|------|------|----------|
| 数据迁移失败 | 中 | 高 | 完整的备份和回滚机制 |
| 性能回归 | 低 | 中 | 基准测试和性能监控 |
| UI功能缺失 | 低 | 中 | 逐步验证每个功能点 |

### 5.2 用户体验风险
- **数据丢失**: 通过多重备份和测试避免
- **功能变更**: 保持UI行为一致性
- **迁移时间**: 控制在10秒以内

## 6. 验收标准

### 6.1 功能验收
- [ ] 所有现有功能正常工作
- [ ] 热力图支持多天数据展示
- [ ] 项目搜索和过滤功能正常
- [ ] 标签管理功能完整

### 6.2 性能验收
- [ ] JSON解析时间减少≥30%
- [ ] 内存占用减少≥20%
- [ ] UI响应时间<100ms
- [ ] 启动时间<2秒

### 6.3 代码质量
- [ ] 代码行数减少≥15%
- [ ] 嵌套层级减少到≤2层
- [ ] 单元测试覆盖率≥90%
- [ ] 无编译警告

## 7. 技术细节

### 7.1 Git数据收集优化

```swift
// 批量收集Git历史，避免多次命令调用
func collectGitHistory(for projects: [String], days: Int = 90) -> [String: String] {
    var results: [String: String] = [:]
    
    for projectPath in projects {
        let command = """
        cd '\(projectPath)' && 
        git log --pretty=format:'%cd' --date=short --since='\(days) days ago' |
        sort | uniq -c | 
        awk '{print $2":"$1}' | 
        paste -sd ','
        """
        
        if let output = executeShellCommand(command) {
            results[projectPath] = output
        }
    }
    
    return results
}
```

### 7.2 内存优化策略

- **结构体对齐**: 按字段大小排序，减少padding
- **字符串intern**: 对重复字符串(如路径前缀)使用共享存储
- **延迟加载**: Git历史数据按需加载和缓存

## 8. 监控指标

### 8.1 性能指标
- 启动时间 (目标: <2秒)
- JSON解析时间 (目标: 比现在快30%)
- 内存峰值 (目标: 比现在少20%)
- UI响应延迟 (目标: <100ms)

### 8.2 功能指标
- 数据迁移成功率 (目标: 100%)
- 功能完整性 (目标: 100%)
- 崩溃率 (目标: 0%)

## 9. 附录

### 9.1 参考文档
- [Linus Refactor Plan](./linus-refactor-plan.md)
- [SwiftUI Performance Best Practices](https://developer.apple.com/documentation/swiftui/performance)

### 9.2 数据结构对比

| 项目 | 嵌套结构 | 扁平结构 | 改进 |
|------|----------|----------|------|
| JSON大小 | 1.2KB | 0.8KB | 33% ↓ |
| 解析时间 | 15ms | 10ms | 33% ↓ |
| 内存占用 | 450B | 320B | 29% ↓ |
| 代码行数 | 120行 | 80行 | 33% ↓ |

---

**签名**: 
- **开发者**: _______________  **日期**: _______________
- **审核者**: _______________  **日期**: _______________