import SwiftUI

/// 项目列表弹窗 - 显示选中日期的活跃项目
struct ProjectListPopover: View {
    let projects: [ProjectData]
    let date: String
    @Binding var isPresented: Bool
    
    var body: some View {
        VStack(alignment: .leading, spacing: AppTheme.tagListSpacing) {
            // 头部
            HStack {
                Text("\(date) 的活跃项目")
                    .font(AppTheme.subtitleFont)
                    .foregroundColor(AppTheme.text)
                Spacer()
                Button("关闭") {
                    isPresented = false
                }
                .keyboardShortcut(.escape)
            }
            .padding(.horizontal, AppTheme.tagListHeaderPaddingH)
            .padding(.vertical, AppTheme.tagListHeaderPaddingV)
            
            // 项目列表
            ScrollView {
                LazyVStack(alignment: .leading, spacing: AppTheme.tagRowSpacing) {
                    ForEach(projects, id: \.id) { project in
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(project.name)
                                    .font(AppTheme.bodyFont)
                                    .fontWeight(.medium)
                                    .foregroundColor(AppTheme.text)
                                
                                Text(project.path)
                                    .font(AppTheme.captionFont)
                                    .foregroundColor(AppTheme.secondaryText)
                                    .truncationMode(.middle)
                                
                                if let gitInfo = project.gitInfo {
                                    Text("提交数: \(gitInfo.commitCount)")
                                        .font(AppTheme.captionFont)
                                        .foregroundColor(AppTheme.success)
                                }
                            }
                            Spacer()
                        }
                        .padding(AppTheme.tagRowPaddingH)
                        .background(AppTheme.cardBackground)
                        .cornerRadius(AppTheme.tagRowCornerRadius)
                    }
                }
            }
            .padding(.horizontal, AppTheme.tagListContentPaddingV)
        }
        .padding()
        .frame(minWidth: 300, maxWidth: 400, minHeight: 200, maxHeight: 400)
        .background(AppTheme.secondaryBackground)
    }
}

// MARK: - Preview
#if DEBUG
struct ProjectListPopover_Previews: PreviewProvider {
    static var previews: some View {
        ProjectListPopover(
            projects: createSampleProjects(),
            date: "8月26日",
            isPresented: .constant(true)
        )
    }
    
    static func createSampleProjects() -> [ProjectData] {
        let now = Date()
        
        return [
            ProjectData(
                id: UUID(),
                name: "ProjectManager",
                path: "/Users/example/Projects/ProjectManager",
                lastModified: now,
                tags: ["Swift", "macOS"],
                gitInfo: ProjectData.GitInfoData(
                    commitCount: 5,
                    lastCommitDate: now
                ),
                fileSystemInfo: ProjectData.FileSystemInfoData(
                    modificationDate: now,
                    size: 1024000,
                    checksum: "sha256:sample1",
                    lastCheckTime: now
                )
            ),
            ProjectData(
                id: UUID(),
                name: "WebApp",
                path: "/Users/example/Projects/WebApp",
                lastModified: now,
                tags: ["React", "TypeScript"],
                gitInfo: ProjectData.GitInfoData(
                    commitCount: 12,
                    lastCommitDate: now
                ),
                fileSystemInfo: ProjectData.FileSystemInfoData(
                    modificationDate: now,
                    size: 2048000,
                    checksum: "sha256:sample2",
                    lastCheckTime: now
                )
            )
        ]
    }
}
#endif