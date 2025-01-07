import SwiftUI

struct TagRow: View {
    let tag: String
    let isSelected: Bool
    let count: Int
    let action: () -> Void
    @ObservedObject var tagManager: TagManager
    
    var body: some View {
        HStack {
            Circle()
                .fill(isSelected ? Color.blue : Color.clear)
                .frame(width: 12, height: 12)
            
            Text(tag)
            
            Spacer()
            
            Text("\(count)")
                .foregroundColor(.secondary)
                .font(.caption)
        }
        .padding(.vertical, 4)
        .padding(.horizontal, 8)
        .background(Color.clear)
        .contentShape(Rectangle())
        .onTapGesture(perform: action)
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