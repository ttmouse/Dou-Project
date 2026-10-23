import AppKit
import SwiftUI

/// 原生鼠标跟踪不依赖按钮按下或窗口先获得焦点，也不拦截按钮点击。
struct IconHoverTracking: NSViewRepresentable {
    let onHover: (Bool) -> Void

    func makeNSView(context: Context) -> IconHoverTrackingView {
        let view = IconHoverTrackingView()
        view.onHover = onHover
        return view
    }

    func updateNSView(_ view: IconHoverTrackingView, context: Context) {
        view.onHover = onHover
    }
}

final class IconHoverTrackingView: NSView {
    var onHover: (Bool) -> Void = { _ in }
    private var hoverArea: NSTrackingArea?

    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let hoverArea { removeTrackingArea(hoverArea) }
        let area = NSTrackingArea(rect: .zero,
                                  options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
                                  owner: self)
        addTrackingArea(area)
        hoverArea = area
    }

    override func mouseEntered(with event: NSEvent) { onHover(true) }
    override func mouseExited(with event: NSEvent) { onHover(false) }
}
