# E-001：测试目标当前无法编译

```json
{
  "id": "E-001",
  "kind": "evidence",
  "status": "active",
  "summary": "swift build --build-tests 在测试模块编译阶段失败，swift test 当前不可作为回归依据",
  "scope": ["Tests/ProjectManagerTests"],
  "sources": [
    "project-ledger/evidence/2026-09-20-swift-build-tests.txt",
    "Tests/ProjectManagerTests/MockSystem.swift",
    "Tests/ProjectManagerTests/ProjectSystemTests.swift",
    "Tests/ProjectManagerTests/TagSystemTests.swift"
  ],
  "key": "test-suite-health",
  "recorded_at": "2026-09-20",
  "verified_at": "2026-09-20"
}
```

## 核验方法

- 命令：`swift build --build-tests`
- 环境：macOS 27.0（26A428），Apple Swift 6.4，target `arm64-apple-macos14.0`，仓库 HEAD `553b1c7`（分支 `main`）
- 结果：退出码 **1**，在测试模块 `emit-module` 阶段失败，耗时约 3 秒（主 target 已在同一次调用中增量构建成功）
- 原始输出：`project-ledger/evidence/2026-09-20-swift-build-tests.txt`

## 错误类别（共 18 条 error）

- `cannot find type 'TagColorInfo' in scope` ×6 —— 该类型在整个仓库中只出现在测试里，没有定义。
- `cannot find type 'SimpleTagManager' in scope` ×4、`cannot find type 'SimpleProjectManager' in scope` ×2 —— 这两个类型在 `Sources/` 中不存在。
- `cannot override immutable 'let' property 'appSupportURL'` ×2 —— `MockTagStorage` 试图 override `TagStorage.swift:9` 的存储属性 `let appSupportURL`。

## 可以声称 / 不能声称

- 可以声称：主 target 在 Debug 下可构建；测试目标不能编译，因此 `swift test` 不会真正执行任何用例。
- 不能声称：任何一个测试通过或失败；不能声称测试覆盖率。
- 影响：C-003 要求的「合并后必须构建+测试」目前只能完成构建部分。任何「改了模型，测试应该还过」的说法在此修复前都不成立。

## 相关状态

- `Tests/ProjectManagerTests/` 共 7 个文件：`MockSystem`、`FileMonitoringTests`、`TagSystemTests`、`BusinessTaggerTests`、`ProjectSystemTests`、`DataSerializationTests`、`DirectoryLogicTests`。
- `DirectoryLogicTests.swift` 是未跟踪的新文件（测 `DirectoryLogic` 的目录归属不变量，含 `Σ目录+未分类==总数`），它本身是否编译通过尚未单独验证——整目标编译失败使它无法单独运行。
- 未查清 `SimpleTagManager` / `SimpleProjectManager` 是「曾被删除」还是「从未实现」。
