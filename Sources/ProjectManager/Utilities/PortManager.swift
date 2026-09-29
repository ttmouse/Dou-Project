import Foundation

/// 端口管理器 - 处理端口检测和进程管理
class PortManager {

    /// 运行外部命令，参数走数组，不经 shell 解释（2026-09-29 安全收尾：
    /// 消除 `bash -c` 辅助入口，防止后人复用引入注入面）。
    private static func runProcess(executable: String, arguments: [String]) -> (output: String, success: Bool) {
        let process = Process()
        let pipe = Pipe()
        let errorPipe = Pipe()

        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
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

    /// 检查端口是否被占用
    /// - Parameter port: 端口号
    /// - Returns: 是否被占用
    static func isPortInUse(_ port: Int) -> Bool {
        // /usr/sbin/lsof 直调 + 参数数组（原为 executeShellCommand 拼 shell 字符串）
        // -i :<port>  显示指定端口的网络文件
        // -sTCP:LISTEN 仅显示监听状态的连接
        // -t 仅输出 PID
        let result = runProcess(executable: "/usr/sbin/lsof",
                                arguments: ["-i", ":\(port)", "-sTCP:LISTEN", "-t"])
        return result.success && !result.output.isEmpty
    }

    /// 查找可用端口
    /// - Parameter startPort: 起始端口
    /// - Returns: 可用端口号
    static func findAvailablePort(startPort: Int = 8000) -> Int {
        var port = startPort
        while isPortInUse(port) {
            port += 1
            // 防止无限循环，设置一个上限
            if port > 65535 {
                return 0 // 未找到可用端口
            }
        }
        return port
    }

    /// 获取占用端口的进程 PID
    /// - Parameter port: 端口号
    /// - Returns: PID (如果存在)
    static func getPidOnPort(_ port: Int) -> Int? {
        let result = runProcess(executable: "/usr/sbin/lsof",
                                arguments: ["-i", ":\(port)", "-sTCP:LISTEN", "-t"])
        if result.success, let pid = Int(result.output.trimmingCharacters(in: .whitespacesAndNewlines)) {
            return pid
        }
        return nil
    }

    /// 终止占用端口的进程
    /// - Parameter port: 端口号
    /// - Returns: 操作结果
    static func killProcessOnPort(_ port: Int) -> Bool {
        guard let pid = getPidOnPort(port) else {
            return false // 没有进程占用该端口
        }

        // /bin/kill 直调，PID 走参数数组（默认信号 TERM）
        var result = runProcess(executable: "/bin/kill", arguments: ["\(pid)"])

        if !result.success {
            // 如果失败，尝试强制终止（SIGKILL）
            result = runProcess(executable: "/bin/kill", arguments: ["-9", "\(pid)"])
        }

        return result.success
    }
}
