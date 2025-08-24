import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// 项目卡片组件，用于在网格视图中显示项目信息
struct ProjectCard: View {
    // MARK: - 属性
    
    let project: Project
    let isSelected: Bool
    let selectedCount: Int  // 添加选中数量
    let selectedProjects: Set<UUID>  // 添加选中的项目集合
    @ObservedObject var tagManager: TagManager
    @ObservedObject var editorManager: EditorManager  // 添加对编辑器管理器的观察
    @State private var isEditingTags = false
    let onTagSelected: (String) -> Void
    let onSelect: (Bool) -> Void

    // MARK: - 子视图
    
    /// 头部视图，包含项目名称和操作按钮
    private var headerView: some View {
        HStack {
            Text(project.name)
                .font(AppTheme.titleFont)
                .foregroundColor(AppTheme.text)
                .lineLimit(1)

            Spacer()

            // 编辑标签按钮
            Button(action: { isEditingTags = true }) {
                Image(systemName: "tag")
                    .foregroundColor(AppTheme.secondaryIcon)
            }
            .buttonStyle(.plain)
            .help("编辑标签")

            // 在 Cursor 中打开按钮
            Button(action: { AppOpenHelper.openInCursor(path: project.path) }) {
                Image(systemName: "cursorarrow.rays")
                    .foregroundColor(AppTheme.secondaryIcon)
            }
            .buttonStyle(.plain)
            .help("在 Cursor 中打开")

            // 打开文件夹按钮
            Button(action: { AppOpenHelper.openInFinder(path: project.path) }) {
                Image(systemName: "folder")
                    .foregroundColor(AppTheme.folderIcon)
            }
            .buttonStyle(.plain)
            .help("打开文件夹")
        }
    }

    /// 路径视图，显示项目路径
    private var pathView: some View {
        Text(project.path)
            .font(AppTheme.captionFont)
            .foregroundColor(AppTheme.secondaryText)
            .lineLimit(1)
    }

    /// 信息视图，显示项目日期和Git提交次数
    private var infoView: some View {
        HStack {
            // 日期信息
            HStack(spacing: 4) {
                Image(systemName: "calendar")
                    .foregroundColor(AppTheme.secondaryIcon)
                Text(project.lastModified, style: .date)
                    + Text(" ")
                    + Text(project.lastModified, style: .time)
            }
            .font(AppTheme.captionFont)
            .foregroundColor(AppTheme.secondaryText)

            Spacer()

            // Git 提交次数
            if let gitInfo = project.gitInfo {
                HStack(spacing: 4) {
                    Text("\(gitInfo.commitCount)")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(AppTheme.accent)
                    Text("次提交")
                        .font(AppTheme.captionFont)
                        .foregroundColor(AppTheme.secondaryText)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(AppTheme.accent.opacity(0.1))
                .cornerRadius(6)
            }
        }
    }

    /// 标签视图，显示项目相关标签
    private var tagsView: some View {
        Group {
            if !project.tags.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 4) {
                        ForEach(Array(project.tags).sorted(), id: \.self) { tag in
                            TagView(
                                tag: tag,
                                color: tagManager.getColor(for: tag),
                                fontSize: 13,
                                onDelete: {
                                    tagManager.removeTagFromProject(projectId: project.id, tag: tag)
                                }
                            )
                            .onTapGesture {
                                onTagSelected(tag)
                            }
                            .id("\(tag)-\(tagManager.colorManager.getColor(for: tag)?.description ?? "")")
                        }
                    }
                }
            } else {
                EmptyView()
            }
        }
    }
    
    // MARK: - 右键菜单
    
    @ViewBuilder
    private var contextMenuContent: some View {
        // 打开方式菜单
        Menu("打开方式") {
            let sortedEditors = editorManager.editors.sorted { $0.displayOrder < $1.displayOrder }
            // let _ = print("🎯 构建右键菜单，编辑器数量: \(sortedEditors.count)")
            // let _ = print("📋 编辑器列表: \(sortedEditors.map { "\($0.name)(\($0.isEnabled ? "✓" : "✗"))" })")
            
            ForEach(sortedEditors, id: \.id) { editor in
                Button(action: {
                    AppOpenHelper.openInEditor(editor, path: project.path)
                }) {
                    HStack {
                        Label(editor.name, systemImage: getEditorIcon(for: editor))
                        Spacer()
                        
                        // 状态指示器
                        if !editor.isEnabled {
                            Image(systemName: "minus.circle")
                                .foregroundColor(.gray)
                                .font(.caption)
                        } else if !editor.isAvailable {
                            Image(systemName: "exclamationmark.triangle")
                                .foregroundColor(.orange)
                                .font(.caption)
                        } else {
                            Image(systemName: "checkmark.circle")
                                .foregroundColor(.green)
                                .font(.caption)
                        }
                    }
                }
                .disabled(!editor.isEnabled || !editor.isAvailable)
            }
            
            if editorManager.editors.isEmpty {
                Divider()
                Text("无配置的编辑器")
                    .foregroundColor(.secondary)
                    .font(.caption)
            }
        }
        
        Divider()
        
        // 系统操作
        Button(action: {
            AppOpenHelper.performSystemAction(.openInTerminal, path: project.path)
        }) {
            Label("在终端打开", systemImage: "terminal")
        }
        
        Button(action: {
            AppOpenHelper.performSystemAction(.showInFinder, path: project.path)
        }) {
            Label("在Finder中显示", systemImage: "folder")
        }
        
        Button(action: {
            AppOpenHelper.performSystemAction(.copyPath, path: project.path)
        }) {
            Label("复制路径", systemImage: "doc.on.doc")
        }
        
        Button(action: {
            AppOpenHelper.performSystemAction(.copyProjectInfo, path: project.path)
        }) {
            Label("复制项目信息", systemImage: "info.circle")
        }
    }
    
    // MARK: - 辅助方法
    
    private func getEditorIcon(for editor: EditorConfig) -> String {
        switch editor.name.lowercased() {
        case "cursor":
            return "cursorarrow.rays"
        case "visual studio code", "vscode", "code":
            return "chevron.left.slash.chevron.right"
        case "sublime text":
            return "doc.text"
        case "ghostty":
            return "terminal.fill"
        default:
            return "app"
        }
    }

    // MARK: - 主视图
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // 标题部分 - 固定于顶部位置
            headerView
                .padding(.bottom, 8)
                .padding(.top, 16) // 固定标题到顶部的距离
            
            // 路径部分
            pathView
                .padding(.bottom, 8)
            
            // 信息部分
            infoView
                .padding(.bottom, 8)
            
            // 标签部分（如果有）
            if !project.tags.isEmpty {
                tagsView
                    .padding(.bottom, 4)
            }
            
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 16)
        .frame(height: AppTheme.cardHeight)
        .background(
            RoundedRectangle(cornerRadius: AppTheme.cardCornerRadius)
                .fill(isSelected ? AppTheme.cardSelectedBackground : AppTheme.cardBackground)
        )
        .overlay(
            RoundedRectangle(cornerRadius: AppTheme.cardCornerRadius)
                .strokeBorder(
                    isSelected ? AppTheme.cardSelectedBorder : AppTheme.cardBorder,
                    lineWidth: isSelected
                        ? AppTheme.cardSelectedBorderWidth : AppTheme.cardBorderWidth
                )
        )
        .shadow(
            color: isSelected ? AppTheme.cardSelectedShadow : AppTheme.cardShadow,
            radius: isSelected ? AppTheme.cardSelectedShadowRadius : 4,
            x: 0,
            y: 2
        )
        .onTapGesture {
            let flags = NSEvent.modifierFlags
            onSelect(flags.contains(.shift))
        }
        .onDrag {
            // 确保当前项目被选中
            let flags = NSEvent.modifierFlags
            let isShiftPressed = flags.contains(.shift)
            let isCommandPressed = flags.contains(.command)
            
            // 如果没有按下修饰键，且当前项目未被选中，则只选中当前项目
            if !isShiftPressed && !isCommandPressed && !isSelected {
                onSelect(false)
            }
            
            // 创建包含所有选中项目的数据
            let selectedIds = selectedCount > 1 ? selectedProjects : [project.id]
            let data = try? JSONEncoder().encode(selectedIds)
            return NSItemProvider(item: data as NSData?, typeIdentifier: UTType.data.identifier)
        } preview: {
            // 拖拽预览
            HStack(spacing: 4) {
                Image(systemName: "folder.fill")
                    .foregroundColor(AppTheme.folderIcon)
                if selectedCount > 1 {
                    Text("\(selectedCount) 个项目")
                        .foregroundColor(AppTheme.text)
                } else {
                    Text(project.name)
                        .foregroundColor(AppTheme.text)
                        .lineLimit(1)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(AppTheme.cardBackground)
            .cornerRadius(4)
            .frame(maxWidth: 200)
        }
        .contextMenu {
            contextMenuContent
        }
        .sheet(isPresented: $isEditingTags) {
            TagEditorView(project: project, tagManager: tagManager)
        }
    }
}

#if DEBUG
struct ProjectCard_Previews: PreviewProvider {
    static var previews: some View {
        ProjectCard(
            project: Project(
                id: UUID(),
                name: "示例项目",
                path: "/Users/example/Projects/demo",
                lastModified: Date(),
                tags: ["Swift", "iOS"]
            ),
            isSelected: false,
            selectedCount: 1,
            selectedProjects: Set(),
            tagManager: {
                let container = TagManager()
                return TagManager()
            }(),
            editorManager: EditorManager(),
            onTagSelected: { _ in },
            onSelect: { _ in }
        )
        .padding()
    }
}
#endif
