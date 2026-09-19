# E-002：热力图缓存是否存在——性能报告与代码/磁盘冲突

```json
{
  "id": "E-002",
  "kind": "evidence",
  "status": "contested",
  "summary": "性能报告称热力图无缓存，但代码已实现缓存且磁盘上缓存文件当天被写过；未见裁决",
  "scope": ["Sources/ProjectManager/Models/HeatmapDataStore.swift", "Sources/ProjectManager/Views/Components"],
  "sources": [
    "docs/performance-report.md",
    "Sources/ProjectManager/Models/HeatmapDataStore.swift",
    "Sources/ProjectManager/Models/GitDailyCollector.swift",
    "Sources/ProjectManager/Views/Components/SidebarView.swift"
  ],
  "relations": [
    {"type": "related_to", "target": "D-003"},
    {"type": "related_to", "target": "R-001"}
  ],
  "key": "heatmap-cache-state",
  "recorded_at": "2026-09-20"
}
```

## 一方的说法

`docs/performance-report.md`（署期 2026-08-17）在 P0-2 优化项里称 `UnifiedHeatmapView.generateHeatmapData` **没有缓存**，需要补上「预解析 + DateFormatter 单例」缓存。

## 另一方的证据（代码 + 磁盘）

- `Models/HeatmapDataStore.swift:8` 存在 `static let shared = HeatmapDataStore()`，类上还有 `ObservableObject` 与缓存处理逻辑。
- 使用点：`Views/Components/SidebarView.swift:91` 调 `HeatmapDataStore.shared.refreshIfNeeded(projects:)`，`SidebarHeatmapView.swift:5` 以 `@ObservedObject` 订阅同一个 store。
- 磁盘：`~/Library/Application Support/ProjectManager/heatmap_cache.json`（65KB）的修改时间是 **2026-09-19**，说明应用最近仍在写这份缓存。
- git 记录：2026-01-19 有提交 `perf: 热力图缓存架构重构 - 提升性能`。

## 待裁决的问题

性能报告的结论基于哪个 revision / 哪个分支？如果报告是过期快照，应在其上标注或撤回，否则它会持续误导「热力图还没缓存」的判断。目前**不能**据此认定缓存已完善——只认定「报告里『无缓存』这句与当前代码和磁盘状态不符」。

## 未知

未实际测量热力图性能；`HeatmapDataStore` 的缓存命中率未核验。

## 复核记录

2026-09-20 02:31：`GitDailyCollector.swift:12` 已出现 `static let dateKeyFormatter: DateFormatter` 并在 `:116` 复用，即性能报告 P0-2 提到的「DateFormatter 单例」已在未提交代码中落实。`heatmap_cache.json` 已增至 83KB，修改时间 02:29，缓存确实在活跃写入。**但报告里「无缓存」那句与代码的矛盾仍未裁决**：单例落实不等于报告当时判断正确，只能说明报告的待办项已被执行。
