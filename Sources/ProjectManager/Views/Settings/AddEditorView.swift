import SwiftUI

/// 添加编辑器对话框
struct AddEditorView: View {
    @ObservedObject var editorManager: EditorManager
    @Environment(\.presentationMode) var presentationMode
    
    @State private var name: String = ""
    @State private var bundleId: String = ""
    @State private var commandPath: String = ""
    @State private var arguments: String = ""
    @State private var selectedPreset: EditorPreset?
    
    var body: some View {
        VStack(spacing: 20) {
            // 标题
            Text("添加自定义编辑器")
                .font(.title2)
                .fontWeight(.medium)
            
            // 预设选择
            VStack(alignment: .leading) {
                Text("快速添加预设编辑器:")
                    .font(.headline)
                
                LazyVGrid(columns: [
                    GridItem(.flexible()),
                    GridItem(.flexible()),
                    GridItem(.flexible())
                ], spacing: 12) {
                    ForEach(EditorPreset.allPresets, id: \.name) { preset in
                        Button(action: {
                            selectedPreset = preset
                            applyPreset(preset)
                        }) {
                            VStack {
                                Image(systemName: preset.icon)
                                    .font(.title2)
                                    .foregroundColor(.accentColor)
                                Text(preset.name)
                                    .font(.caption)
                                    .multilineTextAlignment(.center)
                            }
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(
                                RoundedRectangle(cornerRadius: 8)
                                    .fill(selectedPreset?.name == preset.name ? Color.accentColor.opacity(0.1) : Color.secondary.opacity(0.1))
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 8)
                                    .stroke(selectedPreset?.name == preset.name ? Color.accentColor : Color.clear, lineWidth: 2)
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            
            Divider()
            
            // 手动配置
            VStack(alignment: .leading, spacing: 12) {
                Text("或手动配置:")
                    .font(.headline)
                
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("名称:")
                            .frame(width: 80, alignment: .leading)
                        TextField("编辑器名称", text: $name)
                            .textFieldStyle(.roundedBorder)
                    }
                    
                    HStack {
                        Text("Bundle ID:")
                            .frame(width: 80, alignment: .leading)
                        TextField("如: com.microsoft.VSCode", text: $bundleId)
                            .textFieldStyle(.roundedBorder)
                    }
                    
                    HStack {
                        Text("命令路径:")
                            .frame(width: 80, alignment: .leading)
                        TextField("如: /usr/local/bin/code", text: $commandPath)
                            .textFieldStyle(.roundedBorder)
                    }
                    
                    HStack {
                        Text("启动参数:")
                            .frame(width: 80, alignment: .leading)
                        TextField("可选，如: --wait", text: $arguments)
                            .textFieldStyle(.roundedBorder)
                    }
                }
            }
            
            // 按钮
            HStack {
                Button("取消") {
                    presentationMode.wrappedValue.dismiss()
                }
                .keyboardShortcut(.escape)
                
                Spacer()
                
                Button("添加") {
                    addEditor()
                }
                .buttonStyle(.borderedProminent)
                .disabled(name.isEmpty || (bundleId.isEmpty && commandPath.isEmpty))
                .keyboardShortcut(.return)
            }
        }
        .padding(24)
        .frame(width: 500)
        .background(AppTheme.background)
    }
    
    private func applyPreset(_ preset: EditorPreset) {
        name = preset.name
        bundleId = preset.bundleId ?? ""
        commandPath = preset.commandPath ?? ""
        arguments = preset.arguments.joined(separator: " ")
    }
    
    private func addEditor() {
        let argumentsArray = arguments.split(separator: " ").map { String($0) }
        
        editorManager.addCustomEditor(
            name: name,
            bundleId: bundleId.isEmpty ? nil : bundleId,
            commandPath: commandPath.isEmpty ? nil : commandPath,
            arguments: argumentsArray
        )
        
        presentationMode.wrappedValue.dismiss()
    }
}

/// 编辑器预设
struct EditorPreset {
    let name: String
    let bundleId: String?
    let commandPath: String?
    let arguments: [String]
    let icon: String
    
    static let allPresets: [EditorPreset] = [
        EditorPreset(
            name: "Nova",
            bundleId: "com.panic.Nova",
            commandPath: nil,
            arguments: [],
            icon: "star"
        ),
        EditorPreset(
            name: "Xcode",
            bundleId: "com.apple.dt.Xcode",
            commandPath: "/usr/bin/xed",
            arguments: [],
            icon: "hammer"
        ),
        EditorPreset(
            name: "TextMate",
            bundleId: "com.macromates.TextMate",
            commandPath: "/usr/local/bin/mate",
            arguments: [],
            icon: "doc.text"
        ),
        EditorPreset(
            name: "BBEdit",
            bundleId: "com.barebones.bbedit",
            commandPath: "/usr/local/bin/bbedit",
            arguments: [],
            icon: "pencil"
        ),
        EditorPreset(
            name: "Neovim",
            bundleId: nil,
            commandPath: "/usr/local/bin/nvim",
            arguments: [],
            icon: "terminal"
        ),
        EditorPreset(
            name: "Emacs",
            bundleId: "org.gnu.Emacs",
            commandPath: "/usr/local/bin/emacs",
            arguments: [],
            icon: "keyboard"
        )
    ]
}

/// 通用设置视图占位符
struct GeneralSettingsView: View {
    var body: some View {
        VStack {
            Text("通用设置")
                .font(.title2)
            Text("暂无通用设置项")
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

#if DEBUG
struct AddEditorView_Previews: PreviewProvider {
    static var previews: some View {
        AddEditorView(editorManager: EditorManager())
    }
}
#endif