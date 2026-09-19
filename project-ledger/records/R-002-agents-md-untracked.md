# R-002：AGENTS.md 未被 git 跟踪

```json
{
  "id": "R-002",
  "kind": "risk",
  "status": "active",
  "summary": "仓库根 AGENTS.md（项目规则正本）不在版本控制中，克隆或清理工作区即丢失",
  "scope": ["AGENTS.md"],
  "sources": ["AGENTS.md"],
  "key": "agents-md-tracking",
  "recorded_at": "2026-09-20"
}
```

## 事实（2026-09-20 实测）

- `git ls-files AGENTS.md` 输出为空 → 未被跟踪。
- `git check-ignore -v AGENTS.md` 退出码 1、无输出 → **也不在忽略列表里**，即它只是一个未加入索引的新文件。
- 索引中只有 `docs/archive/AGENTS.md`（那份是重复的旧副本，且其「项目结构」段列出的 `Extensions/`、`Utils/` 目录已不存在）。
- 对比：`CLAUDE.md`、`CONTRIBUTING.md`、`SECURITY.md`、`USER_GUIDE.md`、两个 trees 脚本都在跟踪中。

## 影响

AGENTS.md 是当前项目的规则正本（构建/测试命令、架构原则、禁止 TODO、分支红线、安全要求），也是 C-002 / C-003 的主要来源。它未入库意味着：换机器、重新克隆、或执行 `git clean -fdx` 后会直接丢失，而 `docs/archive/AGENTS.md` 那份已经过期。

## 建议（未执行）

由开发者决定是否 `git add AGENTS.md` 并提交；同时清理或标注 `docs/archive/AGENTS.md` 与根文件的重复关系。本记录不代为执行。
