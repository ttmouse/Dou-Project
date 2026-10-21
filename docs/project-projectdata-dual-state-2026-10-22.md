# Project / ProjectData 双份状态：差异清单与收敛前置条件

对应审计：`docs/performance-audit-2026-10-21.md` → 后续重构 #1「收敛双份项目状态」。

本文件只做一件事：在选定唯一状态模型**之前**，把两份模型的实际差异写清楚，并用契约测试钉住。
不迁移、不改 `projects.json` 格式、不改任何用户可见行为。

## 1. 现状：两个类型，谁在什么时候被用

| | `Project` | `ProjectData` |
| --- | --- | --- |
| 定义 | `Models/Project.swift` | `Models/DataModels.swift` |
| 角色 | 应用的真实状态 | BusinessLogic 的纯输入/输出 |
| 持久化 | **是**：`projects.json` 编码的就是它 | 否，纯内存 |
| 是否引用磁盘 | 是（`notes` 计算属性、初始化器可回落探测） | 否（全存储属性） |
| 唯一写入者 | `TagManager.projects`（+ `sortManager`） | 无。只在函数间流动 |

关键事实：`projects.json` 只认 `Project`。`ProjectData` 从不落盘，它只是
`BusinessLogic.swift` 里那批纯函数的参数类型；`TagManager` 每次调用前后都要
`toProjectData()` / `fromProjectData()` 来回搬一趟。

因此**唯一状态模型**的答案几乎只能是 `Project`（或一个 `Project` 能无损映射过去的类型），
`ProjectData` 若保留就应退化成只读投影，而不是第二份真相。

## 2. 逐字段差异

`Project` 有 15 个存储属性；`ProjectData` 有 16 个（多一个 `notes`，少一个 `activityAt`）。

| 字段 | `Project` | `ProjectData` | 差异后果 |
| --- | --- | --- | --- |
| `id` `name` `path` `tags` | 存储 | 存储 | 一致 |
| `mtime` `size` `checksum` | 存储 | 存储 | 一致 |
| `git_commits` `git_last_commit` `git_daily` | 存储 | 存储 | 一致（但见 §3 的复制缺陷） |
| `startupCommand` `customPort` | 存储 | 存储 | 一致（但见 §3） |
| `created` `checked` | 存储 | 存储 | 一致（但见 §3） |
| **`activityAt`** | 存储，`var`，**排序键 + 日期筛选键** | **不存在** | 往返后退化为 `mtime` |
| **`notes`** | 每次访问同步读 `PROJECT_NOTES.md` | 转换瞬间的内存快照 | 语义完全不同 |
| `Equatable` | 手写，**排除** `notes` | 合成，**包含** `notes` | 两个模型对「相等」的定义不同 |

### 2.1 `activityAt`：真正会改变行为的缺口

`TagManagerComponents` 的排序比较器用 `activityAt` 排 `.lastModified`，
`ProjectListView` 的日期筛选也用 `activityAt`。`ProjectData` 里没有这个字段，
`Project.fromProjectData` 只能让初始化器把 `activityAt` 缺省成 `mtime`。

后果：任何走过 `ProjectData` 的操作（加/删标签、批量打标、刷新、重命名）
回写后，该项目的 `activityAt` 会被抹成 `mtime`，列表顺序和日期筛选结果随之变化。
`TagUsageSortingTests`、`ProjectListSortingTests` 都直接读 `Project.activityAt`，
所以这条缺口不会被现有测试发现。

### 2.2 `notes`：一侧是磁盘，一侧是内存

- `Project.notes` 是计算属性，**每次读取都同步做一次文件 I/O**。
  `ProjectListView` 的搜索注释里已明确记录过这条代价，并因此在搜索路径上禁用。
- `ProjectData.notes` 是转换那一刻的快照，之后不再变化。

于是 `Project → ProjectData → Project` 会把内存中的备注丢掉（除非磁盘上还有文件），
而 `ProjectData` 的 `Equatable` 又包含 `notes`，所以同一个项目仅因磁盘备注变化就「不相等」。
这在语义上是自相矛盾的：`ProjectData` 声称自己是纯数据，却让磁盘内容参与了相等性。

### 2.3 转换本身的隐式 I/O

`Project.init` 在元数据缺失时才读磁盘（2026-10-21 已修）。但 `fromProjectData`
的 15 个参数里 `activityAt` 恒为 `nil`，其余齐全，所以当前转换不会触发 Git 探测。
契约测试 `testConversionDoesNotTouchDiskWhenMetadataComplete` 用不存在的路径锁住了这一点，
防止未来的收敛改动把 I/O 带回转换路径。

## 3. 已确认并修复的复制缺陷（本轮）

在写契约测试时暴露出来的真实数据丢失，不是设计取舍：

`TagLogic.addTagToProject` / `removeTagFromProject`、`ProjectOperations.updateProject` /
`batchUpdateTags` / `mergeProject`，以及刷新与重命名路径，都用
`ProjectData(lastModified:tags:notes:gitInfo:fileSystemInfo:)` 这个**旧嵌套初始化器**复制对象。
该初始化器只认旧结构，会把 `git_daily`、`startupCommand`、`customPort` 置为 `nil`，
并把 `created` 改写成 `fileSystemInfo.lastCheckTime`。

`TagManager.addTagToProject` 随后执行 `Project.fromProjectData(...)` 并 `saveAll()`,
所以**给项目打一个标签就会把该项目写进 `projects.json` 的 `git_daily` / `startupCommand` /
`customPort` 清空、`created` 改成今天**。热力图会因此丢数据，自定义端口会丢配置。

修复方式：`ProjectData` 增加按字段就地复制的方法（`replacingTags`、`replacingNotes`、
`replacingFileSystem`、`replacingGit`），全部走扁平初始化器，只改调用方点名的字段。
改动集中在 6 个纯函数，不触及状态归属，不属于「大规模迁移」。

## 4. 收敛时必须先回答的问题（本卡不回答）

1. `activityAt` 是否升格为两份模型共有的字段？如果升，`projects.json` 契约不变（它本来就有）。
2. `notes` 留在模型里，还是变成按需查询的旁路服务？只要它还是计算属性，
   `Equatable`、排序、任何批量操作都无法安全地直接读它。
3. `ProjectData` 是删除，还是降级为「不含 I/O 的只读投影」？
4. `TagManager` 现在同时维护 `projects: [UUID: Project]` 与 `appState.projects: [UUID: ProjectData]`
   两份字典，并在 13 处手工同步。这是真正的双份状态，收掉它才算收敛完成。

## 5. 验证

```sh
swift test --disable-sandbox --filter ProjectDataConversionContractTests
swift test --disable-sandbox
```

`--disable-sandbox` 是本机 `swift test` 默认沙箱在 Package.swift manifest 编译阶段
报 `sandbox_apply: Operation not permitted` 时需要的绕行，与代码质量无关。

契约测试分两类：
- **契约**：字段映射必须恒成立；
- **已知缺口**：`activityAt` 与 `notes` 的当下行为，用于把差异固定成可执行的断言。
  收敛落地时这些断言应随之翻转，而不是被静默删除。
