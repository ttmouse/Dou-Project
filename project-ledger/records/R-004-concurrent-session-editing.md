# R-004：仓库存在并发会话同时编辑，工作区状态不可假设

```json
{
  "id": "R-004",
  "kind": "risk",
  "status": "active",
  "summary": "同一仓库有多个 AI 会话同时改代码并共用一个知识库，未提交差异和构建结果都可能在数分钟内失效",
  "scope": ["Sources", "Tests", "project-ledger"],
  "sources": [
    "project-ledger/records/D-006-vibe-coding-entry-loop.md",
    "project-ledger/evidence/2026-09-20-swift-build-tests-run2.txt"
  ],
  "key": "concurrent-session-editing",
  "relations": [
    {"type": "related_to", "target": "E-001"},
    {"type": "related_to", "target": "R-001"}
  ],
  "recorded_at": "2026-09-20"
}
```

## 观察到的事实（2026-09-20 01:14 → 02:33 实测）

- 同一天内工作区被反复改动：01:14 有 8 个已修改文件，02:31 增至 12 个（+566/−496 行），并新增未跟踪源码 `FileSystemEventMonitor.swift`、`Views/ScanStatusView.swift`、`Utilities/Log.swift`。
- 改动方在编辑前会留下 `Sources/**/*.bak.<yyyyMMddHHmmss>`，清点时有 6 个（如 `TagManager.swift.bak.20260920023041`）。
- 时间戳证明编辑是「正在进行」而非「已完成」：`SearchSortBar.swift` 的 mtime 为 02:32:53，24 秒后仍是编译失败状态。
- 两个会话共用同一个知识库：`D-006`（30 秒进入工作状态的 P0 闭环）由另一会话写入，并用 `related_to` 指向 `D-002`。它的正文称「发布版构建成功，应用已启动」，与 02:32 主 target 编译失败并存——两句话都对，只是快照时刻不同。

## 为什么是风险

- 本记录库在 01:14 采集的「现状」在 02:31 就有 4 条记录的行号、行数、未知项对不上代码（见各记录的复核记录）。
- 主 target 在 02:32 编译失败，直接导致 E-001 的复跑到不了测试模块。构建/测试结论只在某一时刻成立，不能跨时刻引用。
- 未提交的差异既可能是「别人做到一半的工作」，也可能是「已完成但没提交的工作」，从 diff 本身无法区分。按后者处理会做出错误判断（例如把半成品当成已完成功能）。

## 行为约束

- 声明「能构建 / 测试通过 / 功能已实现」时必须带时刻与 revision，并说明当时工作区是否干净。
- 读取工作区差异前先看 mtime 与 `*.bak.*` 残留；发现目标文件在几分钟内被改过，就等而不是改。
- 不要替别人把连锁的编译错误「顺手修完」：那是在猜对方的设计（例如 02:32 的 `projectViewMode` 缺参数需要决定它是否为新 `@Binding`）。只修明确属于自己的、语义无歧义的那一处。
- 复跑验证前先确认主 target 能构建，否则测不到目标结论。

## 未知

无法确定同时活跃的会话数量与各自范围；本记录只覆盖 01:14–02:33 观测到的行为。
