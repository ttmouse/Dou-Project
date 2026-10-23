import SwiftUI

struct TagEditDialog: View {
    let title: String
    let originalName: String
    @Binding var isPresented: Bool
    let onSubmit: (String, Color) -> Void

    @State private var tagName: String
    @State private var errorMessage: String = ""
    @State private var selectedColor: Color = .blue
    @ObservedObject var tagManager: TagManager

    init(
        title: String,
        originalName: String = "",
        isPresented: Binding<Bool>,
        tagManager: TagManager,
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
        VStack(alignment: .leading, spacing: 20) {
            Text(title)
                .font(.system(size: 18, weight: .semibold))
                .foregroundColor(AppTheme.text)
                .frame(maxWidth: .infinity)

            TextField("标签名称", text: $tagName)
                .textFieldStyle(AppDialogTextFieldStyle())

            HStack {
                Text("标签颜色")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(AppTheme.text)
                Spacer()
                ColorPicker("", selection: $selectedColor)
                    .labelsHidden()
            }
            .frame(height: 32)

            HStack(spacing: 10) {
                Text("预览")
                    .font(.system(size: 12))
                    .foregroundColor(AppTheme.secondaryText)
                TagView(
                    tag: tagName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                        ? "标签名称"
                        : tagName,
                    color: selectedColor,
                    fontSize: 13,
                    isPreview: true
                )
            }
            .frame(height: 30)

            Text(errorMessage.isEmpty ? " " : errorMessage)
                .foregroundColor(.red)
                .font(.caption)
                .lineLimit(1)
                .frame(height: 16, alignment: .leading)

            HStack(spacing: 12) {
                Button("取消") {
                    isPresented = false
                }
                .font(.system(size: 14, weight: .medium))
                .buttonStyle(AppButtonStyle())
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
                .font(.system(size: 14, weight: .medium))
                .buttonStyle(AppButtonStyle(isPrimary: true))
                .keyboardShortcut(.return)
                .disabled(tagName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            .frame(maxWidth: .infinity)
        }
        .padding(24)
        .frame(width: 360)
        .background(AppTheme.secondaryBackground)
        .onExitCommand { isPresented = false }
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
