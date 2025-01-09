import AppKit
import SwiftUI

@main
struct ProjectManagerApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        WindowGroup {
            ContentView()
                .frame(minWidth: 800, minHeight: 600)
                .background(AppTheme.background)
                .preferredColorScheme(.dark)
        }
        .windowStyle(.hiddenTitleBar)
    }
}

struct ContentView: View {
    @StateObject var tagManager = TagManager()

    var body: some View {
        ProjectListView()
            .environmentObject(tagManager)
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
        contentView.rootView.tagManager.saveAll()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return true
    }
}
