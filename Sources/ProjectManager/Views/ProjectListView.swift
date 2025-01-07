import SwiftUI

struct ProjectListView: View {
    @State private var searchText = ""
    @State private var selectedTags: Set<String> = []
    @EnvironmentObject var tagManager: TagManager
    
    // 分步过滤
    private var filteredProjects: [Project] {
        var result = Array(tagManager.projects.values)
        
        // 搜索过滤
        if !searchText.isEmpty {
            result = result.filter { $0.name.localizedCaseInsensitiveContains(searchText) }
        }
        
        // 标签过滤
        if !selectedTags.isEmpty {
            result = result.filter { project in
                !selectedTags.isDisjoint(with: project.tags)
            }
        }
        
        return result.sorted { $0.lastModified > $1.lastModified }
    }
    
    var body: some View {
        NavigationView {
            // 侧边栏
            VStack(spacing: 0) {
                // 标签列表
                List {
                    HStack {
                        Text("标签")
                            .font(.headline)
                            .foregroundColor(.secondary)
                        
                        Spacer()
                        
                        Button("清除筛选") {
                            selectedTags.removeAll()
                        }
                        .buttonStyle(.plain)
                        .foregroundColor(selectedTags.isEmpty ? .secondary : .blue)
                        .disabled(selectedTags.isEmpty)
                    }
                    .listRowInsets(EdgeInsets())
                    .padding(.horizontal)
                    .padding(.vertical, 8)
                    
                    ForEach(Array(tagManager.allTags).sorted(), id: \.self) { tag in
                        TagRow(
                            tag: tag,
                            isSelected: selectedTags.contains(tag),
                            count: tagManager.getUsageCount(for: tag),
                            action: {
                                if selectedTags.contains(tag) {
                                    selectedTags.remove(tag)
                                } else {
                                    selectedTags = [tag]
                                }
                            },
                            tagManager: tagManager
                        )
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
        DispatchQueue.global(qos: .userInitiated).async {
            let baseDir = "/Users/douba/Downloads/GPT插件/"
            let loadedProjects = Project.loadProjects(from: baseDir)
            
            DispatchQueue.main.async {
                loadedProjects.forEach { project in
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
