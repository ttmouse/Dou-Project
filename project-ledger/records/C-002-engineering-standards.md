# C-002：工程规范与当前偏差

```json
{
  "id": "C-002",
  "kind": "constraint",
  "status": "active",
  "summary": "禁 TODO/占位符、业务逻辑纯函数须配测试、可读性优先；行宽规范存在未裁决冲突",
  "scope": [],
  "sources": ["AGENTS.md", "CLAUDE.md", "CONTRIBUTING.md", ".swiftlint.yml", ".cursorrules"],
  "key": "engineering-standards",
  "recorded_at": "2026-09-20"
}
```

## 规范

- 禁止 TODO、占位符和未完成片段：AGENTS.md「编码风格」、CLAUDE.md「代码风格」、.cursorrules。
- 可读性 > 性能：同上。
- 业务逻辑必须无状态、无副作用；新增业务函数须配单元测试：AGENTS.md / CLAUDE.md「架构原则」。
- 提交用约定式 `type(scope): description`：AGENTS.md「Git 与协作」、CONTRIBUTING.md。
- 不提交密钥、不硬编码用户专属路径：AGENTS.md「安全与稳健性」、SECURITY.md。

## 与现状的偏差（2026-09-20 于 HEAD 553b1c7 实测）

- 源码仍有 2 处 TODO，与「禁止 TODO」冲突：`Views/Settings/EditorSettingsView.swift:255`、`Models/BusinessLogic.swift:215`。
- 行宽规范未裁决：CONTRIBUTING.md 要求每行 ≤100 字符，`.swiftlint.yml` 设 `line_length` warning 120 / error 150。
- `.swiftlint.yml` 自相矛盾：`disabled_rules` 里禁用 `identifier_name`，同文件下方又详细配置 `identifier_name`。
- AGENTS.md「测试」示例 `swift test --filter TagManagerTests` 指向不存在的测试文件：`Tests/ProjectManagerTests/` 下没有 `TagManagerTests.swift`。测试目标当前也不能编译，见 E-001。

## 未知

未运行 SwiftLint，当前违规数量未知。
