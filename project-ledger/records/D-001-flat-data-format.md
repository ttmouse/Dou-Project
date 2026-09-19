# D-001：落盘数据已扁平化，业务层仍部分使用嵌套兼容 API

```json
{
  "id": "D-001",
  "kind": "decision",
  "status": "active",
  "summary": "采用扁平 JSON 字段 + 旧格式兼容解码；存储已扁平，业务层迁移未完成",
  "scope": ["Sources/ProjectManager/Models"],
  "sources": [
    "Sources/ProjectManager/Models/Project.swift",
    "Sources/ProjectManager/Models/DataModels.swift",
    "Sources/ProjectManager/Models/ProjectDataMigration.swift",
    "docs/TRD-flat-data-structure.md",
    "docs/flat-data-refactor-complete.md"
  ],
  "key": "project-data-format",
  "recorded_at": "2026-09-20"
}
```

## 为什么

`docs/TRD-flat-data-structure.md`（2025-08-26）记录的原因：原嵌套结构 `project.gitInfo?.commitCount` 多层解引用、`lastModified` 与 `fileSystemInfo.modificationDate` 重复、加字段要改多处、热力图只能存最后一次提交。方案是扁平字段 + `git_daily` 紧凑串 `"YYYY-MM-DD:count,..."`，并为旧数据提供自动迁移。

## 当前实际状态（2026-09-20 读代码）

**已经扁平的部分**

- `Project.swift:148-149` 的 `CodingKeys` 是新字段：`id, name, path, tags` + `mtime, size, checksum`，`encode(to:)` 于 `:196` 输出扁平结构。
- `DataModels.swift` 的 `ProjectData` 同样是扁平字段。
- `ProjectDataMigration.swift` 提供嵌套 `LegacyProject` → 扁平 `Project` 的迁移。
- 落盘样本 `projects.json`（约 33KB）已是扁平格式。

**没有迁移完的部分**

- `Project.swift:76/81` 仍保留 `GitInfo` / `FileSystemInfo` 嵌套类型，`:128` 的旧初始化器标了 `@available(*, deprecated)`；`CodingKeys` 仍容纳 `lastModified, gitInfo, fileSystemInfo` 以便解码旧文件。
- 业务逻辑还在走兼容 API，而非扁平字段：`BusinessLogic.swift:76-80` 用 `project.lastModified` 与 `project.gitInfo?.commitCount` 排序，`:98` 用 `project.fileSystemInfo.lastCheckTime`，`:218-221` 取 `project.gitInfo`，`:300-311` 的构造仍传 `lastModified` / `gitInfo`。
- `TagStorage.swift` 已标 deprecated 但仍在被使用。

## 验证状态

`docs/flat-data-refactor-complete.md`（同日）声称「✅ 完成」「可安全部署到生产环境」，但唯一证据是一条 `swift build` 输出；`docs/TRD-flat-data-structure.md` 的验收清单（含「单元测试覆盖率≥90%」）至今全未勾选。因此「扁平化完成」目前只有构建级证据，没有测试级证据（且测试目标当下不能编译，见 E-001）。文档声称的工作分支 `flat-data-v2` 也不存在。

## 对后续任务的含义

改数据模型时，扁平字段是当前事实来源，但删除嵌套兼容层会波及 `BusinessLogic` 多处；要么先迁移业务层，要么明确保留兼容层。文档与代码在这里不一致，不能只看文档。
