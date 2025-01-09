import SwiftUI

struct ScrollIndicatorView: View {
    @State private var opacity: Double = 0

    var body: some View {
        Capsule()
            .fill(AppTheme.scrollBar)
            .frame(width: 3)
            .padding(.trailing, 2)
            .padding(.vertical, 8)
            .opacity(opacity)
            .onAppear {
                // 显示滚动条
                withAnimation(.easeIn(duration: 0.3)) {
                    opacity = 1
                }
                // 2秒后淡出
                DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                    withAnimation(.easeOut(duration: 0.3)) {
                        opacity = 0.3
                    }
                }
            }
            .onHover { hovering in
                withAnimation(.easeInOut(duration: 0.2)) {
                    opacity = hovering ? 1 : 0.3
                }
            }
    }
}

#if DEBUG
    struct ScrollIndicatorView_Previews: PreviewProvider {
        static var previews: some View {
            ScrollIndicatorView()
                .frame(height: 300)
                .background(Color.black)
                .preferredColorScheme(.dark)
        }
    }
#endif
