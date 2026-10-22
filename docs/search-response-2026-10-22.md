# 搜索跟手性修复 · 2026-10-22

用户反馈：输入名称后，结果不够及时，搜索感觉卡顿。此前只验证过滤计算时间，没有验证文本编辑到结果更新的完整路径。

## 复现

- 新增“下一轮主队列即显示当前输入结果”“输入本身不通知整个列表”“快速替换只显示最新查询”三个回归测试。旧实现共出现 9 条断言失败。
- 新增目录候选复用测试，确认选中目录后每次输入都会重新解析目录归属；旧实现失败。
- 原因包括固定 180 ms 停顿等待、搜索文字直接属于整页观察的 ObservableObject，以及目录/标签筛选每个字符重复计算。

## 改动

1. 搜索框使用独立 ProjectSearchInput。只有搜索框观察原始输入，列表只在结果确实改变时发布更新。
2. 移除本地搜索的 180 ms 等待，下一轮主队列读取已写入的最新文字。保留原生 SwiftUI TextField 与输入法处理。
3. 目录、隐藏标签、标签和热力图筛选的结果缓存为搜索候选，仅这些条件或项目数据变化时重建。输入只匹配已有索引并计算日期筛选。
4. Git 历史回填同时更新候选缓存，避免后续搜索重新拿到旧历史。搜索仍覆盖名称和路径，保持现有排序。

## 验证

全量 `swift test`：**92 个测试，1 个已有跳过，0 失败**。搜索相关的 **11 个测试在 Release 下全部通过**。

原生交互测试创建隐藏 NSWindow，托管真实 SearchBar 与 SwiftUI 结果列表，使用 NSTextView 的真实编辑事件逐字输入、退格及清空。501 个项目下验证匹配结果及时变化，结果更新不更换文本编辑器、不丢失焦点。

Release 单次样本，四个字符从原生编辑事件到匹配结果和夹具布局完成分别为 **55.17、3.76、2.50、2.32 ms**。第一项含首次结果布局，不能只报告后续字符；这些数字也不能当作完整应用网格的帧时间。旧 180 ms 等待已确定移除。

本机桌面驱动未运行且权限状态未返回，因此没有通过桌面自动化测量用户当前窗口。上述原生组件测试不依赖桌面自动化，不接触真实项目存储。

复现命令：

```sh
swift test
swift test -c release --filter ProjectListViewModelTests
swift build -c release
```

按用户要求重新生成项目根目录的 ProjectManager.app 与 ProjectManager.dmg；旧包保留在本地打包临时目录。原有异步保存测试仍可能在临时目录清理后输出保存错误，此次不把测试断言通过解释为该生命周期问题已解决。

## 已关闭（2026-10-23）

- **「异步保存测试仍可能在临时目录清理后输出保存错误」——已关闭**，`17d8e14`
  `fix(storage): harden async save after temp dir removal`：
  去抖保存从 `Timer.scheduledTimer`（依赖调用线程 RunLoop，后台队列上永远不触发）
  换成 `DebouncedWorkScheduler`（串行队列 + `DispatchWorkItem`，任意线程可调度）；
  新增 `LocalJSONFile` / `LocalPersistenceError`，写盘前确认目标目录仍在，
  缺失时返回 `.directoryUnavailable` 而不是重建目录或静默丢任务；
  `TagStorage` / `AppStateStorage` 增加返回 `Result` 的保存入口，
  `TagManager` 暴露 `lastSaveError`、`drainPendingWrites`、`flushPendingSave`。
  `AsyncSaveLifecycleTests`（16 条，含「目录删除后的整条生命周期」）覆盖该契约，
  并改用临时目录注入点，不再触碰真实用户数据。本条不再作为未解释的残留保留。

仍开放：

- 本文「本机桌面驱动未运行且权限状态未返回」那条测量缺口，后来由
  `docs/live-search-measurement-2026-10-22.md` 用 ScreenCaptureKit 补上
  （搜索切换中位数 **159 ms**、清空恢复 **542 ms**，样本数有限）。
  但那份数据对应**修复前**的运行包，当前包的端到端耗时仍需按同一方法复测 —— 见新卡。
