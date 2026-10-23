import AppKit
import SwiftUI

private final class ProjectOverlayScroller: NSScroller {
    override class var isCompatibleWithOverlayScrollers: Bool { true }

    override func drawKnob() {
        let knobRect = rect(for: .knob)
        let knobWidth = min(8, knobRect.width)
        let horizontalInset = max(0, (knobRect.width - knobWidth) / 2)
        let indicatorRect = knobRect.insetBy(dx: horizontalInset, dy: 1)
        guard indicatorRect.width > 0, indicatorRect.height > 0 else { return }

        NSColor(AppTheme.scrollBar).setFill()
        NSBezierPath(
            roundedRect: indicatorRect,
            xRadius: knobWidth / 2,
            yRadius: knobWidth / 2
        ).fill()
    }
}

extension NSScrollView {
    /// 网格和列表统一使用覆盖式自动隐藏指示器，不占用内容宽度。
    func configureProjectScrollIndicators() {
        hasVerticalScroller = true
        hasHorizontalScroller = false
        autohidesScrollers = true
        scrollerStyle = .overlay
        if !(verticalScroller is ProjectOverlayScroller) {
            verticalScroller = ProjectOverlayScroller(frame: .zero)
        }
    }
}
