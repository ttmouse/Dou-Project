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
    private var isHovering = false

    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let hoverArea { removeTrackingArea(hoverArea) }
        let area = NSTrackingArea(rect: .zero,
                                  options: [.mouseEnteredAndExited, .mouseMoved, .activeAlways, .inVisibleRect],
                                  owner: self)
        addTrackingArea(area)
        hoverArea = area
        // 布局或行位置变化时，旧的进入/离开状态可能仍留在上一行。
        DispatchQueue.main.async { [weak self] in
            guard let self, let window = self.window, window.isVisible else { return }
            self.updateHover(at: window.mouseLocationOutsideOfEventStream)
        }
    }

    override func mouseEntered(with event: NSEvent) { updateHover(at: event.locationInWindow) }
    override func mouseMoved(with event: NSEvent) { updateHover(at: event.locationInWindow) }
    override func mouseExited(with event: NSEvent) { setHovered(false) }

    private func updateHover(at windowPoint: NSPoint) {
        let point = convert(windowPoint, from: nil)
        setHovered(!isHiddenOrHasHiddenAncestor && bounds.contains(point))
    }

    private func setHovered(_ value: Bool) {
        guard isHovering != value else { return }
        isHovering = value
        onHover(value)
    }
}
