import SwiftUI
import AppKit

/// 处理 Command+A 快捷键的 Responder Chain Handler
///
/// 工作原理：
/// 1. TextField 获得焦点时，它会处理 Command+A（系统默认行为）
/// 2. TextField 没有焦点时，这个 Handler 会响应 Command+A
/// 3. 通过 Responder Chain 自然工作，不覆盖系统行为
struct SelectAllResponder: NSViewRepresentable {
    let action: () -> Void

    func makeNSView(context: Context) -> NSView {
        let view = SelectAllResponderView()
        view.selectAllAction = action
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        if let view = nsView as? SelectAllResponderView {
            view.selectAllAction = action
        }
    }
}

/// 自定义 NSView，能够响应 selectAll: 动作
private class SelectAllResponderView: NSView {
    var selectAllAction: (() -> Void)?

    override var acceptsFirstResponder: Bool {
        return true
    }

    /// 响应 Command+A
    @objc override func selectAll(_ sender: Any?) {
        selectAllAction?()
    }
}
