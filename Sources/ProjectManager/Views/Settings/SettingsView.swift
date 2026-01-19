import SwiftUI

// MARK: - 设置面板 - 重新设计

enum SettingsTab: String, CaseIterable {
    case editors = "编辑器"
    case autoTagging = "自动标签"
    case businessTagging = "业务标签"
    case other = "其他"

    var icon: String {
        switch self {
        case .editors: return "pencil"
        case .autoTagging: return "tag"
        case .businessTagging: return "doc.text.magnifyingglass"
        case .other: return "gear"
        }
    }
}

// MARK: - 主视图

struct SettingsView: View {
    @State private var selectedTab: SettingsTab = .editors
    @ObservedObject var tagManager: TagManager
    @ObservedObject var editorManager = AppOpenHelper.editorManager

    var body: some View {
        VStack(spacing: 0) {
            // 标题栏
            HStack {
                Text("偏好设置")
                    .font(.headline)
                    .fontWeight(.medium)

                Spacer()
            }
            .padding(16)
            .background(AppTheme.sidebarBackground)

            // Tab 选择器
            HStack(spacing: 0) {
                ForEach(SettingsTab.allCases, id: \.self) { tab in
                    Button(action: { selectedTab = tab }) {
                        HStack(spacing: 8) {
                            Image(systemName: tab.icon)
                                .font(.system(size: 14))
                            Text(tab.rawValue)
                                .font(.system(size: 13, weight: .medium))
                        }
                        .foregroundColor(selectedTab == tab ? AppTheme.text : AppTheme.secondaryText)
                        .padding(.horizontal, 20)
                        .padding(.vertical, 12)
                        .background(
                            RoundedRectangle(cornerRadius: 8)
                                .fill(selectedTab == tab ? AppTheme.accent.opacity(0.1) : Color.clear)
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(AppTheme.secondaryBackground)

            Divider()
                .background(AppTheme.divider)

            // 内容区域
            VStack(spacing: 0) {
                switch selectedTab {
                case .editors:
                    EditorsTabView(editorManager: editorManager)
                case .autoTagging:
                    AutoTaggingTabView(tagManager: tagManager)
                case .businessTagging:
                    BusinessTaggingTabView(tagManager: tagManager)
                case .other:
                    OtherTabView()
                }
            }
            .frame(maxHeight: .infinity)

            Spacer()
        }
        .frame(width: 700, height: 650)
        .background(AppTheme.background)
    }
}

// MARK: - 编辑器 Tab

struct EditorsTabView: View {
    @ObservedObject var editorManager: EditorManager

    @State private var showingAddEditor = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // 工具栏
                HStack {
                    Text("已配置的编辑器")
                        .font(.subheadline)
                        .fontWeight(.medium)

                    Spacer()

                    Button(action: { showingAddEditor = true }) {
                        HStack(spacing: 6) {
                            Image(systemName: "plus.circle")
                            Text("添加")
                        }
                    }
                    .font(.system(size: 13))
                    .buttonStyle(.borderedProminent)

                    Button(action: { editorManager.detectAvailableEditors() }) {
                        HStack(spacing: 6) {
                            Image(systemName: "arrow.clockwise")
                            Text("检测")
                        }
                    }
                    .font(.system(size: 13))
                    .buttonStyle(.bordered)
                }
                .padding(16)
                .background(AppTheme.secondaryBackground)
                .cornerRadius(8)

                // 编辑器列表
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(editorManager.editors.sorted { $0.displayOrder < $1.displayOrder }, id: \.id) { editor in
                        EditorRowView(editor: editor, editorManager: editorManager)
                    }
                }
            }
            .padding(16)
        }
        .sheet(isPresented: $showingAddEditor) {
            AddEditorView(editorManager: editorManager)
        }
    }
}

struct EditorRowView: View {
    let editor: EditorConfig
    @ObservedObject var editorManager: EditorManager

    var body: some View {
        HStack(spacing: 12) {
            // 可用性指示器
            Circle()
                .fill(editor.isAvailable ? Color.green.opacity(0.8) : Color.orange.opacity(0.8))
                .frame(width: 10, height: 10)

            VStack(alignment: .leading, spacing: 2) {
                Text(editor.name)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(AppTheme.text)

                if let commandPath = editor.commandPath {
                    Text(commandPath)
                        .font(.caption)
                        .foregroundColor(AppTheme.secondaryText)
                        .lineLimit(1)
                }
            }

            Spacer()

            // 默认标记
            if editor.isDefault {
                HStack(spacing: 4) {
                    Image(systemName: "star.fill")
                        .foregroundColor(.yellow)
                        .font(.system(size: 10))
                    Text("默认")
                        .font(.caption)
                        .foregroundColor(AppTheme.secondaryText)
                }
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
            .toggleStyle(SwitchToggleStyle(tint: AppTheme.accent))
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(AppTheme.background)
        .cornerRadius(6)
    }
}

// MARK: - 自动标签 Tab

struct AutoTaggingTabView: View {
    @ObservedObject var tagManager: TagManager

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                // 说明区域
                VStack(alignment: .leading, spacing: 16) {
                    HStack(spacing: 12) {
                        Image(systemName: "info.circle.fill")
                            .font(.system(size: 24))
                            .foregroundColor(AppTheme.accent)

                        VStack(alignment: .leading, spacing: 4) {
                            Text("自动标签功能")
                                .font(.headline)
                                .foregroundColor(AppTheme.text)

                            Text("请在「业务标签」标签页中配置和管理您的标签规则")
                                .font(.subheadline)
                                .foregroundColor(AppTheme.secondaryText)
                        }
                    }
                }
                .padding(20)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(AppTheme.secondaryBackground)
                .cornerRadius(12)

                // 快速操作
                VStack(alignment: .leading, spacing: 12) {
                    Text("快速操作")
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .foregroundColor(AppTheme.text)

                    HStack(spacing: 12) {
                        Button(action: {
                            tagManager.applyTaggingRulesToAllProjects()
                        }) {
                            HStack(spacing: 6) {
                                if tagManager.isRunningTaggingRules {
                                    ProgressView()
                                        .controlSize(.small)
                                    Text("正在打标...")
                                } else {
                                    Image(systemName: "bolt.fill")
                                    Text("立即运行打标")
                                }
                            }
                            .font(.system(size: 13))
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(tagManager.isRunningTaggingRules)

                        if let message = tagManager.lastTaggingRuleMessage {
                            Text(message)
                                .font(.caption)
                                .foregroundColor(AppTheme.accent)
                                .lineLimit(2)
                        }
                    }
                }
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(AppTheme.background)
                .cornerRadius(8)

                Divider()

                // 提示信息
                VStack(alignment: .leading, spacing: 8) {
                    Text("提示")
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .foregroundColor(AppTheme.text)

                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 8) {
                            Image(systemName: "arrow.right.circle")
                                .foregroundColor(AppTheme.secondaryIcon)
                                Text("在「业务标签」标签页中添加、编辑或删除规则")
                                .font(.caption)
                                .foregroundColor(AppTheme.secondaryText)
                        }

                        HStack(spacing: 8) {
                            Image(systemName: "arrow.right.circle")
                                .foregroundColor(AppTheme.secondaryIcon)
                                Text("点击「立即运行打标」应用所有已配置的规则")
                                .font(.caption)
                                .foregroundColor(AppTheme.secondaryText)
                        }

                        HStack(spacing: 8) {
                            Image(systemName: "arrow.right.circle")
                                .foregroundColor(AppTheme.secondaryIcon)
                            Text("规则仅对启用状态的规则生效")
                                .font(.caption)
                                .foregroundColor(AppTheme.secondaryText)
                        }
                    }
                }
                .padding(16)
            }
            .padding(16)
        }
    }
}

// MARK: - 其他 Tab（占位）

struct OtherTabView: View {
    var body: some View {
        VStack(spacing: 20) {
            Text("更多设置即将推出")
                .font(.subheadline)
                .foregroundColor(AppTheme.secondaryText)

            Image(systemName: "ellipsis.circle")
                .font(.system(size: 48))
                .foregroundColor(AppTheme.secondaryIcon)
        }
        .frame(maxHeight: .infinity)
    }
}

// MARK: - 业务标签 Tab

struct BusinessTaggingTabView: View {
    @ObservedObject var tagManager: TagManager
    @StateObject private var ruleStorage = BusinessTagger.getStorage()
    @State private var showingAddRule = false
    @State private var editingRule: BusinessTagRuleStorage.StoredRule?
    @State private var testProjectPath: String = ""
    @State private var testResults: [String] = []
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // 说明区域
                VStack(alignment: .leading, spacing: 8) {
                    Text("业务标签规则")
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .foregroundColor(AppTheme.text)
                    
                    Text("基于项目 README.md 等文档内容，自动识别业务场景并添加标签")
                        .font(.caption)
                        .foregroundColor(AppTheme.secondaryText)
                        .lineLimit(nil)
                }
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(AppTheme.secondaryBackground)
                .cornerRadius(8)
                
                // 工具栏
                HStack(spacing: 12) {
                    Text("已配置 \(ruleStorage.rules.count) 条规则")
                        .font(.caption)
                        .foregroundColor(AppTheme.secondaryText)
                    
                    Spacer()
                    
                    Button(action: {
                        tagManager.applyTaggingRulesToAllProjects()
                    }) {
                        HStack(spacing: 6) {
                            if tagManager.isRunningTaggingRules {
                                ProgressView()
                                    .controlSize(.small)
                                Text("正在打标...")
                            } else {
                                Image(systemName: "bolt.fill")
                                Text("立即运行打标")
                            }
                        }
                        .font(.system(size: 13))
                    }
                    .buttonStyle(.bordered)
                    .disabled(tagManager.isRunningTaggingRules)
                    
                    if let message = tagManager.lastTaggingRuleMessage {
                        Text(message)
                            .font(.caption)
                            .foregroundColor(AppTheme.accent)
                    }
                    
                    Button(action: { showingAddRule = true }) {
                        HStack(spacing: 6) {
                            Image(systemName: "plus.circle")
                            Text("添加规则")
                        }
                        .font(.system(size: 13))
                    }
                    .buttonStyle(.borderedProminent)
                }
                .padding(.horizontal, 16)
                
                // 规则列表（启用的在上，禁用的在下）
                VStack(spacing: 8) {
                    let sortedRules = ruleStorage.rules.sorted { $0.isEnabled && !$1.isEnabled }
                    ForEach(sortedRules) { rule in
                        BusinessRuleRowView(
                            rule: rule,
                            onToggle: { ruleStorage.toggleRule(rule) },
                            onEdit: { editingRule = rule },
                            onDelete: { ruleStorage.deleteRule(rule) }
                        )
                    }
                }
                .padding(.horizontal, 16)
                
                Divider()
                    .padding(.vertical, 8)
                
                // 测试区域
                VStack(alignment: .leading, spacing: 12) {
                    Text("测试业务标签")
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .foregroundColor(AppTheme.text)
                    
                    HStack(spacing: 8) {
                        TextField("项目路径", text: $testProjectPath)
                            .textFieldStyle(.roundedBorder)
                            .font(.system(size: 13))
                        
                        Button(action: { testBusinessTagging() }) {
                            Text("测试")
                                .font(.system(size: 13, weight: .medium))
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(testProjectPath.isEmpty)
                    }
                    
                    if !testResults.isEmpty {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("匹配的规则:")
                                .font(.caption)
                                .foregroundColor(AppTheme.secondaryText)
                            
                            ForEach(testResults, id: \.self) { ruleName in
                                HStack(spacing: 6) {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundColor(.green)
                                        .font(.system(size: 10))
                                    Text(ruleName)
                                        .font(.caption)
                                        .foregroundColor(AppTheme.text)
                                }
                            }
                        }
                        .padding(12)
                        .background(AppTheme.secondaryBackground)
                        .cornerRadius(8)
                    }
                }
                .padding(.horizontal, 16)
            }
            .padding(.vertical, 16)
        }
        .sheet(isPresented: $showingAddRule) {
            BusinessRuleEditView(
                rule: nil,
                onSave: { newRule in
                    ruleStorage.addRule(newRule)
                    showingAddRule = false
                },
                onCancel: { showingAddRule = false }
            )
        }
        .sheet(item: $editingRule) { rule in
            BusinessRuleEditView(
                rule: rule,
                onSave: { updatedRule in
                    ruleStorage.updateRule(updatedRule)
                    editingRule = nil
                },
                onCancel: { editingRule = nil }
            )
        }
    }
    
    private func testBusinessTagging() {
        let fm = FileManager.default
        guard fm.fileExists(atPath: testProjectPath) else {
            testResults = ["路径不存在"]
            return
        }
        
        testResults = BusinessTagger.debugRules(for: testProjectPath)
        if testResults.isEmpty {
            testResults = ["未匹配任何规则"]
        }
    }
}

// MARK: - 规则行视图

struct BusinessRuleRowView: View {
    let rule: BusinessTagRuleStorage.StoredRule
    let onToggle: () -> Void
    let onEdit: () -> Void
    let onDelete: () -> Void
    
    var body: some View {
        HStack(spacing: 12) {
            // 启用状态
            Circle()
                .fill(rule.isEnabled ? Color.green.opacity(0.8) : Color.gray.opacity(0.5))
                .frame(width: 10, height: 10)
            
            VStack(alignment: .leading, spacing: 4) {
                Text(rule.name)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(rule.isEnabled ? AppTheme.text : AppTheme.secondaryText)
                
                HStack(spacing: 4) {
                    Text("关键词: \(rule.keywords.prefix(3).joined(separator: ", "))")
                        .font(.caption)
                        .foregroundColor(AppTheme.secondaryText)
                    
                    if rule.keywords.count > 3 {
                        Text("+\(rule.keywords.count - 3)")
                            .font(.caption)
                            .foregroundColor(AppTheme.accent)
                    }
                }
                
                HStack(spacing: 4) {
                    ForEach(rule.tags, id: \.self) { tag in
                        Text(tag)
                            .font(.system(size: 10))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(AppTheme.accent.opacity(0.15))
                            .foregroundColor(AppTheme.accent)
                            .cornerRadius(4)
                    }
                }
            }
            
            Spacer()
            
            // 操作按钮
            HStack(spacing: 8) {
                Toggle("", isOn: .init(
                    get: { rule.isEnabled },
                    set: { _ in onToggle() }
                ))
                .toggleStyle(SwitchToggleStyle(tint: AppTheme.accent))
                
                Button(action: onEdit) {
                    Image(systemName: "pencil")
                        .font(.system(size: 12))
                        .foregroundColor(AppTheme.secondaryText)
                }
                .buttonStyle(.plain)
                
                Button(action: onDelete) {
                    Image(systemName: "trash")
                        .font(.system(size: 12))
                        .foregroundColor(.red.opacity(0.8))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(AppTheme.background)
        .cornerRadius(8)
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(AppTheme.divider, lineWidth: 1)
        )
    }
}

// MARK: - 规则编辑视图

struct BusinessRuleEditView: View {
    let rule: BusinessTagRuleStorage.StoredRule?
    let onSave: (BusinessTagRuleStorage.StoredRule) -> Void
    let onCancel: () -> Void
    
    @State private var name: String = ""
    @State private var keywordsText: String = ""
    @State private var tagsText: String = ""
    @State private var isEnabled: Bool = true
    
    private var isEditing: Bool { rule != nil }
    
    var body: some View {
        VStack(spacing: 0) {
            // 标题栏
            HStack {
                Text(isEditing ? "编辑规则" : "添加规则")
                    .font(.headline)
                    .fontWeight(.medium)
                
                Spacer()
                
                Button(action: onCancel) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 20))
                        .foregroundColor(AppTheme.secondaryText)
                }
                .buttonStyle(.plain)
            }
            .padding(16)
            .background(AppTheme.sidebarBackground)
            
            // 表单
            VStack(alignment: .leading, spacing: 20) {
                // 规则名称
                VStack(alignment: .leading, spacing: 6) {
                    Text("规则名称")
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .foregroundColor(AppTheme.text)
                    
                    TextField("例如：视频项目", text: $name)
                        .textFieldStyle(.roundedBorder)
                }
                
                // 关键词
                VStack(alignment: .leading, spacing: 6) {
                    Text("关键词（逗号分隔）")
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .foregroundColor(AppTheme.text)
                    
                    TextField("例如：video, 视频, streaming, ffmpeg", text: $keywordsText)
                        .textFieldStyle(.roundedBorder)
                    
                    Text("匹配 README.md 中包含这些关键词的项目")
                        .font(.caption)
                        .foregroundColor(AppTheme.secondaryText)
                }
                
                // 标签
                VStack(alignment: .leading, spacing: 6) {
                    Text("生成的标签（逗号分隔）")
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .foregroundColor(AppTheme.text)
                    
                    TextField("例如：视频, 多媒体", text: $tagsText)
                        .textFieldStyle(.roundedBorder)
                    
                    Text("匹配成功后自动添加这些标签")
                        .font(.caption)
                        .foregroundColor(AppTheme.secondaryText)
                }
                
                // 启用状态
                Toggle("启用此规则", isOn: $isEnabled)
                    .toggleStyle(SwitchToggleStyle(tint: AppTheme.accent))
                
                Spacer()
                
                // 按钮
                HStack {
                    Spacer()
                    
                    Button("取消") {
                        onCancel()
                    }
                    .buttonStyle(.bordered)
                    
                    Button(isEditing ? "保存" : "添加") {
                        saveRule()
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(name.isEmpty || keywordsText.isEmpty || tagsText.isEmpty)
                }
            }
            .padding(20)
        }
        .frame(width: 450, height: 400)
        .background(AppTheme.background)
        .onAppear {
            if let rule = rule {
                name = rule.name
                keywordsText = rule.keywords.joined(separator: ", ")
                tagsText = rule.tags.joined(separator: ", ")
                isEnabled = rule.isEnabled
            }
        }
    }
    
    private func saveRule() {
        let keywords = keywordsText
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        
        let tags = tagsText
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        
        let newRule = BusinessTagRuleStorage.StoredRule(
            id: rule?.id ?? UUID(),
            name: name,
            keywords: keywords,
            tags: tags,
            isEnabled: isEnabled
        )
        
        onSave(newRule)
    }
}

// MARK: - 预览

#if DEBUG
struct SettingsView_Previews: PreviewProvider {
    static var previews: some View {
        SettingsView()
    }
}
#endif
