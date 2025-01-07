import SwiftUI

struct SearchBar: View {
    @Binding var text: String
    @FocusState private var isFocused: Bool
    
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "magnifyingglass")
                .foregroundColor(AppTheme.secondaryText)
                .font(.system(size: 14))
            
            TextField("搜索项目...", text: $text)
                .textFieldStyle(.plain)
                .focused($isFocused)
                .font(.system(size: 14))
                .foregroundColor(AppTheme.text)
            
            if !text.isEmpty {
                Button(action: {
                    text = ""
                    isFocused = true
                }) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(AppTheme.secondaryText)
                        .font(.system(size: 14))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(AppTheme.secondaryBackground)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(isFocused ? AppTheme.accent : AppTheme.border, lineWidth: 1)
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