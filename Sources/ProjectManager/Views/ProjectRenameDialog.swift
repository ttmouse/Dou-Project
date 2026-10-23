import SwiftUI

struct ProjectRenameDialog: View {
    let project: Project
    @Binding var isPresented: Bool
    @ObservedObject var tagManager: TagManager
    let onComplete: (Result<Void, RenameError>) -> Void

    @State private var projectName: String
    @State private var errorMessage: String = ""
    @State private var isRenaming: Bool = false

    init(
        project: Project,
        isPresented: Binding<Bool>,
        tagManager: TagManager,
        onComplete: @escaping (Result<Void, RenameError>) -> Void
    ) {
        self.project = project
        self._isPresented = isPresented
        self.tagManager = tagManager
        self.onComplete = onComplete
        self._projectName = State(initialValue: project.name)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("重命名项目")
                .font(.system(size: 18, weight: .semibold))
                .foregroundColor(AppTheme.text)
                .frame(maxWidth: .infinity)

            VStack(alignment: .leading, spacing: 6) {
                Text("项目名称")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(AppTheme.text)
                
                TextField("项目名称", text: $projectName)
                    .textFieldStyle(AppDialogTextFieldStyle())
                    .disabled(isRenaming)
                    .onSubmit {
                        performRename()
                    }
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("当前路径")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(AppTheme.text)
                
                Text(project.path)
                    .font(.system(size: 12))
                    .foregroundColor(AppTheme.secondaryText)
                    .lineLimit(2)
                    .textSelection(.enabled)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(AppTheme.cardBackground.opacity(0.55), in: RoundedRectangle(cornerRadius: 8))
            }
            
            if !projectName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && 
               projectName != project.name {
                VStack(alignment: .leading, spacing: 4) {
                    Text("新路径预览")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(AppTheme.accent)
                    
                    Text(newPathPreview)
                        .font(.system(size: 12))
                        .foregroundColor(AppTheme.accent)
                        .lineLimit(2)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 8)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(AppTheme.accent.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
                }
            }

            if !errorMessage.isEmpty {
                Text(errorMessage)
                    .foregroundColor(.red)
                    .font(.caption)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            HStack(spacing: 12) {
                Button("取消") {
                    isPresented = false
                }
                .buttonStyle(AppButtonStyle())
                .keyboardShortcut(.escape)
                .disabled(isRenaming)

                Button(isRenaming ? "重命名中..." : "确定") {
                    performRename()
                }
                .buttonStyle(AppButtonStyle(isPrimary: true))
                .keyboardShortcut(.return)
                .disabled(isRenaming || !isValidName)
            }
            .frame(maxWidth: .infinity)
            
            if isRenaming {
                ProgressView()
                    .scaleEffect(0.8)
            }
        }
        .padding(24)
        .background(AppTheme.secondaryBackground)
        .frame(width: 360)
        .onExitCommand {
            if !isRenaming { isPresented = false }
        }
    }
    
    // MARK: - 计算属性
    
    private var isValidName: Bool {
        let trimmed = projectName.trimmingCharacters(in: .whitespacesAndNewlines)
        return !trimmed.isEmpty && trimmed != project.name
    }
    
    private var newPathPreview: String {
        let parentDir = URL(fileURLWithPath: project.path).deletingLastPathComponent()
        return parentDir.appendingPathComponent(projectName.trimmingCharacters(in: .whitespacesAndNewlines)).path
    }
    
    // MARK: - 方法
    
    private func performRename() {
        let trimmedName = projectName.trimmingCharacters(in: .whitespacesAndNewlines)
        
        // 验证名称
        if trimmedName.isEmpty {
            errorMessage = "项目名称不能为空"
            return
        }
        
        if trimmedName == project.name {
            errorMessage = "项目名称未更改"
            return
        }
        
        // 开始重命名
        errorMessage = ""
        isRenaming = true
        
        tagManager.renameProject(project.id, newName: trimmedName) { result in
            DispatchQueue.main.async {
                self.isRenaming = false
                
                switch result {
                case .success():
                    self.isPresented = false
                    self.onComplete(.success(()))
                    
                case .failure(let error):
                    self.errorMessage = error.localizedDescription
                    self.onComplete(.failure(error))
                }
            }
        }
    }
}

#if DEBUG
struct ProjectRenameDialog_Previews: PreviewProvider {
    static var previews: some View {
        ProjectRenameDialog(
            project: Project(
                name: "示例项目",
                path: "/Users/example/Projects/demo",
                tags: ["Swift", "iOS"]
            ),
            isPresented: .constant(true),
            tagManager: TagManager(),
            onComplete: { _ in }
        )
        .background(AppTheme.background)
    }
}
#endif
