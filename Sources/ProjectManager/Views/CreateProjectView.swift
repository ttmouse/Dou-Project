import SwiftUI

struct CreateProjectView: View {
    @Environment(\.presentationMode) var presentationMode
    
    // 基本信息
    @State private var projectName: String = ""
    
    // 标签相关
    @State private var selectedTags: Set<String> = []
    
    // 状态管理
    @State private var isCreating = false
    @State private var showingError = false
    @State private var errorMessage = ""
    
    let parentDirectory: String
    let tagManager: TagManager
    
    init(parentDirectory: String, tagManager: TagManager) {
        self.parentDirectory = parentDirectory
        self.tagManager = tagManager
    }
    
    var body: some View {
        VStack(spacing: 0) {
            headerView
                .padding(.top, 24)
                .padding(.bottom, 20)
            
            formContentView
                .padding(.horizontal, 24)
            
            Spacer(minLength: 20)
            
            buttonView
                .padding(.horizontal, 24)
                .padding(.bottom, 24)
        }
        .frame(width: 450, height: 380)
        .background(Color(NSColor.controlBackgroundColor))
        .alert("创建失败", isPresented: $showingError) {
            Button("确定", role: .cancel) { }
        } message: {
            Text(errorMessage)
        }
    }
    
    private var headerView: some View {
        Text("创建新项目")
            .font(.title2)
            .fontWeight(.bold)
    }
    
    private var formContentView: some View {
        VStack(alignment: .leading, spacing: 18) {
            projectNameSection
            locationSection
            tagSection
        }
    }
    
    private var projectNameSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("项目名称")
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(.primary)
            
            TextField("输入项目名称", text: $projectName)
                .textFieldStyle(RoundedBorderTextFieldStyle())
                .frame(height: 28)
        }
    }
    
    private var locationSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("创建位置")
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(.primary)
            
            Text(parentDirectory)
                .font(.system(size: 12))
                .foregroundColor(.secondary)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(NSColor.controlBackgroundColor).opacity(0.5))
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(Color.gray.opacity(0.3), lineWidth: 1)
                )
                .cornerRadius(6)
        }
    }
    
    
    private var tagSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("常用标签")
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(.primary)
            
            // 展示 top5 最高频标签 - 使用普通 VStack 避免 LazyVGrid 的性能问题
            tagGridView
        }
    }
    
    @ViewBuilder
    private var tagGridView: some View {
        let topTags = topFrequentTags // 预计算避免重复计算
        if !topTags.isEmpty {
            let rows = createTagRows(from: topTags)
            VStack(spacing: 8) {
                ForEach(0..<rows.count, id: \.self) { rowIndex in
                    HStack(spacing: 10) {
                        ForEach(rows[rowIndex], id: \.self) { tag in
                            TagButton(
                                tag: tag,
                                color: tagManager.getColor(for: tag),
                                isSelected: selectedTags.contains(tag)
                            ) {
                                toggleTagSelection(tag)
                            }
                        }
                        
                        // 填充剩余空间
                        if rows[rowIndex].count < 3 {
                            Spacer()
                        }
                    }
                }
            }
            .padding(.top, 4)
        } else {
            Text("暂无常用标签")
                .foregroundColor(.secondary)
                .font(.caption)
                .padding(.top, 4)
        }
    }
    
    // 预计算 top5 标签，避免重复计算
    private var topFrequentTags: [String] {
        let allTags = Array(tagManager.allTags)
        return allTags
            .map { tag in
                (tag: tag, count: tagManager.getUsageCount(for: tag))
            }
            .sorted { $0.count > $1.count }
            .prefix(5)
            .map { $0.tag }
    }
    
    // 将标签按行分组，每行最多3个
    private func createTagRows(from tags: [String]) -> [[String]] {
        var rows: [[String]] = []
        var currentRow: [String] = []
        
        for tag in tags {
            currentRow.append(tag)
            if currentRow.count == 3 {
                rows.append(currentRow)
                currentRow = []
            }
        }
        
        if !currentRow.isEmpty {
            rows.append(currentRow)
        }
        
        return rows
    }
    
    private func toggleTagSelection(_ tag: String) {
        if selectedTags.contains(tag) {
            selectedTags.remove(tag)
        } else {
            selectedTags.insert(tag)
        }
    }
    
    
    private var buttonView: some View {
        HStack {
            Button("取消") {
                presentationMode.wrappedValue.dismiss()
            }
            .keyboardShortcut(.escape)
            
            Spacer()
            
            Button("创建项目") {
                createProject()
            }
            .buttonStyle(.borderedProminent)
            .disabled(projectName.isEmpty || isCreating)
            .keyboardShortcut(.return)
        }
    }
    
    private func createProject() {
        guard !projectName.isEmpty else { return }
        
        isCreating = true
        
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                let projectPath = "\(parentDirectory)/\(projectName)"
                
                // 检查目录是否已存在
                if FileManager.default.fileExists(atPath: projectPath) {
                    throw ProjectCreationError.directoryExists
                }
                
                // 创建项目目录
                try FileManager.default.createDirectory(
                    at: URL(fileURLWithPath: projectPath),
                    withIntermediateDirectories: true,
                    attributes: nil
                )
                
                // 创建基本 README 文件
                try createBasicFiles(at: projectPath)
                
                // 创建项目对象
                let project = Project(
                    name: projectName,
                    path: projectPath,
                    tags: selectedTags
                )
                
                // 注册项目
                DispatchQueue.main.async {
                    tagManager.registerProject(project)
                    
                    isCreating = false
                    presentationMode.wrappedValue.dismiss()
                }
                
            } catch {
                DispatchQueue.main.async {
                    isCreating = false
                    errorMessage = error.localizedDescription
                    showingError = true
                }
            }
        }
    }
    
    private func createBasicFiles(at path: String) throws {
        // 创建一个简单的 README 文件
        let readmeContent = "# \(projectName)\n\n这是一个新项目。\n"
        try readmeContent.write(
            to: URL(fileURLWithPath: "\(path)/README.md"),
            atomically: true,
            encoding: .utf8
        )
    }
}

// MARK: - 项目创建错误
enum ProjectCreationError: Error, LocalizedError {
    case directoryExists
    case creationFailed(Error)
    
    var errorDescription: String? {
        switch self {
        case .directoryExists:
            return "项目目录已存在"
        case .creationFailed(let error):
            return "创建失败：\(error.localizedDescription)"
        }
    }
}

// MARK: - 标签按钮组件
struct TagButton: View {
    let tag: String
    let color: Color
    let isSelected: Bool
    let action: () -> Void
    
    @State private var isHovered = false
    
    var body: some View {
        Button(action: action) {
            Text(tag)
                .font(.system(size: 11, weight: .medium))
                .lineLimit(1)
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .frame(maxWidth: .infinity)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(backgroundColor)
                        .overlay(
                            RoundedRectangle(cornerRadius: 6)
                                .stroke(borderColor, lineWidth: isSelected ? 0 : 1)
                        )
                )
                .foregroundColor(textColor)
                .scaleEffect(isHovered ? 1.02 : 1.0)
                .animation(.easeInOut(duration: 0.15), value: isHovered)
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            isHovered = hovering
        }
    }
    
    private var backgroundColor: Color {
        if isSelected {
            return color
        } else if isHovered {
            return color.opacity(0.3)
        } else {
            return color.opacity(0.15)
        }
    }
    
    private var textColor: Color {
        isSelected ? .white : color
    }
    
    private var borderColor: Color {
        color.opacity(0.4)
    }
}

#if DEBUG
struct CreateProjectView_Previews: PreviewProvider {
    static var previews: some View {
        CreateProjectView(
            parentDirectory: "/Users/test/Projects",
            tagManager: TagManager()
        )
    }
}
#endif