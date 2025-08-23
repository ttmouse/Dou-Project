# Repository Guidelines

## 项目结构与模块
- 源码：`Sources/ProjectManager/` 按领域划分：`Models/`、`Views/`、`Protocols/`、`Extensions/`、`Utils/` 与 `Utilities/`、`Theme/`、`Resources/`。
- 可执行目标：`ProjectManager`（见 `Package.swift`），应用入口在 `ProjectManagerApp.swift`。
- 资源：`Sources/ProjectManager/Resources/`（含 `Assets.xcassets`）。
- 测试：`Tests/ProjectManagerTests/`，使用 XCTest（如 `TagSystemTests.swift`）。

## 构建、测试与运行
- 调试构建：`swift build`
- 发布构建：`swift build -c release`
- 本地运行：`swift run ProjectManager`
- 一键打包（App + DMG）：`./build.sh`
- 单元测试：`swift test`
- 回归测试：`./regression-test.sh`
- 性能检查：`./performance-test.sh`
脚本会在仓库生成日志（如 `build_perf.log`、`test_perf.log`）。

## 代码风格与命名
- 语言：Swift 5.7+，目标 macOS 12。
- 缩进：4 空格，不用 Tab；建议行长 ≤120 列。
- 命名：类型与文件用 `PascalCase`（如 `SimpleTagManager.swift`）；变量/函数用 `lowerCamelCase`；测试文件以 `Tests.swift` 结尾。
- 组织：UI 放在 `Views/`，数据/状态在 `Models/`，通用工具在 `Utils/`/`Utilities/`，契约在 `Protocols/`。
- 卫生：提交前运行 `./code-cleanup.sh` 清理调试输出并检查未使用 import/死代码。

## 测试规范
- 框架：XCTest。
- 位置：在 `Tests/ProjectManagerTests/` 下新增测试，结构与源码对应。
- 约定：测试文件命名为 `SomethingTests.swift`；保持确定性与数据驱动（参考 `DataSerializationTests.swift`）。
- 运行：`swift test`；更广泛校验使用 `./regression-test.sh`（含构建与完整性检查）。

## 提交与合并请求规范
- 提交风格：遵循历史中的 Conventional Commits 前缀（`feat:`、`docs:`、`chore:` 等），主题使用祈使语、简洁明确，必要时在正文补充背景。
- PR 内容：清晰描述与动机、关联 Issue（如有）、测试覆盖说明；UI 改动附截图/GIF。
- 质量门：本地通过 `swift build`、`swift test`、`./regression-test.sh`；性能相关改动运行 `./performance-test.sh`。

## 安全与配置
- 机密：不要提交真实凭据。若使用 `.env`，仅保留本地或提供脱敏示例；如发现泄露请立即轮换密钥。
- 平台：需要 macOS 工具链；请安装 Xcode 命令行工具或官方 Swift 工具链。
