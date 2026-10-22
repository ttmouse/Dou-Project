# ProjectManager 性能审计报告 v3

> 日期：2026-09-20 ｜ 取代 2026-08-17 / v2 版
> 方法：静态定位 + 真实数据实测 + 抽取仓库源码跑对照。所有数字可复现，脚本见文末。
> 状态：**P0-1（热力图）已修复并验证**；P0-2、P1 待办。

---

## 0. 结论

| 优先级 | 问题 | 状态 |
|---|---|---|
| P0-1 | 热力图重算 5.3 s，且跑在主 actor 上（看板切页冻结） | ✅ **已修复**：5.35 s → 0.0064 s，主 actor 不再被独占 |
| 测试套件 | `swift test` 编译不过（68 个用例基于已删除的架构）、且测试会读写真实用户数据 | ✅ **已修复**：删 68 / 重写 2 文件 / 新增 39 → 60 通过 · 1 跳过 · 2.9 s，且不再触碰真实数据 |
| P0-2 | git 采集阻塞主线程（注册 / 全量重载路径） | ✅ **主线程部分已修复**：358 项目注册 3.9~10.5 s → **15.4 ms**；遗留每项目一次 `rev-parse`（3.8 s，已在后台） |
| P1 | 增量扫描未接 `needsRescan`；两套热力图实现并存；`body` 内副作用；目录归属每次重算 | ⏳ 待办（可顺手做） |
| P2 | `isProjectExists` O(P²) 等 | 🚫 不做（实测 0.6 ms，纯噪音） |

---

## 1. 基线（当前用户真实数据）

| 指标 | 数值 |
|---|---|
| 项目总数 | 347 |
| 含 `git_daily` | 193（56%） |
| `git_daily` 数据点合计 | 4356（均值 22.6/项目） |
| `projects.json` / `project_index.json` | 165 KB / 277 KB |
| 监视目录 | 6 个，两层共 2376 个目录 |

---

## 2. P0-1 热力图 5 秒冻结（已修复）

### 症状

切到「数据看板」时整个界面冻结约 5 秒；`projects` 每次变化都会再冻结一次。

### 根因（两条独立叠加）

1. **算法**：`HeatmapLogic.generateHeatmapData` 按「天 × 项目」双重循环（365 × 347 ≈ 12.7 万次），
   每次 `getCommitCount` 都**新建 `DateFormatter`** 并**重新解析整条 `git_daily`**。
2. **线程**：`UnifiedHeatmapView.generateHeatmapData` 用 `Task {}`。`View` 协议在 SDK 中带 `@MainActor`，
   结构体成员被推断为 MainActor 隔离 → `Task {}` 继承主 actor → 这 5 秒**同步跑在主 actor 上**，期间 UI 无响应。

### 分层实测（三段实现全部从仓库源码抽取，同一进程内对比）

输入：347 个项目 / 193 个含 `git_daily` 的真实数据。

| 版本 | days=365 | days=90 | 说明 |
|---|---|---|---|
| A 现状（HEAD 原文） | **5.3~5.7 s** | 1.31~1.36 s | 每次调用新建 formatter + 全量 parse |
| B 只把 formatter 提为静态 | 1.77 s | 0.43 s | 证明 DateFormatter 占 ~67% 开销 |
| C 本次改动 | **0.0064 s** | 0.0057 s | 预解析 + 日期倒排索引 + 每天只格式化一次 |

- **指纹 A == B == C ✅**：按「日期 \| 当日提交数 \| 当日项目名及顺序」逐日哈希比对完全一致，
  365 天与 90 天两条路径都通过（365 天指纹 `9b2238dbba7e…`，总提交 18229；90 天 `fd3698dc71bf…`，总提交 14488）。
- 提速：**836×（365 天）/ 230×（90 天）**。

### 功能验证：主 actor 到底被独占多久

与 `UnifiedHeatmapView` 同构的 `struct: View`（成员被推断为 `@MainActor`），在窗口内以 10 ms 周期打主 actor 心跳：

| 写法 | 耗时 | 主 actor 心跳达成率 | 判定 |
|---|---|---|---|
| 旧 `Task {}`（`assertIsolated` 通过 → 确在主 actor） | 5.69 s | **0%**（应约 568 次，实际 2 次） | 主 actor 被独占，期间 UI 冻结 ⛔️ |
| 新 `Task.detached` | 0.05 s | **100%** | 主 actor 正常响应 ✅ |

### 改动（3 个文件）

| 文件 | 改动 |
|---|---|
| `Models/BusinessLogic.swift` | `generateHeatmapData`：每个项目只解析一次 `git_daily`，按日期建「日期 → 当日活跃项目」倒排索引；`DateFormatter` 提为静态单例；删除 6 条每次重算都打印的日志。复杂度 O(天数 × 项目数 × 解析) → O(数据点 + 天数 × 当日活跃项目数) |
| `Views/Components/UnifiedHeatmapView.swift` | `Task {}` → `Task.detached(priority: .userInitiated)`；新增 `generationToken` 丢弃过期结果（并行后可能后发先至，旧写法因主 actor 串行而不存在此问题） |
| `Models/GitDailyCollector.swift` | `getCommitCount` 的 `DateFormatter` 提为静态复用（同上根因，避免后续复用者再踩） |

### 遗留

- 未在 GUI 中实测（无头环境里 `Thread.isMainThread` 与 MainActor 的映射不可靠，故改用上面的主 actor 心跳法）。
  建议你在真机上切一次看板复验：应当瞬时出图，无 5 秒白屏。
- 侧边栏走的是另一套 `HeatmapDataStore`（已预解析），与看板口径不同 —— 见 P1-2。

---

## 3. P0-2 git 采集阻塞主线程（主线程部分已修复）

### 症状

启动/刷新/添加目录/`Cmd+Shift+T` 时界面冻住数秒，且与「有没有新项目」无关。

### 根因

1. `ProjectOperationManager.registerProjects` 第一件事就是同步 `GitDailyCollector.updateProjectsWithGitDaily`；
   而它的调用方基本都在主线程（`DispatchQueue.main.async`、通知回调、工具栏命令）。
2. 更糟的是 `TagManager.reloadProjects()`（`Cmd+Shift+T`）在**主线程**链路里调 `projectIndex.loadProjects`，
   而每个项目都要跑 git（`loadGitInfo`）并算 SHA256 校验。
3. 放大因子（仍在，但已不在主线程）：`updateProjectsWithGitDaily` 为**每个项目**跑一次 `git rev-parse HEAD`（实测净开销 10.9 ms/项目），冷启动还要跑全量 `git log`（32 ms/仓库）。

### 实测（改动前预估 → 改动后实测）

| 场景 | 之前（主线程阻塞） | 现在 |
|---|---|---|
| 358 个项目注册（真实数据） | HEAD 检查 10.9 ms × 358 ≈ **3.9 s**（全部未变也要付）；冷启动再加 32 ms × 205 ≈ 6.6 s → 最坏 **~10.5 s** | **15.4 ms**（实测：注册 + 内存合并 + 写盘，git 全程不占主线程） |

### 改动

| 文件 | 改动 |
|---|---|
| `Models/TagManagerComponents.swift` | `registerProjects` 不再同步采 git：只做内存合并（项目立即可见），git 交给新增的 `refreshGitDailyInBackground`（串行 `gitQueue`）→ 完成回主线程逐个回写。**且只为本次真正入库的项目采集**，被跳过的已存在项目不再做无用采集 |
| `Models/TagManager.swift` | `reloadProjects()`：`projectIndex.loadProjects`（git + 校验和）移到 `ioQueue`，回主线程只做注册 |
| `Models/Project.swift` | 新增 `copyWith(gitDaily:)`：回写时只替换 git_daily，不用采集时的旧快照覆盖用户此刻改过的标签/端口 |
| `Models/TagStorage.swift` | 新增 `init(appSupportURL:)`：让存储可注入（测试不再碰真实用户数据） |
| `Models/GitDailyCollector.swift` | 新增 `gitHeadCacheURLOverride`：HEAD 缓存路径可注入（此前写死真实目录、不经过 TagStorage） |

### 验证

- `Tests/ProjectManagerTests/ProjectRegistrationTests.swift`（6 例）：断言 `registerProjects` **返回时 git_daily 仍为 nil**（即调用线程没跑 git）且项目已可见，随后异步补齐；`updateGitDaily: false` 不触发采集；重复注册被跳过；写入只落在注入的临时存储。
- 全量套件：60 通过 / 1 跳过 / 0 失败 / 2.9 s；且实测 `swift test` 前后真实目录的 `git_heads.json` 与 `projects.json` **未变动**。

### 遗留（同为后台，但仍是浪费）

- **每个项目一次 `git rev-parse HEAD`**（10.9 ms × N ≈ 3.8 s）：可直接读 `.git/HEAD` + 对应 ref 文件（零进程），或先按目录 mtime 粗筛。
- `collectGitDaily` 仍串行（16-30 行），且 `git log` 无 `--since`、外套 `bash -c`：冷启动全量 193 仓库 ≈ 7.0 s；加 `--since` + 直调 `/usr/bin/git` ≈ 4.6 s，并发 6 路 ≈ 1.2 s。
- 每个项目仍打 2 行含完整输出的 `print`（193 项目 = 386 行同步日志）。

---

## 4. P1（待办，可顺手做）

| # | 位置 | 问题 | 实测 | 修法 |
|---|---|---|---|---|
| 1 | `ProjectLoaderOptimized.updateProjectsIncremental`（150-200） | 每次增量都全量遍历；`ProjectIndex.needsRescan(_:)`（`ProjectIndex.swift:236`）定义后**无人调用**（死代码） | 2376 目录 ≈ 0.6 s（后台） | 未过期目录直接读索引 `children` |
| 2 | `HeatmapDataStore` vs `HeatmapLogic` | 侧边栏与看板两套实现、两种口径（本次只修了看板这条） | — | 收敛到 `HeatmapDataStore` |
| 3 | `SidebarView.swift:91` | 在 `body` 里调用 `HeatmapDataStore.shared.refreshIfNeeded(...)`，副作用进了渲染路径 | 触发时全量重算 | 移到 `.task {}` / `onChange` |
| 4 | `DirectoryListView.swift:17-19`、`TagManager.swift:838-858` | 每次 body 重算 `directoryAssignment()`；`unassignedProjects()` 内部又重算一次 | 毫秒级 | 缓存 assignment，`projects` 变化时失效 |
| 5 | `GitDailyCollector.getCommitCount` / `getRecentActivity` | 热力图改完后**已无调用方**（本次保留 API，只修了 formatter） | — | 确认无外部用途后可删 |
| 6 | `MainContentView.swift:120-128` | 每卡片每次渲染重算 `project.tags.sorted().map { getColor }` | 347 × 排序+查色 | 已用 `.equatable()`，收益有限，低优先 |

---

## 5. 不建议做

- `Project.isProjectExists` 的 O(P²) 查重：**实测 0.6 ms**。
- `ProjectIndex.saveIndex` 全量写 277 KB：低频、批量后一次，可接受。
- 引入 FSEvents 替掉定时增量扫描：架构改动大，当前 0.6 s 后台开销不构成痛点。
- 给 `Project` 换存储结构 / 拆 1679 行的 `TagManager`：可维护性议题，与性能无关。

---

## 6. 测试套件修复（2026-09-20）

`swift test` 此前编译不过，且死因不只是编译错：

| 文件 | 测试数 | 处理 |
|---|---|---|
| `TagSystemTests` | 22 | 🗑 删除 —— 全部基于已删除的 `SimpleTagManager`（2026-01-19 「Linus 重构」删除） |
| `ProjectSystemTests` | 15 | 🗑 删除 —— 全部基于已删除的 `SimpleProjectManager` |
| `FileMonitoringTests` | 16 | 🗑 删除 —— 用 `SimpleTagManager` 做 delegate |
| `DataSerializationTests` | 15 | 🗑 删除 —— 测 `TagColorInfo`、`convertToLinusFormat` 等已删类型 |
| `MockSystem` | — | ♻️ 重写 —— 去掉无法编译的 `MockTagStorage`（`TagStorage` 不可子类化，见下）；`MockProject` 改为适配当前扁平模型的 `ProjectFixtures` |
| `BusinessTaggerTests` | 10 | ♻️ 重写 —— 原用例把内容写进未被使用的 `content` 变量，实际靠「项目名 + 用户当时的规则集」命中，用户改规则就红（本机实测 2 条红）。现：README 落盘临时目录 + 显式传 `defaultRules` |
| `GitDailyCollectorTests` | 13 | ➕ 新增（解析/格式化/查表的纯函数契约 + formatter 单例护栏） |
| `ProjectModelTests` | 10 | ➕ 新增（projects.json 字段契约、往返、前后兼容、Equatable、兼容属性） |
| `HeatmapLogicTests` | 10 | ➕ 新增（P0-1 回归：窗口形状、每日聚合与顺序、侧边栏数据驱动范围、确定性、365 天 × 200 项目 < 1s） |
| `DirectoryLogicTests`（并行会话新增） | 11 | 其中 1 条端到端用例默认跳过，原因见下 |
| `ProjectRegistrationTests` | 6 | ➕ 新增（P0-2 回归：注册不在调用线程采 git、异步补齐、跳过已存在、存储隔离） |

**结果**：`swift test` 60 个用例、1 跳过、0 失败，全程 **2.9 s**。

**必须知道的两件事**

1. **测试曾会污染真实用户数据**。`TagManager()` 是生产组合根：它读真实 `~/Library/Application Support/com.projectmanager`（本机 358 个项目）、在 `initializeTagColors()` 里 `saveAll(force: true)` 写回、并开始监视真实目录。`DirectoryLogicTests.testTagManagerDirectoryCountMatchesFilterResult` 直接构造了它 —— 断言因此失真（用真实数据算），且会写你的数据。现已默认跳过（`XCTSkip`，需要时设 `RUN_TAGMANAGER_E2E=1` 强制跑），并已实测：修复后 `swift test` 前后 `projects.json` / `app_state.json` / `git_heads.json` **均未改动**。
   - 除组合根外，还补了另一个漏点：`GitDailyCollector` 的 HEAD 缓存（`git_heads.json`）原先写死真实目录、**不经过 `TagStorage`**，任何跑 git 采集的测试都会写真实目录；现已可注入（`gitHeadCacheURLOverride`）。
2. **`MockTagStorage` 不是笔误，是设计缺口**。`TagStorage.appSupportURL` 原本是 `let` 且类非 open，跨模块无法子类化。现已补上 `init(appSupportURL:)`，`ProjectOperationManager` 这一层已可完全隔离测试（`ProjectRegistrationTests` 就是这么做的）。剩下的一半是 `TagManager` 本身的注入点 —— 它的 init 硬构造 `AppStateStorage()`/`TagStorage()`，也是那条 e2e 用例恢复的前提（待其重构落地后再做）。

**顺带修的真 bug**：`GitDailyCollector.parseGitDaily` 会把 `":3"` 解析成 `["": 3]`（空日期键，永远查不到），已收紧为拒绝空键。

---

## 7. 验证方法与已知边界

- **P0-1 的验证**：分层对照 harness（从 `git show HEAD:...` 与工作区源码抽取函数原文，唯一人为改名是让旧函数调旧 `getCommitCount`）+ 主 actor 心跳功能验证 + 现在新增加的 `HeatmapLogicTests` 作为长期回归护栏。复现命令见附录。
- **门禁**：`swift test` 可用（60 通过 / 1 跳过 / 0 失败 / 2.9 s）；`swift build` 通过。
- 主线程/主 actor 结论来自「`View` 协议 MainActor 隔离 + `Task` 继承 + `assertIsolated` + 心跳实测」，未做 Instruments Time Profiler 采样。

---

## 附：复现脚本

```bash
# 1) 导出真实数据
python3 -c "
import json,os
d=os.path.expanduser('~/Library/Application Support/com.projectmanager')
a=json.load(open(os.path.join(d,'projects.json')))
open('/tmp/proj.tsv','w').write(''.join('%s\t%s\n' % (p['name'], p.get('git_daily') or '') for p in a))"

# 2) 生成分层对照 + 功能验证 harness（从仓库源码抽取，不手抄）
#    模板：/tmp/heatparity/template2.swift（含 A/B/C 三段 enum 与 %PARSE% %OLD_GEN% %MID_GEN% %NEW_GEN% 占位）
#    抽取：git show HEAD:...BusinessLogic.swift 取旧 generate；
#          工作区 BusinessLogic.swift 取新 generate；GitDailyCollector.swift 取 parseGitDaily；
#          git show HEAD:...GitDailyCollector.swift 取旧 getCommitCount（改名 getCommitCountHead 以并列对照）
swiftc -O /tmp/heatparity/layered.swift -o /tmp/heatparity/layered && /tmp/heatparity/layered
# 期望：A 5.3s / B 1.7s / C 0.006s，且「指纹 A==B==C ✅」与 PARITY: PASS
```
