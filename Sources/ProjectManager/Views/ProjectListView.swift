import SwiftUI

struct ProjectListView: View {
    @State private var searchText = ""
    @State private var selectedTags: Set<String> = []
    @State private var projects: [Project] = []
    @EnvironmentObject var tagManager: TagManager
    
    // 分步过滤
    private var searchFiltered: [Project] {
        if searchText.isEmpty {
            return projects
        }
        return projects.filter { $0.name.localizedCaseInsensitiveContains(searchText) }
    }
    
    private var tagFiltered: [Project] {
        if selectedTags.isEmpty {
            return searchFiltered
        }
        return searchFiltered.filter { !selectedTags.isDisjoint(with: $0.tags) }
    }
    
    var body: some View {
        NavigationView {
            // 侧边栏
            SidebarView(
                selectedTags: $selectedTags,
                tagManager: tagManager,
                projects: projects
            )
            
            // 主内容
            MainContentView(
                searchText: $searchText,
                projects: tagFiltered,
                tagManager: tagManager
            )
        }
        .onAppear {
            loadProjects()
        }
    }
    
    private func loadProjects() {
        DispatchQueue.global(qos: .userInitiated).async { [self] in
            let baseDir = "/Users/douba/Downloads/GPT插件/"
            let loadedProjects = Project.loadProjects(from: baseDir)
            
            DispatchQueue.main.async { [self] in
                projects = loadedProjects
                // 注册所有项目到标签管理器
                projects.forEach { project in
                    tagManager.registerProject(project)
                    project.tags.forEach { tagManager.addTag($0) }
                }
            }
        }
    }
}

// MARK: - 子视图

private struct MainContentView: View {
    @Binding var searchText: String
    let projects: [Project]
    @ObservedObject var tagManager: TagManager
    
    var body: some View {
        VStack {
            SearchBar(text: $searchText)
                .padding()
            
            ScrollView {
                LazyVGrid(
                    columns: [GridItem(.adaptive(minimum: 250, maximum: 400))],
                    spacing: 16
                ) {
                    ForEach(projects) { project in
                        ProjectCard(
                            project: project,
                            tagManager: tagManager
                        )
                    }
                }
                .padding()
            }
        }
    }
}

private struct SidebarView: View {
    @Binding var selectedTags: Set<String>
    @ObservedObject var tagManager: TagManager
    let projects: [Project]
    
    var body: some View {
        VStack(spacing: 0) {
            // 常用标签
            TagSection(
                title: "常用标签",
                tags: tagManager.commonTags,
                selectedTags: $selectedTags,
                projects: projects,
                tagManager: tagManager
            )
            
            Divider().padding(.vertical)
            
            // 项目标签
            TagSection(
                title: "项目标签",
                tags: Array(tagManager.allTags).sorted(),
                selectedTags: $selectedTags,
                projects: projects,
                tagManager: tagManager
            )
        }
        .frame(minWidth: 200, maxWidth: 300)
        .background(Color(.windowBackgroundColor))
    }
}

private struct TagSection: View {
    let title: String
    let tags: [String]
    @Binding var selectedTags: Set<String>
    let projects: [Project]
    @ObservedObject var tagManager: TagManager
    
    // 预计算标签计数
    private func tagCount(_ tag: String) -> Int {
        projects.filter { $0.tags.contains(tag) }.count
    }
    
    // 处理标签选择
    private func toggleTag(_ tag: String) {
        if selectedTags.contains(tag) {
            selectedTags.remove(tag)
        } else {
            selectedTags.insert(tag)
        }
    }
    
    var body: some View {
        VStack(alignment: .leading) {
            Text(title)
                .font(.headline)
                .padding(.horizontal)
            
            ScrollView {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(tags, id: \.self) { tag in
                        TagRow(
                            tag: tag,
                            isSelected: selectedTags.contains(tag),
                            count: tagCount(tag),
                            action: { toggleTag(tag) },
                            tagManager: tagManager
                        )
                    }
                }
                .padding(.horizontal)
            }
        }
    }
}

#if DEBUG
struct ProjectListView_Previews: PreviewProvider {
    static var previews: some View {
        ProjectListView()
    }
}
#endif 