import SwiftUI

// ViewModifier方式获取视图引用
struct ViewReferenceSetter<T: View>: ViewModifier {
    @Binding var reference: T?

    func body(content: Content) -> some View {
        content
            .onAppear {
                // 当视图出现时保存引用
                reference = content as? T
            }
            .onDisappear {
                // 当视图消失时移除引用
                reference = nil
            }
    }
} 