# R-003：.gitignore 末行粘连，安全报告声称的措施未生效

```json
{
  "id": "R-003",
  "kind": "risk",
  "status": "active",
  "summary": ".gitignore 末行是 .trees 与文件名粘连的无效条目，projects-linus-format.json 实际未被忽略",
  "scope": [".gitignore"],
  "sources": [".gitignore", "docs/security-check-report.md"],
  "key": "gitignore-rules",
  "recorded_at": "2026-09-20"
}
```

## 事实（2026-09-20 实测）

- `.gitignore` 末行为 `.treesprojects-linus-format.json` —— `.trees` 与 `projects-linus-format.json` 之间缺换行，粘连成一条无效模式。
- 因此 `.trees` 未被忽略，`projects-linus-format.json` 也未被忽略。经核对，`.gitignore` 内也没有单独一行 `projects-linus-format.json`。
- 而 `docs/security-check-report.md`（「已采取的措施」段）明确声称「已将该文件添加到 .gitignore」。

## 为什么算风险

`projects-linus-format.json` 是包含用户本机项目路径的数据文件。安全报告声称已处理，实际措施无效，会让人误以为该数据不会被提交。同一份报告还把路径写成 `doc/TREES_WORKSPACE_GUIDE.md`、`doc/linus-refactor-plan.md`，实际目录名是 `docs/` —— 报告本身未经复核。

## 待办（未执行）

由开发者决定正确的忽略规则（`.trees/` 与 `projects-linus-format.json` 分两行），并修正或撤回安全报告中的该条声称。本记录不代为修改文件。
