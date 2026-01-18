import AppKit
import SwiftUI

@main
struct ProjectManagerApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject private var tagManager = TagManager()

    var body: some Scene {
        WindowGroup {
            ContentView(tagManager: tagManager)
                .frame(minWidth: 800, minHeight: 600)
                .background(AppTheme.background)
                .preferredColorScheme(.dark)
        }
        .windowStyle(.hiddenTitleBar)
        .commands {
            CommandGroup(after: .toolbar) {
                Button("全选") {
                    NotificationCenter.default.post(name: NSNotification.Name("selectAll"), object: nil)
                }
                .keyboardShortcut("a")
            }
            
            CommandMenu("项目") {
                Button("重新生成所有项目标签") {
                    print("📢 发送 reloadAllProjects 通知")
                    NotificationCenter.default.post(name: NSNotification.Name("reloadAllProjects"), object: nil)
                    print("✅ 通知已发送")
                }
                .keyboardShortcut("t", modifiers: [.command, .shift])

                Divider()

                Button("切换性能监控面板") {
                    NotificationCenter.default.post(name: NSNotification.Name("togglePerformanceMonitor"), object: nil)
                }
                .keyboardShortcut("p", modifiers: [.command, .option])
            }
        }
        
        Settings {
            SettingsView(tagManager: tagManager)
        }
    }
}

struct ContentView: View {
    @ObservedObject var tagManager: TagManager

    var body: some View {
        ProjectListView()
            .environmentObject(tagManager)
            .onAppear {
                // 延迟启动git_daily数据收集，避免阻塞UI
                DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                    print("🚀 启动git_daily数据收集...")
                    // 临时注释掉自动收集，避免阻塞
                    // tagManager.updateAllProjectsGitDaily()
                    print("⏭️ 跳过自动git_daily收集，可手动触发")
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("reloadAllProjects"))) { notification in
                print("🔄 收到重新生成所有项目标签命令")
                print("📋 通知对象: \(notification.object ?? "无")")
                tagManager.reloadProjects()
                print("✅ reloadProjects() 调用完成")
            }
    }
}

class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        if let window = NSApplication.shared.windows.first {
            window.backgroundColor = NSColor(AppTheme.background)

            window.titleVisibility = .hidden
            window.titlebarAppearsTransparent = true
            window.styleMask.insert(.fullSizeContentView)

            let buttonTypes: [NSWindow.ButtonType] = [
                .closeButton, .miniaturizeButton, .zoomButton,
            ]
            buttonTypes.forEach { buttonType in
                if let button = window.standardWindowButton(buttonType) {
                    button.wantsLayer = true
                }
            }

            if let textView = window.fieldEditor(true, for: nil) as? NSTextView {
                textView.isAutomaticTextReplacementEnabled = false
                textView.isAutomaticQuoteSubstitutionEnabled = false
                textView.isAutomaticDashSubstitutionEnabled = false
            }
        }

        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }

    func applicationWillTerminate(_ notification: Notification) {
        // 获取 TagManager 实例
        guard let window = NSApplication.shared.windows.first,
            let contentView = window.contentViewController as? NSHostingController<ContentView>
        else {
            return
        }

        // 强制保存所有数据
        contentView.rootView.tagManager.saveAll(force: true)
        
        // 等待一小段时间确保数据写入
        Thread.sleep(forTimeInterval: 0.5)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return true
    }
}
