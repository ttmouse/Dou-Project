# D-005：构建、依赖与版本号基线

```json
{
  "id": "D-005",
  "kind": "decision",
  "status": "active",
  "summary": "SPM + 零第三方依赖 + macOS 12 起；打包靠手工 build.sh，版本号无单一事实来源",
  "scope": ["Package.swift", "build.sh"],
  "sources": [
    "Package.swift",
    "build.sh",
    "Sources/ProjectManager/Resources/Version.plist",
    "CHANGELOG.md",
    "VERSION_MANAGEMENT.md",
    "AGENTS.md"
  ],
  "key": "build-and-version",
  "recorded_at": "2026-09-20"
}
```

## 技术基线（当前有效）

- `Package.swift`：`swift-tools-version:5.7`，平台 `.macOS(.v12)`，**`dependencies: []`（无任何第三方依赖）**。
- 主 target 编译设置 `-enable-private-imports -suppress-warnings`；test target 为 `-enable-private-imports`。
- 可执行产物名 `ProjectManager`。
- 构建/测试命令：`swift build`、`swift build -c release`、`swift test`、`./build.sh`（AGENTS.md「命令参考」）。
- 引入新依赖会打破「零依赖 + 手写打包」的现状：加依赖前需说明理由，并确认仍能用 `build.sh` 打包。

## 打包现状

- `build.sh` 是手工打包脚本：清空 `.build/release`，重建 `ProjectManager.app`；拷贝 `.build/release/ProjectManager` 进 bundle；**自行生成 `Info.plist`，其中 `CFBundleShortVersionString` 写死 `1.0`**，`LSMinimumSystemVersion` 为 `12.0`；脚本内有「严禁复制到桌面或其他位置」的注释。
- `build.sh` 里没有任何版本递增或读取版本文件的逻辑。

## 版本号不一致（未裁决）

| 位置 | 值 |
|---|---|
| `build.sh` 生成的 Info.plist | `1.0`（写死） |
| `Sources/ProjectManager/Resources/Version.plist` | `1.0.1`，BuildNumber 2，BuildDate 2025-07-14 |
| `CHANGELOG.md` | 首版 `[1.0.0] - 2024-12-XX`（日期是占位符 XX） |
| `SECURITY.md` | 声称支持 `1.0.x` |

## 文档与现状冲突

`VERSION_MANAGEMENT.md` 给出 `./Scripts/increment_version.sh patch|minor|major` 与 `./Scripts/build_release.sh`，AGENTS.md / CLAUDE.md / README.md 也各自引用过 `scripts/increment_version.sh`。实测：**`Scripts/` 目录为空**（2026-09-20），两个脚本都不存在，且引用的大小写不一致（`Scripts` vs `scripts`）。发布流程中「自动递增版本号」这一步目前没有可执行实现。

## 未知

真实发布（生成 DMG / 对外分发）的实际流程未核验；`.github/` 下是否有 CI 未核验。
