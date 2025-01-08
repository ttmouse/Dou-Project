import SwiftUI

// MARK: - 辅助函数
private func openInCursor(path: String) {
    let task = Process()
    task.executableURL = URL(fileURLWithPath: "/usr/local/bin/cursor")
    task.arguments = [path]
    
    do {
        try task.run()
    } catch {
        print("Error opening Cursor: \(error)")
        
        // 如果直接打开失败，尝试使用 open 命令
        let openTask = Process()
        openTask.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        openTask.arguments = ["-a", "Cursor", path]
        
        do {
            try openTask.run()
        } catch {
            print("Error using open command: \(error)")
        }
    }
}

struct ProjectCard: View {
    let project: Project
    @ObservedObject var tagManager: TagManager
    @State private var isEditingTags = false
    let onTagSelected: (String) -> Void  // 添加标签选择回调
    
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
            Button(action: { openInCursor(path: project.path) }) {
                Image(systemName: "cursorarrow.rays")
                    .foregroundColor(AppTheme.secondaryIcon)
            }
            .buttonStyle(.plain)
            .help("在 Cursor 中打开")
            
            // 打开文件夹按钮
            Button(action: { NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: project.path) }) {
                Image(systemName: "folder")
                    .foregroundColor(AppTheme.folderIcon)
            }
            .buttonStyle(.plain)
            .help("打开文件夹")
        }
    }
    
    private var pathView: some View {
        Text(project.path)
            .font(AppTheme.captionFont)
            .foregroundColor(AppTheme.secondaryText)
            .lineLimit(1)
    }
    
    private var infoView: some View {
        HStack(spacing: 12) {
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
            
            // Git 提交次数
            if let gitInfo = project.gitInfo {
                HStack(spacing: 4) {
                    Image(systemName: "clock.arrow.circlepath")
                        .foregroundColor(AppTheme.gitIcon)
                    Text("\(gitInfo.commitCount)")
                        .foregroundColor(AppTheme.gitIcon)
                        .fontWeight(.medium)
                    Text("次提交")
                        .foregroundColor(AppTheme.secondaryText)
                }
                // 设置字体大小为12号
                .font(AppTheme.captionFont)
                // 水平方向内边距8点
                .padding(.horizontal, 8)
                // 垂直方向内边距2点
                .padding(.vertical, 4)
                // 设置背景色为卡片背景色
                .background(AppTheme.cardBackground)
                // 不设置圆角
                .cornerRadius(0)
            }
        }
    }
    
    private var tagsView: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 4) {
                ForEach(Array(project.tags).sorted(), id: \.self) { tag in
                    TagView(
                        tag: tag,
                        color: tagManager.getColor(for: tag),
                        fontSize: 11
                    )
                    .onTapGesture {
                        onTagSelected(tag)
                    }
                }
            }
            .padding(.vertical, 4)
        }
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            headerView
            pathView
            infoView
            tagsView
        }
        .padding()
        .frame(height: 120)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(AppTheme.cardBackground)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(AppTheme.cardBorder, lineWidth: 1)
        )
        .shadow(color: AppTheme.cardShadow, radius: 4, x: 0, y: 2)
        .sheet(isPresented: $isEditingTags) {
            TagEditorView(project: project, tagManager: tagManager)
        }
    }
}

// MARK: - 标签编辑器视图
struct TagEditorView: View {
    @State private var currentProject: Project
    @ObservedObject var tagManager: TagManager
    @Environment(\.dismiss) private var dismiss
    @State private var searchText = ""
    
    init(project: Project, tagManager: TagManager) {
        _currentProject = State(initialValue: project)
        self.tagManager = tagManager
    }
    
    private var filteredTags: [String] {
        let allTags = Array(tagManager.allTags).sorted()
        if searchText.isEmpty {
            return allTags
        }
        return allTags.filter { $0.localizedCaseInsensitiveContains(searchText) }
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // 顶部栏
            HStack {
                // 搜索框
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass")
                        .foregroundColor(.secondary)
                    TextField("搜索或创建新标签", text: $searchText)
                        .textFieldStyle(.plain)
                        .onSubmit {
                            if !searchText.isEmpty {
                                addNewTag(searchText)
                            }
                        }
                    if !searchText.isEmpty {
                        Button(action: { searchText = "" }) {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundColor(.secondary)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(8)
                .background(Color(.textBackgroundColor))
                .cornerRadius(6)
                
                // 确认按钮
                Button("确定") {
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
            }
            .padding()
            
            Divider()
            
            // 标签列表
            List {
                ForEach(filteredTags, id: \.self) { tag in
                    HStack {
                        TagView(
                            tag: tag,
                            color: tagManager.getColor(for: tag),
                            fontSize: 13,
                            isSelected: currentProject.tags.contains(tag)
                        )
                        Spacer()
                        if currentProject.tags.contains(tag) {
                            Image(systemName: "checkmark")
                                .foregroundColor(.blue)
                        }
                    }
                    .contentShape(Rectangle())
                    .onTapGesture {
                        if currentProject.tags.contains(tag) {
                            tagManager.removeTagFromProject(projectId: currentProject.id, tag: tag)
                        } else {
                            tagManager.addTagToProject(projectId: currentProject.id, tag: tag)
                        }
                        currentProject = tagManager.projects[currentProject.id] ?? currentProject
                    }
                }
                
                // 如果搜索的标签不存在，显示创建选项
                if !searchText.isEmpty && !tagManager.allTags.contains(searchText.trimmingCharacters(in: .whitespaces)) {
                    Button(action: { addNewTag(searchText) }) {
                        HStack {
                            Image(systemName: "plus.circle.fill")
                            Text("创建标签「\(searchText)」")
                        }
                        .foregroundColor(.blue)
                    }
                }
            }
        }
        .frame(width: 300, height: 400)
    }
    
    private func addNewTag(_ text: String) {
        let tag = text.trimmingCharacters(in: .whitespaces)
        if !tag.isEmpty {
            tagManager.addTag(tag)
            tagManager.addTagToProject(projectId: currentProject.id, tag: tag)
            currentProject = tagManager.projects[currentProject.id] ?? currentProject
            searchText = ""
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
            tagManager: TagManager(),
            onTagSelected: { _ in }
        )
        .padding()
    }
}
#endif 
