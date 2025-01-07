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
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // 项目名称和按钮
            HStack {
                Text(project.name)
                    .font(.headline)
                    .lineLimit(1)
                
                Spacer()
                
                Button(action: {
                    openInCursor(path: project.path)
                }) {
                    Image(systemName: "chevron.right.circle")
                        .foregroundColor(.blue)
                }
                .buttonStyle(.plain)
                .help("在 Cursor 中打开")
            }
            
            // 项目路径
            Text(project.path)
                .font(.caption)
                .foregroundColor(.secondary)
                .lineLimit(1)
            
            // 最后修改时间
            Text(project.lastModified)
                .font(.caption)
                .foregroundColor(.secondary)
            
            // 标签流布局
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 4) {
                    ForEach(Array(project.tags).sorted(), id: \.self) { tag in
                        TagView(
                            tag: tag,
                            color: tagManager.getColor(for: tag),
                            fontSize: 11
                        )
                    }
                }
                .padding(.vertical, 4)
            }
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color(.textBackgroundColor))
                .shadow(radius: 2)
        )
        .contentShape(Rectangle())
        .onTapGesture {
            openInCursor(path: project.path)
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
                lastModified: "2024-01-01",
                tags: ["Swift", "iOS"]
            ),
            tagManager: TagManager()
        )
        .padding()
    }
}
#endif 