import SwiftUI

struct SearchBar: View {
    @Binding var text: String
    @FocusState private var isFocused: Bool

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundColor(isFocused ? AppTheme.searchBarActiveIcon : AppTheme.titleBarIcon)

            TextField("搜索项目...", text: $text)
                .textFieldStyle(.plain)
                .font(AppTheme.searchBarFont)
                .foregroundColor(AppTheme.searchBarText)
                .tint(AppTheme.searchBarCursor)
                .focused($isFocused)

            if !text.isEmpty {
                Button(action: { text = "" }) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(AppTheme.titleBarIcon)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(8)
        .background(isFocused ? AppTheme.searchBarActiveBackground : AppTheme.searchBarBackground)
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .strokeBorder(
                    isFocused ? AppTheme.searchBarActiveBorder : AppTheme.searchBarBorder,
                    lineWidth: 1)
        )
        .animation(.easeInOut(duration: 0.2), value: isFocused)
    }
}

#if DEBUG
    struct SearchBar_Previews: PreviewProvider {
        static var previews: some View {
            VStack(spacing: 20) {
                SearchBar(text: .constant(""))
                SearchBar(text: .constant("测试搜索"))
            }
            .padding()
            .background(Color(.windowBackgroundColor))
            .previewLayout(.sizeThatFits)
        }
    }
#endif
