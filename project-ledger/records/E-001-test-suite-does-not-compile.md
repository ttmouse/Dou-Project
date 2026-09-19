# E-001：测试目标当前无法编译

```json
{
  "id": "E-001",
  "kind": "evidence",
  "status": "active",
  "summary": "swift test 当前不可用（测试模块编译错误）；2026-09-20 02:32 复跑时主 target 也因并发未提交改动无法编译",
  "scope": ["Tests/ProjectManagerTests"],
  "sources": [
    "project-ledger/evidence/2026-09-20-swift-build-tests.txt",
    "project-ledger/evidence/2026-09-20-swift-build-tests-run2.txt",
    "Tests/ProjectManagerTests/MockSystem.swift"
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

## 复跑（2026-09-20 02:32）

- 命令与环境同上，HEAD 变为 `92dfca1` + 12 个文件未提交改动。原始输出：`project-ledger/evidence/2026-09-20-swift-build-tests-run2.txt`。
- 结果：退出码仍为 **1**，但**本次失败点前移到了主 target** —— `Sources/ProjectManager/Models/FileSystemEventMonitor.swift:58` 把 `[FSEventStreamCreateFlags]` 数组传给了需要单个 `UInt32` 的参数。该文件属另一会话正在编写的未提交代码（文件修改时间 02:31）。
- 因此本次复跑**到达不了测试模块**，上面第 18 条错误的清单既未被重现也未被推翻；`swift test` 不可用的结论继续保持，但当前阻碍已变成「主 target 也编译不过」。
- 教训：证明「测试能不能跑」的前提是主 target 能构建。复跑前先确认工作区没有被并发改动打断。

## 状态变化（2026-09-20 02:33，未经核验）

本记录原本也把 `Tests/ProjectManagerTests/ProjectSystemTests.swift` 与 `TagSystemTests.swift` 列为来源，现在这两个文件已被删除，故从来源列表移除（原文描述的错误内容保留在 `project-ledger/evidence/2026-09-20-swift-build-tests.txt` 的原始输出里）。

同一时间另一会话对测试目录做了整体处理：删除 `DataSerializationTests.swift`、`FileMonitoringTests.swift`、`ProjectSystemTests.swift`、`TagSystemTests.swift`（均为上述错误所在文件），新增 `GitDailyCollectorTests.swift`、`ProjectModelTests.swift`，并修改 `MockSystem.swift`。

**测试目标是「已经修好」还是「仍在改」尚未验证**：截至 02:33 主 target 也仍编译不过（`MainContentView.swift:26` 与 `SearchSortBar` 的 `projectViewMode` 参数不匹配），所以无法复跑测试。本记录继续有效，直到有人实际跑出 `swift build --build-tests` 通过为止；届时应用新记录说明替代关系，不要直接改本记录的结论。
