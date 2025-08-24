import SwiftUI

// MARK: - Project Detail View
// 项目详情面板 - 显示项目信息和集成分支管理功能

struct ProjectDetailView: View {
    let project: ProjectData
    @Binding var isVisible: Bool
    
    @State private var selectedTab: DetailTab = .overview
    @State private var showDeleteConfirmation = false
    @State private var branchToDelete: BranchInfo?
    @State private var showMergeConfirmation = false
    @State private var branchToMerge: BranchInfo?
    @State private var operationResult: BranchOperationResult?
    @State private var showOperationAlert = false
    @State private var showAdvancedMergeDialog = false
    
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
    
    var body: some View {
        VStack(spacing: 0) {
            // 详情面板头部
            headerSection
            
            // 标签栏
            tabSection
            
            // 内容区域
            contentSection
        }
        .background(Color(NSColor.windowBackgroundColor))
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
                    projectPath: project.path,
                    onConfirmMerge: { strategy in
                        mergeBranchWithStrategy(branch, strategy: strategy)
                    }
                )
            }
        }
    }
    
    // MARK: - View Components
    
    private var headerSection: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(project.name)
                    .font(.title2)
                    .fontWeight(.semibold)
                    .lineLimit(1)
                
                Text(abbreviatedPath)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }
            
            Spacer()
            
            // 关闭按钮
            Button(action: { isVisible = false }) {
                Image(systemName: "xmark")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .buttonStyle(PlainButtonStyle())
            .help("关闭详情面板")
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
        .background(Color(NSColor.controlBackgroundColor).opacity(0.5))
    }
    
    private var tabSection: some View {
        HStack(spacing: 0) {
            ForEach(DetailTab.allCases, id: \.self) { tab in
                Button(action: { selectedTab = tab }) {
                    HStack(spacing: 6) {
                        Image(systemName: tab.icon)
                        Text(tab.rawValue)
                    }
                    .font(.caption)
                    .foregroundColor(selectedTab == tab ? .primary : .secondary)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(
                        selectedTab == tab ?
                        Color(NSColor.selectedControlColor).opacity(0.3) :
                        Color.clear
                    )
                    .cornerRadius(6)
                }
                .buttonStyle(PlainButtonStyle())
            }
            
            Spacer()
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 8)
        .background(Color(NSColor.controlBackgroundColor).opacity(0.3))
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
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // 基本信息
                projectBasicInfo
                
                // Git 信息
                if let gitInfo = project.gitInfo {
                    projectGitInfo(gitInfo)
                }
                
                // 标签信息
                projectTagInfo
                
                // 文件系统信息
                projectFileSystemInfo
            }
            .padding(20)
        }
    }
    
    private var projectBasicInfo: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeader("基本信息", icon: "info.circle")
            
            VStack(alignment: .leading, spacing: 8) {
                infoRow("项目路径", project.path)
                infoRow("最后修改", formatDate(project.lastModified))
                infoRow("项目ID", project.id.uuidString)
            }
        }
    }
    
    private func projectGitInfo(_ gitInfo: ProjectData.GitInfoData) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeader("Git 信息", icon: "branch")
            
            VStack(alignment: .leading, spacing: 8) {
                infoRow("提交数量", "\(gitInfo.commitCount)")
                infoRow("最后提交", formatDate(gitInfo.lastCommitDate))
            }
        }
    }
    
    private var projectTagInfo: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeader("标签", icon: "tag")
            
            if project.tags.isEmpty {
                Text("无标签")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .padding(.leading, 8)
            } else {
                FlowLayout(spacing: 6, data: Array(project.tags.sorted())) { tag in
                    AnyView(
                        Text(tag)
                            .font(.caption)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Color.blue.opacity(0.2))
                            .foregroundColor(.blue)
                            .cornerRadius(4)
                    )
                }
                .padding(.leading, 8)
            }
        }
    }
    
    private var projectFileSystemInfo: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeader("文件系统", icon: "folder")
            
            VStack(alignment: .leading, spacing: 8) {
                infoRow("文件大小", formatFileSize(project.fileSystemInfo.size))
                infoRow("修改时间", formatDate(project.fileSystemInfo.modificationDate))
                infoRow("上次检查", formatDate(project.fileSystemInfo.lastCheckTime))
                infoRow("校验和", project.fileSystemInfo.checksum.isEmpty ? "无" : String(project.fileSystemInfo.checksum.prefix(16)) + "...")
            }
        }
    }
    
    private var branchManagement: some View {
        BranchListView(
            projectPath: findGitRoot(from: project.path),
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
    }
    
    // MARK: - Helper Views
    
    private func sectionHeader(_ title: String, icon: String) -> some View {
        HStack {
            Image(systemName: icon)
                .foregroundColor(.blue)
            Text(title)
                .font(.headline)
                .fontWeight(.semibold)
            Spacer()
        }
    }
    
    private func infoRow(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label)
                .font(.caption)
                .foregroundColor(.secondary)
                .frame(width: 80, alignment: .leading)
            
            Text(value)
                .font(.caption)
                .foregroundColor(.primary)
                .lineLimit(1)
                .help(value) // 完整文本提示
            
            Spacer()
            
            // 复制按钮
            Button(action: { copyToClipboard(value) }) {
                Image(systemName: "doc.on.doc")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
            .buttonStyle(PlainButtonStyle())
            .help("复制")
        }
        .padding(.leading, 8)
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
        let url = URL(fileURLWithPath: project.path)
        let components = url.pathComponents
        
        if components.count > 4 {
            let start = components.prefix(2).joined(separator: "/")
            let end = components.suffix(2).joined(separator: "/")
            return "\(start)/…/\(end)"
        } else {
            return project.path
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
        DispatchQueue.global(qos: .userInitiated).async {
            let gitRootPath = self.findGitRoot(from: self.project.path)
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
        DispatchQueue.global(qos: .userInitiated).async {
            let gitRootPath = self.findGitRoot(from: self.project.path)
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
        DispatchQueue.global(qos: .userInitiated).async {
            let gitRootPath = self.findGitRoot(from: self.project.path)
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
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
    
    private func formatFileSize(_ size: UInt64) -> String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useBytes, .useKB, .useMB, .useGB]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: Int64(size))
    }
    
    private func copyToClipboard(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
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
        isVisible: .constant(true)
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