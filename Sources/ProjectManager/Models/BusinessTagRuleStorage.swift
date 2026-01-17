import Foundation

/// 业务标签规则存储管理器
/// 负责规则的持久化存储和加载
class BusinessTagRuleStorage: ObservableObject {
    
    // MARK: - 可持久化的规则模型
    
    struct StoredRule: Codable, Identifiable, Equatable {
        var id: UUID
        var name: String
        var keywords: [String]
        var tags: [String]
        var isEnabled: Bool
        
        init(id: UUID = UUID(), name: String, keywords: [String], tags: [String], isEnabled: Bool = true) {
            self.id = id
            self.name = name
            self.keywords = keywords
            self.tags = tags
            self.isEnabled = isEnabled
        }
        
        /// 从 BusinessTagger.BusinessTagRule 转换
        init(from rule: BusinessTagger.BusinessTagRule, isEnabled: Bool = true) {
            self.id = UUID()
            self.name = rule.name
            self.keywords = rule.keywords
            self.tags = rule.tags
            self.isEnabled = isEnabled
        }
        
        /// 转换为 BusinessTagger.BusinessTagRule
        func toBusinessTagRule() -> BusinessTagger.BusinessTagRule {
            BusinessTagger.BusinessTagRule(name: name, keywords: keywords, tags: tags)
        }
    }
    
    // MARK: - 属性
    
    @Published var rules: [StoredRule] = []
    
    private let storageKey = "BusinessTagRules"
    private let userDefaults = UserDefaults.standard
    
    // MARK: - 初始化
    
    init() {
        loadRules()
    }
    
    // MARK: - 公共 API
    
    /// 加载规则，如果没有存储的规则则使用默认规则
    func loadRules() {
        if let data = userDefaults.data(forKey: storageKey),
           let storedRules = try? JSONDecoder().decode([StoredRule].self, from: data) {
            rules = storedRules
            print("📦 加载了 \(rules.count) 条业务标签规则")
        } else {
            // 使用默认规则初始化
            rules = Self.defaultRules
            saveRules()
            print("📦 使用默认业务标签规则初始化")
        }
    }
    
    /// 保存规则
    func saveRules() {
        if let data = try? JSONEncoder().encode(rules) {
            userDefaults.set(data, forKey: storageKey)
            print("💾 保存了 \(rules.count) 条业务标签规则")
        }
    }
    
    /// 添加规则
    func addRule(_ rule: StoredRule) {
        rules.append(rule)
        saveRules()
    }
    
    /// 更新规则
    func updateRule(_ rule: StoredRule) {
        if let index = rules.firstIndex(where: { $0.id == rule.id }) {
            rules[index] = rule
            saveRules()
        }
    }
    
    /// 删除规则
    func deleteRule(_ rule: StoredRule) {
        rules.removeAll { $0.id == rule.id }
        saveRules()
    }
    
    /// 删除规则（通过 IndexSet）
    func deleteRules(at offsets: IndexSet) {
        rules.remove(atOffsets: offsets)
        saveRules()
    }
    
    /// 移动规则顺序
    func moveRules(from source: IndexSet, to destination: Int) {
        rules.move(fromOffsets: source, toOffset: destination)
        saveRules()
    }
    
    /// 切换规则启用状态
    func toggleRule(_ rule: StoredRule) {
        if let index = rules.firstIndex(where: { $0.id == rule.id }) {
            rules[index].isEnabled.toggle()
            saveRules()
        }
    }
    
    /// 重置为默认规则
    func resetToDefaults() {
        rules = Self.defaultRules
        saveRules()
    }
    
    /// 获取所有启用的规则（转换为 BusinessTagRule）
    func enabledBusinessTagRules() -> [BusinessTagger.BusinessTagRule] {
        rules.filter { $0.isEnabled }.map { $0.toBusinessTagRule() }
    }
    
    // MARK: - 默认规则
    
    static let defaultRules: [StoredRule] = [
        StoredRule(
            name: "视频项目",
            keywords: ["视频", "video", "直播", "streaming", "recording", "mp4", "ffmpeg", "rtmp"],
            tags: ["视频", "多媒体"]
        ),
        StoredRule(
            name: "输入法/拼音工具",
            keywords: ["拼音", "pinyin", "input", "输入", "中文", "typing", "ime", "keyboard"],
            tags: ["输入法", "拼音"]
        ),
        StoredRule(
            name: "手机应用",
            keywords: ["mobile", "android", "ios", "app", "移动", "手机", "react-native", "flutter"],
            tags: ["移动端"]
        ),
        StoredRule(
            name: "桌面应用",
            keywords: ["desktop", "macos", "windows", "electron", "tauri", "桌面", "gui"],
            tags: ["桌面端"]
        ),
        StoredRule(
            name: "Web 应用",
            keywords: ["web", "website", "网站", "网页", "浏览器", "browser", "spa"],
            tags: ["Web"]
        ),
        StoredRule(
            name: "CLI 工具",
            keywords: ["cli", "命令行", "terminal", "console", "shell", "script", "自动化"],
            tags: ["CLI", "命令行"]
        ),
        StoredRule(
            name: "教育学习",
            keywords: ["教育", "学习", "tutorial", "course", "教程", "教学", "quiz", "题库"],
            tags: ["教育", "学习"]
        ),
        StoredRule(
            name: "社交/聊天",
            keywords: ["chat", "聊天", "social", "message", "im", "社交", "通讯", "群组"],
            tags: ["社交", "聊天"]
        ),
        StoredRule(
            name: "电商平台",
            keywords: ["电商", "e-commerce", "shopping", "cart", "购物车", "支付", "商城", "订单"],
            tags: ["电商", "购物"]
        ),
        StoredRule(
            name: "文档工具",
            keywords: ["文档", "document", "note", "笔记", "wiki", "知识库", "notion", "obsidian"],
            tags: ["文档", "笔记"]
        ),
        StoredRule(
            name: "游戏",
            keywords: ["game", "游戏", "gaming", "play", "player", "unity", "unreal", "steam"],
            tags: ["游戏"]
        ),
        StoredRule(
            name: "数据分析",
            keywords: ["data", "数据", "analytics", "分析", "chart", "图表", "可视化", "dashboard"],
            tags: ["数据分析"]
        ),
        StoredRule(
            name: "AI/机器学习",
            keywords: ["ai", "machine learning", "深度学习", "llm", "模型", "智能", "neural", "tensorflow", "pytorch"],
            tags: ["AI", "机器学习"]
        ),
        StoredRule(
            name: "博客/内容平台",
            keywords: ["博客", "blog", "cms", "内容", "article", "文章", "发布"],
            tags: ["博客", "内容平台"]
        ),
        StoredRule(
            name: "开发工具",
            keywords: ["开发工具", "devtool", "插件", "plugin", "extension", "ide", "编辑器"],
            tags: ["开发工具"]
        ),
        StoredRule(
            name: "监控系统",
            keywords: ["monitor", "监控", "logging", "日志", "alert", "告警", "trace"],
            tags: ["监控", "运维"]
        ),
    ]
}
