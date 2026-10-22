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

            if !input.text.isEmpty {
                Button(action: { input.text = "" }) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(AppTheme.titleBarIcon)
                }
                .buttonStyle(.plain)
            }
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
