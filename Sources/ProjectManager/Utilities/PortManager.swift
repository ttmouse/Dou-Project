import Foundation

/// 端口管理器 - 处理端口检测和进程管理
class PortManager {
    
    /// 检查端口是否被占用
    /// - Parameter port: 端口号
    /// - Returns: 是否被占用
    static func isPortInUse(_ port: Int) -> Bool {
        // 使用 lsof 检查端口
        // -i :<port>  显示指定端口的网络文件
        // -sTCP:LISTEN 仅显示监听状态的连接
        // -t 仅输出 PID
        let result = ShellExecutor.executeShellCommand("lsof -i :\(port) -sTCP:LISTEN -t", workingDir: "/tmp")
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
        let result = ShellExecutor.executeShellCommand("lsof -i :\(port) -sTCP:LISTEN -t", workingDir: "/tmp")
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
        
        // 尝试正常终止
        var result = ShellExecutor.executeShellCommand("kill \(pid)", workingDir: "/tmp")
        
        if !result.success {
            // 如果失败，尝试强制终止
            result = ShellExecutor.executeShellCommand("kill -9 \(pid)", workingDir: "/tmp")
        }
        
        return result.success
    }
}
