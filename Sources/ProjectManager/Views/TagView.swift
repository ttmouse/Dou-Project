import SwiftUI

struct TagView: View {
    let tag: String
    let color: Color
    let fontSize: CGFloat
    var isSelected: Bool = false
    var isPreview: Bool = false  // 新增：是否为预览状态（新建标签时）
    var onDelete: (() -> Void)? = nil
    var onClick: (() -> Void)? = nil  // 新增：点击回调

    @State private var isHovered = false
    @State private var isPressed = false

    // 添加一个 id 来强制视图更新
    private var viewId: String {
        "\(tag)-\(color.description)-\(isSelected)-\(isPreview)"
    }

    var body: some View {
        Button(action: {
            // 添加点击反馈动画
            withAnimation(.easeInOut(duration: 0.1)) {
                isPressed = true
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                withAnimation(.easeInOut(duration: 0.1)) {
                    isPressed = false
                }
            }
            // 调用点击回调
            print("🏷️ TagView 点击: \(tag)")
            onClick?()
        }) {
            HStack(spacing: 4) {
                Text(tag)
                    .font(.system(size: fontSize))
                    .foregroundColor(textColor)

                if isHovered && onDelete != nil {
                    Button(action: {
                        onDelete?()
                    }) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: fontSize))
                            .foregroundColor(textColor.opacity(0.8))
                    }
                    .buttonStyle(.plain)
                    .transition(.opacity)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(backgroundColor)
                    .scaleEffect(isPressed ? 0.95 : 1.0)
            )
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.2)) {
                isHovered = hovering
            }
        }
        .scaleEffect(isHovered ? 1.05 : 1.0)
        .animation(.easeInOut(duration: 0.15), value: isHovered)
        .animation(.easeInOut(duration: 0.1), value: isPressed)
        .id(viewId)  // 使用动态 id 确保视图更新
    }
    
    // 计算文字颜色
    private var textColor: Color {
        if isSelected {
            return .white
        } else if isPreview {
            // 预览状态下使用更高对比度的文字颜色
            return color.opacity(1.0)
        } else {
            return color.opacity(0.9)
        }
    }
    
    // 计算背景颜色
    private var backgroundColor: Color {
        if isSelected {
            return color
        } else if isPreview {
            // 预览状态下使用更高对比度的背景颜色
            return color.opacity(0.3)
        } else {
            return color.opacity(0.2)
        }
    }
}

#if DEBUG
    struct TagView_Previews: PreviewProvider {
        static var previews: some View {
            Group {
                // 浅色背景预览
                VStack(spacing: 20) {
                    TagView(tag: "iOS", color: .blue, fontSize: 13)
                    TagView(tag: "Swift", color: .orange, fontSize: 13)
                    TagView(tag: "Selected", color: .green, fontSize: 13, isSelected: true)
                    TagView(tag: "Preview", color: .purple, fontSize: 13, isPreview: true)
                    TagView(
                        tag: "Deletable",
                        color: .purple,
                        fontSize: 13,
                        onDelete: {},
                        onClick: {}
                    )
                }
                .padding()
                .background(Color.white)
                
                // 深色背景预览
                VStack(spacing: 20) {
                    TagView(tag: "iOS", color: .blue, fontSize: 13)
                    TagView(tag: "Swift", color: .orange, fontSize: 13)
                    TagView(tag: "Selected", color: .green, fontSize: 13, isSelected: true)
                    TagView(tag: "Preview", color: .purple, fontSize: 13, isPreview: true)
                    TagView(
                        tag: "Deletable",
                        color: .purple,
                        fontSize: 13,
                        onDelete: {},
                        onClick: {}
                    )
                }
                .padding()
                .background(AppTheme.background)
            }
        }
    }
#endif
