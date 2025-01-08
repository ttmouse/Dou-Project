import SwiftUI

struct SearchBar: View {
    @Binding var text: String
    
    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundColor(AppTheme.titleBarIcon)
            
            TextField("搜索项目...", text: $text)
                .textFieldStyle(.plain)
                .foregroundColor(AppTheme.titleBarText)
            
            if !text.isEmpty {
                Button(action: { text = "" }) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(AppTheme.titleBarIcon)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(8)
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
            SearchBar(text: .constant(""))
            SearchBar(text: .constant("测试搜索"))
        }
        .padding()
        .background(Color(.windowBackgroundColor))
        .previewLayout(.sizeThatFits)
    }
}
#endif 