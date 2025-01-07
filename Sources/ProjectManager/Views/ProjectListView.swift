import SwiftUI

struct ProjectListView: View {
    @State private var searchText = ""
    @State private var selectedTags: Set<String> = []
    @State private var projects: [Project] = []
    @EnvironmentObject var tagManager: TagManager
    
    // 分步过滤
    private var filteredProjects: [Project] {
        var result = projects
        
        // 搜索过滤
        if !searchText.isEmpty {
            result = result.filter { $0.name.localizedCaseInsensitiveContains(searchText) }
        }
        
        // 标签过滤
        if !selectedTags.isEmpty {
            print("选中的标签: \(selectedTags)")
            result = result.filter { project in
                print("检查项目 '\(project.name)' 的标签: \(project.tags)")
                let hasTag = !selectedTags.isDisjoint(with: project.tags)
                print("项目 '\(project.name)' \(hasTag ? "包含" : "不包含")选中的标签")
                return hasTag
            }
        }
        
        return result
    }
    
    var body: some View {
        NavigationView {
            // 侧边栏
            VStack(spacing: 0) {
                // 标签列表
                List {
                    Section {
                        if !selectedTags.isEmpty {
                            HStack {
                                Spacer()
                                Button("清除筛选") {
                                    print("清除标签筛选")
                                    selectedTags.removeAll()
                                }
                                .buttonStyle(.plain)
                                .foregroundColor(.blue)
                            }
                        }
                        
                        ForEach(Array(tagManager.allTags).sorted(), id: \.self) { tag in
                            TagRow(
                                tag: tag,
                                isSelected: selectedTags.contains(tag),
                                count: tagManager.getUsageCount(for: tag),
                                action: {
                                    print("点击标签: \(tag)")
                                    if selectedTags.contains(tag) {
                                        print("移除标签: \(tag)")
                                        selectedTags.remove(tag)
                                    } else {
                                        print("选择标签: \(tag)")
                                        selectedTags = [tag]
                                    }
                                    print("当前选中的标签: \(selectedTags)")
                                },
                                tagManager: tagManager
                            )
                        }
                    } header: {
                        Text("标签")
                    }
                }
            }
            .frame(minWidth: 200, maxWidth: 300)
            
            // 主内容
            VStack {
                SearchBar(text: $searchText)
                    .padding()
                
                if filteredProjects.isEmpty {
                    VStack(spacing: 20) {
                        Spacer()
                        
                        Image(systemName: "doc.text.magnifyingglass")
                            .font(.system(size: 36))
                            .foregroundColor(.secondary)
                        
                        Text("没有匹配的项目")
                            .font(.headline)
                        
                        Text("尝试修改搜索条件或清除标签筛选")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                        
                        Spacer()
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    ScrollView {
                        LazyVGrid(
                            columns: [GridItem(.adaptive(minimum: 250, maximum: 400))],
                            spacing: 16
                        ) {
                            ForEach(filteredProjects) { project in
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
        .onAppear {
            loadProjects()
        }
    }
    
    private func loadProjects() {
        DispatchQueue.global(qos: .userInitiated).async { [self] in
            let baseDir = "/Users/douba/Downloads/GPT插件/"
            let loadedProjects = Project.loadProjects(from: baseDir)
            
            DispatchQueue.main.async { [self] in
                print("加载项目数量: \(loadedProjects.count)")
                projects = loadedProjects
                projects.forEach { project in
                    print("注册项目: \(project.name), 标签: \(project.tags)")
                    tagManager.registerProject(project)
                }
            }
        }
    }
}

#if DEBUG
struct ProjectListView_Previews: PreviewProvider {
    static var previews: some View {
        ProjectListView()
            .environmentObject(TagManager())
    }
}
#endif
