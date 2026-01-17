import SwiftUI

// MARK: - Project Detail View
// 项目详情面板 - 显示项目信息和集成分支管理功能

struct ProjectDetailView: View {
    let project: ProjectData
    @Binding var isVisible: Bool
    @ObservedObject var tagManager: TagManager
    @State private var selectedTab: DetailTab = .overview
    @State private var showDeleteConfirmation = false
    @State private var branchToDelete: BranchInfo?
    @State private var showMergeConfirmation = false
    @State private var branchToMerge: BranchInfo?
    @State private var operationResult: BranchOperationResult?
    @State private var showOperationAlert = false
    @State private var showAdvancedMergeDialog = false
    
    // 启动配置状态
    @State private var editingStartupCommand: String = ""
    @State private var editingCustomPort: String = ""
    @State private var isConfigDirty = false
    @State private var showLaunchErrorAlert = false
    @State private var launchErrorMessage = ""
    @State private var showPortConflictDialog = false
    @State private var conflictPort = 0
    @State private var pendingLaunchProject: Project?
    
    // 备注编辑状态
    @State private var noteDraft: String = ""
    @State private var noteLoadedSnapshot: String = ""
    @State private var noteSaveWorkItem: DispatchWorkItem?
    @State private var activeProjectId: UUID?
    @State private var projectSnapshot: ProjectData

    init(project: ProjectData, isVisible: Binding<Bool>, tagManager: TagManager) {
        self.project = project
        self._isVisible = isVisible
        self._tagManager = ObservedObject(initialValue: tagManager)
        _projectSnapshot = State(initialValue: project)
    }
    
    enum DetailTab: String, CaseIterable {
        case overview = "概览"
        case branches = "分支"
        
        var icon: String {
            switch self {
            case .overview: return "info.circle"
            case .branches: return "branch"
            }
        }
    }

    private var currentProjectData: ProjectData {
        return projectSnapshot
    }
    
    
    // MARK: - 备注编辑逻辑
    private func syncNoteEditor() {
        noteSaveWorkItem?.cancel()
        let snapshot = currentProjectData.notes ?? ""
        noteLoadedSnapshot = snapshot
        noteDraft = snapshot
    }
    
    private func refreshNoteEditorFromStore() {
        refreshProjectSnapshotFromStore()
        let snapshot = currentProjectData.notes ?? ""
        let wasDirty = noteDraft != noteLoadedSnapshot
        noteLoadedSnapshot = snapshot
        if !wasDirty {
            noteDraft = snapshot
        }
    }
    
    private func handleNoteDraftChange(_ newValue: String) {
        if newValue == noteLoadedSnapshot {
            noteSaveWorkItem?.cancel()
            return
        }
        scheduleNoteSave(with: newValue)
    }
    
    private func scheduleNoteSave(with text: String) {
        noteSaveWorkItem?.cancel()
        let pendingText = text
        let projectId = currentProjectData.id
        let workItem = DispatchWorkItem {
            tagManager.updateProjectNotes(projectId: projectId, notes: pendingText)
        }
        noteSaveWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8, execute: workItem)
    }

    private func commitPendingNote(for projectId: UUID? = nil) {
        noteSaveWorkItem?.cancel()
        guard noteDraft != noteLoadedSnapshot else { return }
        let targetId = projectId ?? activeProjectId ?? projectSnapshot.id
        let currentText = noteDraft
        tagManager.updateProjectNotes(projectId: targetId, notes: currentText)
        noteLoadedSnapshot = currentText
    }

    private func refreshProjectSnapshotFromStore(for targetId: UUID? = nil) {
        let lookupId = targetId ?? activeProjectId ?? project.id
        if let liveProject = tagManager.projects[lookupId] {
            projectSnapshot = ProjectData(from: liveProject)
        } else if lookupId == project.id {
            projectSnapshot = project
        }
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // 详情面板头部
            headerSection
            
            // 标签栏
            tabSection
            
            // 内容区域
            contentSection
        }
        .background(AppTheme.background)
        .frame(width: 380)
        .confirmationDialog(
            "删除分支",
            isPresented: $showDeleteConfirmation,
            titleVisibility: .visible
        ) {
            deleteConfirmationButtons
        } message: {
            if let branch = branchToDelete {
                Text("确定要删除分支 \"\(branch.name)\" 吗？\n\n这将删除分支的所有内容，此操作不可撤销。")
            }
        }
        .confirmationDialog(
            "合并分支",
            isPresented: $showMergeConfirmation,
            titleVisibility: .visible
        ) {
            mergeConfirmationButtons
        } message: {
            if let branch = branchToMerge {
                Text("确定要将分支 \"\(branch.name)\" 合并到主分支吗？")
            }
        }
        .alert("操作结果", isPresented: $showOperationAlert) {
            Button("确定") { operationResult = nil }
        } message: {
            if let result = operationResult {
                Text(result.message)
            }
        }
        .sheet(isPresented: $showAdvancedMergeDialog) {
            if let branch = branchToMerge {
                MergeConfirmationView(
                    isPresented: $showAdvancedMergeDialog,
                    branch: branch,
                    projectPath: currentProjectData.path,
                    onConfirmMerge: { strategy in
                        mergeBranchWithStrategy(branch, strategy: strategy)
                    }
                )
            }
        }
        .onAppear {
            activeProjectId = project.id
            refreshProjectSnapshotFromStore(for: project.id)
            loadProjectConfiguration()
            syncNoteEditor()
        }
        .onChange(of: project.id) { newId in
            commitPendingNote(for: activeProjectId)
            activeProjectId = newId
            refreshProjectSnapshotFromStore(for: newId)
            loadProjectConfiguration()
            syncNoteEditor()
        }
        .onChange(of: noteDraft) { newValue in
            handleNoteDraftChange(newValue)
        }
        .onReceive(tagManager.$projects) { _ in
            refreshNoteEditorFromStore()
        }
        .onDisappear {
            commitPendingNote(for: activeProjectId)
        }
    }
    
    // MARK: - View Components
    
    private var headerSection: some View {
        let data = currentProjectData
        return HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(data.name)
                    .font(AppTheme.titleFont)
                    .foregroundColor(AppTheme.text)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .layoutPriority(1)

                Text(abbreviatedPath)
                    .font(AppTheme.captionFont)
                    .foregroundColor(AppTheme.secondaryText)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Spacer()
            
            // 关闭按钮
            Button(action: { isVisible = false }) {
                Image(systemName: "xmark")
                    .font(.system(size: 14))
                    .foregroundColor(AppTheme.secondaryIcon)
            }
            .buttonStyle(.plain)
            .padding(8)
            .background(AppTheme.buttonBackground)
            .cornerRadius(6)
            .help("关闭详情面板")
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
        .background(AppTheme.secondaryBackground)
        .overlay(
            Rectangle()
                .fill(AppTheme.divider)
                .frame(height: 1),
            alignment: .bottom
        )
    }
    
    private var tabSection: some View {
        HStack(spacing: 12) {
            ForEach(DetailTab.allCases, id: \.self) { tab in
                Button(action: { selectedTab = tab }) {
                    HStack(spacing: 8) {
                        Image(systemName: tab.icon)
                            .font(.system(size: 13))
                        Text(tab.rawValue)
                            .font(AppTheme.bodyFont)
                    }
                    .foregroundColor(selectedTab == tab ? AppTheme.text : AppTheme.secondaryText)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(
                        selectedTab == tab ?
                        AppTheme.accent.opacity(0.2) :
                        Color.clear
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .strokeBorder(
                                selectedTab == tab ? AppTheme.accent.opacity(0.5) : Color.clear,
                                lineWidth: 1
                            )
                    )
                    .cornerRadius(8)
                }
                .buttonStyle(.plain)
            }
            
            Spacer()
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .background(AppTheme.sidebarBackground)
        .overlay(
            Rectangle()
                .fill(AppTheme.divider)
                .frame(height: 1),
            alignment: .bottom
        )
    }
    
    private var contentSection: some View {
        Group {
            switch selectedTab {
            case .overview:
                projectOverview
            case .branches:
                branchManagement
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    private var projectOverview: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(spacing: 0) {
                projectNotesSection
                sectionDivider
                projectTagInfo
                sectionDivider
                projectConfigInfo
            }
            .background(AppTheme.background)
        }
    }
    
    private var projectNotesSection: some View {
        sectionContainer {
            sectionHeader("项目备注", icon: "note.text")
            
            DetailTextEditor(placeholder: "输入备注…", text: $noteDraft)
            
            HStack(spacing: 12) {
                Text("自动保存 · 搜索可用")
                    .font(AppTheme.captionFont)
                    .foregroundColor(AppTheme.secondaryText)
                    .lineLimit(1)
                    .truncationMode(.tail)

                Spacer()

                Text(noteDraft != noteLoadedSnapshot ? "未保存" : "已保存")
                    .font(AppTheme.captionFont)
                    .foregroundColor(noteDraft != noteLoadedSnapshot ? AppTheme.accent : AppTheme.secondaryText)

                Button("清除") {
                    noteDraft = ""
                }
                .font(AppTheme.captionFont)
                .foregroundColor(AppTheme.accent)
                .buttonStyle(.plain)
                .disabled(noteDraft.isEmpty)
            }
        }
    }
    
    private var projectTagInfo: some View {
        let data = currentProjectData
        return sectionContainer {
            sectionHeader("标签", icon: "tag")
            
            if data.tags.isEmpty {
                HStack(spacing: 10) {
                    Image(systemName: "tray")
                        .foregroundColor(AppTheme.secondaryText)
                    Text("尚未设置标签")
                        .font(AppTheme.bodyFont)
                        .foregroundColor(AppTheme.secondaryText)
                    Spacer()
                }
                .padding(.vertical, 6)
            } else {
                FlowLayout(spacing: 8, data: Array(data.tags.sorted())) { tag in
                    AnyView(
                        TagView(
                            tag: tag,
                            color: tagManager.getColor(for: tag),
                            fontSize: 12
                        )
                    )
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }
    
    private var projectConfigInfo: some View {
        sectionContainer {
            VStack(alignment: .leading, spacing: 12) {
                sectionHeader("启动配置", icon: "gearshape")

                HStack(spacing: 12) {
                    Button {
                        saveConfig()
                    } label: {
                        Label("保存", systemImage: "tray.and.arrow.down")
                            .font(.system(size: 12, weight: .semibold))
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(
                                Capsule()
                                    .fill(AppTheme.accent.opacity(isConfigDirty ? 1 : 0.35))
                            )
                            .foregroundColor(.white)
                    }
                    .buttonStyle(.plain)
                    .disabled(!isConfigDirty)
                    .opacity(isConfigDirty ? 1 : 0.6)

                    Button {
                        runStartupCommand()
                    } label: {
                        Label("启动", systemImage: "bolt.fill")
                            .font(.system(size: 12, weight: .semibold))
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(
                                Capsule()
                                    .fill(
                                        LinearGradient(
                                            colors: [Color.green.opacity(0.9), Color.green.opacity(0.7)],
                                            startPoint: .leading,
                                            endPoint: .trailing
                                        )
                                    )
                            )
                            .foregroundColor(.white)
                    }
                    .buttonStyle(.plain)
                    .disabled(!hasRunnableStartupCommand)
                    .opacity(hasRunnableStartupCommand ? 1 : 0.4)
                    .help("在终端运行启动命令")
                }
            }
            
            VStack(alignment: .leading, spacing: 14) {
                DetailInputField(
                    title: "启动命令",
                    icon: "terminal",
                    placeholder: "例如: npm start",
                    text: $editingStartupCommand
                ) { _ in
                    isConfigDirty = true
                }
                
                DetailInputField(
                    title: "端口",
                    icon: "network",
                    placeholder: "例如: 3000",
                    text: $editingCustomPort
                ) { _ in
                    isConfigDirty = true
                }
            }
        }
        .alert("启动失败", isPresented: $showLaunchErrorAlert) {
            Button("确定", role: .cancel) {
                launchErrorMessage = ""
            }
        } message: {
            Text(launchErrorMessage)
        }
        .confirmationDialog(
            "端口冲突",
            isPresented: $showPortConflictDialog,
            titleVisibility: .visible
        ) {
            Button("终止占用进程并启动", role: .destructive) {
                guard let launchProject = pendingLaunchProject else { return }
                let result = ProjectRunner.killProcessAndRun(launchProject)
                handleLaunchResult(result, for: launchProject)
            }
            Button("使用随机端口启动") {
                guard let launchProject = pendingLaunchProject else { return }
                runProject(launchProject, useRandomPort: true)
            }
            Button("取消", role: .cancel) {
                pendingLaunchProject = nil
            }
        } message: {
            Text("端口 \(conflictPort) 正在被使用。请选择操作方式。")
        }
    }
    
    private func saveConfig() {
        // 1. 转换当前 ProjectData 为 Project
        let currentProject = Project.fromProjectData(currentProjectData)
        
        // 2. 更新配置
        let trimmedCommand = editingStartupCommand.trimmingCharacters(in: .whitespacesAndNewlines)
        let newCommand = trimmedCommand.isEmpty ? nil : trimmedCommand
        let trimmedPort = editingCustomPort.trimmingCharacters(in: .whitespacesAndNewlines)
        let newPort = trimmedPort.isEmpty ? nil : Int(trimmedPort)
        
        // 3. 创建更新后的 Project (需要扩展 Project 以支持 copyWith 更新这些字段，或者重新构建)
        // 由于 Project 是不可变的，我们需要一个新的构造方式或者 copyWith
        // 这里我们使用重新构建的方式，因为 copyWith 还没有更新支持这些字段
        
        let updatedProject = Project(
            id: currentProject.id,
            name: currentProject.name,
            path: currentProject.path,
            tags: currentProject.tags,
            mtime: currentProject.mtime,
            size: currentProject.size,
            checksum: currentProject.checksum,
            git_commits: currentProject.git_commits,
            git_last_commit: currentProject.git_last_commit,
            git_daily: currentProject.git_daily,
            startupCommand: newCommand,
            customPort: newPort,
            created: currentProject.created,
            checked: currentProject.checked
        )
        
        // 4. 保存
        tagManager.updateProject(updatedProject)
        editingStartupCommand = newCommand ?? ""
        editingCustomPort = newPort.map(String.init) ?? ""
        isConfigDirty = false
    }
    
    private func loadProjectConfiguration() {
        editingStartupCommand = currentProjectData.startupCommand ?? ""
        editingCustomPort = currentProjectData.customPort.map(String.init) ?? ""
        isConfigDirty = false
    }
    
    private var hasRunnableStartupCommand: Bool {
        !editingStartupCommand.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
    
    private func makeLaunchProject() -> Project {
        let trimmedCommand = editingStartupCommand.trimmingCharacters(in: .whitespacesAndNewlines)
        let portString = editingCustomPort.trimmingCharacters(in: .whitespacesAndNewlines)
        let resolvedPort = portString.isEmpty ? nil : Int(portString)
        let data = currentProjectData
        
        return Project(
            id: data.id,
            name: data.name,
            path: data.path,
            tags: data.tags,
            mtime: data.mtime,
            size: data.size,
            checksum: data.checksum,
            git_commits: data.git_commits,
            git_last_commit: data.git_last_commit,
            git_daily: data.git_daily,
            startupCommand: trimmedCommand.isEmpty ? nil : trimmedCommand,
            customPort: resolvedPort,
            created: data.created,
            checked: data.checked
        )
    }
    
    private func runStartupCommand() {
        let launchProject = makeLaunchProject()
        runProject(launchProject)
    }
    
    private func runProject(_ project: Project, useRandomPort: Bool = false) {
        let result = ProjectRunner.run(project, useRandomPort: useRandomPort)
        handleLaunchResult(result, for: project)
    }
    
    private func handleLaunchResult(_ result: ProjectRunResult, for project: Project) {
        switch result {
        case .success:
            pendingLaunchProject = nil
            showPortConflictDialog = false
        case .failure(let error):
            pendingLaunchProject = nil
            showPortConflictDialog = false
            launchErrorMessage = error
            showLaunchErrorAlert = true
        case .portBusy(let port, _):
            conflictPort = port
            pendingLaunchProject = project
            showPortConflictDialog = true
        }
    }
    
    
    private var branchManagement: some View {
        BranchListView(
            projectPath: findGitRoot(from: currentProjectData.path),
            onOpenBranch: openBranchInEditor,
            onCreateBranch: createBranch,
            onDeleteBranch: { branch in
                branchToDelete = branch
                showDeleteConfirmation = true
            },
            onMergeBranch: { branch in
                branchToMerge = branch
                showAdvancedMergeDialog = true
            }
        )
        .id(currentProjectData.id) // 强制刷新：当project.id变化时，重新创建BranchListView
    }
    
    // MARK: - Helper Views
    
    private func sectionHeader(_ title: String, icon: String, subtitle: String? = nil) -> some View {
        HStack(alignment: .center, spacing: 12) {
            ZStack {
                Circle()
                    .fill(AppTheme.accent.opacity(0.15))
                    .frame(width: 34, height: 34)
                Image(systemName: icon)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundColor(AppTheme.accent)
            }
            
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(AppTheme.subtitleFont)
                    .foregroundColor(AppTheme.text)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .layoutPriority(1)
                if let subtitle {
                    Text(subtitle)
                        .font(AppTheme.captionFont)
                        .foregroundColor(AppTheme.secondaryText)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Spacer()
        }
    }
    
    private func sectionContainer<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            content()
        }
        .padding(.horizontal, 22)
        .padding(.vertical, 18)
    }
    
    private var sectionDivider: some View {
        Rectangle()
            .fill(AppTheme.cardBorder.opacity(0.6))
            .frame(height: 1)
    }
    
    private func infoRow(_ label: String, _ value: String) -> some View {
        HStack(spacing: 12) {
            Text(label)
                .font(AppTheme.captionFont)
                .foregroundColor(AppTheme.secondaryText)
                .frame(width: 80, alignment: .leading)
            
            Text(value)
                .font(AppTheme.captionFont)
                .foregroundColor(AppTheme.text)
                .lineLimit(1)
                .help(value)
            
            Spacer()
            
            // 复制按钮
            Button(action: { copyToClipboard(value) }) {
                Image(systemName: "doc.on.doc")
                    .font(.system(size: 11))
                    .foregroundColor(AppTheme.secondaryIcon)
            }
            .buttonStyle(.plain)
            .padding(4)
            .background(AppTheme.buttonBackground.opacity(0.5))
            .cornerRadius(4)
            .help("复制")
        }
    }
    
    private var deleteConfirmationButtons: some View {
        Group {
            Button("取消", role: .cancel) {
                branchToDelete = nil
            }
            
            Button("删除", role: .destructive) {
                if let branch = branchToDelete {
                    deleteBranch(branch, force: false)
                }
                branchToDelete = nil
            }
            
            if branchToDelete?.hasUncommittedChanges == true {
                Button("强制删除", role: .destructive) {
                    if let branch = branchToDelete {
                        deleteBranch(branch, force: true)
                    }
                    branchToDelete = nil
                }
            }
        }
    }
    
    private var mergeConfirmationButtons: some View {
        Group {
            Button("取消", role: .cancel) {
                branchToMerge = nil
            }
            
            Button("合并") {
                if let branch = branchToMerge {
                    mergeBranch(branch)
                }
                branchToMerge = nil
            }
        }
    }
    
    // MARK: - Computed Properties
    
    private var abbreviatedPath: String {
        let url = URL(fileURLWithPath: currentProjectData.path)
        let components = url.pathComponents
        
        if components.count > 4 {
            let start = components.prefix(2).joined(separator: "/")
            let end = components.suffix(2).joined(separator: "/")
            return "\(start)/…/\(end)"
        } else {
            return currentProjectData.path
        }
    }
    
    // MARK: - Actions
    
    private func openBranchInEditor(_ branch: BranchInfo) {
        // 使用与项目卡片相同的编辑器打开逻辑
        AppOpenHelper.openInDefaultEditor(path: branch.path)
    }
    
    private func createBranch(_ params: BranchCreationParams) {
        DispatchQueue.global(qos: .userInitiated).async {
            let result = BranchLogic.createBranch(params: params)
            
            DispatchQueue.main.async {
                self.operationResult = result
                self.showOperationAlert = true
            }
        }
    }
    
    private func deleteBranch(_ branch: BranchInfo, force: Bool) {
        let projectPath = currentProjectData.path
        DispatchQueue.global(qos: .userInitiated).async {
            let gitRootPath = self.findGitRoot(from: projectPath)
            let result = BranchLogic.deleteBranch(
                name: branch.name,
                path: branch.path,
                projectPath: gitRootPath,
                force: force
            )
            
            DispatchQueue.main.async {
                self.operationResult = result
                self.showOperationAlert = true
            }
        }
    }
    
    private func mergeBranch(_ branch: BranchInfo) {
        let projectPath = currentProjectData.path
        DispatchQueue.global(qos: .userInitiated).async {
            let gitRootPath = self.findGitRoot(from: projectPath)
            let result = BranchLogic.mergeBranch(
                source: branch.name,
                target: "main",
                projectPath: gitRootPath
            )
            
            DispatchQueue.main.async {
                self.operationResult = result
                self.showOperationAlert = true
            }
        }
    }
    
    private func mergeBranchWithStrategy(_ branch: BranchInfo, strategy: MergeStrategy) {
        let projectPath = currentProjectData.path
        DispatchQueue.global(qos: .userInitiated).async {
            let gitRootPath = self.findGitRoot(from: projectPath)
            let result = BranchLogic.mergeBranch(
                source: branch.name,
                target: "main",
                projectPath: gitRootPath,
                strategy: strategy
            )
            
            DispatchQueue.main.async {
                self.operationResult = result
                self.showOperationAlert = true
                self.branchToMerge = nil
            }
        }
    }
    
    // MARK: - Helper Functions
    
    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone.current
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return formatter.string(from: date)
    }
    
private func copyToClipboard(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }
    
}

private struct DetailTextEditor: View {
    let placeholder: String
    @Binding var text: String
    var minHeight: CGFloat = 140
    var maxHeight: CGFloat = 220
    
    var body: some View {
        ZStack(alignment: .topLeading) {
            if text.isEmpty {
                Text(placeholder)
                    .font(AppTheme.captionFont)
                    .foregroundColor(AppTheme.secondaryText)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
            }
            
            TextEditor(text: $text)
                .font(AppTheme.bodyFont)
                .foregroundColor(AppTheme.text)
                .padding(.horizontal, 8)
                .padding(.vertical, 8)
                .background(Color.clear)
        }
        .frame(minHeight: minHeight, maxHeight: maxHeight)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(AppTheme.secondaryBackground.opacity(0.95))
        )
    }
}

private struct DetailInputField: View {
    let title: String
    let icon: String
    let placeholder: String
    @Binding var text: String
    var onChanged: ((String) -> Void)? = nil
    
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(AppTheme.captionFont)
                .foregroundColor(AppTheme.secondaryText)
            
            HStack(spacing: 10) {
                Image(systemName: icon)
                    .foregroundColor(AppTheme.secondaryText)
                    .font(.system(size: 13))
                
                TextField(placeholder, text: $text)
                    .textFieldStyle(.plain)
                    .foregroundColor(AppTheme.text)
            }
            .padding(.vertical, 10)
            .padding(.horizontal, 12)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(AppTheme.secondaryBackground.opacity(0.9))
            )
        }
        .onChange(of: text) { newValue in
            onChanged?(newValue)
        }
    }
}

// MARK: - Preview

#Preview {
    ProjectDetailView(
        project: ProjectData(
            id: UUID(),
            name: "示例项目",
            path: "/Users/test/Projects/ExampleProject",
            lastModified: Date().addingTimeInterval(-3600),
            tags: ["Swift", "macOS", "开发中"],
            gitInfo: ProjectData.GitInfoData(
                commitCount: 127,
                lastCommitDate: Date().addingTimeInterval(-7200)
            ),
            fileSystemInfo: ProjectData.FileSystemInfoData(
                modificationDate: Date().addingTimeInterval(-3600),
                size: 1024 * 1024 * 50,
                checksum: "abc123def456",
                lastCheckTime: Date()
            )
        ),
        isVisible: .constant(true),
        tagManager: TagManager()
    )
}

// MARK: - Helper Functions Extension

extension ProjectDetailView {
    /// 从给定路径向上查找Git仓库根目录
    /// - Parameter path: 起始路径
    /// - Returns: Git仓库根目录路径
    private func findGitRoot(from path: String) -> String {
        var currentPath = path
        
        // 如果当前路径已经是一个Git根目录，直接返回
        if FileManager.default.fileExists(atPath: currentPath + "/.git") {
            return currentPath
        }
        
        // 向上查找，直到找到.git目录或达到根目录
        while currentPath != "/" {
            let gitPath = currentPath + "/.git"
            if FileManager.default.fileExists(atPath: gitPath) {
                return currentPath
            }
            
            currentPath = URL(fileURLWithPath: currentPath).deletingLastPathComponent().path
        }
        
        // 如果没有找到Git根目录，返回原路径
        return path
    }
}
