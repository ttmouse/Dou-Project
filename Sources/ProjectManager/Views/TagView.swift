import SwiftUI

struct TagView: View {
    let tag: String
    var color: Color = .blue
    var fontSize: CGFloat = 11
    var isSelected: Bool = false
    
    var body: some View {
        Text(tag)
            .font(.system(size: fontSize, weight: .medium))
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(
                RoundedRectangle(cornerRadius: 4)
                    .fill(color.opacity(0.1))
                    .overlay(
                        RoundedRectangle(cornerRadius: 4)
                            .strokeBorder(color.opacity(0.3), lineWidth: 1)
                    )
            )
            .foregroundColor(color)
            .overlay(
                RoundedRectangle(cornerRadius: 4)
                    .strokeBorder(color, lineWidth: isSelected ? 2 : 0)
            )
    }
}

#if DEBUG
struct TagView_Previews: PreviewProvider {
    static var previews: some View {
        VStack(spacing: 10) {
            HStack {
                TagView(tag: "SwiftUI", color: .blue)
                TagView(tag: "macOS", color: .green)
                TagView(tag: "Swift", color: .orange)
            }
            
            HStack {
                TagView(tag: "开发中", color: .purple, isSelected: true)
                TagView(tag: "已完成", color: .green)
                TagView(tag: "待处理", color: .red)
            }
            
            HStack {
                TagView(tag: "大标签", color: .blue, fontSize: 14)
                TagView(tag: "小标签", color: .gray, fontSize: 9)
            }
        }
        .padding()
    }
}
#endif 