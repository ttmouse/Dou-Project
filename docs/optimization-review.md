# 优化审查记录

> 本文档由 ZCode 定时优化审查任务自动维护：定期扫描近期改动，聚焦最近修改的文件输出有代码依据的优化点。已有条目不重复记录，修复后请在对应条目标注「已修复（日期）」。

最近更新：2026-09-29 03:09

## 2026-09-29 03:09

本轮范围：git 未提交改动（TagManager、GitDailyCollector、TagManagerComponents、AutoTagger/BusinessTagger 等模型层近期重构）。本轮改动整体质量较高（删除 200+ 行 NSAlert 进度弹窗、git 采集移后台、热力图建倒排索引、DateFormatter 静态复用、print→Log 迁移、测试补齐）。

- [高] Sources/ProjectManager/Models/TagManagerComponents.swift:357-378 + 288-299 + 317-330 — FSEvents 每次（0.8s 防抖）批次都会在主线程同步全量重写 projects.json，且写入非原子
  证据：`FileSystemEventMonitor` 开启 FileEvents（防抖后回调 `updateActivity(for:)` 与 `incrementallyReloadProjects`，342-345 行）；`updateActivity` 在 `DispatchQueue.main.async` 里先做 O(变更路径×项目数) 的 `hasPrefix` 匹配（361-365 行），随后 `updateProjects`（376 行）→ `saveToCache()`（298 行）→ 主线程同步 `JSONEncoder().encode` 全部项目 + `try data.write(to: cacheURL)`（320-325 行），无 `.atomic`。对比同批新增的 `saveGitHeadCache` 用了 `.atomic`（GitDailyCollector.swift:249）。
  为什么改：构建/编辑活动期间每 0.8s 一次全量 JSON 编码+写盘都落在主线程（每条 git_daily 是 365 天紧凑字符串，300 项目可达 MB 级），是新的卡顿源；非原子写入在崩溃瞬间可截断 projects.json——而它是 TagManager 启动恢复的唯一缓存。
  怎么改：合并留在主线程、`saveToCache` 挪到串行 I/O 队列异步执行并加 2-3s 合并去抖；写入改 `.atomic`；路径匹配复用 `DirectoryLogic.isSubpath`。

- [高] Sources/ProjectManager/Models/GitDailyCollector.swift:70-79 + 277-309 — git 历史采集仍走 `bash -c` 拼接命令，路径含单引号即可逃逸引号，且比新代码风格落后一代
  证据：`collectSingleProjectGitDaily` 构造 `cd '\(project.path)' && git log ... | sort | uniq -c | awk ... | tr ... | sed ...` 交 `executeShellCommand`（280-282 行 `process.arguments = ["-c", command]`）执行；同文件本轮新增的 `currentGitHead`（255-274 行）已示范正确写法：`process.executableURL = /usr/bin/git` + `arguments`，不经 shell。另外 `executeShellCommand` 每次打印完整命令与完整输出（278、303 行）。
  为什么改：项目路径来自磁盘扫描/拖拽，任何含 `'` 的目录名既导致采集失败，也可注入任意 shell 命令（本地安全/健壮性隐患）；5 个管道子进程纯属浪费，Swift 端按天聚合一行 `git log --pretty=%cd --date=short` 输出即可。
  怎么改：仿 `currentGitHead` 用 `Process` 直接调 git，在 Swift 里按天计数生成 git_daily，删除 `executeShellCommand`。

- [中] Sources/ProjectManager/Models/GitDailyCollector.swift:327-345 — `withUpdatedGitDaily` 重建 Project 时漏传 `activityAt`，会把活动时间悄悄回退为 mtime
  证据：329 行起的 `Project(id:...)` 参数列表没有 `activityAt:`，而 `Project.init` 中 `self.activityAt = activityAt ?? self.mtime`（Project.swift:119）；唯一调用点是右键「刷新项目」（TagManager.swift:1006）。同批改动在其他所有重建点都补了 `activityAt: project.activityAt`（AutoTagger.swift:324/343、BusinessTagger.swift:229/248 等），唯独此处遗漏。排序 `.lastModified` 比较的就是 `activityAt`（TagManagerComponents.swift:74），日期筛选也用它。
  为什么改：刷新单个项目后，该项目会从「最近活动」排序和日期筛选中错误地退回 mtime；且暴露结构性风险——全仓有 9 处手工重建 Project 的样板，每加一个字段都要遍历修改，这次就漏了一处。
  怎么改：短期在 329 行补 `activityAt: project.activityAt`；长期仿照已有的 `Project.copyWith(...)` 把全部字段重建收敛为一个统一 copy 助手，替换散落各文件的样板。

- [中] Sources/ProjectManager/Models/AutoTagger.swift:1-367 — 整个 AutoTagger（367 行）在生产代码中已无任何调用者，是 BusinessTagger 的同构重复
  证据：全仓 grep `AutoTagger` 仅命中 TagManager.swift:407 的注释，`generateTags/applyAutoTags/debugRules`（281/314/358 行）无调用、无测试引用；其结构与 BusinessTagger 完全同构，规则体里还有逐项目解析 package.json 的磁盘 I/O（24-56 行）。本轮 diff 仍不得不为它的两处 Project 重建补 `activityAt`——死代码也要跟着改。另：本轮新增的 `TagManager.isProject(_:in:)`（880-882 行）与 `projectCount(in:)`（896-898 行）同样无任何调用点。
  为什么改：约 400 行不可达代码继续参与编译与字段同步维护，误导后续开发者以为有两条打标链路。
  怎么改：删除 AutoTagger.swift 与 TagManager 中两个无调用助手；若想保留「文件特征打标」能力，先把规则迁移进 BusinessTagger 的规则存储并配测试，而不是留双轨。

- [低] Sources/ProjectManager/Models/GitDailyCollector.swift:278/303 + TagManagerComponents.swift:188-189/326/328 — 本轮专门新建了 Log.swift 分级日志，但热路径的 print 迁移未完成
  证据：Log.swift 注释明确写着「此前大量 print 直接输出导致日志可达 50KB+」（8-9 行），但同一批改动里：`executeShellCommand` 每项目打印命令+全量输出（278/303 行）；`registerProjects` 每批打印 3 行（188/189/248 行）；`saveToCache` 每次保存都打印——结合第一条，该函数现在每个 FSEvents 批次都会执行一次；TagManager.swift 仍余 63 处 print（含本轮触碰过的 233、275、904 行）。
  为什么改：Release 包里这些 print 依旧输出（`#if DEBUG` 只保护了已迁移部分），高频路径反而因 FSEvents 变得更吵。
  怎么改：把改动文件内 print 全部收口到 `Log.debug/info/error`（操作统计用 info，逐项目循环体用 debug）；顺手给 `Log.info/error` 也加 `@autoclosure`。
