import SwiftUI

// MARK: - Create Branch Dialog
// 创建分支对话框 - 提供分支名称、描述等输入

struct CreateBranchView: View {
    @Binding var isPresented: Bool
    let projectPath: String
    let onCreateBranch: (BranchCreationParams) -> Void
    
    @State private var branchName = ""
    @State private var description = ""
    @State private var baseBranch = "main"
    @State private var isCreating = false
    @State private var validationError: String?
    
    // 可用的基础分支列表
    @State private var availableBranches: [String] = ["main", "master", "develop"]
    
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            // 对话框标题
            header
            
            // 输入表单
            VStack(alignment: .leading, spacing: 16) {
                // 分支名称输入
                branchNameInput
                
                // 分支描述输入
                descriptionInput
                
                // 基础分支选择
                baseBranchSelector
                
                // 验证错误提示
                if let error = validationError {
                    errorMessage(error)
                }
            }
            
            // 按钮区域
            actionButtons
        }
        .padding(24)
        .frame(width: 400)
        .background(Color(NSColor.windowBackgroundColor))
        .cornerRadius(12)
        .shadow(radius: 10)
        .onAppear {
            loadAvailableBranches()
        }
    }
    
    // MARK: - View Components
    
    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("创建新分支")
                .font(.title2)
                .fontWeight(.semibold)
            
            Text("基于现有分支创建新的Git worktree分支")
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }
    
    private var branchNameInput: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label("分支名称", systemImage: "branch")
                .font(.headline)
            
            TextField("例如：feature-login 或 bugfix-ui", text: $branchName)
                .textFieldStyle(RoundedBorderTextFieldStyle())
                .onChange(of: branchName) { newValue in
                    validateBranchName(newValue)
                }
            
            Text("分支名称只能包含字母、数字、点、下划线和斜杠")
                .font(.caption2)
                .foregroundColor(.secondary)
        }
    }
    
    private var descriptionInput: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label("描述（可选）", systemImage: "text.alignleft")
                .font(.headline)
            
            TextField("描述这个分支的用途", text: $description)
                .textFieldStyle(RoundedBorderTextFieldStyle())
        }
    }
    
    private var baseBranchSelector: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label("基于分支", systemImage: "arrow.triangle.branch")
                .font(.headline)
            
            Picker("基于分支", selection: $baseBranch) {
                ForEach(availableBranches, id: \.self) { branch in
                    HStack {
                        if isMainBranch(branch) {
                            Image(systemName: "star.fill")
                                .foregroundColor(.blue)
                                .font(.caption)
                        }
                        Text(branch)
                    }
                    .tag(branch)
                }
            }
            .pickerStyle(MenuPickerStyle())
            
            Text("新分支将基于选中的分支创建")
                .font(.caption2)
                .foregroundColor(.secondary)
        }
    }
    
    private var actionButtons: some View {
        HStack {
            // 取消按钮
            Button("取消") {
                isPresented = false
            }
            .keyboardShortcut(.escape)
            
            Spacer()
            
            // 创建按钮
            Button(action: createBranch) {
                HStack {
                    if isCreating {
                        ProgressView()
                            .scaleEffect(0.8)
                    }
                    Text(isCreating ? "创建中..." : "创建分支")
                }
            }
            .keyboardShortcut(.return)
            .disabled(!isFormValid || isCreating)
            .buttonStyle(.borderedProminent)
        }
    }
    
    private func errorMessage(_ error: String) -> some View {
        HStack {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundColor(.red)
            Text(error)
                .foregroundColor(.red)
                .font(.caption)
        }
        .padding(8)
        .background(Color.red.opacity(0.1))
        .cornerRadius(6)
    }
    
    // MARK: - Computed Properties
    
    private var isFormValid: Bool {
        !branchName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        validationError == nil
    }
    
    // MARK: - Actions
    
    private func createBranch() {
        guard isFormValid else { return }
        
        isCreating = true
        validationError = nil
        
        let params = BranchCreationParams(
            name: branchName.trimmingCharacters(in: .whitespacesAndNewlines),
            description: description.trimmingCharacters(in: .whitespacesAndNewlines),
            baseBranch: baseBranch,
            projectPath: projectPath
        )
        
        // 执行创建操作
        onCreateBranch(params)
        
        // 重置状态
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            isCreating = false
            isPresented = false
            resetForm()
        }
    }
    
    private func validateBranchName(_ name: String) {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        
        if trimmedName.isEmpty {
            validationError = nil
            return
        }
        
        // 检查分支名称是否有效
        let params = BranchCreationParams(name: trimmedName, projectPath: projectPath)
        if !params.isValidName {
            validationError = "分支名称格式无效"
            return
        }
        
        // 检查是否与现有分支重名
        if availableBranches.contains(trimmedName) {
            validationError = "分支名称已存在"
            return
        }
        
        // 检查是否包含保留字
        let reservedNames = ["HEAD", "refs", "logs"]
        if reservedNames.contains(trimmedName) {
            validationError = "不能使用保留的分支名称"
            return
        }
        
        validationError = nil
    }
    
    private func loadAvailableBranches() {
        // 获取项目的现有分支列表
        let worktrees = BranchLogic.listWorktrees(projectPath: projectPath)
        let branchNames = Set(worktrees.map { $0.branch })
        
        // 合并默认分支和实际分支
        var branches = Set(["main", "master", "develop"])
        branches.formUnion(branchNames)
        
        availableBranches = Array(branches).sorted { branch1, branch2 in
            // 主分支排在前面
            let isMain1 = isMainBranch(branch1)
            let isMain2 = isMainBranch(branch2)
            
            if isMain1 && !isMain2 {
                return true
            } else if !isMain1 && isMain2 {
                return false
            } else {
                return branch1.localizedCaseInsensitiveCompare(branch2) == .orderedAscending
            }
        }
        
        // 设置默认基础分支
        if let currentBranch = ShellExecutor.getCurrentBranch(path: projectPath),
           availableBranches.contains(currentBranch) {
            baseBranch = currentBranch
        } else if availableBranches.contains("main") {
            baseBranch = "main"
        } else if availableBranches.contains("master") {
            baseBranch = "master"
        } else if !availableBranches.isEmpty {
            baseBranch = availableBranches.first!
        }
    }
    
    private func isMainBranch(_ branch: String) -> Bool {
        BranchLogic.isMainBranch(name: branch)
    }
    
    private func resetForm() {
        branchName = ""
        description = ""
        baseBranch = availableBranches.first ?? "main"
        validationError = nil
    }
}

// MARK: - Preview

#Preview {
    CreateBranchView(
        isPresented: .constant(true),
        projectPath: "/Users/test/project",
        onCreateBranch: { params in
            print("创建分支：\(params.name)")
        }
    )
}