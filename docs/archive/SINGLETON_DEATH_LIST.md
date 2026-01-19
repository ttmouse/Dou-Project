# 🔪 单例死刑名单 - Linus式清理计划

## 主要罪犯 (Application Singletons)

### 1. **TagManager.shared** ⚰️ 最大罪犯
- **位置**: `Sources/ProjectManager/Models/TagManager.swift:17`
- **罪状**: 核心业务逻辑单例，破坏测试能力
- **处决方案**: 使用依赖注入容器替代
- **影响评估**: HIGH - 核心组件，需要谨慎处理

### 2. **SelectAllHandler.shared** ⚰️ UI单例
- **位置**: `Sources/ProjectManager/Utils/ViewModifiers.swift:27`  
- **罪状**: 全局UI事件处理单例
- **处决方案**: 通过环境对象或父视图管理
- **影响评估**: MEDIUM - UI功能，相对安全

### 3. **TagSystemSync中的TagManager.shared依赖** ⚰️ 间接罪犯
- **位置**: `Sources/ProjectManager/Models/TagSystemSync.swift:145`
- **罪状**: 通过TagManager.shared获取颜色
- **处决方案**: 使用TagSystemSyncV2的颜色提供接口
- **影响评估**: LOW - 已有替代方案

## 系统单例 (保留)

这些是macOS系统提供的，不是我们的罪犯：
- `NSWorkspace.shared` - 系统工作空间
- `NSApplication.shared` - 应用程序实例

## 处决策略

### Phase 2.1: 创建依赖注入基础设施
1. 创建 `ServiceContainer` 
2. 创建 `TagManagerFactory`
3. 更新应用启动流程

### Phase 2.2: TagManager.shared 处决
1. 保留旧接口（标记为deprecated）
2. 通过环境对象传递新实例
3. 逐步迁移所有调用点

### Phase 2.3: 其他单例清理
1. SelectAllHandler 重构为环境管理
2. 清理TagSystemSync依赖

### Phase 2.4: 验证和清理
1. 确保所有 `.shared` 调用都是系统的
2. 验证功能完整性
3. 清理废弃代码

## 成功标准

- [ ] 0个应用级单例
- [ ] 所有组件可独立测试
- [ ] 功能100%保持
- [ ] 编译无警告

---

> "Singletons are like cockroaches. Kill one, and you find ten more hiding in the code." - Linus (probably)