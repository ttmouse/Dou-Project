import Foundation

enum ProjectDiscoveryPolicy {
    /// 点号目录属于工具配置或运行环境，不是用户项目。
    static func isEligibleChildDirectory(named name: String) -> Bool {
        !name.hasPrefix(".")
    }

    static func isEligibleProjectPath(_ path: String) -> Bool {
        isEligibleChildDirectory(named: URL(fileURLWithPath: path).lastPathComponent)
    }

    static func isWatchedRoot(_ projectPath: String, watchedDirectories: Set<String>) -> Bool {
        let normalizedProjectPath = URL(fileURLWithPath: projectPath).standardizedFileURL.path
        return watchedDirectories.contains {
            URL(fileURLWithPath: $0).standardizedFileURL.path == normalizedProjectPath
        }
    }
}
