# D-002：分层架构现状与单例

```json
{
  "id": "D-002",
  "kind": "decision",
  "status": "active",
  "summary": "Models + 纯函数 BusinessLogic + 中枢 TagManager + 单一 ViewModel；仍有 3 个单例",
  "scope": ["Sources/ProjectManager"],
  "sources": [
    "Sources/ProjectManager/Models/BusinessLogic.swift",
    "Sources/ProjectManager/Models/TagManager.swift",
    "Sources/ProjectManager/Models/TagManagerComponents.swift",
    "Sources/ProjectManager/Models/TagCache.swift",
    "Sources/ProjectManager/Models/HeatmapDataStore.swift",
    "Sources/ProjectManager/ViewModels/DashboardViewModel.swift",
    "CLAUDE.md"
  ],
  "key": "architecture-layering",
  "recorded_at": "2026-09-20"
}
```

## 当前分层实况（2026-09-20）

- **纯函数业务逻辑**集中在 `Models/BusinessLogic.swift`（1416 行），以 enum 命名空间组织：`ProjectLogic / HeatmapLogic / TagLogic / FilterLogic / ProjectOperations / BranchLogic / AppStateLogic / DashboardLogic / DirectoryLogic`。
- **服务与存储**也在 `Models/`：`AppStateStorage`、`ProjectIndex`、`TagColorManager`、`BusinessTagRuleStorage`、`BusinessTagger`、`GitDailyCollector`、`TagSystemSync(+Optimized)`、`BatchTagLoader`、`ProjectLoaderOptimized`、`ProjectNotesManager`，以及 `TagStorage`（已标 deprecated 但仍在用）。
- **中枢协调器**是 `Models/TagManager.swift`（1679 行，`class TagManager: ObservableObject`），持有 `AppStateStorage / TagStorage / ProjectIndex / TagColorManager / ProjectSortManager`。
- **组件化 manager** 在 `Models/TagManagerComponents.swift`：`ProjectSortManager`、`ProjectOperationManager`、`DirectoryWatcher`。
- **ViewModel 只有一个**：`ViewModels/DashboardViewModel.swift`。
- **View**：`Views/MainTabView.swift` 只有「项目 / 仪表盘」两个主 tab；分支管理不在主导航，从项目详情进入。

## 单例（全部 `shared`）

| 单例 | 位置 | 状态 |
|---|---|---|
| `HeatmapDataStore.shared` | `Models/HeatmapDataStore.swift:8` | 活跃，`SidebarView.swift:91`、`SidebarHeatmapView.swift:5` 在用 |
| `TagCache.shared` | `Models/TagCache.swift:10` | 活跃，被批量加载组件复用 |
| `TagManager.shared` | `Models/TagManager.swift:18` | `static weak var`，已标 deprecated（注释称「单例癌症，即将死亡」），但仍在初始化时赋值 |

## 与历史计划的关系

`docs/archive/` 下 `SINGLETON_DEATH_LIST.md`、`LINUS_BRUTAL_REFACTORING_PLAN.md`、`REFACTORING_COMPLETION_REPORT.md`、`PHASE3/4/5` 等报告描述的处决方案，依赖 `TagManagerFactory`、`SimpleTagManager`、`SimpleProjectManager`、`ProjectStore`、`WorktreeManager`、`TagColorInfo` 等类型——这些在 `Sources/` 中检索不到（2026-09-20 实测）。这些报告声称的「0 个应用层单例」与现状冲突。仅 `Protocols/LinusProtocols.swift` 里的协议定义留存。

## 未知

未评估拆分 `TagManager` 的成本与风险；上述历史计划中是否仍有部分应当补做，未裁决。
