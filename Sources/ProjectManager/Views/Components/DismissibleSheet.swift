import AppKit
import SwiftUI

/// Adds consistent outside-click and Escape dismissal to app-owned sheets.
struct DismissibleSheet: ViewModifier {
    @Binding var isPresented: Bool

    func body(content: Content) -> some View {
        content
            .background(OutsideClickDismissal(isPresented: $isPresented))
            .onExitCommand { isPresented = false }
    }
}

private struct OutsideClickDismissal: NSViewRepresentable {
    @Binding var isPresented: Bool

    func makeNSView(context: Context) -> MonitorView {
        let view = MonitorView()
        view.onOutsideClick = { isPresented = false }
        return view
    }

    func updateNSView(_ view: MonitorView, context: Context) {
        view.onOutsideClick = { isPresented = false }
    }

    final class MonitorView: NSView {
        var onOutsideClick: (() -> Void)?
        private var monitor: Any?

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            guard monitor == nil else { return }
            monitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] event in
                guard let self, let panelWindow = self.window else { return event }
                let screenPoint = event.window?.convertPoint(toScreen: event.locationInWindow) ?? NSEvent.mouseLocation
                if !panelWindow.frame.contains(screenPoint) {
                    DispatchQueue.main.async { self.onOutsideClick?() }
                }
                return event
            }
        }

        deinit {
            if let monitor { NSEvent.removeMonitor(monitor) }
        }
    }
}

extension View {
    func dismissibleSheet(isPresented: Binding<Bool>) -> some View {
        modifier(DismissibleSheet(isPresented: isPresented))
    }
}
