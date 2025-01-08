import SwiftUI

struct TagRow: View {
    let tag: String
    let isSelected: Bool
    let count: Int
    let action: () -> Void
    @ObservedObject var tagManager: TagManager
    
    var body: some View {
        Button(action: action) {
            HStack {
                TagView(
                    tag: tag,
                    color: tagManager.getColor(for: tag),
                    fontSize: 13,
                    isSelected: isSelected
                )
                
                Spacer()
                
                Text("\(count)")
                    .font(.caption)
                    .foregroundColor(isSelected ? AppTheme.accent : AppTheme.sidebarSecondaryText)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 2)
                    .background(isSelected ? AppTheme.sidebarSelectedBackground : AppTheme.sidebarDirectoryBackground)
                    .cornerRadius(4)
            }
            .contentShape(Rectangle())
            .padding(.vertical, 4)
            .padding(.horizontal, 16)
        }
        .buttonStyle(.plain)
        .background(isSelected ? AppTheme.sidebarSelectedBackground : Color.clear)
        .animation(.easeInOut(duration: 0.2), value: isSelected)
    }
}

#if DEBUG
struct TagRow_Previews: PreviewProvider {
    static var previews: some View {
        VStack {
            TagRow(
                tag: "SwiftUI",
                isSelected: true,
                count: 5,
                action: {},
                tagManager: TagManager()
            )
            TagRow(
                tag: "macOS",
                isSelected: false,
                count: 3,
                action: {},
                tagManager: TagManager()
            )
        }
        .padding()
    }
}
#endif 