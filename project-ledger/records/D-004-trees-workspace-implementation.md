# D-004：Trees/工作区存在两套并行实现，且文档互相矛盾

```json
{
  "id": "D-004",
  "kind": "decision",
  "status": "contested",
  "summary": "分支工作区同时有 shell 脚本与 App 内 Swift 两套实现，脚本之间产物互不识别，未见裁决记录",
  "scope": ["Sources/ProjectManager/Views/Branch", "Sources/ProjectManager/Models/BranchModels.swift", "Sources/ProjectManager/Utilities/ShellExecutor.swift"],
  "sources": [
    "docs/Trees分支管理功能规格文档.md",
    "Sources/ProjectManager/Utilities/ShellExecutor.swift",
    "Sources/ProjectManager/Models/BranchModels.swift",
    "Sources/ProjectManager/Models/BranchStatusMonitor.swift",
    "trees-manager.sh",
    "trees-workspace.sh"
  ],
  "key": "trees-workspace-implementation",
  "recorded_at": "2026-09-20"
}
```

## A. App 内 Swift 实现（已落地）

- `Utilities/ShellExecutor.swift`：真实执行 git，含 `createWorktree`（`git worktree add -b <name> <path> HEAD`，自动建 `.trees/`）、`removeWorktree`、`getWorktreeList`、`readBranchInfo`、`mergeBranch`、`checkMergeability`、`getBranchDiff`。
- `Models/BranchModels.swift`：`BranchInfo / BranchStatus / BranchOperation / WorktreeInfo / BranchCreationParams`，`targetPath = "<project>/.trees/<name>"`，分支名有正则校验。
- `BusinessLogic.swift` 的 `BranchLogic`：创建/删除/合并/状态/差异，并禁止操作主分支；`diskSize` 被硬编码为 0（注释写明是性能考虑）。
- `Models/BranchStatusMonitor.swift`：轮询分支状态（默认 30s，脏分支 5s）。
- 视图：`Views/Branch/` 下 `BranchListView / BranchCard / CreateBranchView / MergeConfirmationView / ProjectDetailView`，从 `ProjectListView.swift:293` 进入。

## B. Shell 脚本实现（同样在仓库里）

- `trees-manager.sh`：走 `git worktree add .trees/<name>`，生成 `info.json`。
- `trees-workspace.sh`：走 **rsync 全量复制**得到「完整项目副本」，靠 `.trees_branch` 标记识别。
- 两者产物互不识别（一方认 `info.json`，另一方认 `.trees_branch` 标记）。

## C. 文档层的冲突（四份 TREES 文档互不一致）

- `TREES_QUICK_START.md` / `TREES_SIMPLE_GUIDE.md` 讲 `./trees-manager.sh`；`TREES_WORKSPACE_GUIDE.md` 讲 `./trees-workspace.sh`。
- `TREES_QUICK_START.md` 提到的 `./trees-interactive.sh` 在仓库中不存在。
- `TREES_DEVELOPMENT_GUIDE.md` 描述的「进度快照」模型（`.trees/<分支>/{info.json,changes.log,modified_files}`）与 `trees-manager.sh` 的实际实现不符。
- 仓库根 `.branch_info` 实际是 `BRANCH_NAME=... / CREATED_AT=...` 的 KEY=VALUE 文本，而 `TREES_WORKSPACE_GUIDE.md` 与规格文档都称它是 JSON。
- `.trees/.current` 内容为 `UI`，但不存在 `.trees/UI`，也没有对应分支——残留状态。

## 待裁决

现行方案是「App 内 Swift worktree」还是「shell 脚本」？两者的 `.trees/` 产物是否共用？在裁决前，改动分支功能需要先确认调用路径，不能只按文档做。

## 未知

未核验 App 内 `ShellExecutor` 与两个 shell 脚本是否操作同一 `.trees/` 目录；未核验 `.trees/.current` 的写入方。
