# C-001：项目标签通过 Finder 扩展属性持久化

```json
{
  "id": "C-001",
  "kind": "constraint",
  "status": "active",
  "summary": "项目标签落在文件系统 xattr（com.apple.metadata:_kMDItemUserTags），改动属高风险操作",
  "scope": ["Sources/ProjectManager/Models", "Sources/ProjectManager/Views"],
  "sources": [
    "Sources/ProjectManager/Models/TagSystemSync.swift",
    "Sources/ProjectManager/Models/TagManager.swift",
    "Sources/ProjectManager/Models/BatchTagLoader.swift",
    "README.md",
    "SECURITY.md",
    "USER_GUIDE.md"
  ],
  "key": "tag-persistence-mechanism",
  "recorded_at": "2026-09-20"
}
```

## 约束内容

标签不是纯应用内数据，而是用户 Finder 里可见的系统元数据：

- `TagSystemSync.swift:124` 用 `(url as NSURL).setResourceValue(_:forKey: .tagNamesKey)` 写入标签名，`:154` 用 `.labelColorKey` 写颜色。
- 批量读取走 `TagSystemSyncOptimized.loadTagsFromFile`（`BatchTagLoader.swift:82`）。
- 保存链路：`TagManager.swift:707` 的保存流程调用 `TagSystemSync.syncTagsToSystem(tagsSnapshot)`。
- `Project.swift:361-365` 的标签扩展也在同一机制上读写。

## 必须遵守（改动前对照）

- 先备份数据再改动（README.md「标签系统安全」、SECURITY.md「标签系统」、CONTRIBUTING.md「重要开发注意事项」）。
- 保持原子写入，避免部分写入损坏 xattr。
- 必须验证三种场景的持久性：应用重启、项目重载、系统重启。
- 只在有备份的数据上做实验。

## 记录到的冲突

`USER_GUIDE.md`「数据与限制」称「当前版本不会把应用内标签写回 Finder 文件标签（系统元数据）」，与上述代码路径不符。以代码为准；该文档句子尚未修正，属待清理的过期陈述。

## 未知

未在真实数据上跑过写回验证，也未核验标签颜色在 Finder 中的实际展示行为。
