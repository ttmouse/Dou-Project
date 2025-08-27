import Foundation

// MARK: - Shell Command Execution Utility
// Git命令执行工具 - 兼容现有trees.sh脚本的实现

/// Shell命令执行器 - 专门处理Git worktree操作
class ShellExecutor {
    
    // MARK: - Core Git Command Execution
    
    /// 执行Git命令
    /// - Parameters:
    ///   - args: Git命令参数数组
    ///   - workingDir: 工作目录路径
    /// - Returns: 执行结果(输出内容, 是否成功)
    static func executeGitCommand(args: [String], workingDir: String) -> (output: String, success: Bool) {
        let process = Process()
        let pipe = Pipe()
        let errorPipe = Pipe()
        
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.arguments = args
        process.currentDirectoryURL = URL(fileURLWithPath: workingDir)
        process.standardOutput = pipe
        process.standardError = errorPipe
        
        do {
            try process.run()
            process.waitUntilExit()
            
            let outputData = pipe.fileHandleForReading.readDataToEndOfFile()
            let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()
            
            let output = String(data: outputData, encoding: .utf8) ?? ""
            let errorOutput = String(data: errorData, encoding: .utf8) ?? ""
            
            let success = process.terminationStatus == 0
            let combinedOutput = success ? output : "\(output)\n\(errorOutput)".trimmingCharacters(in: .whitespacesAndNewlines)
            
            return (output: combinedOutput, success: success)
        } catch {
            return (output: "执行命令失败: \(error.localizedDescription)", success: false)
        }
    }
    
    /// 执行shell命令（非Git命令）
    /// - Parameters:
    ///   - command: 完整的shell命令
    ///   - workingDir: 工作目录路径
    /// - Returns: 执行结果(输出内容, 是否成功)
    static func executeShellCommand(_ command: String, workingDir: String) -> (output: String, success: Bool) {
        let process = Process()
        let pipe = Pipe()
        let errorPipe = Pipe()
        
        process.executableURL = URL(fileURLWithPath: "/bin/bash")
        process.arguments = ["-c", command]
        process.currentDirectoryURL = URL(fileURLWithPath: workingDir)
        process.standardOutput = pipe
        process.standardError = errorPipe
        
        do {
            try process.run()
            process.waitUntilExit()
            
            let outputData = pipe.fileHandleForReading.readDataToEndOfFile()
            let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()
            
            let output = String(data: outputData, encoding: .utf8) ?? ""
            let errorOutput = String(data: errorData, encoding: .utf8) ?? ""
            
            let success = process.terminationStatus == 0
            let combinedOutput = success ? output : "\(output)\n\(errorOutput)".trimmingCharacters(in: .whitespacesAndNewlines)
            
            return (output: combinedOutput, success: success)
        } catch {
            return (output: "执行命令失败: \(error.localizedDescription)", success: false)
        }
    }
    
    // MARK: - Git Worktree Operations
    
    /// 创建Git worktree分支 - 兼容trees.sh脚本
    /// - Parameters:
    ///   - branchName: 分支名称
    ///   - targetPath: 目标路径
    ///   - basePath: 基础项目路径  
    ///   - description: 分支描述
    /// - Returns: 创建是否成功
    static func createWorktree(
        branchName: String, 
        targetPath: String, 
        basePath: String,
        description: String = ""
    ) -> BranchOperationResult {
        
        // 1. 检查目标路径是否已存在
        if FileManager.default.fileExists(atPath: targetPath) {
            return BranchOperationResult.failure(
                operation: .create,
                message: "目标路径已存在: \(targetPath)",
                branchName: branchName
            )
        }
        
        // 2. 确保.trees目录存在
        let treesDir = "\(basePath)/.trees"
        do {
            try FileManager.default.createDirectory(atPath: treesDir, withIntermediateDirectories: true)
        } catch {
            return BranchOperationResult.failure(
                operation: .create,
                message: "无法创建.trees目录: \(error.localizedDescription)",
                branchName: branchName
            )
        }
        
        // 3. 创建Git worktree
        let worktreeResult = executeGitCommand(
            args: ["worktree", "add", "-b", branchName, targetPath, "HEAD"],
            workingDir: basePath
        )
        
        if !worktreeResult.success {
            return BranchOperationResult.failure(
                operation: .create,
                message: "创建worktree失败: \(worktreeResult.output)",
                branchName: branchName,
                output: worktreeResult.output
            )
        }
        
        // 4. 创建分支信息文件 (.branch_info) - 兼容trees.sh格式
        let branchInfoPath = "\(targetPath)/.branch_info"
        let branchInfo = """
        BRANCH_NAME=\(branchName)
        DESCRIPTION=\(description)
        CREATED_AT=\(ISO8601DateFormatter().string(from: Date()))
        BASE_PATH=\(basePath)
        """
        
        do {
            try branchInfo.write(toFile: branchInfoPath, atomically: true, encoding: .utf8)
        } catch {
            // 如果写入分支信息失败，仍然认为创建成功，但记录警告
            print("警告: 无法创建分支信息文件: \(error.localizedDescription)")
        }
        
        // 5. 创建返回主目录的便捷脚本 (back-to-main.sh) - 兼容trees.sh
        let backScriptPath = "\(targetPath)/back-to-main.sh"
        let backScript = """
        #!/bin/bash
        # 自动生成的返回主项目脚本
        cd "\(basePath)"
        if command -v cursor > /dev/null 2>&1; then
            cursor .
        elif command -v code > /dev/null 2>&1; then
            code .
        else
            open .
        fi
        """
        
        do {
            try backScript.write(toFile: backScriptPath, atomically: true, encoding: .utf8)
            // 设置脚本执行权限
            let attributes = [FileAttributeKey.posixPermissions: 0o755]
            try FileManager.default.setAttributes(attributes, ofItemAtPath: backScriptPath)
        } catch {
            print("警告: 无法创建返回脚本: \(error.localizedDescription)")
        }
        
        return BranchOperationResult.success(
            operation: .create,
            message: "成功创建分支 \(branchName)",
            branchName: branchName,
            output: worktreeResult.output
        )
    }
    
    /// 删除Git worktree分支
    /// - Parameters:
    ///   - path: 分支路径
    ///   - branchName: 分支名称
    ///   - basePath: 基础项目路径
    ///   - force: 是否强制删除
    /// - Returns: 删除是否成功
    static func removeWorktree(
        path: String, 
        branchName: String, 
        basePath: String, 
        force: Bool = false
    ) -> BranchOperationResult {
        
        // 1. 检查是否有未提交的更改（非强制删除时）
        if !force {
            let statusResult = getGitStatus(path: path)
            if !statusResult.clean && statusResult.changes > 0 {
                return BranchOperationResult.failure(
                    operation: .delete,
                    message: "分支有 \(statusResult.changes) 个未提交的更改，请先提交或使用强制删除",
                    branchName: branchName
                )
            }
        }
        
        // 2. 移除Git worktree
        let removeArgs = force ? 
            ["worktree", "remove", path, "--force"] : 
            ["worktree", "remove", path]
        
        let removeResult = executeGitCommand(
            args: removeArgs,
            workingDir: basePath
        )
        
        if !removeResult.success {
            return BranchOperationResult.failure(
                operation: .delete,
                message: "删除worktree失败: \(removeResult.output)",
                branchName: branchName,
                output: removeResult.output
            )
        }
        
        // 3. 删除本地分支
        let deleteBranchResult = executeGitCommand(
            args: ["branch", force ? "-D" : "-d", branchName],
            workingDir: basePath
        )
        
        // 分支删除失败不算致命错误，因为worktree已经删除
        if !deleteBranchResult.success {
            print("警告: 删除本地分支失败: \(deleteBranchResult.output)")
        }
        
        return BranchOperationResult.success(
            operation: .delete,
            message: "成功删除分支 \(branchName)",
            branchName: branchName,
            output: removeResult.output
        )
    }
    
    /// 获取Git状态
    /// - Parameter path: 检查路径
    /// - Returns: 状态信息(是否干净, 更改数量)
    static func getGitStatus(path: String) -> (clean: Bool, changes: Int) {
        let statusResult = executeGitCommand(
            args: ["status", "--porcelain"],
            workingDir: path
        )
        
        if !statusResult.success {
            return (clean: false, changes: 0)
        }
        
        let changes = statusResult.output.components(separatedBy: .newlines)
            .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            .count
        
        return (clean: changes == 0, changes: changes)
    }
    
    /// 获取worktree列表
    /// - Parameter basePath: 基础项目路径
    /// - Returns: worktree信息列表
    static func getWorktreeList(basePath: String) -> [WorktreeInfo] {
        let listResult = executeGitCommand(
            args: ["worktree", "list", "--porcelain"],
            workingDir: basePath
        )
        
        if !listResult.success {
            return []
        }
        
        return parseWorktreeList(listResult.output, basePath: basePath)
    }
    
    /// 解析worktree列表输出
    private static func parseWorktreeList(_ output: String, basePath: String) -> [WorktreeInfo] {
        var worktrees: [WorktreeInfo] = []
        var currentWorktree: [String: String] = [:]
        
        let lines = output.components(separatedBy: .newlines)
        
        for line in lines {
            let trimmedLine = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmedLine.isEmpty {
                // 空行表示一个worktree记录结束
                if let path = currentWorktree["worktree"],
                   let branch = currentWorktree["branch"],
                   let commit = currentWorktree["HEAD"] {
                    
                    let isMain = path == basePath
                    // Linus: 不要为每个分支都检查状态！这是性能杀手！
                    // let status = getGitStatus(path: path).clean ? BranchStatus.clean : BranchStatus.hasChanges
                    let status = BranchStatus.unknown // 够用了！需要时再检查
                    let lastModified = getLastModifiedDate(path: path)
                    
                    let worktree = WorktreeInfo(
                        path: path,
                        branch: branch,
                        commit: commit,
                        isMain: isMain,
                        status: status,
                        lastModified: lastModified
                    )
                    worktrees.append(worktree)
                }
                currentWorktree.removeAll()
            } else {
                // 解析键值对
                let components = trimmedLine.components(separatedBy: " ")
                if components.count >= 2 {
                    let key = components[0]
                    let value = components.dropFirst().joined(separator: " ")
                    currentWorktree[key] = value
                }
            }
        }
        
        // 处理最后一个worktree（如果没有空行结尾）
        if let path = currentWorktree["worktree"],
           let branch = currentWorktree["branch"],
           let commit = currentWorktree["HEAD"] {
            
            let isMain = path == basePath
            // Linus: 同样的垃圾代码，删掉！
            // let status = getGitStatus(path: path).clean ? BranchStatus.clean : BranchStatus.hasChanges
            let status = BranchStatus.unknown // 简单粗暴！
            let lastModified = getLastModifiedDate(path: path)
            
            let worktree = WorktreeInfo(
                path: path,
                branch: branch,
                commit: commit,
                isMain: isMain,
                status: status,
                lastModified: lastModified
            )
            worktrees.append(worktree)
        }
        
        return worktrees
    }
    
    /// 获取路径最后修改时间
    private static func getLastModifiedDate(path: String) -> Date {
        do {
            let attributes = try FileManager.default.attributesOfItem(atPath: path)
            return attributes[.modificationDate] as? Date ?? Date()
        } catch {
            return Date()
        }
    }
    
    // MARK: - Branch Information Utilities
    
    /// 读取分支信息文件 (.branch_info)
    /// - Parameter branchPath: 分支路径
    /// - Returns: 分支描述信息
    static func readBranchInfo(branchPath: String) -> String {
        let branchInfoPath = "\(branchPath)/.branch_info"
        
        guard let content = try? String(contentsOfFile: branchInfoPath, encoding: .utf8) else {
            return ""
        }
        
        // 解析DESCRIPTION行
        let lines = content.components(separatedBy: .newlines)
        for line in lines {
            if line.hasPrefix("DESCRIPTION=") {
                return String(line.dropFirst("DESCRIPTION=".count))
            }
        }
        
        return ""
    }
    
    /// 检查路径的磁盘使用情况
    /// - Parameter path: 检查路径
    /// - Returns: 磁盘使用量（字节）
    static func getDiskUsage(path: String) -> UInt64 {
        guard let enumerator = FileManager.default.enumerator(atPath: path) else {
            return 0
        }
        
        var totalSize: UInt64 = 0
        
        while let fileName = enumerator.nextObject() as? String {
            let filePath = "\(path)/\(fileName)"
            do {
                let attributes = try FileManager.default.attributesOfItem(atPath: filePath)
                if let fileSize = attributes[.size] as? UInt64 {
                    totalSize += fileSize
                }
            } catch {
                continue
            }
        }
        
        return totalSize
    }
    
    /// 验证Git仓库
    /// - Parameter path: 检查路径
    /// - Returns: 是否为有效的Git仓库
    static func isValidGitRepository(path: String) -> Bool {
        let result = executeGitCommand(
            args: ["rev-parse", "--is-inside-work-tree"],
            workingDir: path
        )
        
        return result.success && result.output.trimmingCharacters(in: .whitespacesAndNewlines) == "true"
    }
    
    /// 获取当前分支名称
    /// - Parameter path: 检查路径
    /// - Returns: 当前分支名称
    static func getCurrentBranch(path: String) -> String? {
        let result = executeGitCommand(
            args: ["branch", "--show-current"],
            workingDir: path
        )
        
        guard result.success else { return nil }
        
        let branch = result.output.trimmingCharacters(in: .whitespacesAndNewlines)
        return branch.isEmpty ? nil : branch
    }
    
    // MARK: - Advanced Branch Operations
    
    /// 合并分支到目标分支
    /// - Parameters:
    ///   - sourceBranch: 源分支名称
    ///   - targetBranch: 目标分支名称（通常是main）
    ///   - projectPath: 项目路径
    ///   - strategy: 合并策略
    /// - Returns: 合并操作结果
    static func mergeBranch(
        sourceBranch: String,
        targetBranch: String = "main", 
        projectPath: String,
        strategy: MergeStrategy = .recursive
    ) -> BranchOperationResult {
        
        // 1. 检查是否为Git仓库
        guard isValidGitRepository(path: projectPath) else {
            return BranchOperationResult.failure(
                operation: .merge,
                message: "不是有效的Git仓库",
                branchName: sourceBranch
            )
        }
        
        // 2. 检查源分支和目标分支是否存在
        let branchListResult = executeGitCommand(
            args: ["branch", "--list"],
            workingDir: projectPath
        )
        
        guard branchListResult.success else {
            return BranchOperationResult.failure(
                operation: .merge,
                message: "无法获取分支列表",
                branchName: sourceBranch,
                output: branchListResult.output
            )
        }
        
        let branches = branchListResult.output.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: "*", with: "").trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        
        guard branches.contains(sourceBranch) else {
            return BranchOperationResult.failure(
                operation: .merge,
                message: "源分支 '\(sourceBranch)' 不存在",
                branchName: sourceBranch
            )
        }
        
        guard branches.contains(targetBranch) else {
            return BranchOperationResult.failure(
                operation: .merge,
                message: "目标分支 '\(targetBranch)' 不存在",
                branchName: sourceBranch
            )
        }
        
        // 3. 检查工作区是否干净
        let statusCheck = getGitStatus(path: projectPath)
        if !statusCheck.clean {
            return BranchOperationResult.failure(
                operation: .merge,
                message: "工作区不干净，有 \(statusCheck.changes) 个未提交的更改，请先提交或暂存",
                branchName: sourceBranch
            )
        }
        
        // 4. 切换到目标分支
        let checkoutResult = executeGitCommand(
            args: ["checkout", targetBranch],
            workingDir: projectPath
        )
        
        if !checkoutResult.success {
            return BranchOperationResult.failure(
                operation: .merge,
                message: "无法切换到目标分支 '\(targetBranch)': \(checkoutResult.output)",
                branchName: sourceBranch,
                output: checkoutResult.output
            )
        }
        
        // 5. 拉取最新更改（如果有远程仓库）
        let pullResult = executeGitCommand(
            args: ["pull", "origin", targetBranch],
            workingDir: projectPath
        )
        
        // 拉取失败不算致命错误，可能没有远程仓库
        if !pullResult.success {
            print("警告: 无法拉取远程更改: \(pullResult.output)")
        }
        
        // 6. 执行合并
        var mergeArgs = ["merge"]
        
        // 添加合并策略
        switch strategy {
        case .recursive:
            mergeArgs.append("--strategy=recursive")
        case .ours:
            mergeArgs.append("--strategy=ours")
        case .theirs:
            mergeArgs.append("--strategy-option=theirs")
        case .noFastForward:
            mergeArgs.append("--no-ff")
        }
        
        // 添加提交信息
        mergeArgs.append("-m")
        mergeArgs.append("Merge branch '\(sourceBranch)' into \(targetBranch)")
        mergeArgs.append(sourceBranch)
        
        let mergeResult = executeGitCommand(
            args: mergeArgs,
            workingDir: projectPath
        )
        
        if !mergeResult.success {
            // 检查是否是合并冲突
            if mergeResult.output.contains("CONFLICT") {
                return BranchOperationResult.failure(
                    operation: .merge,
                    message: "合并冲突，请手动解决冲突后再试",
                    branchName: sourceBranch,
                    output: mergeResult.output
                )
            } else {
                return BranchOperationResult.failure(
                    operation: .merge,
                    message: "合并失败: \(mergeResult.output)",
                    branchName: sourceBranch,
                    output: mergeResult.output
                )
            }
        }
        
        return BranchOperationResult.success(
            operation: .merge,
            message: "成功将分支 '\(sourceBranch)' 合并到 '\(targetBranch)'",
            branchName: sourceBranch,
            output: mergeResult.output
        )
    }
    
    /// 检查分支是否可以安全合并
    /// - Parameters:
    ///   - sourceBranch: 源分支名称
    ///   - targetBranch: 目标分支名称
    ///   - projectPath: 项目路径
    /// - Returns: 合并预检查结果
    static func checkMergeability(
        sourceBranch: String,
        targetBranch: String = "main",
        projectPath: String
    ) -> MergeabilityCheck {
        
        // 1. 基本检查
        guard isValidGitRepository(path: projectPath) else {
            return MergeabilityCheck(
                canMerge: false,
                conflicts: [],
                warnings: ["不是有效的Git仓库"],
                recommendations: ["确保在Git仓库中执行操作"]
            )
        }
        
        var warnings: [String] = []
        var recommendations: [String] = []
        var conflicts: [String] = []
        
        // 2. 检查工作区状态
        let statusCheck = getGitStatus(path: projectPath)
        if !statusCheck.clean {
            warnings.append("工作区有 \(statusCheck.changes) 个未提交的更改")
            recommendations.append("合并前请提交或暂存所有更改")
        }
        
        // 3. 检查是否有分歧的提交
        let divergenceResult = executeGitCommand(
            args: ["rev-list", "--left-right", "--count", "\(targetBranch)...\(sourceBranch)"],
            workingDir: projectPath
        )
        
        if divergenceResult.success {
            let counts = divergenceResult.output.trimmingCharacters(in: .whitespacesAndNewlines).components(separatedBy: .whitespaces)
            if counts.count == 2, let behind = Int(counts[0]), let ahead = Int(counts[1]) {
                if behind > 0 {
                    warnings.append("目标分支领先源分支 \(behind) 个提交")
                    recommendations.append("合并前考虑先更新源分支")
                }
                if ahead == 0 {
                    warnings.append("源分支没有新提交")
                    recommendations.append("确认是否真的需要合并")
                }
            }
        }
        
        // 4. 检查潜在冲突（模拟合并）
        let mergeBase = executeGitCommand(
            args: ["merge-base", targetBranch, sourceBranch],
            workingDir: projectPath
        )
        
        if mergeBase.success {
            // 使用--name-only检查可能冲突的文件
            let conflictCheck = executeGitCommand(
                args: ["diff", "--name-only", mergeBase.output.trimmingCharacters(in: .whitespacesAndNewlines), targetBranch],
                workingDir: projectPath
            )
            
            if conflictCheck.success && !conflictCheck.output.isEmpty {
                let targetFiles = Set(conflictCheck.output.components(separatedBy: .newlines).filter { !$0.isEmpty })
                
                let sourceCheck = executeGitCommand(
                    args: ["diff", "--name-only", mergeBase.output.trimmingCharacters(in: .whitespacesAndNewlines), sourceBranch],
                    workingDir: projectPath
                )
                
                if sourceCheck.success && !sourceCheck.output.isEmpty {
                    let sourceFiles = Set(sourceCheck.output.components(separatedBy: .newlines).filter { !$0.isEmpty })
                    let commonFiles = targetFiles.intersection(sourceFiles)
                    
                    if !commonFiles.isEmpty {
                        conflicts = Array(commonFiles)
                        warnings.append("检测到 \(commonFiles.count) 个可能冲突的文件")
                        recommendations.append("合并时请仔细检查这些文件")
                    }
                }
            }
        }
        
        let canMerge = statusCheck.clean && conflicts.isEmpty
        
        return MergeabilityCheck(
            canMerge: canMerge,
            conflicts: conflicts,
            warnings: warnings,
            recommendations: recommendations
        )
    }
    
    /// 获取两个分支之间的差异统计
    /// - Parameters:
    ///   - sourceBranch: 源分支
    ///   - targetBranch: 目标分支
    ///   - projectPath: 项目路径
    /// - Returns: 差异统计信息
    static func getBranchDiff(
        sourceBranch: String,
        targetBranch: String,
        projectPath: String
    ) -> BranchDiffStats? {
        
        // 获取提交数差异
        let commitDiff = executeGitCommand(
            args: ["rev-list", "--count", "\(targetBranch)..\(sourceBranch)"],
            workingDir: projectPath
        )
        
        guard commitDiff.success, let commitsAhead = Int(commitDiff.output.trimmingCharacters(in: .whitespacesAndNewlines)) else {
            return nil
        }
        
        // 获取文件变更统计
        let statResult = executeGitCommand(
            args: ["diff", "--stat", "\(targetBranch)...\(sourceBranch)"],
            workingDir: projectPath
        )
        
        var filesChanged = 0
        var insertions = 0
        var deletions = 0
        
        if statResult.success && !statResult.output.isEmpty {
            let lines = statResult.output.components(separatedBy: .newlines)
            if let lastLine = lines.last?.trimmingCharacters(in: .whitespacesAndNewlines), !lastLine.isEmpty {
                // 解析如 "3 files changed, 45 insertions(+), 12 deletions(-)" 的格式
                let components = lastLine.components(separatedBy: ",")
                for component in components {
                    let trimmed = component.trimmingCharacters(in: .whitespacesAndNewlines)
                    if trimmed.contains("file") {
                        filesChanged = Int(trimmed.components(separatedBy: " ").first ?? "0") ?? 0
                    } else if trimmed.contains("insertion") {
                        insertions = Int(trimmed.components(separatedBy: " ").first ?? "0") ?? 0
                    } else if trimmed.contains("deletion") {
                        deletions = Int(trimmed.components(separatedBy: " ").first ?? "0") ?? 0
                    }
                }
            } else {
                // 如果没有统计信息，计算文件数量
                let changedFiles = executeGitCommand(
                    args: ["diff", "--name-only", "\(targetBranch)...\(sourceBranch)"],
                    workingDir: projectPath
                )
                if changedFiles.success {
                    filesChanged = changedFiles.output.components(separatedBy: .newlines).filter { !$0.isEmpty }.count
                }
            }
        }
        
        return BranchDiffStats(
            commitsAhead: commitsAhead,
            filesChanged: filesChanged,
            insertions: insertions,
            deletions: deletions
        )
    }
}

// MARK: - Supporting Types

/// 合并策略
enum MergeStrategy {
    case recursive      // 默认递归策略
    case ours          // 冲突时使用我们的版本
    case theirs        // 冲突时使用他们的版本
    case noFastForward // 禁用快进合并
}

/// 合并可行性检查结果
struct MergeabilityCheck {
    let canMerge: Bool
    let conflicts: [String]
    let warnings: [String]
    let recommendations: [String]
}

/// 分支差异统计
struct BranchDiffStats {
    let commitsAhead: Int
    let filesChanged: Int
    let insertions: Int
    let deletions: Int
    
    var summary: String {
        if commitsAhead == 0 {
            return "无新提交"
        }
        
        var parts: [String] = []
        parts.append("\(commitsAhead) 个提交")
        
        if filesChanged > 0 {
            parts.append("\(filesChanged) 个文件")
        }
        
        if insertions > 0 || deletions > 0 {
            parts.append("+\(insertions)/-\(deletions)")
        }
        
        return parts.joined(separator: ", ")
    }
}