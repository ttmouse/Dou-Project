import SwiftUI

struct TagView: View {
    let tag: String
    let color: Color
    let fontSize: CGFloat
    var isSelected: Bool = false
    var onDelete: (() -> Void)? = nil

    @State private var isHovered = false

    var body: some View {
        HStack(spacing: 4) {
            Text(tag)
                .font(.system(size: fontSize))
                .foregroundColor(isSelected ? .white : color)

            if isHovered && onDelete != nil {
                Button(action: {
                    onDelete?()
                }) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: fontSize))
                        .foregroundColor(isSelected ? .white.opacity(0.8) : color.opacity(0.8))
                }
                .buttonStyle(.plain)
                .transition(.opacity)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(isSelected ? color : color.opacity(0.15))
        )
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.2)) {
                isHovered = hovering
            }
        }
    }
}

#if DEBUG
    struct TagView_Previews: PreviewProvider {
        static var previews: some View {
            VStack(spacing: 20) {
                TagView(tag: "iOS", color: .blue, fontSize: 13)
                TagView(tag: "Swift", color: .orange, fontSize: 13)
                TagView(tag: "Selected", color: .green, fontSize: 13, isSelected: true)
                TagView(
                    tag: "Deletable",
                    color: .purple,
                    fontSize: 13,
                    onDelete: {}
                )
            }
            .padding()
        }
    }
#endif
