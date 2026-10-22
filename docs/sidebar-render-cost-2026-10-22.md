# 侧边栏重绘成本修复 · 2026-10-22

用户反馈：搜索感觉卡顿。搜索链路的**过滤计算**此前已被优化并验证，但真实界面里
还有两条与搜索无关、却会被搜索的整页重绘一起带上的重路径。本轮只处理这两条。

## 复现与测量

用真实数据规模（`~/Library/Application Support/ProjectManager/projects.json`，131 个项目）
复刻生产同构的纯逻辑路径，用独立可执行文件测量（`swiftc -O`）：

| 路径 | 旧实现 | 新实现 |
| --- | --- | --- |
| `DirectoryLogic.assign`（131 项目 / 4 目录） | 3.71 ms | 0.061 ms |
| `DirectoryLogic.assign`（500 项目 / 4 目录） | 12.93 ms | 0.239 ms |
| `DirectoryLogic.assign`（2000 项目 / 4 目录） | 48.91 ms | 0.952 ms |
| 标签排序（比较器内重算统计，131 项目 / 20 标签） | 3.67 ms | 0.020 ms |
| 标签排序（2000 项目 / 20 标签） | 11.47 ms | — |

两条路径都在**侧边栏 body 求值**里执行，因此每次搜索引起整页重绘时都会被走一遍。

## 根因

### 1. 目录归属：逐项目收集全部候选目录

`DirectoryLogic.assign` 对每个项目做
`normalizedDirectories.filter { isSubpath(path, of: $0) }` 收集**全部**匹配目录，
再 `max(by: { $0.count < $1.count })` 取最深的一个。而 `isSubpath` 内部
每次调用都重新规范化两条路径（`expandingTildeInPath` + 去尾斜杠）。
复杂度是 O(项目数 × 目录数)，每次比较还附带两次路径规范化。

`DirectoryListView.body` 无条件调用 `tagManager.directoryAssignment()`，
而它是 `@ObservedObject`，所以 `TagManager` 每次变化都会重算一遍。

### 2. 标签排序：比较器内重算全量统计

`TagListView.tagListContent` 写的是：

```swift
Array(tagManager.allTags).sorted { tag1, tag2 in
    let count1 = tagManager.getUsageCount(for: tag1)   // 每次都重算整份统计
    let count2 = tagManager.getUsageCount(for: tag2)
    return count1 > count2
}
```

`getUsageCount` → `AppStateLogic.getTagStatistics` → `TagLogic.calculateTagUsage`
每次都遍历全部项目重算。排序比较器被调用 O(标签数 × log 标签数) 次，
等于把全量统计重算了这么多次。

## 改动

1. **目录归属**：目录预先按路径长度降序排列，命中最深目录即可停止，
   每个项目只需一次前缀判断。`standardizedPath` 只在路径以 `~` 开头时才调
   `expandingTildeInPath`（其余情况 Foundation 原样返回，属于无谓开销）。
2. **标签排序**：统计先算一次再排序，排序逻辑抽成可测的纯函数
   `TagLogic.sortTagsByUsage(_:usage:)`；并列时按名称升序，保证结果稳定可复现
   （旧实现的并列顺序取决于 `Set` 的迭代顺序，不可复现）。

## 等价性验证

- 新旧 `assign` 实现用随机化输入做对照：2000 组随机
  （0–4 个目录、0–12 条路径，含前缀相似目录、嵌套目录、根目录），
  **2000/2000 结果完全一致**。
- 语义护栏：最深目录优先、与输入顺序无关、同长度目录确定可复现、
  根目录吞掉一切、组件边界不误吞、`~` 与尾斜杠规范化照常生效。

## 验证

```sh
swift test                      # 106 个测试，1 个已有跳过，0 失败
swift test -c release --filter "ProjectListViewModelTests|DirectoryAssignmentPerformanceTests|TagUsageSortingTests|SidebarRenderCostTests"
swift build -c release
```

新增三个测试文件（14 个测试）：

- `DirectoryAssignmentPerformanceTests`（7 个）—— 归属语义 + 成本护栏
- `TagUsageSortingTests`（6 个）—— 排序语义 + 成本护栏
- `SidebarRenderCostTests`（1 个）—— 一次侧边栏重绘的总成本

Release 实测：

- 搜索输入到结果（原生 `NSTextView` 逐字输入，501 项目）：**65.67 / 4.14 / 5.77 / 2.82 ms**
  （首值含首次结果布局，不能只报后续字符）
- 侧边栏重绘（1000 项目 / 40 标签）：**0.68 ms**
- 目录归属（2000 项目 / 4 目录）：**0.84 ms**

## 边界

- 未做 Instruments 真实滚动帧时间采样，数字是计算成本与夹具布局成本，不是完整帧时间。
- `TagManager` 仍缺存储注入点（`DirectoryLogicTests` 里那个 e2e 测试因此默认跳过），
  本轮没有动这个结构性问题。
- 目录归属的 `Assignment` 仍在每次 body 求值时重算。本轮把它从 48.91 ms 降到 0.95 ms，
  属于「消除重复计算」而非「加缓存」。若项目数继续增长，下一步应改为按
  `projects` / `watchedDirectories` 变更事件失效的缓存。
- 同一天另有并发会话在改搜索链路本身（去 180 ms 停顿、拆搜索与筛选、
  目录候选复用），本轮只动了它没有碰的两个文件：`BusinessLogic.swift`、
  `SidebarView.swift`。两边无文件重叠。
