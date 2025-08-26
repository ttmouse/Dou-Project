import Foundation

/// Git每日数据收集器
/// 
/// 实现TRD v1.0中的多天Git活跃度统计功能
/// 使用紧凑字符串格式存储每日提交统计
struct GitDailyCollector {
    
    /// 批量收集项目的Git历史数据
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
        
        // 获取完整Git历史记录，不限制时间范围
        let command = """
        cd '\(project.path)' && \
        git log --pretty=format:'%cd' --date=short | \
        sort | uniq -c | \
        awk '{print $2":"$1}' | \
        tr '\\n' ',' | \
        sed 's/,$//'
        """
        
        return executeShellCommand(command)
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
        
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"
        let dateString = dateFormatter.string(from: date)
        
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
        let gitDailyData = collectGitDaily(for: projects, days: days)
        
        return projects.map { project in
            if let gitDaily = gitDailyData[project.id] {
                return Project(
                    id: project.id,
                    name: project.name,
                    path: project.path,
                    tags: project.tags,
                    mtime: project.mtime,
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
    
    /// 执行shell命令并返回输出
    private static func executeShellCommand(_ command: String) -> String? {
        print("🐚 GitDailyCollector: 执行命令 - \(command)")
        
        let process = Process()
        process.launchPath = "/bin/bash"
        process.arguments = ["-c", command]
        
        let pipe = Pipe()
        let errorPipe = Pipe()
        process.standardOutput = pipe
        process.standardError = errorPipe
        
        do {
            try process.run()
            process.waitUntilExit()
            
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()
            
            if let errorOutput = String(data: errorData, encoding: .utf8), !errorOutput.isEmpty {
                print("⚠️ GitDailyCollector: 命令stderr - \(errorOutput)")
            }
            
            let output = String(data: data, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines)
            
            print("📊 GitDailyCollector: 命令输出 - \(output ?? "nil")")
            return output?.isEmpty == false ? output : nil
        } catch {
            print("❌ GitDailyCollector: 执行命令失败 - \(error)")
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