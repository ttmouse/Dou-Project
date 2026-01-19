import SwiftUI

/// TextField 焦点追踪修饰符
///
/// 用于让 TextField 自动通知全局焦点状态管理器
struct FocusTrackingModifier: ViewModifier {
    @EnvironmentObject private var focusStateManager: FocusStateManager
    @FocusState private var isFocused: Bool

    func body(content: Content) -> some View {
        content
            .focused($isFocused)
            .onChange(of: isFocused) { focused in
                focusStateManager.setTextFieldFocused(focused)
            }
    }
}

extension View {
    /// 为 TextField 添加焦点追踪功能
    ///
    /// 当 TextField 获得/失去焦点时，自动通知全局 FocusStateManager
    func trackTextFieldFocus() -> some View {
        modifier(FocusTrackingModifier())
    }
}
