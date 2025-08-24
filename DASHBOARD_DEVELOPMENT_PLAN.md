# 📊 项目管理器仪表盘开发计划

## 🎯 项目目标

为项目管理器添加一个功能强大的仪表盘，帮助开发者更好地理解和管理一两百个小型项目的开发活动。基于现有的Git集成和数据架构，提供类似GitHub的活动可视化和项目健康度分析。

## 📋 现有架构分析

### 已有的数据基础
- `Project.gitInfo`: 包含 `commitCount` 和 `lastCommitDate`
- `Project.fileSystemInfo`: 包含文件修改时间和大小信息
- 标签系统：已完善的标签管理和过滤功能
- 业务逻辑层：`BusinessLogic.swift` 中的纯函数架构

### 技术栈
- SwiftUI + macOS原生框架
- 现有的MVVM架构
- 文件系统集成
- Git命令行工具集成

## 🚀 核心功能模块

### 1. 📈 每日提交活动热图
**功能描述**: 类似GitHub的贡献图，显示最近90天的开发活动

**数据结构**:
```swift
struct DailyActivity {
    let date: Date
    let commitCount: Int
    let projects: Set<UUID>  // 哪些项目有提交
}
```

**实现要点**:
- 基于现有 `GitInfo.lastCommitDate` 和 `commitCount`
- 按日期聚合所有项目的提交数据
- 热图可视化，颜色深浅表示活跃度
- 支持点击查看具体项目和提交详情

### 2. 🏆 项目活跃度排行
**功能描述**: 根据提交活动计算项目活跃度分数，帮助识别重要项目

**数据结构**:
```swift
struct ProjectActivityScore {
    let projectId: UUID
    let score: Int  // 基于提交频率和最近活动
    let trend: Trend  // 上升/下降/稳定
}
```

**实现要点**:
- 活跃度算法：`score = commitCount * recencyWeight`
- 趋势分析：比较最近7天 vs 前7天的提交数量
- 排行榜展示，支持按不同时间段筛选
- 快速跳转到项目详情

### 3. 🔍 开发模式分析
**功能描述**: 分析个人开发习惯和模式

**数据结构**:
```swift
struct DevelopmentPattern {
    let mostActiveHour: Int
    let mostActiveDay: String
    let averageCommitsPerDay: Double
    let streakDays: Int  // 连续开发天数
    let totalProjects: Int
}
```

**实现要点**:
- 基于提交时间分析开发时段偏好
- 计算连续开发天数（类似GitHub streak）
- 平均每日/每周提交统计
- 项目切换频率分析

### 4. 🏥 项目健康状态
**功能描述**: 监控项目健康度，识别需要维护的项目

**数据结构**:
```swift
struct ProjectHealth {
    let projectId: UUID
    let lastActivity: Date
    let commitFrequency: Double  // 每周平均提交数
    let isStale: Bool  // 超过30天无活动
    let sizeGrowth: Double  // 项目大小变化
}
```

**实现要点**:
- 健康度评分算法
- 闲置项目警告（30天+无活动）
- 项目大小增长趋势
- 依赖更新状态检查（未来扩展）

### 5. 🏷️ 标签活动统计
**功能描述**: 基于现有标签系统，分析不同标签的项目活动

**数据结构**:
```swift
struct TagActivity {
    let tagName: String
    let projectCount: Int
    let totalCommits: Int
    let lastActivity: Date
}
```

**实现要点**:
- 按标签聚合项目活动数据
- 标签热度排行
- 标签活动趋势图
- 支持点击标签查看相关项目

## 📁 文件结构规划

```
Sources/ProjectManager/
├── Models/
│   ├── Dashboard/                   # 新增仪表盘相关模型
│   │   ├── DashboardModels.swift   # 仪表盘数据结构
│   │   └── DashboardAnalytics.swift # 分析计算逻辑
│   ├── BusinessLogic.swift         # 扩展统计分析函数
│   └── Project.swift               # 扩展计算属性
├── Views/
│   ├── Dashboard/                   # 新增仪表盘视图
│   │   ├── DashboardView.swift     # 主仪表盘视图
│   │   ├── ActivityHeatmap.swift   # 活动热图组件
│   │   ├── ProjectRanking.swift    # 项目排行组件
│   │   ├── DevelopmentPattern.swift # 开发模式组件
│   │   ├── ProjectHealth.swift    # 项目健康度组件
│   │   └── TagActivity.swift      # 标签活动组件
│   └── Components/
│       └── ChartComponents.swift  # 图表基础组件
├── ViewModels/
│   └── DashboardViewModel.swift    # 仪表盘视图模型
└── Resources/
    └── Assets.xcassets/            # 图表相关资源
```

## 🛠️ 技术实现方案

### 第1阶段：数据层扩展
1. **扩展Project模型**
   - 添加计算属性：`activityScore`, `healthStatus`
   - 扩展GitInfo分析方法

2. **创建DashboardAnalytics**
   - 实现数据聚合算法
   - 活动统计分析
   - 趋势计算逻辑

3. **扩展BusinessLogic**
   - 添加纯函数统计分析
   - 健康度评估算法
   - 排序和过滤逻辑

### 第2阶段：视图层开发
1. **创建DashboardView**
   - 采用现有的SwiftUI设计风格
   - 响应式布局适配不同屏幕尺寸
   - 与现有导航系统集成

2. **开发图表组件**
   - 热图组件（类似GitHub贡献图）
   - 柱状图和折线图组件
   - 进度条和指示器组件

3. **集成现有UI组件**
   - 复用现有标签样式
   - 使用现有主题色彩
   - 保持交互模式一致

### 第3阶段：性能优化
1. **数据缓存策略**
   - 利用现有的缓存机制
   - 增量数据更新
   - 后台预计算

2. **UI性能优化**
   - 虚拟化列表
   - 图表渲染优化
   - 防抖和节流处理

## 🎨 UI/UX设计原则

### 设计风格
- 保持与现有应用的一致性
- 使用现有的主题色彩系统
- 遵循macOS设计规范

### 交互设计
- 点击图表元素查看详情
- 支持时间段筛选（日/周/月）
- 快速跳转到相关项目
- 支持数据导出功能

### 信息层级
- 重要指标优先显示
- 使用颜色和大小传达信息重要性
- 提供详细的工具提示

## 📅 开发时间线

### 第1周：数据层开发
- 扩展Project模型和计算属性
- 实现DashboardAnalytics
- 扩展BusinessLogic统计分析

### 第2周：核心视图开发
- 创建DashboardView主界面
- 实现活动热图组件
- 开发项目排行组件

### 第3周：高级功能开发
- 开发模式分析组件
- 项目健康度监控
- 标签活动统计

### 第4周：优化和完善
- 性能优化
- UI细节完善
- 测试和bug修复

## 🎯 成功指标

### 功能指标
- ✅ 90天内活动数据可视化
- ✅ 项目活跃度准确计算
- ✅ 开发模式识别准确率 > 90%
- ✅ 闲置项目识别准确率 > 95%

### 性能指标
- ⚡ 仪表盘加载时间 < 2秒
- ⚡ 图表交互响应时间 < 200ms
- ⚡ 内存使用增长 < 50MB

### 用户体验指标
- 🎯 用户满意度 > 4.5/5
- 🎯 功能使用率 > 70%
- 🎯 用户留存率提升 > 20%

## 🔧 集成考虑

### 与现有功能的集成
- 在主界面添加仪表盘入口
- 与项目列表视图保持导航一致性
- 利用现有的标签系统进行数据过滤

### 数据同步
- 与现有的文件监控系统集成
- 确保Git数据实时更新
- 保持与项目缓存的一致性

### 扩展性考虑
- 为未来添加更多图表类型预留接口
- 支持自定义仪表盘布局
- 考虑导出和分享功能

## 📝 注意事项

### 技术风险
- Git命令执行性能问题
- 大量数据可视化的性能挑战
- 复杂统计计算的准确性

### 用户体验风险
- 信息过载影响可用性
- 学习成本增加
- 与现有工作流整合

### 缓解策略
- 采用渐进式加载
- 提供简化视图选项
- 保持现有功能不变性

---

**文档创建时间**: 2025-08-24  
**预计完成时间**: 4周  
**优先级**: 高  
**负责人**: 开发团队  

这个计划将帮助开发者更好地理解和管理大量小型项目，提供类似GitHub的专业级项目分析功能。