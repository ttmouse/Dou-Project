import Foundation

/// 业务标签提取器 - Phase 2: 基于文档内容的业务特征分析
///
/// 设计原则：
/// 1. 零延迟：基于 README 和 .md 文档，无需外部调用
/// 2. 可扩展：用户可自定义规则
/// 3. 业务导向：关注项目类型、应用场景、功能特征
enum BusinessTagger {

    // MARK: - 业务标签规则

    struct BusinessTagRule {
        let name: String
        let keywords: [String]
        let tags: [String]

        func matches(content: String) -> Bool {
            let lowercasedContent = content.lowercased()
            return keywords.contains { keyword in
                lowercasedContent.contains(keyword.lowercased())
            }
        }

        func matchedKeywords(content: String) -> [String] {
            let lowercasedContent = content.lowercased()
            return keywords.filter { keyword in
                lowercasedContent.contains(keyword.lowercased())
            }
        }
    }

    // MARK: - 规则存储（单例）
    
    /// 共享的规则存储实例
    private static let ruleStorage = BusinessTagRuleStorage()
    
    /// 获取当前启用的规则（优先从存储加载，否则使用默认规则）
    static var activeRules: [BusinessTagRule] {
        ruleStorage.enabledBusinessTagRules()
    }
    
    /// 获取规则存储实例（用于 UI 绑定）
    static func getStorage() -> BusinessTagRuleStorage {
        ruleStorage
    }

    /// 默认规则（作为备用）
    static let defaultRules: [BusinessTagRule] = [
        BusinessTagRule(
            name: "视频项目",
            keywords: ["视频", "video", "直播", "streaming", "recording", "mp4", "ffmpeg", "rtmp"],
            tags: ["视频", "多媒体"]
        ),
        BusinessTagRule(
            name: "输入法/拼音工具",
            keywords: ["拼音", "pinyin", "input", "输入", "中文", "typing", "ime", "keyboard"],
            tags: ["输入法", "拼音"]
        ),
        BusinessTagRule(
            name: "手机应用",
            keywords: ["mobile", "android", "ios", "app", "移动", "手机", "react-native", "flutter"],
            tags: ["移动端"]
        ),
        BusinessTagRule(
            name: "桌面应用",
            keywords: ["desktop", "macos", "windows", "electron", "tauri", "桌面", "gui"],
            tags: ["桌面端"]
        ),
        BusinessTagRule(
            name: "Web 应用",
            keywords: ["web", "website", "网站", "网页", "浏览器", "browser", "spa"],
            tags: ["Web"]
        ),
        BusinessTagRule(
            name: "CLI 工具",
            keywords: ["cli", "命令行", "terminal", "console", "shell", "script", "自动化"],
            tags: ["CLI", "命令行"]
        ),
        BusinessTagRule(
            name: "教育学习",
            keywords: ["教育", "学习", "tutorial", "course", "教程", "教学", "quiz", "题库"],
            tags: ["教育", "学习"]
        ),
        BusinessTagRule(
            name: "社交/聊天",
            keywords: ["chat", "聊天", "social", "message", "im", "社交", "通讯", "群组"],
            tags: ["社交", "聊天"]
        ),
        BusinessTagRule(
            name: "电商平台",
            keywords: ["电商", "e-commerce", "shopping", "cart", "购物车", "支付", "商城", "订单"],
            tags: ["电商", "购物"]
        ),
        BusinessTagRule(
            name: "文档工具",
            keywords: ["文档", "document", "note", "笔记", "wiki", "知识库", "notion", "obsidian"],
            tags: ["文档", "笔记"]
        ),
        BusinessTagRule(
            name: "游戏",
            keywords: ["game", "游戏", "gaming", "play", "player", "unity", "unreal", "steam"],
            tags: ["游戏"]
        ),
        BusinessTagRule(
            name: "数据分析",
            keywords: ["data", "数据", "analytics", "分析", "chart", "图表", "可视化", "dashboard"],
            tags: ["数据分析"]
        ),
        BusinessTagRule(
            name: "AI/机器学习",
            keywords: ["ai", "machine learning", "深度学习", "llm", "模型", "智能", "neural", "tensorflow", "pytorch"],
            tags: ["AI", "机器学习"]
        ),
        BusinessTagRule(
            name: "博客/内容平台",
            keywords: ["博客", "blog", "cms", "内容", "article", "文章", "发布"],
            tags: ["博客", "内容平台"]
        ),
        BusinessTagRule(
            name: "开发工具",
            keywords: ["开发工具", "devtool", "插件", "plugin", "extension", "ide", "编辑器"],
            tags: ["开发工具"]
        ),
        BusinessTagRule(
            name: "监控系统",
            keywords: ["monitor", "监控", "logging", "日志", "alert", "告警", "trace"],
            tags: ["监控", "运维"]
        ),
    ]

    // MARK: - 文档扫描

    /// 扫描项目文档，提取内容
    private static func scanProjectDocuments(at path: String) -> String {
        let fileManager = FileManager.default
        var documentContents: [String] = []

        let readmeFiles = ["README.md", "README.txt", "README.rst"]

        for readmeFile in readmeFiles {
            let readmePath = "\(path)/\(readmeFile)"
            if let content = try? String(contentsOfFile: readmePath, encoding: .utf8) {
                documentContents.append(content)
                print("📄 读取 README: \(readmeFile)")
                break
            }
        }

        if documentContents.isEmpty {
            do {
                let contents = try fileManager.contentsOfDirectory(atPath: path)
                for file in contents where file.hasSuffix(".md") && file != "README.md" {
                    let filePath = "\(path)/\(file)"
                    if let content = try? String(contentsOfFile: filePath, encoding: .utf8) {
                        documentContents.append(content)
                        print("📄 读取文档: \(file)")
                    }
                }
            } catch {
                print("⚠️ 扫描文档失败: \(error)")
            }
        }

        let combinedContent = documentContents.joined(separator: "\n\n---\n\n")
        return combinedContent
    }

    // MARK: - 公共 API

    /// 为指定项目路径生成业务标签
    static func generateBusinessTags(
        for projectPath: String,
        projectName: String? = nil,
        existingTags: Set<String> = [],
        rules: [BusinessTagRule] = activeRules
    ) -> Set<String> {
        let documentContent = scanProjectDocuments(at: projectPath)
        
        // 将项目名称也加入到待分析内容中，提升匹配能力
        let analysisContent = (projectName ?? "") + "\n\n" + documentContent

        guard !analysisContent.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            print("⚠️ 未找到文档且无项目名称，跳过业务标签生成")
            return []
        }

        var businessTags: Set<String> = []

        for rule in rules {
            if rule.matches(content: analysisContent) {
                let matchedKeywords = rule.matchedKeywords(content: analysisContent)
                print("   ✅ 匹配规则 [\(rule.name)]: 关键词 \(matchedKeywords)")

                for tag in rule.tags {
                    if !existingTags.contains(tag) {
                        businessTags.insert(tag)
                    }
                }
            }
        }

        return businessTags
    }

    /// 为指定的 Project 对象应用业务标签
    /// 应用业务标签
    /// - Parameter rules: 参与匹配的规则集。默认用当前启用规则（读用户配置）；
    ///   测试或批量重扫可显式传入，避免依赖用户磁盘上的配置。
    static func applyBusinessTags(
        to project: Project,
        overwrite: Bool = false,
        rules: [BusinessTagRule] = activeRules
    ) -> Project {
        let newTags = generateBusinessTags(
            for: project.path,
            projectName: project.name,
            existingTags: project.tags,
            rules: rules
        )

        if overwrite {
            return Project(
                id: project.id,
                name: project.name,
                path: project.path,
                tags: newTags,
                mtime: project.mtime,
                activityAt: project.activityAt,
                size: project.size,
                checksum: project.checksum,
                git_commits: project.git_commits,
                git_last_commit: project.git_last_commit,
                git_daily: project.git_daily,
                startupCommand: project.startupCommand,
                customPort: project.customPort,
                created: project.created,
                checked: project.checked
            )
        } else {
            let mergedTags = project.tags.union(newTags)
            return Project(
                id: project.id,
                name: project.name,
                path: project.path,
                tags: mergedTags,
                mtime: project.mtime,
                activityAt: project.activityAt,
                size: project.size,
                checksum: project.checksum,
                git_commits: project.git_commits,
                git_last_commit: project.git_last_commit,
                git_daily: project.git_daily,
                startupCommand: project.startupCommand,
                customPort: project.customPort,
                created: project.created,
                checked: project.checked
            )
        }
    }

    /// 调试信息：返回指定路径匹配的规则名称
    static func debugRules(
        for projectPath: String,
        projectName: String? = nil,
        rules: [BusinessTagRule] = activeRules
    ) -> [String] {
        let documentContent = scanProjectDocuments(at: projectPath)
        let analysisContent = (projectName ?? "") + "\n\n" + documentContent
        return rules.filter { $0.matches(content: analysisContent) }.map { $0.name }
    }
}
