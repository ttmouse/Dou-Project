import SwiftUI

// MARK: - Branch List View
// 分支列表视图 - 显示和管理项目的所有分支

struct BranchListView: View {
    let projectPath: String
    let onOpenBranch: (BranchInfo) -> Void
    let onCreateBranch: (BranchCreationParams) -> Void
    let onDeleteBranch: (BranchInfo) -> Void
    let onMergeBranch: ((BranchInfo) -> Void)?
    
    @State private var branches: [BranchInfo] = []
    @State private var isLoading = true
    @State private var showCreateDialog = false
    @State private var sortCriteria: BranchSortCriteria = .lastUsed
    @State private var showMainBranch = true
    @State private var statusFilter: Set<BranchStatus> = []
    @State private var searchText = ""
    @StateObject private var statusMonitor = BranchStatusMonitor()
    @State private var selectedBranches: Set<UUID> = []
    @State private var showBatchOperations = false
    @State private var isInSelectionMode = false
    
    var body: some View {
        VStack(spacing: 0) {
            // 分支列表头部
            headerSection
            
            // 筛选和排序控制
            filterSection
            
            // 批量操作栏
            if isInSelectionMode && !selectedBranches.isEmpty {
                batchOperationBar
            }
            
            // 分支列表内容
            if isLoading {
                loadingView
            } else if filteredBranches.isEmpty {
                emptyStateView
            } else {
                branchListContent
            }
        }
        .onAppear {
            loadBranches()
        }
        .onDisappear {
            statusMonitor.stopMonitoring()
        }
        .onReceive(NotificationCenter.default.publisher(for: .branchStatusChanged)) { notification in
            handleBranchStatusChange(notification)
        }
        .sheet(isPresented: $showCreateDialog) {
            CreateBranchView(
                isPresented: $showCreateDialog,
                projectPath: projectPath,
                onCreateBranch: { params in
                    onCreateBranch(params)
                    // 创建后刷新列表
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                        loadBranches()
                    }
                }
            )
        }
    }
    
    // MARK: - View Components
    
    private var headerSection: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("分支管理")
                    .font(.headline)
                    .fontWeight(.semibold)
                
                if !branches.isEmpty {
                    HStack(spacing: 4) {
                        Text("\(branches.count) 个分支")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        
                        if statusMonitor.isMonitoring {
                            HStack(spacing: 2) {
                                Circle()
                                    .fill(Color.green)
                                    .frame(width: 4, height: 4)
                                Text("实时监控")
                                    .font(.caption2)
                                    .foregroundColor(.green)
                            }
                        }
                    }
                }
            }
            
            Spacer()
            
            // 操作按钮
            HStack(spacing: 8) {
                // 批量选择按钮
                Button(action: toggleSelectionMode) {
                    Image(systemName: isInSelectionMode ? "checkmark.circle.fill" : "checkmark.circle")
                        .font(.caption)
                        .foregroundColor(isInSelectionMode ? .blue : .secondary)
                }
                .help(isInSelectionMode ? "退出选择模式" : "批量选择")
                
                // 刷新按钮
                Button(action: loadBranches) {
                    Image(systemName: "arrow.clockwise")
                        .font(.caption)
                }
                .help("刷新分支列表")
                
                // 创建分支按钮
                Button(action: { showCreateDialog = true }) {
                    Image(systemName: "plus")
                        .font(.caption)
                }
                .help("创建新分支")
            }
            .buttonStyle(PlainButtonStyle())
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }
    
    private var filterSection: some View {
        VStack(spacing: 8) {
            // 搜索框
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(.secondary)
                
                TextField("搜索分支...", text: $searchText)
                    .textFieldStyle(PlainTextFieldStyle())
                
                if !searchText.isEmpty {
                    Button(action: { searchText = "" }) {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(PlainButtonStyle())
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(Color(NSColor.controlBackgroundColor))
            .cornerRadius(6)
            
            // 筛选和排序控制
            HStack {
                // 显示选项
                Menu {
                    Toggle("显示主分支", isOn: $showMainBranch)
                    
                    Divider()
                    
                    Text("状态筛选")
                    Toggle("干净", isOn: .constant(statusFilter.contains(.clean)))
                        .onTapGesture { toggleStatusFilter(.clean) }
                    Toggle("有更改", isOn: .constant(statusFilter.contains(.hasChanges)))
                        .onTapGesture { toggleStatusFilter(.hasChanges) }
                    Toggle("未知", isOn: .constant(statusFilter.contains(.unknown)))
                        .onTapGesture { toggleStatusFilter(.unknown) }
                    
                    if !statusFilter.isEmpty {
                        Divider()
                        Button("清除筛选") { statusFilter.removeAll() }
                    }
                } label: {
                    HStack {
                        Image(systemName: "line.3.horizontal.decrease.circle")
                        Text("筛选")
                    }
                    .font(.caption)
                }
                .menuStyle(BorderlessButtonMenuStyle())
                
                Spacer()
                
                // 排序选择
                Picker("排序", selection: $sortCriteria) {
                    ForEach(BranchSortCriteria.allCases, id: \.self) { criteria in
                        Text(criteria.displayName).tag(criteria)
                    }
                }
                .pickerStyle(MenuPickerStyle())
                .font(.caption)
            }
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 8)
    }
    
    private var batchOperationBar: some View {
        VStack {
            Divider()
            
            HStack {
                // 选择统计
                Text("已选择 \(selectedBranches.count) 个分支")
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                Spacer()
                
                // 批量操作按钮
                HStack(spacing: 12) {
                    // 全选/取消全选
                    Button(selectedBranches.count == selectableBranches.count ? "取消全选" : "全选") {
                        if selectedBranches.count == selectableBranches.count {
                            selectedBranches.removeAll()
                        } else {
                            selectedBranches = Set(selectableBranches.map { $0.id })
                        }
                    }
                    .font(.caption)
                    .foregroundColor(.blue)
                    
                    Divider()
                        .frame(height: 12)
                    
                    // 批量删除
                    Button("删除") {
                        showBatchDeleteConfirmation()
                    }
                    .font(.caption)
                    .foregroundColor(.red)
                    .disabled(selectedBranches.isEmpty)
                    
                    // 批量合并（仅非主分支）
                    if selectedNonMainBranches.count > 0 {
                        Button("合并到主分支") {
                            showBatchMergeConfirmation()
                        }
                        .font(.caption)
                        .foregroundColor(.green)
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(Color(NSColor.controlBackgroundColor))
        }
    }
    
    private var loadingView: some View {
        VStack(spacing: 16) {
            ProgressView()
                .scaleEffect(0.8)
            Text("加载分支列表...")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    private var emptyStateView: some View {
        VStack(spacing: 16) {
            Image(systemName: "branch")
                .font(.system(size: 48))
                .foregroundColor(.secondary)
            
            VStack(spacing: 4) {
                Text("暂无分支")
                    .font(.headline)
                    .foregroundColor(.primary)
                
                Text("点击 + 按钮创建第一个分支")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Button("创建分支") {
                showCreateDialog = true
            }
            .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    private var branchListContent: some View {
        ScrollView {
            LazyVStack(spacing: 8) {
                ForEach(filteredBranches, id: \.id) { branch in
                    BranchCard(
                        branch: branch,
                        onOpen: { onOpenBranch(branch) },
                        onDelete: { onDeleteBranch(branch) },
                        onMerge: branch.isMain ? nil : { onMergeBranch?(branch) },
                        isSelectionMode: isInSelectionMode,
                        isSelected: selectedBranches.contains(branch.id),
                        onSelectionToggle: branch.isMain ? nil : {
                            if selectedBranches.contains(branch.id) {
                                selectedBranches.remove(branch.id)
                            } else {
                                selectedBranches.insert(branch.id)
                            }
                        }
                    )
                    .padding(.horizontal, 16)
                }
                
                // 统计信息
                if !filteredBranches.isEmpty {
                    statisticsFooter
                        .padding(.horizontal, 16)
                        .padding(.top, 16)
                }
            }
            .padding(.vertical, 8)
        }
    }
    
    private var statisticsFooter: some View {
        let stats = BranchLogic.generateStatistics(branches)
        
        return VStack(alignment: .leading, spacing: 8) {
            Divider()
            
            VStack(alignment: .leading, spacing: 4) {
                Text("统计信息")
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundColor(.secondary)
                
                HStack {
                    statisticItem("总计", "\(stats.totalBranches)", .blue)
                    statisticItem("干净", "\(stats.cleanBranches)", .green)
                    statisticItem("有更改", "\(stats.branchesWithChanges)", .orange)
                    
                    Spacer()
                    
                    Text("占用：\(stats.formattedTotalSize)")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }
        }
        .padding(12)
        .background(Color(NSColor.controlBackgroundColor).opacity(0.5))
        .cornerRadius(6)
    }
    
    private func statisticItem(_ label: String, _ value: String, _ color: Color) -> some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundColor(color)
            Text(label)
                .font(.caption2)
                .foregroundColor(.secondary)
        }
    }
    
    // MARK: - Computed Properties
    
    /// 可选择的分支（排除主分支）
    private var selectableBranches: [BranchInfo] {
        return filteredBranches.filter { !$0.isMain }
    }
    
    /// 已选择的非主分支
    private var selectedNonMainBranches: [BranchInfo] {
        return filteredBranches.filter { selectedBranches.contains($0.id) && !$0.isMain }
    }
    
    private var filteredBranches: [BranchInfo] {
        let filtered = BranchLogic.filterBranches(
            branches,
            showMain: showMainBranch,
            statusFilter: statusFilter.isEmpty ? nil : statusFilter
        )
        
        let searchFiltered = searchText.isEmpty ? filtered : filtered.filter { branch in
            branch.name.localizedCaseInsensitiveContains(searchText) ||
            branch.description.localizedCaseInsensitiveContains(searchText)
        }
        
        return BranchLogic.sortBranches(searchFiltered, by: sortCriteria, ascending: false)
    }
    
    // MARK: - Actions
    
    private func loadBranches() {
        isLoading = true
        
        DispatchQueue.global(qos: .userInitiated).async {
            // 确保使用Git仓库的根路径而不是子路径
            let gitRootPath = self.findGitRoot(from: self.projectPath)
            let worktrees = BranchLogic.listWorktrees(projectPath: gitRootPath)
            let branchInfos = worktrees.compactMap { worktree in
                BranchLogic.getBranchInfo(path: worktree.path)
            }
            
            DispatchQueue.main.async {
                self.branches = branchInfos
                self.isLoading = false
                
                // 启动状态监控
                if !branchInfos.isEmpty {
                    self.statusMonitor.startMonitoring(
                        projectPath: gitRootPath,
                        branches: branchInfos
                    )
                }
            }
        }
    }
    
    private func toggleStatusFilter(_ status: BranchStatus) {
        if statusFilter.contains(status) {
            statusFilter.remove(status)
        } else {
            statusFilter.insert(status)
        }
    }
    
    
    private func handleBranchStatusChange(_ notification: Notification) {
        guard let userInfo = notification.userInfo,
              let branchPath = userInfo["branchPath"] as? String,
              let newStatus = userInfo["newStatus"] as? BranchStatus,
              let changeCount = userInfo["changeCount"] as? Int else {
            return
        }
        
        // 更新分支列表中对应分支的状态
        if let index = branches.firstIndex(where: { $0.path == branchPath }) {
            var updatedBranch = branches[index]
            // 这里需要创建一个新的BranchInfo，因为BranchInfo是结构体
            let newBranchInfo = BranchInfo(
                name: updatedBranch.name,
                path: updatedBranch.path,
                description: updatedBranch.description,
                status: newStatus,
                createdAt: updatedBranch.createdAt,
                lastUsed: updatedBranch.lastUsed,
                uncommittedChanges: changeCount,
                diskSize: updatedBranch.diskSize,
                isMain: updatedBranch.isMain
            )
            
            branches[index] = newBranchInfo
        }
    }
    
    // MARK: - Batch Operations
    
    private func toggleSelectionMode() {
        isInSelectionMode.toggle()
        if !isInSelectionMode {
            selectedBranches.removeAll()
        }
    }
    
    private func showBatchDeleteConfirmation() {
        let selectedBranchInfos = filteredBranches.filter { selectedBranches.contains($0.id) }
        
        let alert = NSAlert()
        alert.messageText = "批量删除分支"
        alert.informativeText = "确定要删除选中的 \(selectedBranchInfos.count) 个分支吗？此操作不可撤销。"
        alert.alertStyle = .warning
        alert.addButton(withTitle: "删除")
        alert.addButton(withTitle: "取消")
        
        if alert.runModal() == .alertFirstButtonReturn {
            performBatchDelete(selectedBranchInfos)
        }
    }
    
    private func showBatchMergeConfirmation() {
        let nonMainBranches = selectedNonMainBranches
        
        let alert = NSAlert()
        alert.messageText = "批量合并分支"
        alert.informativeText = "确定要将选中的 \(nonMainBranches.count) 个分支合并到主分支吗？"
        alert.alertStyle = .informational
        alert.addButton(withTitle: "合并")
        alert.addButton(withTitle: "取消")
        
        if alert.runModal() == .alertFirstButtonReturn {
            performBatchMerge(nonMainBranches)
        }
    }
    
    private func performBatchDelete(_ branchesToDelete: [BranchInfo]) {
        DispatchQueue.global(qos: .userInitiated).async {
            var results: [BranchOperationResult] = []
            let gitRootPath = self.findGitRoot(from: self.projectPath)
            
            for branch in branchesToDelete {
                let result = BranchLogic.deleteBranch(
                    name: branch.name,
                    path: branch.path,
                    projectPath: gitRootPath,
                    force: false
                )
                results.append(result)
                
                // 短暂延迟避免过快操作
                Thread.sleep(forTimeInterval: 0.1)
            }
            
            DispatchQueue.main.async {
                self.handleBatchOperationResults(results, operation: "删除")
                self.selectedBranches.removeAll()
                self.loadBranches() // 刷新列表
            }
        }
    }
    
    private func performBatchMerge(_ branchesToMerge: [BranchInfo]) {
        DispatchQueue.global(qos: .userInitiated).async {
            var results: [BranchOperationResult] = []
            let gitRootPath = self.findGitRoot(from: self.projectPath)
            
            for branch in branchesToMerge {
                let result = BranchLogic.mergeBranch(
                    source: branch.name,
                    target: "main",
                    projectPath: gitRootPath
                )
                results.append(result)
                
                // 短暂延迟避免过快操作
                Thread.sleep(forTimeInterval: 0.2)
            }
            
            DispatchQueue.main.async {
                self.handleBatchOperationResults(results, operation: "合并")
                self.selectedBranches.removeAll()
                self.loadBranches() // 刷新列表
            }
        }
    }
    
    private func handleBatchOperationResults(_ results: [BranchOperationResult], operation: String) {
        let successCount = results.filter { $0.success }.count
        let failureCount = results.count - successCount
        
        let alert = NSAlert()
        if failureCount == 0 {
            alert.messageText = "\(operation)完成"
            alert.informativeText = "成功\(operation) \(successCount) 个分支。"
            alert.alertStyle = .informational
        } else {
            alert.messageText = "\(operation)部分完成"
            alert.informativeText = "成功\(operation) \(successCount) 个分支，失败 \(failureCount) 个分支。"
            alert.alertStyle = .warning
            
            // 显示失败的详细信息
            let failedResults = results.filter { !$0.success }
            let failureDetails = failedResults.map { "\($0.branchName ?? "未知"): \($0.message)" }.joined(separator: "\n")
            alert.informativeText += "\n\n失败详情:\n\(failureDetails)"
        }
        
        alert.addButton(withTitle: "确定")
        alert.runModal()
    }
    
    // MARK: - Helper Functions
    
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

// MARK: - Preview

#Preview {
    BranchListView(
        projectPath: "/Users/test/project",
        onOpenBranch: { branch in
            print("打开分支：\(branch.name)")
        },
        onCreateBranch: { params in
            print("创建分支：\(params.name)")
        },
        onDeleteBranch: { branch in
            print("删除分支：\(branch.name)")
        },
        onMergeBranch: { branch in
            print("合并分支：\(branch.name)")
        }
    )
    .frame(width: 350, height: 600)
}