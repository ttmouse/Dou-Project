import SwiftUI

/// 输入变化只通知搜索框；列表在匹配结果改变时再刷新。
final class ProjectSearchInput: ObservableObject {
    @Published var text: String = ""
}

struct SearchBar: View {
    @ObservedObject var input: ProjectSearchInput
    @FocusState private var isFocused: Bool

    // 添加一个方法来清除焦点
    func clearFocus() {
        isFocused = false
    }

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundColor(AppTheme.titleBarIcon)

            TextField("搜索项目...", text: $input.text)
                .textFieldStyle(.plain)
                .font(AppTheme.searchBarFont)
                .foregroundColor(AppTheme.searchBarText)
                .tint(AppTheme.searchBarCursor)
                .focused($isFocused)

            // 清除按钮始终存在，只用透明度控制可见性。
            //
            // 原先写成 `if !input.text.isEmpty { Button }`：每敲一个字都会
            // 从这个 HStack 里插入/移除一个子视图，导致这一行的布局尺寸变化。
            // 而它挂在窗口最顶层的 VStack 上，尺寸变化会向上传导，触发整窗
            // `_layoutViewTree` —— 实测搜索时该路径占 14.7%，同样场景下只滚动
            // 则只有 0.1%，可见不是滚动固有的代价，而是搜索引起的重布局。
            // 结构恒定的写法把这条触发链去掉。
            Button(action: { input.text = "" }) {
                Image(systemName: "xmark.circle.fill")
                    .foregroundColor(AppTheme.titleBarIcon)
            }
            .buttonStyle(IconButtonStyle(iconSize: 12, buttonSize: 24))
            .opacity(input.text.isEmpty ? 0 : 1)
            .allowsHitTesting(!input.text.isEmpty)
            .accessibilityHidden(input.text.isEmpty)
        }
        .padding(.horizontal, 8)
        .frame(height: AppTheme.searchBarControlHeight)
        .background(AppTheme.searchBarBackground)
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .strokeBorder(AppTheme.searchBarBorder, lineWidth: 1)
        )
    }
}

#if DEBUG
    struct SearchBar_Previews: PreviewProvider {
        static var previews: some View {
            VStack(spacing: 20) {
                SearchBar(input: ProjectSearchInput())
            }
            .padding()
            .background(Color(.windowBackgroundColor))
            .previewLayout(.sizeThatFits)
        }
    }
#endif
