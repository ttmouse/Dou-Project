import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// 用于视图显示的轻量级标签数据
struct TagDisplayData: Equatable, Identifiable {
    var id: String { name }
    let name: String
    let color: Color
}

/// 项目卡片组件，用于在网格视图中显示项目信息
struct ProjectCard: View, Equatable {
    // MARK: - 属性
    
    let project: Project
    let isSelected: Bool
    // 移除直接传递的 selectedProjects 集合，改用闭包获取，避免每次选择变化都触发所有卡片重绘
    let getSelectedProjects: () -> Set<UUID>
    
    // Decoupled from TagManager: only holds a reference for actions, doesn't observe changes
    let tagManager: TagManager
    let displayTags: [TagDisplayData]
    
    @ObservedObject var editorManager: EditorManager
    @State private var isEditingTags = false
    @State private var isRenamingProject = false
    let onTagSelected: (String) -> Void
    let onSelect: (Bool) -> Void
    let onShowDetail: () -> Void

    @State private var showPortConflictAlert = false
    @State private var conflictPort = 0
    
    // MARK: - 子视图
    
    /// 头部视图，包含项目名称和操作按钮
    private var headerView: some View {
        HStack {
            Text(project.name)
                .font(AppTheme.titleFont)
                .foregroundColor(AppTheme.text)
                .lineLimit(1)

            Spacer()

            // 快速启动按钮
            if project.startupCommand != nil {
                Button(action: handleQuickStart) {
                    Image(systemName: "play.fill")
                    .foregroundColor(.green)
                }
                .buttonStyle(.plain)
                .help("快速启动 (端口: \(project.customPort.map(String.init) ?? "默认"))")
            }

            // 编辑标签按钮
            Button(action: { isEditingTags = true }) {
                Image(systemName: "tag")
                    .foregroundColor(AppTheme.secondaryIcon)
            }
            .buttonStyle(.plain)
            .help("编辑标签")

            // 在默认编辑器中打开按钮
            Button(action: { AppOpenHelper.openInDefaultEditor(path: project.path) }) {
                Image(systemName: "cursorarrow.rays")
                    .foregroundColor(AppTheme.secondaryIcon)
            }
            .buttonStyle(.plain)
            .help("在默认编辑器中打开")

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
                Text(ProjectCard.dateTimeFormatter.string(from: project.lastModified))
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
            if !displayTags.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 4) {
                        ForEach(displayTags) { tagData in
                            TagView(
                                tag: tagData.name,
                                color: tagData.color,
                                fontSize: 13,
                                onDelete: {
                                    tagManager.removeTagFromProject(projectId: project.id, tag: tagData.name)
                                },
                                onClick: {
                                    print("🏷️ ProjectCard onClick: \(tagData.name)")
                                    onTagSelected(tagData.name)
                                }
                            )
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
                                .foregroundColor(AppTheme.secondaryText)
                                .font(.caption)
                        } else if !editor.isAvailable {
                            Image(systemName: "exclamationmark.triangle")
                                .foregroundColor(AppTheme.warning)
                                .font(.caption)
                        } else {
                            Image(systemName: "checkmark.circle")
                                .foregroundColor(AppTheme.success)
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
        
        Divider()
        
        Button(action: {
            tagManager.refreshSingleProject(project.id)
        }) {
            Label("刷新项目", systemImage: "arrow.clockwise")
        }
        
        Button(action: {
            isRenamingProject = true
        }) {
            Label("重命名项目", systemImage: "pencil")
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
    
    private func handleQuickStart() {
        let result = ProjectRunner.run(project)
        switch result {
        case .success(_):
            break
        case .failure(let error):
            print("启动失败: \(error)")
        case .portBusy(let port, _):
            conflictPort = port
            showPortConflictAlert = true
        }
    }

    // MARK: - 主视图
    
    // MARK: - Equatable
    
    static func == (lhs: ProjectCard, rhs: ProjectCard) -> Bool {
        return lhs.project == rhs.project &&
               lhs.isSelected == rhs.isSelected &&
               lhs.displayTags == rhs.displayTags && // Compare explicit data
               lhs.isEditingTags == rhs.isEditingTags &&
               lhs.isRenamingProject == rhs.isRenamingProject &&
               lhs.showPortConflictAlert == rhs.showPortConflictAlert
    }

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
            if !displayTags.isEmpty {
                tagsView
                    .padding(.bottom, 4)
                    .allowsHitTesting(true)  // 确保标签区域可以接收点击
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
            let isShiftPressed = flags.contains(.shift)
            let isCommandPressed = flags.contains(.command)
            
            if isShiftPressed || isCommandPressed {
                // 按住修饰键时，执行多选逻辑
                onSelect(isShiftPressed)
            } else {
                // 单击时打开详情侧边栏
                onShowDetail()
            }
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
            
            // 获取最新选中状态
            let selectedProjects = getSelectedProjects()
            let selectedCount = selectedProjects.count
            
            // 创建包含所有选中项目的数据
            let selectedIds = selectedCount > 1 ? selectedProjects : [project.id]
            let data = try? JSONEncoder().encode(selectedIds)
            return NSItemProvider(item: data as NSData?, typeIdentifier: UTType.data.identifier)
        } preview: {
            // 拖拽预览
            let selectedCount = getSelectedProjects().count
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
            .frame(width: 200, height: 28)
        }
        .contextMenu {
            contextMenuContent
        }
        .sheet(isPresented: $isEditingTags) {
            TagEditorView(project: project, tagManager: tagManager)
        }
        .sheet(isPresented: $isRenamingProject) {
            ProjectRenameDialog(
                project: project,
                isPresented: $isRenamingProject,
                tagManager: tagManager
            ) { result in
                // 处理重命名结果
                switch result {
                case .success():
                    print("✅ 项目重命名成功")
                case .failure(let error):
                    print("❌ 项目重命名失败: \(error.localizedDescription)")
                }
            }
        }
        .alert("端口冲突", isPresented: $showPortConflictAlert) {
            Button("终止占用进程并启动", role: .destructive) {
                _ = ProjectRunner.killProcessAndRun(project)
            }
            Button("使用随机端口启动") {
                _ = ProjectRunner.run(project, useRandomPort: true)
            }
            Button("取消", role: .cancel) { }
        } message: {
            Text("端口 \(conflictPort) 正在被使用。您想如何处理？")
        }
        // 使用 drawingGroup 优化复杂视图渲染，特别是阴影
        // 注意：drawingGroup 会将视图渲染为位图，对于包含大量文本的视图可能需要测试清晰度
        // 在这里主要是为了优化阴影和圆角的重绘性能
        // .drawingGroup() 
        // 暂时注释掉，drawingGroup 在某些情况下会导致文字模糊，待进一步测试
    }
}

extension ProjectCard {
    private static let dateTimeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone.current
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return formatter
    }()
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
            getSelectedProjects: { [] },
            tagManager: {
                let container = TagManager()
                return TagManager()
            }(),
            displayTags: [
                TagDisplayData(name: "Swift", color: .orange),
                TagDisplayData(name: "iOS", color: .blue)
            ],
            editorManager: EditorManager(),
            onTagSelected: { _ in },
            onSelect: { _ in },
            onShowDetail: { }
        )
        .padding()
    }
}
#endif
