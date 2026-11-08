import AppKit
import Foundation

/// 项目路径的剪贴板复制行为，供卡片与列表行共用，保证复制内容与提示文案一致。
enum ProjectPathClipboard {
    /// 复制提示的统一文案。
    static let toastMessage = "已复制路径"

    /// 把完整路径写入剪贴板。
    ///
    /// 复制的是磁盘上的真实路径（不做 `~` 缩写），粘贴到终端或编辑器后可直接使用。
    @discardableResult
    static func copy(path: String, pasteboard: NSPasteboard = .general) -> Bool {
        pasteboard.clearContents()
        return pasteboard.setString(path, forType: .string)
    }

    /// 复制路径并弹出提示。
    static func copyWithToast(path: String) {
        guard copy(path: path) else { return }
        NotificationCenter.default.post(
            name: Notification.Name("ShowToast"),
            object: nil,
            userInfo: ["message": toastMessage]
        )
    }
}
