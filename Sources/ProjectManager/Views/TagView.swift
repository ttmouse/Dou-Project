import SwiftUI

struct TagView: View {
    let tag: String
    let color: Color
    let fontSize: CGFloat
    var isSelected: Bool = false
    
    var body: some View {
        Text(tag)
            .font(.system(size: fontSize))
            .foregroundColor(isSelected ? .white : color)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(isSelected ? color : color.opacity(0.15))
            )
    }
}

#if DEBUG
struct TagView_Previews: PreviewProvider {
    static var previews: some View {
        VStack(spacing: 20) {
            TagView(tag: "iOS", color: .blue, fontSize: 13)
            TagView(tag: "Swift", color: .orange, fontSize: 13)
            TagView(tag: "Selected", color: .green, fontSize: 13, isSelected: true)
        }
        .padding()
    }
}
#endif 