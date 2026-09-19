# R-001：文档声称的产物与现状大面积不符，不能当作当前状态依据

```json
{
  "id": "R-001",
  "kind": "risk",
  "status": "active",
  "summary": "docs/archive 的多份“完成报告”和 docs/ 中的脚本引用与代码现状冲突，缺失产物达十余项",
  "scope": ["docs"],
  "sources": [
    "docs/archive",
    "VERSION_MANAGEMENT.md",
    "docs/flat-data-refactor-complete.md",
    "docs/TREES_QUICK_START.md",
    "project-ledger/records/E-001-test-suite-does-not-compile.md"
  ],
  "key": "doc-vs-reality",
  "recorded_at": "2026-09-20"
}
```

## 风险

`docs/` 下有 13 篇文档，`docs/archive/` 下另有 21 篇历史方案（含 5 份「完成报告」）。其中多份声称已完成的工作，在仓库中查不到对应产物；照文档办事会直接踩空。

## 已被证伪的声称（2026-09-20 实测）

- `docs/flat-data-refactor-complete.md` 列出的新增文件里，`ProjectStore.swift` 在 `Sources/` 不存在。
- `docs/Trees分支管理功能规格文档.md` 列出的 `WorktreeManager.swift` 不存在。
- `REFACTORING_COMPLETION_REPORT.md` 声称创建的 `TagStore.swift` / `ProjectStore.swift` / `TagManagerModular.swift` / `ServiceContainer.swift` 均不存在；测试引用的 `SimpleTagManager` / `SimpleProjectManager` 也不存在于源码（E-001）。
- `PHASE4` / `PHASE5` 报告声称的 `regression-test.sh`、`performance-test.sh`、`code-cleanup.sh`、`final-release-check.sh`、`linus-check.sh` 均不存在；两份报告还称「0 个应用层单例」，与 D-002 列出的 3 个单例冲突。
- `VERSION_MANAGEMENT.md` / AGENTS.md / README.md 共同引用的 `increment_version.sh`、`build_release.sh` 不存在，`Scripts/` 目录为空（D-005）。
- `TREES_QUICK_START.md` 提到的 `./trees-interactive.sh` 不存在。
- `docs/SCREENSHOTS.md` 规定截图放在 `docs/screenshots/`，该目录不存在，README 也未引用任何截图。

## 使用建议

- `docs/archive/` 一律按「历史方案」对待，只能用来解释「为什么当年这么想」，不能用来判断现状。
- 引用 `docs/` 中任何「已完成/已经存在」的结论前，先在仓库里验证产物。
- 时间线本身也不可靠：`CHANGELOG.md` 首版标 2024-12-XX、Trees 系列文档标 2024-08-24，都早于 git 初始提交 2025-01-08；文档日期不能当作依据。

## 未知

未逐篇核对 34 份文档的每一条声称；以上是抽样证伪的清单，不代表其余声称都成立。项目唯一的正式需求文档 `docs/archive/项目管理器 (ProjectManager) 需求文档.md` 未被验证，其条目是否仍有效未知。
