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
        }
    }
}

struct ContentView: View {
    @StateObject private var tagManager = TagManager()

    var body: some View {
        ProjectListView()
            .environmentObject(tagManager)
    }
}

class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        if let window = NSApplication.shared.windows.first {
            window.backgroundColor = NSColor(AppTheme.background)

            window.titlebarAppearsTransparent = true
            window.titlebarSeparatorStyle = .none

            if let titlebar = window.standardWindowButton(.closeButton)?.superview?.superview {
                titlebar.wantsLayer = true
                titlebar.layer?.backgroundColor = NSColor(AppTheme.titleBarBackground).cgColor
            }

            window.title = "项目管理器"
            if let titleView = window.standardWindowButton(.closeButton)?.superview?.superview?
                .subviews.first(where: { $0 is NSTextField }) as? NSTextField
            {
                titleView.textColor = NSColor(AppTheme.titleBarText)
            }

            let buttonTypes: [NSWindow.ButtonType] = [
                .closeButton, .miniaturizeButton, .zoomButton,
            ]
            buttonTypes.forEach { buttonType in
                if let button = window.standardWindowButton(buttonType) {
                    button.wantsLayer = true
                }
            }
        }

        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return true
    }
}
