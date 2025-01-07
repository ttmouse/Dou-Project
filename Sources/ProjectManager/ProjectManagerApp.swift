import SwiftUI
import AppKit

@main
struct ProjectManagerApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject private var tagManager = TagManager()
    
    var body: some Scene {
        WindowGroup {
            ProjectListView()
                .environmentObject(tagManager)
                .frame(minWidth: 800, minHeight: 600)
                .background(Color(.windowBackgroundColor))
        }
    }
}

class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }
    
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return true
    }
} 
