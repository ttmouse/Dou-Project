import SwiftUI

struct TagEditDialog: View {
    let title: String
    let originalName: String
    @Binding var isPresented: Bool
    let onSubmit: (String) -> Void

    @State private var tagName: String
    @State private var errorMessage: String = ""
    @ObservedObject var tagManager: TagManager

    init(
        title: String,
        originalName: String = "",
        isPresented: Binding<Bool>,
        tagManager: TagManager,
        onSubmit: @escaping (String) -> Void
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

            TextField("标签名称", text: $tagName)
                .textFieldStyle(.roundedBorder)
                .frame(width: 200)

            if !errorMessage.isEmpty {
                Text(errorMessage)
                    .foregroundColor(.red)
                    .font(.caption)
            }

            HStack(spacing: 12) {
                Button("取消") {
                    isPresented = false
                }
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

                    onSubmit(name)
                    isPresented = false
                }
                .keyboardShortcut(.return)
                .disabled(tagName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding()
    }
}

#if DEBUG
    struct TagEditDialog_Previews: PreviewProvider {
        static var previews: some View {
            TagEditDialog(
                title: "新建标签",
                isPresented: .constant(true),
                tagManager: TagManager(),
                onSubmit: { _ in }
            )
        }
    }
#endif
