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
        VStack(spacing: 16) {
            Text("重命名项目")
                .font(.headline)
                .foregroundColor(AppTheme.text)

            VStack(alignment: .leading, spacing: 8) {
                Text("项目名称")
                    .font(.caption)
                    .foregroundColor(AppTheme.secondaryText)
                
                TextField("项目名称", text: $projectName)
                    .textFieldStyle(CustomTextFieldStyle())
                    .frame(width: 300)
                    .disabled(isRenaming)
                    .onSubmit {
                        performRename()
                    }
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("当前路径")
                    .font(.caption)
                    .foregroundColor(AppTheme.secondaryText)
                
                Text(project.path)
                    .font(.caption)
                    .foregroundColor(AppTheme.secondaryText)
                    .padding(8)
                    .background(AppTheme.cardBackground)
                    .cornerRadius(4)
                    .frame(width: 300, alignment: .leading)
            }
            
            if !projectName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && 
               projectName != project.name {
                VStack(alignment: .leading, spacing: 4) {
                    Text("新路径预览")
                        .font(.caption)
                        .foregroundColor(AppTheme.accent)
                    
                    Text(newPathPreview)
                        .font(.caption)
                        .foregroundColor(AppTheme.accent)
                        .padding(8)
                        .background(AppTheme.accent.opacity(0.1))
                        .cornerRadius(4)
                        .frame(width: 300, alignment: .leading)
                }
            }

            if !errorMessage.isEmpty {
                Text(errorMessage)
                    .foregroundColor(.red)
                    .font(.caption)
                    .frame(width: 300, alignment: .leading)
            }

            HStack(spacing: 12) {
                Button("取消") {
                    isPresented = false
                }
                .buttonStyle(CustomButtonStyle(isPrimary: false))
                .keyboardShortcut(.escape)
                .disabled(isRenaming)

                Button(isRenaming ? "重命名中..." : "确定") {
                    performRename()
                }
                .buttonStyle(CustomButtonStyle(isPrimary: true))
                .keyboardShortcut(.return)
                .disabled(isRenaming || !isValidName)
            }
            
            if isRenaming {
                ProgressView()
                    .scaleEffect(0.8)
            }
        }
        .padding()
        .background(AppTheme.secondaryBackground)
        .cornerRadius(8)
        .frame(width: 350)
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