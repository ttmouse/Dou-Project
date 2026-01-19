import Foundation
import AppKit

enum ProjectRunResult {
    case success(pid: Int32)
    case failure(String)
    case portBusy(port: Int, pid: Int?)
}

class ProjectRunner {
    
    static func run(_ project: Project, useRandomPort: Bool = false) -> ProjectRunResult {
        // 1. 获取启动命令
        guard let command = project.startupCommand, !command.isEmpty else {
            // 如果没有自定义命令，尝试默认行为 (兼容旧逻辑)
            project.runProject()
            return .success(pid: 0) // 无法获取 PID，因为是旧逻辑
        }
        
        // 2. 获取端口
        var port = project.customPort
        
        // 3. 检查端口冲突
        if let targetPort = port {
            if useRandomPort {
                // 如果指定使用随机端口，则查找一个可用端口
                let newPort = PortManager.findAvailablePort(startPort: targetPort + 1)
                if newPort > 0 {
                    port = newPort
                } else {
                    return .failure("无法找到可用端口")
                }
            } else if PortManager.isPortInUse(targetPort) {
                // 端口被占用
                let pid = PortManager.getPidOnPort(targetPort)
                return .portBusy(port: targetPort, pid: pid)
            }
        }
        
        // 4. 构建并执行命令
        return executeCommand(command, at: project.path, port: port)
    }
    
    private static func executeCommand(_ command: String, at path: String, port: Int?) -> ProjectRunResult {
        print("🚀 ProjectRunner: 准备执行命令")
        print("   命令: \(command)")
        print("   路径: \(path)")
        print("   端口: \(port?.description ?? "无")")
        
        // 使用终端执行，以便用户可以看到输出
        let scriptSource: String
        if let port = port {
            // 注入 PORT 环境变量
            scriptSource = "export PORT=\(port); \(command)"
        } else {
            scriptSource = command
        }
        
        // 转义路径和命令中的特殊字符
        let escapedPath = path.replacingOccurrences(of: "\\", with: "\\\\")
                              .replacingOccurrences(of: "\"", with: "\\\"")
        let escapedCommand = scriptSource.replacingOccurrences(of: "\\", with: "\\\\")
                                         .replacingOccurrences(of: "\"", with: "\\\"")
        
        let appleScript = """
        tell application "Terminal"
            do script "cd " & quoted form of "\(escapedPath)" & " && \(escapedCommand)"
            activate
        end tell
        """
        
        print("📝 AppleScript:")
        print(appleScript)
        
        let script = NSAppleScript(source: appleScript)
        var error: NSDictionary?
        let result = script?.executeAndReturnError(&error)
        
        if let error = error {
            print("❌ AppleScript 执行失败: \(error)")
            return .failure("无法启动终端: \(error)")
        }
        
        print("✅ AppleScript 执行成功")
        if let result = result {
            print("   结果: \(result)")
        }
        
        return .success(pid: 0) // 外部进程，无法追踪 PID
    }
    
    static func killProcessAndRun(_ project: Project) -> ProjectRunResult {
        if let port = project.customPort {
            _ = PortManager.killProcessOnPort(port)
            // 等待一小会儿让端口释放
            Thread.sleep(forTimeInterval: 0.5)
        }
        return run(project)
    }
}
