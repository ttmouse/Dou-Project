import SwiftUI

struct ToastView: View {
    let message: String
    @Binding var isPresented: Bool
    
    var body: some View {
        Text(message)
            .font(.system(size: 14))
            .foregroundColor(.white)
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(Color.black.opacity(0.7))
            .cornerRadius(8)
            .transition(.move(edge: .top).combined(with: .opacity))
    }
}

struct ToastModifier: ViewModifier {
    @State private var message: String = ""
    @State private var isPresented: Bool = false
    @State private var workItem: DispatchWorkItem?
    
    func body(content: Content) -> some View {
        content
            .overlay(
                ZStack {
                    if isPresented {
                        ToastView(message: message, isPresented: $isPresented)
                            .padding(.top, 4)
                    }
                }
                .animation(.easeInOut(duration: 0.3), value: isPresented),
                alignment: .top
            )
            .onReceive(NotificationCenter.default.publisher(for: .init("ShowToast"))) { notification in
                if let message = notification.userInfo?["message"] as? String {
                    self.message = message
                    self.isPresented = true
                    
                    // 取消之前的隐藏计时器
                    workItem?.cancel()
                    
                    // 创建新的隐藏计时器
                    let duration = (notification.userInfo?["duration"] as? Double) ?? 2.0
                    let task = DispatchWorkItem {
                        self.isPresented = false
                    }
                    workItem = task
                    DispatchQueue.main.asyncAfter(deadline: .now() + duration, execute: task)
                }
            }
    }
}

extension View {
    func toast() -> some View {
        modifier(ToastModifier())
    }
} 