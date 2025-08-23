# 功能对比检查清单

## 标签管理功能对比

### 旧架构 (TagManager + 6个组件)
- [ ] 创建标签 - `addTag(_ tag: String, color: Color)`
- [ ] 删除标签 - `removeTag(_ tag: String)`
- [ ] 重命名标签 - `renameTag(_ oldName: String, to newName: String, color: Color)`
- [ ] 标签颜色管理 - `getColor(for tag: String)`, `setColor(_ color: Color, for tag: String)`
- [ ] 标签隐藏/显示 - `toggleTagVisibility(_ tag: String)`, `isTagHidden(_ tag: String)`
- [ ] 批量标签操作 - `addTagToProjects(projectIds: Set<UUID>, tag: String)`
- [ ] 标签统计 - `getUsageCount(for tag: String)`
- [ ] 系统标签同步 - `saveTagsToSystem()`, `loadSystemTags()`

### 新架构 (CoreTagManager) ✅
- [x] 创建标签 - `addTag(_ tag: String, color: Color)` ✅
- [x] 删除标签 - `removeTag(_ tag: String)` ✅
- [x] 重命名标签 - `renameTag(_ oldName: String, to newName: String, color: Color)` ✅
- [x] 标签颜色管理 - `getColor(for tag: String)`, `setColor(_ color: Color, for tag: String)` ✅
- [x] 标签隐藏/显示 - `toggleTagVisibility(_ tag: String)`, `isTagHidden(_ tag: String)` ✅
- [ ] 批量标签操作 - 需要项目管理器配合实现
- [x] 标签统计 - `updateTagUsage()`, `getUsageCount(for tag: String)` ✅
- [ ] 系统标签同步 - 暂不实现，保持与现有版本一致

## 项目管理功能对比

### 旧架构 (ProjectOperationManager + ProjectSortManager + ProjectIndex)
- [ ] 项目扫描 - `scanDirectory(_ path: String)`
- [ ] 项目注册 - `registerProject(_ project: Project)`
- [ ] 项目排序 - `setSortCriteria(_ criteria: SortCriteria, ascending: Bool)`
- [ ] 项目过滤 - `getFilteredProjects(withTags tags: Set<String>, searchText: String)`
- [ ] 批量操作 - `registerProjects(_ projects: [Project])`
- [ ] 缓存管理 - `saveAllToCache()`, `loadProjectsFromCache()`
- [ ] 增量更新 - `incrementallyReloadProjects()`

### 新架构 (ProjectManager)
- [ ] 项目扫描 - 待实现
- [ ] 项目注册 - 待实现
- [ ] 项目排序 - 待实现
- [ ] 项目过滤 - 待实现
- [ ] 批量操作 - 待实现
- [ ] 缓存管理 - 待实现
- [ ] 增量更新 - 待实现

## 文件监控功能对比

### 旧架构 (DirectoryWatcher)
- [ ] 目录添加 - `addWatchedDirectory(_ path: String)`
- [ ] 目录移除 - `removeWatchedDirectory(_ path: String)`
- [ ] 文件变化检测 - `incrementallyReloadProjects()`
- [ ] 监视目录持久化 - `saveWatchedDirectories()`, `loadWatchedDirectories()`

### 新架构 (FileWatcher)
- [ ] 目录添加 - 待实现
- [ ] 目录移除 - 待实现
- [ ] 文件变化检测 - 待实现
- [ ] 监视目录持久化 - 待实现

## UI 绑定对比

### 旧架构 (@Published 属性)
- [ ] `@Published var allTags: Set<String>`
- [ ] `@Published var projects: [UUID: Project]`
- [ ] `@Published var watchedDirectories: Set<String>`
- [ ] `@Published var hiddenTags: Set<String>`
- [ ] `@Published var enableAutoIncrementalUpdate: Bool`

### 新架构
- [ ] 相同的 @Published 属性 - 待实现

## 验证步骤

1. **编译测试** - 新架构能否编译通过
2. **功能测试** - 每个功能点都能正常工作
3. **数据兼容性测试** - 新架构能读取旧数据
4. **UI交互测试** - 所有UI操作都正常响应
5. **性能对比** - 新架构不能比旧架构慢

## 替换策略

1. **Phase 1**: 创建新文件，实现核心功能
2. **Phase 2**: 在新文件中通过所有功能测试
3. **Phase 3**: 修改 ContentView 使用新的管理器
4. **Phase 4**: 验证UI功能完全正常
5. **Phase 5**: 删除旧文件（保留在备份中）

## 回滚计划

如果新架构出现任何问题：
1. 立即切换回旧架构（修改 ContentView）
2. 检查数据完整性
3. 分析失败原因
4. 修复后重新尝试