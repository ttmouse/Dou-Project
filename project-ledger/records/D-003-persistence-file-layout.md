# D-003：持久化文件布局，以及 app_state.json 未落地

```json
{
  "id": "D-003",
  "kind": "decision",
  "status": "active",
  "summary": "projects.json 存项目、app_state.json 存标签与目录、另有索引与热力图缓存；app_state.json 实际未生成",
  "scope": ["Sources/ProjectManager/Models"],
  "sources": [
    "Sources/ProjectManager/Models/AppStateStorage.swift",
    "Sources/ProjectManager/Models/TagStorage.swift",
    "Sources/ProjectManager/Models/ProjectIndex.swift",
    "Sources/ProjectManager/Models/HeatmapDataStore.swift"
  ],
  "key": "persistence-file-layout",
  "relations": [{"type": "related_to", "target": "D-001"}],
  "recorded_at": "2026-09-20"
}
```

## 代码意图

- 项目数据：`projects.json`（`TagStorage.swift:112` 用 `JSONEncoder().encode([Project])`，扁平格式）。
- 标签与目录：`app_state.json` v2（`AppStateStorage.swift:58` 定义 `stateFileName = "app_state.json"`），`:64` 保留旧名 `directories.json`，`:89` 在找不到新文件时从旧格式迁移。
- 索引：`project_index.json`（`ProjectIndex.swift`，`children` 是路径数组而非嵌套对象）。
- 热力图：`heatmap_cache.json`（`HeatmapDataStore`）。
- 统一写入口：`TagManager` 的保存流程同时写 app_state 与 projects。

## 磁盘实测（2026-09-20，`~/Library/Application Support/ProjectManager/`）

实际存在：`projects.json`（33KB，2025-09-13）、`project_index.json`（39KB，2025-09-13）、`directories.json`（40B，2025-08-23）、`heatmap_cache.json`（65KB，2026-09-19）、两份备份 `projects.json.backup`、`projects_backup_20250913_220759.json`。

**不存在 `app_state.json`。** 与磁盘时间线一起看：`heatmap_cache.json` 最近被写过（2026-09-19），说明应用在运行；但 app_state 从未落盘，仍停留在旧格式 `directories.json`。

## 未知（重要）

无法判定这是「迁移路径未被执行/被回退」还是「只在特定操作后才写 app_state.json」。2026-01-19 的提交信息 `refactor: Linus式数据存储重构 - 统一标签和目录数据到 app_state.json` 与磁盘现状不一致。凡是涉及「标签和目录存哪」的任务，应先实际验证再动手，不要假定新格式已生效。
