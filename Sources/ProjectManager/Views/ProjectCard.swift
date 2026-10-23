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
    let onTagSelected: (String) -> Void
    let onSelect: (Bool) -> Void
    let onShowDetail: () -> Void

    // 弹层一律上提到网格层。
    //
    // 背景：每张卡原先各挂两个 `.sheet` 和一个 `.alert`。200 张卡就是 600 份
    // 平台弹层锚点与手势识别器，每次列表整体替换都要跟着重建一遍。
    // 卡片只负责「请求」，由 ProjectGridView 用单份弹层承载。
    let onRequestEditTags: (Project) -> Void
    let onRequestRename: (Project) -> Void
    let onPortConflict: (Project, Int) -> Void

    @State private var isHovered = false
    
    // MARK: - 子视图
    
    /// 头部视图，包含项目名称和操作按钮
    private var headerView: some View {
        HStack {
            Text(project.name)
                .font(AppTheme.titleFont)
                .foregroundColor(AppTheme.text)
                .lineLimit(1)

            Spacer()

            HStack(spacing: 4) {
                // 快速启动按钮
                if project.startupCommand != nil {
                    Button(action: handleQuickStart) {
                        Image(systemName: "play.fill")
                    }
                    .buttonStyle(IconButtonStyle(iconSize: 14, buttonSize: 24))
                    .help("快速启动 (端口: \(project.customPort.map(String.init) ?? "默认"))")
                }

                // 打开文件夹按钮
                Button(action: { AppOpenHelper.openInFinder(path: project.path) }) {
                    Image(systemName: "folder")
                }
                .buttonStyle(IconButtonStyle(iconSize: 14, buttonSize: 24))
                .help("打开文件夹")

                // 默认编辑器图标：点击打开项目，切换默认应用请在设置或右键菜单中操作。
                Button(action: { AppOpenHelper.openInDefaultEditor(path: project.path) }) {
                    editorIcon(for: editorManager.defaultEditor)
                        .frame(width: 14, height: 14)
                }
                .buttonStyle(IconButtonStyle(iconSize: 14, buttonSize: 24))
                .help("在\(editorManager.defaultEditor?.name ?? "默认编辑器")中打开")

            }
            .opacity(isHovered ? 1 : 0)
            .allowsHitTesting(isHovered)
            .accessibilityHidden(!isHovered)
            .animation(.easeOut(duration: 0.14), value: isHovered)
        }
    }

    /// 路径视图，显示项目路径
    private var pathView: some View {
        Text(project.displayPath)
            .font(AppTheme.captionFont)
            .foregroundColor(AppTheme.secondaryText)
            .lineLimit(1)
            .help(project.path)
    }

    /// 信息视图，显示项目日期和Git提交次数
    private var infoView: some View {
        HStack {
            // 日期信息
            HStack(spacing: 4) {
                Image(systemName: "calendar")
                    .foregroundColor(AppTheme.secondaryIcon)
                Text(ProjectCard.dateTimeFormatter.string(from: project.mtime))
            }
            .font(AppTheme.captionFont)
            .foregroundColor(AppTheme.secondaryText)

            // Git 提交次数
            if let gitInfo = project.gitInfo {
                HStack(spacing: 4) {
                    Image(systemName: "arrow.branch")
                        .foregroundColor(AppTheme.secondaryIcon)
                    Text("\(gitInfo.commitCount)")
                }
                .font(AppTheme.captionFont)
                .foregroundColor(AppTheme.secondaryText)
                .help("累计提交")
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("累计提交 \(gitInfo.commitCount) 次")
            }
        }
    }

    /// 标签视图，显示项目相关标签
    private var tagsView: some View {
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
                Button(action: { onRequestEditTags(project) }) {
                    Image(systemName: "plus")
                }
                .buttonStyle(IconButtonStyle(iconSize: 14, buttonSize: 24))
                .help("添加标签")
                .accessibilityLabel("添加标签")
                .opacity(isHovered ? 1 : 0)
                .allowsHitTesting(isHovered)
                .accessibilityHidden(!isHovered)
                .animation(.easeOut(duration: 0.14), value: isHovered)
            }
        }
        .frame(height: 26)
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
                        editorIcon(for: editor)
                            .frame(width: 16, height: 16)
                        Text(editor.name)
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
            onRequestRename(project)
        }) {
            Label("重命名项目", systemImage: "pencil")
        }
    }
    
    // MARK: - 辅助方法
    
    private func getEditorIcon(for editor: EditorConfig) -> String {
        switch editor.name.lowercased() {
        case "cursor":
            return "cursor"
        case "visual studio code", "vscode", "code":
            return "vscode"
        case "trae":
            return "trae"
        case "codebuddy cn":
            return "codebuddy"
        case "antigravity":
            return "antigravity"
        case "sublime text":
            return "sublimetext"
        case "ghostty":
            return "ghostty"
        default:
            return "app"
        }
    }

    @ViewBuilder
    private func editorIcon(for editor: EditorConfig?) -> some View {
        let iconName = editor.map(getEditorIcon(for:)) ?? "app"
        if let image = EditorIconAssets.image(named: iconName) {
            Image(nsImage: image)
                .renderingMode(.template)
                .resizable()
                .scaledToFit()
                .foregroundColor(AppTheme.secondaryIcon)
        } else {
            Image(systemName: "chevron.left.forwardslash.chevron.right")
                .resizable()
                .scaledToFit()
                .foregroundColor(AppTheme.secondaryIcon)
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
            onPortConflict(project, port)
        }
    }

    // MARK: - 主视图
    
    // MARK: - Equatable
    
    static func == (lhs: ProjectCard, rhs: ProjectCard) -> Bool {
        // 不再比较本地弹层状态：卡片已经不持有它们。
        return lhs.project == rhs.project &&
               lhs.isSelected == rhs.isSelected &&
               lhs.displayTags == rhs.displayTags
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
            
            // 始终保留标签行，让空标签项目也能添加，悬停时不改变布局。
            tagsView
                .padding(.bottom, 4)
            
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 16)
        .frame(height: AppTheme.cardHeight)
        .background(
            RoundedRectangle(cornerRadius: AppTheme.cardCornerRadius)
                .fill(isSelected || isHovered ? AppTheme.cardSelectedBackground : AppTheme.cardBackground)
        )
        .onHover { isHovered = $0 }

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
        // 弹层已上提到 ProjectGridView：这里只上报意图。
        // 卡片不再持有 @State 弹层开关，也就没有每卡的 sheet/alert 平台锦点。
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
            onShowDetail: { },
            onRequestEditTags: { _ in },
            onRequestRename: { _ in },
            onPortConflict: { _, _ in }
        )
        .padding()
    }
}
#endif
