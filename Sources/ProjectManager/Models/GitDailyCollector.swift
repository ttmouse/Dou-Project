import Foundation

/// Git每日数据收集器
/// 
/// 实现TRD v1.0中的多天Git活跃度统计功能
/// 使用紧凑字符串格式存储每日提交统计
struct GitDailyCollector {

    /// yyyy-MM-dd 格式化器（静态复用）
    /// 背景：DateFormatter 创建成本高，旧实现每次查询某天提交数都新建一个，
    /// 热力图一天 × 全量项目的循环下会造成 6 位数开销。
    static let dateKeyFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()

    private static let cacheLock = NSLock()
    private static var gitHeadCache: [String: String] = loadGitHeadCache()

    /// 测试/隔离用：把 HEAD 缓存指向别处
    /// 背景：此文件此前写死在 `~/Library/Application Support/com.projectmanager`，
    /// 不经过 `TagStorage`，所以任何跑 git 采集的测试都会写到真实用户目录。
    /// 注意：缓存内容在类型首次访问时加载，测试需在首次使用前设置。
    static var gitHeadCacheURLOverride: URL?

    private static var gitHeadCacheURL: URL {
        if let override = gitHeadCacheURLOverride {
            return override
        }
        let appSupport = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        )[0].appendingPathComponent("com.projectmanager", isDirectory: true)
        return appSupport.appendingPathComponent("git_heads.json")
    }

    /// 批量收集项目的Git历史数据
    /// 仅用于显式的全量采集入口；普通刷新应使用 updateProjectsWithGitDaily。

    /// - Parameters:
    ///   - projects: 项目列表
    ///   - days: 保留参数以保持接口兼容性（实际获取完整历史记录）
    /// - Returns: 项目ID到git_daily字符串的映射
    static func collectGitDaily(for projects: [Project], days: Int = 365) -> [UUID: String] {
        var results: [UUID: String] = [:]
        
        for project in projects {
            if let gitDaily = collectSingleProjectGitDaily(project: project, days: days) {
                results[project.id] = gitDaily
            }
        }
        
        return results
    }
    
    /// 收集单个项目的Git历史数据
    /// - Parameters:
    ///   - project: 项目
    ///   - days: 保留参数以保持接口兼容性（实际获取完整历史记录）
    /// - Returns: git_daily字符串，如果失败返回nil
    static func collectSingleProjectGitDaily(project: Project, days: Int = 365) -> String? {
        // 检查是否是Git仓库
        let gitPath = "\(project.path)/.git"
        guard FileManager.default.fileExists(atPath: gitPath) else {
            return nil
        }

        // 获取完整Git历史记录，不限制时间范围。
        // 直接调用 git + currentDirectoryURL，不走 bash 拼接：
        // 路径含单引号时 `cd '...'` 会被注入任意 shell（2026-09-29 修复）。
        guard let logOutput = runGit(arguments: ["log", "--pretty=format:%cd", "--date=short"],
                                     cwd: project.path) else {
            return nil
        }
        return aggregateCommitsPerDay(logOutput)
    }

    /// 直接运行 git 子命令，cwd 与参数分离，避免 shell 解释
    private static func runGit(arguments: [String], cwd: String) -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.currentDirectoryURL = URL(fileURLWithPath: cwd)
        process.arguments = arguments

        let output = Pipe()
        let errorPipe = Pipe()
        process.standardOutput = output
        process.standardError = errorPipe

        do {
            try process.run()
            process.waitUntilExit()

            if let errorOutput = String(data: errorPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8),
               !errorOutput.isEmpty {
                print("⚠️ GitDailyCollector: git stderr - \(errorOutput)")
            }

            let data = output.fileHandleForReading.readDataToEndOfFile()
            let out = String(data: data, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines)
            return out?.isEmpty == false ? out : nil
        } catch {
            print("❌ GitDailyCollector: 运行 git 失败 - \(error)")
            return nil
        }
    }

    /// 把 `git log --date=short` 的逐行日期聚合成 "date:count" 逗号串（Swift 端等价于原 sort|uniq -c|awk|tr|sed 管道）
    static func aggregateCommitsPerDay(_ logOutput: String?) -> String? {
        guard let logOutput, !logOutput.isEmpty else { return nil }

        var counts: [String: Int] = [:]
        for line in logOutput.split(separator: "\n") {
            let date = line.trimmingCharacters(in: .whitespaces)
            guard !date.isEmpty else { continue }
            counts[date, default: 0] += 1
        }
        guard !counts.isEmpty else { return nil }
        return formatGitDaily(counts)
    }
    
    /// 解析git_daily字符串为日期-提交数映射
    /// - Parameter gitDaily: git_daily字符串格式: "2025-08-25:3,2025-08-24:5"
    /// - Returns: 日期到提交数的映射
    static func parseGitDaily(_ gitDaily: String?) -> [String: Int] {
        guard let gitDaily = gitDaily, !gitDaily.isEmpty else {
            return [:]
        }
        
        var result: [String: Int] = [:]
        let entries = gitDaily.components(separatedBy: ",")
        
        for entry in entries {
            let parts = entry.components(separatedBy: ":")
            if parts.count == 2,
               !parts[0].isEmpty,   // 拒绝 ":3" 这类无日期片段，避免产生永远查不到的空键
               let commitCount = Int(parts[1]) {
                result[parts[0]] = commitCount
            }
        }
        
        return result
    }
    
    /// 将日期-提交数映射转换为git_daily字符串
    /// - Parameter dailyCommits: 日期到提交数的映射
    /// - Returns: git_daily字符串
    static func formatGitDaily(_ dailyCommits: [String: Int]) -> String {
        let sortedEntries = dailyCommits
            .sorted { $0.key < $1.key } // 按日期排序
            .map { "\($0.key):\($0.value)" }
        
        return sortedEntries.joined(separator: ",")
    }
    
    /// 获取指定日期的提交数
    /// - Parameters:
    ///   - gitDaily: git_daily字符串
    ///   - date: 目标日期
    /// - Returns: 该日期的提交数，没有数据返回0
    static func getCommitCount(from gitDaily: String?, for date: Date) -> Int {
        guard let gitDaily = gitDaily, !gitDaily.isEmpty else {
            return 0
        }

        let dateString = dateKeyFormatter.string(from: date)
        let dailyData = parseGitDaily(gitDaily)
        let commitCount = dailyData[dateString] ?? 0
        
        // 🔧 调试：详细日志输出
        if !dailyData.isEmpty {
            let availableDates = dailyData.keys.sorted().prefix(5).joined(separator: ", ")
            // print("🔍 GitDailyCollector.getCommitCount: 查找日期=\(dateString), 可用日期=\(availableDates)..., 找到提交数=\(commitCount)")
        }
        
        return commitCount
    }
    
    /// 获取最近N天的提交统计
    /// - Parameters:
    ///   - gitDaily: git_daily字符串
    ///   - days: 天数
    /// - Returns: 每日活跃度数组（按时间倒序）
    static func getRecentActivity(from gitDaily: String?, days: Int = 30) -> [(date: Date, commits: Int)] {
        let calendar = Calendar.current
        let today = Date()
        var activities: [(date: Date, commits: Int)] = []
        
        for dayOffset in 0..<days {
            guard let date = calendar.date(byAdding: .day, value: -dayOffset, to: today) else {
                continue
            }
            
            let commits = getCommitCount(from: gitDaily, for: date)
            activities.append((date: date, commits: commits))
        }
        
        return activities
    }
    
    /// 批量更新项目的git_daily数据
    /// - Parameters:
    ///   - projects: 原项目列表
    ///   - days: 保留参数以保持接口兼容性（实际获取完整历史记录）
    /// - Returns: 更新了git_daily的项目列表
    static func updateProjectsWithGitDaily(_ projects: [Project], days: Int = 365) -> [Project] {
        guard !projects.isEmpty else { return projects }

        var projectsNeedingRefresh: [Project] = []
        var refreshedHeads: [String: String] = [:]

        cacheLock.lock()
        let cachedHeads = gitHeadCache
        cacheLock.unlock()

        for project in projects {
            let gitPath = URL(fileURLWithPath: project.path)
                .appendingPathComponent(".git").path

            guard FileManager.default.fileExists(atPath: gitPath) else {
                continue
            }

            let currentHead = currentGitHead(for: project.path)
            if let currentHead {
                refreshedHeads[project.path] = currentHead
            }

            // 首次遇到项目、没有历史数据，或 HEAD 变化时才重算 git_daily。
            if project.git_daily == nil || cachedHeads[project.path] != currentHead {
                projectsNeedingRefresh.append(project)
            }
        }

        let gitDailyData = collectGitDaily(for: projectsNeedingRefresh, days: days)

        cacheLock.lock()
        for project in projectsNeedingRefresh {
            guard let head = refreshedHeads[project.path],
                  gitDailyData[project.id] != nil else { continue }
            gitHeadCache[project.path] = head
        }
        if !projectsNeedingRefresh.isEmpty {
            saveGitHeadCache(gitHeadCache)
        }
        cacheLock.unlock()

        print("📊 Git 增量采集: 检查 \(projects.count) 个项目，刷新 \(projectsNeedingRefresh.count) 个")

        return projects.map { project in
            if let gitDaily = gitDailyData[project.id] {
                return Project(
                    id: project.id,
                    name: project.name,
                    path: project.path,
                    tags: project.tags,
                    mtime: project.mtime,
                    activityAt: project.activityAt,
                    size: project.size,
                    checksum: project.checksum,
                    git_commits: project.git_commits,
                    git_last_commit: project.git_last_commit,
                    git_daily: gitDaily,
                    created: project.created,
                    checked: project.checked
                )
            } else {
                return project
            }
        }
    }
    
    // MARK: - Private Helper Methods

    private static func loadGitHeadCache() -> [String: String] {
        do {
            let data = try Data(contentsOf: gitHeadCacheURL)
            return try JSONDecoder().decode([String: String].self, from: data)
        } catch {
            return [:]
        }
    }

    private static func saveGitHeadCache(_ cache: [String: String]) {
        do {
            let folder = gitHeadCacheURL.deletingLastPathComponent()
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            let data = try JSONEncoder().encode(cache)
            try data.write(to: gitHeadCacheURL, options: .atomic)
        } catch {
            print("⚠️ Git HEAD 缓存保存失败: \(error)")
        }
    }

    private static func currentGitHead(for path: String) -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.currentDirectoryURL = URL(fileURLWithPath: path)
        process.arguments = ["rev-parse", "HEAD"]

        let output = Pipe()
        process.standardOutput = output
        process.standardError = Pipe()

        do {
            try process.run()
            process.waitUntilExit()
            guard process.terminationStatus == 0 else { return nil }
            return String(data: output.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines)
        } catch {
            return nil
        }
    }
}

// MARK: - 扩展：便利访问方法

extension Project {
    
    /// 获取指定日期的提交数
    func getCommitCount(for date: Date) -> Int {
        return GitDailyCollector.getCommitCount(from: git_daily, for: date)
    }
    
    /// 获取最近N天的提交活动
    func getRecentActivity(days: Int = 30) -> [(date: Date, commits: Int)] {
        return GitDailyCollector.getRecentActivity(from: git_daily, days: days)
    }
    
    /// 更新git_daily数据
    func withUpdatedGitDaily(days: Int = 365) -> Project {
        if let gitDaily = GitDailyCollector.collectSingleProjectGitDaily(project: self, days: days) {
            return Project(
                id: id,
                name: name,
                path: path,
                tags: tags,
                mtime: mtime,
                size: size,
                checksum: checksum,
                git_commits: git_commits,
                git_last_commit: git_last_commit,
                git_daily: gitDaily,
                created: created,
                checked: checked
            )
        }
        return self
    }
}

extension ProjectData {
    
    /// 获取指定日期的提交数
    func getCommitCount(for date: Date) -> Int {
        return GitDailyCollector.getCommitCount(from: git_daily, for: date)
    }
    
    /// 获取最近N天的提交活动
    func getRecentActivity(days: Int = 30) -> [(date: Date, commits: Int)] {
        return GitDailyCollector.getRecentActivity(from: git_daily, days: days)
    }
}
