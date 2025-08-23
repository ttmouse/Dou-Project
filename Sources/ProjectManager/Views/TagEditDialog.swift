import SwiftUI

struct TagEditDialog: View {
    let title: String
    let originalName: String
    @Binding var isPresented: Bool
    let onSubmit: (String, Color) -> Void

    @State private var tagName: String
    @State private var errorMessage: String = ""
    @State private var selectedColor: Color = .blue
    @ObservedObject var tagManager: TagManagerAdapter

    init(
        title: String,
        originalName: String = "",
        isPresented: Binding<Bool>,
        tagManager: TagManagerAdapter,
        onSubmit: @escaping (String, Color) -> Void
    ) {
        self.title = title
        self.originalName = originalName
        self._isPresented = isPresented
        self.tagManager = tagManager
        self.onSubmit = onSubmit
        self._tagName = State(initialValue: originalName)
    }

    var body: some View {
        VStack(spacing: 16) {
            Text(title)
                .font(.headline)
                .foregroundColor(AppTheme.text)

            TextField("标签名称", text: $tagName)
                .textFieldStyle(CustomTextFieldStyle())
                .frame(width: 200)

            ColorPicker("标签颜色", selection: $selectedColor)
                .frame(width: 200)

            if !errorMessage.isEmpty {
                Text(errorMessage)
                    .foregroundColor(.red)
                    .font(.caption)
            }

            if !tagName.isEmpty {
                TagView(
                    tag: tagName,
                    color: selectedColor,
                    fontSize: 13,
                    isPreview: true
                )
            }

            HStack(spacing: 12) {
                Button("取消") {
                    isPresented = false
                }
                .buttonStyle(CustomButtonStyle(isPrimary: false))
                .keyboardShortcut(.escape)

                Button("确定") {
                    let name = tagName.trimmingCharacters(in: .whitespacesAndNewlines)
                    if name.isEmpty {
                        errorMessage = "标签名称不能为空"
                        return
                    }

                    // 检查是否已存在（排除自己）
                    if name != originalName && tagManager.allTags.contains(name) {
                        errorMessage = "标签名称已存在"
                        return
                    }

                    onSubmit(name, selectedColor)
                    isPresented = false
                }
                .buttonStyle(CustomButtonStyle(isPrimary: true))
                .keyboardShortcut(.return)
                .disabled(tagName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding()
        .background(AppTheme.secondaryBackground)
    }
}

// 自定义文本框样式
struct CustomTextFieldStyle: TextFieldStyle {
    func _body(configuration: TextField<Self._Label>) -> some View {
        configuration
            .padding(8)
            .background(AppTheme.cardBackground)
            .cornerRadius(6)
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(AppTheme.border, lineWidth: 1)
            )
            .foregroundColor(AppTheme.text)
    }
}

// 自定义按钮样式
struct CustomButtonStyle: ButtonStyle {
    let isPrimary: Bool
    
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(
                isPrimary ? AppTheme.accent : AppTheme.buttonBackground
            )
            .foregroundColor(AppTheme.text)
            .cornerRadius(6)
            .opacity(configuration.isPressed ? 0.8 : 1.0)
    }
}

//#if DEBUG
//    struct TagEditDialog_Previews: PreviewProvider {
//        static var previews: some View {
//            TagEditDialog(
//                title: "新建标签",
//                isPresented: .constant(true),
//                tagManager: TagManager(),
//                onSubmit: { _, _ in }
//            )
//            .frame(width: 300, height: 200)
//            .background(AppTheme.background)
//        }
//    }
//#endif
