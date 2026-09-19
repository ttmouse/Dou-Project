# C-003：分支与合并红线

```json
{
  "id": "C-003",
  "kind": "constraint",
  "status": "active",
  "summary": "不得自动删分支；合并后必须构建+测试；冲突须给出清晰选项",
  "scope": ["Sources/ProjectManager/Models/BusinessLogic.swift"],
  "sources": ["AGENTS.md", "CLAUDE.md"],
  "relations": [{"type": "related_to", "target": "E-001"}],
  "key": "branch-safety-policy",
  "recorded_at": "2026-09-20"
}
```

## 约束

- 未经明确授权不得删除分支；分支删除决定权归开发者（AGENTS.md「Git 与协作」、CLAUDE.md「🌿分支管理原则」）。
- 合并分支后必须构建并测试（同上）。
- 出现冲突时向开发者提供清晰的解决选项，不自行拍板（同上）。
- 代码内也有同类红线：`BusinessLogic.swift` 中的 `BranchLogic` 禁止删除或合并主分支。

## 与现状的张力

「合并后必须构建+测试」目前只能执行一半：主 target 可构建，测试目标不能编译（E-001）。在测试修复前，合并后的验证实际上只剩构建，不能用「测试通过」作为合并依据。
