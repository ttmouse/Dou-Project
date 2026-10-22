# 文件事件状态发布合并 · 2026-10-22

对应 [2026-10-21 走查](performance-audit-2026-10-21.md) 后续重构第 2 项：合并文件事件引起的状态发布。

## 定位到的逐项发布点

`@Published var projects` 是唯一被逐项写入的字典，写入方全部在 `TagManagerComponents.swift`：

- `DirectoryWatcher.updateActivity(for:)` → `ProjectOperationManager.updateProjects(_:)`：FSEvents 每 0.8s 一批，命中的每个项目各写一次字典。
- `incrementallyReloadProjects` 的删除段：`removeProjectsInDirectory` 和增量删除路径都在主线程 `for` 循环里逐个 `removeProject`，每次都会发一次通知。
- `registerProjects`：循环里逐个 `delegate.projects[...] = project`，末尾再补一次 `notifyProjectsChanged()`，即 N+1 次发布。

对照：Git 回填已经改成「内存合并 + 整批发布一次」（`applyGitDaily` → `applyGitDailyUpdates`），本次把同样的边界补到文件事件路径上。

## 改法

- 新增 `ProjectBatchChange`（updates / removals / affectsTags）和纯函数 `ProjectBatchMerge.apply(into:change:)`，一次写回整本字典，值相同不计入变化。
- `ProjectOperationManager` 增加 `applyProjectBatch(updates:removals:)` 与 `applyActivityBatch(_:at:)`：合并时以**当前字典**为准，只更新仍存在的项目，只覆盖 `activityAt` 一个字段。
- `registerProjects`、`removeProjectsInDirectory`、增量删除、`removeProject` 全部走批次通道，`notifyProjectsChanged()` 不再在批量路径里逐项调用。
- `ProjectSortManager` 增加批次方法（`updateProjectsMetadata` / `insertProjects` / `removeProjects`），避免逐项 `remove(at:)` 的数组搬移。
- 标签索引改为 `ProjectTagIndexLogic.apply(to:change:previous:)` 增量维护，仅元数据变化的批次跳过。
- `Project.copyWith(activityAt:)` 只改活动时间，不覆盖事件排队期间用户改过的标签、端口、启动命令。

## 验证

`Tests/ProjectManagerTests/FileEventBatchPublishTests.swift`（12 个用例），使用注入的临时 `TagStorage(appSupportURL:)`，不碰真实用户数据、不启动第二个应用实例：

- 200 个项目一批事件：发布 **1** 次、变更通知 **1** 次，被删项目不复活、用户期间改的标签保留。
- 同一批次重复到达：发布 **0** 次。
- 对照用例记录旧的逐项写法必然发布 N 次，作为防止改回逐项赋值的护栏。
- 排序缓存跟随批次一次更新，活动时间落到正确位置。
- 标签倒排索引：整批换标签、删除清引用、纯元数据批次跳过。

命令与结果：

```sh
swift test                                              # 131 个测试、1 跳过、0 失败
swift test --filter FileEventBatchPublishTests          # 12 个全部通过
swift test -c release --filter FileEventBatchPublishTests   # 12 个全部通过
swift test -c release --filter ProjectRegistrationTests     # 10 个全部通过
swift build -c release                                  # 通过
```

测量：200 个项目的活动时间批次，Debug **0.90 ms**、Release **0.57 ms**，发布 **1** 次（旧写法为 200 次）。这是合并与发布本身的耗时，**不含 SwiftUI 绘制、不含 FSEvents 采集**，不能当作整帧时间。

边界：一次批次仍有一次必要的主线程状态提交和一次可见视图更新；本卡不做 Instruments 帧时间采样，也未涉及 ShellExecutor、异步保存等其他后续项。

一处测试断言随语义更新：`ProjectRegistrationTests.testAlreadyRegisteredProjectsAreSkipped` 原先要求「重复注册仍发一次通知」，那是旧实现的 N+1 发布；批次通道下内容无变化即不发布，断言改为 `notifyCount` 不再增长。
