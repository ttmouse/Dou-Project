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
        let process = Process()
        process.currentDirectoryURL = URL(fileURLWithPath: path)
        
        // 使用终端执行，以便用户可以看到输出
        // 这里我们使用 Terminal.app 或 iTerm2 打开一个新的标签页/窗口来运行命令
        // 这样更符合 "Quick Start" 的直觉
        
        let scriptSource: String
        if let port = port {
            // 注入 PORT 环境变量
            scriptSource = "export PORT=\(port); \(command)"
        } else {
            scriptSource = command
        }
        
        let appleScript = """
        tell application "Terminal"
            do script "cd \(path) && \(scriptSource)"
            activate
        end tell
        """
        
        let script = NSAppleScript(source: appleScript)
        var error: NSDictionary?
        script?.executeAndReturnError(&error)
        
        if let error = error {
            return .failure("无法启动终端: \(error)")
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
