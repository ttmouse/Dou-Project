import SwiftUI

/// 编辑器设置视图
struct EditorSettingsView: View {
    @ObservedObject var editorManager: EditorManager
    @Binding var showingAddEditor: Bool
    @State private var selectedEditor: EditorConfig?
    
    var body: some View {
        VStack(spacing: 0) {
            AutomationPermissionView()
                .padding()
                .background(AppTheme.secondaryBackground)
            
            Divider()
                .background(AppTheme.border)
            
            HSplitView {
                // 左侧编辑器列表
                VStack(alignment: .leading, spacing: 0) {
                    // 工具栏
                    HStack {
                        Text("已配置的编辑器")
                            .font(.subheadline)
                            .fontWeight(.medium)
                        
                        Spacer()
                        
                        // 添加编辑器按钮
                        Button(action: {
                            showingAddEditor = true
                        }) {
                            Image(systemName: "plus")
                        }
                        .buttonStyle(.borderless)
                        .help("添加自定义编辑器")
                        
                        // 检测编辑器按钮
                        Button(action: {
                            editorManager.detectAvailableEditors()
                        }) {
                            Image(systemName: "arrow.clockwise")
                        }
                        .buttonStyle(.borderless)
                        .help("检测可用编辑器")
                    }
                    .padding(.horizontal)
                    .padding(.vertical, 8)
                    .background(AppTheme.sidebarBackground)
                    
                    // 编辑器列表
                    List(selection: $selectedEditor) {
                        ForEach(editorManager.editors.sorted { $0.displayOrder < $1.displayOrder }, id: \.id) { editor in
                            EditorListRow(
                                editor: editor,
                                isSelected: selectedEditor?.id == editor.id,
                                editorManager: editorManager
                            )
                            .tag(editor)
                        }
                        .onMove { source, destination in
                            editorManager.moveEditors(from: source, to: destination)
                        }
                    }
                    .listStyle(.sidebar)
                }
                .frame(minWidth: 250)
                
                // 右侧详细配置
                if let editor = selectedEditor {
                    EditorDetailView(editor: editor, editorManager: editorManager)
                        .frame(minWidth: 300)
                } else {
                    VStack {
                        Image(systemName: "app.dashed")
                            .font(.system(size: 48))
                            .foregroundColor(.secondary)
                        Text("选择一个编辑器以查看配置")
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

/// 编辑器列表行
struct EditorListRow: View {
    let editor: EditorConfig
    let isSelected: Bool
    @ObservedObject var editorManager: EditorManager
    
    var body: some View {
        HStack {
            // 可用性指示器
            Circle()
                .fill(editor.isAvailable ? Color.green : Color.orange)
                .frame(width: 8, height: 8)
            
            // 编辑器名称
            Text(editor.name)
                .font(.system(size: 13))
                .foregroundColor(AppTheme.text)
            
            Spacer()
            
            // 默认标记
            if editor.isDefault {
                Image(systemName: "star.fill")
                    .foregroundColor(.yellow)
                    .font(.system(size: 10))
            }
            
            // 启用/禁用开关
            Toggle("", isOn: .init(
                get: { editor.isEnabled },
                set: { newValue in
                    var updatedEditor = editor
                    updatedEditor.isEnabled = newValue
                    editorManager.updateEditor(updatedEditor)
                }
            ))
            .toggleStyle(.switch)
            .controlSize(.mini)
        }
        .padding(.vertical, 2)
    }
}

/// 编辑器详细配置视图
struct EditorDetailView: View {
    let editor: EditorConfig
    @ObservedObject var editorManager: EditorManager
    @State private var editedEditor: EditorConfig
    @State private var hasChanges = false
    
    init(editor: EditorConfig, editorManager: EditorManager) {
        self.editor = editor
        self.editorManager = editorManager
        self._editedEditor = State(initialValue: editor)
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // 标题
            HStack {
                Text(editor.name)
                    .font(.title2)
                    .fontWeight(.medium)
                
                Spacer()
                
                // 设为默认按钮
                if !editor.isDefault {
                    Button("设为默认") {
                        editorManager.setDefaultEditor(editor)
                    }
                    .buttonStyle(.bordered)
                }
            }
            
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    // 基本信息
                    GroupBox("基本信息") {
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Text("名称:")
                                    .frame(width: 80, alignment: .leading)
                                TextField("编辑器名称", text: $editedEditor.name)
                                    .textFieldStyle(.roundedBorder)
                                    .onChange(of: editedEditor.name) { _ in hasChanges = true }
                            }
                            
                            HStack {
                                Text("Bundle ID:")
                                    .frame(width: 80, alignment: .leading)
                                TextField("应用包标识符", text: .init(
                                    get: { editedEditor.bundleId ?? "" },
                                    set: { editedEditor.bundleId = $0.isEmpty ? nil : $0 }
                                ))
                                .textFieldStyle(.roundedBorder)
                                .onChange(of: editedEditor.bundleId) { _ in hasChanges = true }
                            }
                            
                            HStack {
                                Text("命令路径:")
                                    .frame(width: 80, alignment: .leading)
                                TextField("命令行工具路径", text: .init(
                                    get: { editedEditor.commandPath ?? "" },
                                    set: { editedEditor.commandPath = $0.isEmpty ? nil : $0 }
                                ))
                                .textFieldStyle(.roundedBorder)
                                .onChange(of: editedEditor.commandPath) { _ in hasChanges = true }
                            }
                        }
                        .padding(.vertical, 4)
                    }
                    
                    // 状态信息
                    GroupBox("状态") {
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text("可用性:")
                                Circle()
                                    .fill(editor.isAvailable ? Color.green : Color.orange)
                                    .frame(width: 8, height: 8)
                                Text(editor.isAvailable ? "可用" : "不可用")
                                    .foregroundColor(editor.isAvailable ? .green : .orange)
                                Spacer()
                            }
                            
                            HStack {
                                Text("状态:")
                                Text(editor.isEnabled ? "已启用" : "已禁用")
                                    .foregroundColor(editor.isEnabled ? .green : .secondary)
                                Spacer()
                            }
                            
                            if editor.isDefault {
                                HStack {
                                    Text("默认:")
                                    Image(systemName: "star.fill")
                                        .foregroundColor(.yellow)
                                    Text("默认编辑器")
                                    Spacer()
                                }
                            }
                        }
                        .padding(.vertical, 4)
                    }
                    
                    // 操作按钮
                    HStack {
                        if hasChanges {
                            Button("保存更改") {
                                editorManager.updateEditor(editedEditor)
                                hasChanges = false
                            }
                            .buttonStyle(.borderedProminent)
                            
                            Button("撤销更改") {
                                editedEditor = editor
                                hasChanges = false
                            }
                            .buttonStyle(.bordered)
                        }
                        
                        Spacer()
                        
                        // 测试按钮
                        Button("测试打开") {
                            // TODO: 实现测试打开功能
                        }
                        .buttonStyle(.bordered)
                        
                        // 删除按钮
                        if !EditorConfig.defaultEditors.contains(where: { $0.name == editor.name }) {
                            Button("删除") {
                                editorManager.deleteEditor(editor)
                            }
                            .buttonStyle(.bordered)
                            .foregroundColor(.red)
                        }
                    }
                }
                .padding()
            }
            
            Spacer()
        }
        .padding()
        .onAppear {
            editedEditor = editor
            hasChanges = false
        }
        .onChange(of: editor) { newEditor in
            editedEditor = newEditor
            hasChanges = false
        }
    }
}

/// 终端授权状态视图
struct AutomationPermissionView: View {
    @State private var status: AutomationPermissionStatus = .unknown
    
    var body: some View {
        GroupBox("终端授权") {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 12) {
                    Image(systemName: status.systemImageName)
                        .font(.system(size: 24))
                        .foregroundColor(status.tintColor)
                    
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Terminal AppleScript 权限")
                            .font(.subheadline)
                            .fontWeight(.medium)
                        Text("ProjectManager 需要向 Terminal 发送 Apple 事件以启动快捷命令。")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    
                    Spacer()
                    
                    Text(status.localizedDescription)
                        .font(.headline)
                        .foregroundColor(status.tintColor)
                }
                
                HStack(spacing: 12) {
                    Button("请求授权") {
                        refreshStatus(prompt: true)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(status == .authorized)
                    
                    Button("打开系统设置…") {
                        openAutomationSettings()
                    }
                    .buttonStyle(.bordered)
                    
                    Button("刷新状态") {
                        refreshStatus()
                    }
                    .buttonStyle(.bordered)
                    
                    Spacer()
                }
            }
            .padding(.vertical, 4)
        }
        .onAppear {
            refreshStatus()
        }
    }
    
    private func refreshStatus(prompt: Bool = false) {
        status = AutomationPermissionManager.terminalPermissionStatus(promptIfNeeded: prompt)
    }
    
    private func openAutomationSettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Automation") else {
            return
        }
        NSWorkspace.shared.open(url)
    }
}

private extension AutomationPermissionStatus {
    var tintColor: Color {
        switch self {
        case .authorized:
            return .green
        case .denied:
            return .red
        case .notDetermined:
            return .orange
        case .unknown:
            return .gray
        }
    }
}

#if DEBUG
struct EditorSettingsView_Previews: PreviewProvider {
    static var previews: some View {
        EditorSettingsView(
            editorManager: EditorManager(),
            showingAddEditor: .constant(false)
        )
        .frame(width: 600, height: 400)
    }
}
#endif
