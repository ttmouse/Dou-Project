import AppKit
import SwiftUI

/// Esc 取消标签筛选的判定规则。
///
/// 「全部」是表示「不筛选」的伪标签，选中它等于没有筛选，
/// 这时按 Esc 不应该产生任何动作（否则会白白吃掉一次 Esc）。
enum TagSelectionEscapeLogic {
    static let unfilteredTag = "全部"

    static func shouldCancel(_ selectedTags: Set<String>) -> Bool {
        selectedTags.contains { $0 != unfilteredTag }
    }
}

/// 在主窗口内监听 Esc，用来取消标签筛选。
///
/// 为什么不用 `.onExitCommand`：点击标签行时会把 first responder 置空，
/// 没有焦点就没有 responder 链来接收 `cancelOperation:`，SwiftUI 的
/// `.onExitCommand` 因此不触发。这里用局部事件监听补上这一层。
///
/// 边界：sheet、字段编辑器（搜索框正在编辑）占用 Esc 时不拦截，
/// 保证对话框关闭、输入回退等原生行为不被抢走。
struct EscapeKeyCanceller: NSViewRepresentable {
    let isEnabled: Bool
    let action: () -> Void

    func makeNSView(context: Context) -> EscapeKeyCancellerView {
        let view = EscapeKeyCancellerView()
        view.isEnabled = isEnabled
        view.onCancel = action
        return view
    }

    func updateNSView(_ view: EscapeKeyCancellerView, context: Context) {
        view.isEnabled = isEnabled
        view.onCancel = action
    }
}

final class EscapeKeyCancellerView: NSView {
    var isEnabled = false
    var onCancel: (() -> Void)?

    private var monitor: Any?

    override var acceptsFirstResponder: Bool { false }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        guard monitor == nil else { return }
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown]) { [weak self] event in
            guard let self else { return event }
            return self.handle(event)
        }
    }

    /// 返回 nil 表示事件已被消费，避免系统再对未处理的 Esc 发出提示音。
    private func handle(_ event: NSEvent) -> NSEvent? {
        guard isEnabled, event.keyCode == 53 else { return event }
        guard let window, window.isKeyWindow, event.window === window else { return event }
        guard window.attachedSheet == nil else { return event }
        guard !(window.firstResponder is NSText) else { return event }

        DispatchQueue.main.async { [weak self] in
            self?.onCancel?()
        }
        return nil
    }

    deinit {
        if let monitor { NSEvent.removeMonitor(monitor) }
    }
}
