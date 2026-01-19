import SwiftUI

/// 全局焦点状态管理器
///
/// 职责：追踪应用中是否有任何文本输入框获得焦点
/// 用途：让 App 级别的命令（如 Command+A）能够条件性地启用/禁用
@MainActor
class FocusStateManager: ObservableObject {
    /// 当前是否有文本输入框获得焦点
    @Published var isTextFieldFocused: Bool = false

    /// 更新焦点状态
    /// - Parameter focused: 是否有文本输入框获得焦点
    func setTextFieldFocused(_ focused: Bool) {
        isTextFieldFocused = focused
    }
}
