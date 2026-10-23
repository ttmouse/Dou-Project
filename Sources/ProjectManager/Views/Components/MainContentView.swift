import Combine
import SwiftUI

final class ProjectTagDisplayCache: ObservableObject {
    private struct Entry {
        let tags: Set<String>
        let colorRevision: Int
        let displayTags: [TagDisplayData]
    }

    private var entries: [UUID: Entry] = [:]

    /// 标签颜色映射的版本号。
    ///
    /// 背景：原先靠 `tagManager.objectWillChange` 无差别 `clear()`。
    /// `objectWillChange` 在项目扫描、选中变化、Git 回填时都会发，等于每次
    /// 都把所有项目的标签展示缓存作废，接着全量重算一遍 —— 而这些事件根本
    /// 不改变任何标签颜色。改为只在颜色字典真的变化时递增版本号。
    private var colorRevision = 0

    /// 由外部在 `TagColorManager.tagColors` 变化时调用。
    func invalidateColors() {
        colorRevision &+= 1
    }

    func displayTags(for project: Project, tagManager: TagManager) -> [TagDisplayData] {
        if let entry = entries[project.id],
           entry.tags == project.tags,
           entry.colorRevision == colorRevision {
            return entry.displayTags
        }

        let displayTags = project.tags.sorted().map { tag in
            TagDisplayData(name: tag, color: tagManager.getColor(for: tag))
        }
        entries[project.id] = Entry(
            tags: project.tags,
            colorRevision: colorRevision,
            displayTags: displayTags
        )
        return displayTags
    }

    /// 全量失效。仅在项目集合结构发生根本变化时使用。
    func clear() {
        entries.removeAll()
    }
}

struct MainContentView: View {
    let searchInput: ProjectSearchInput
    let results: ProjectResultsStore
    @Binding var sortOption: SortOption
    @Binding var dateFilter: DateFilter
    @Binding var selectedProjects: Set<UUID>
    @Binding var searchBarRef: SearchBar?
    @Binding var showDetailPanel: Bool
    @Binding var projectViewMode: ProjectViewMode
    @EnvironmentObject var tagManager: TagManager
    @ObservedObject var editorManager: EditorManager

    let onShowProjectDetail: (Project) -> Void
    let onTagSelected: (String) -> Void
    @StateObject private var tagDisplayCache = ProjectTagDisplayCache()
    
    var body: some View {
        VStack(spacing: 0) {
            SearchSortBar(
                searchInput: searchInput,
                sortOption: $sortOption,
                dateFilter: $dateFilter,
                searchBarRef: $searchBarRef,
                showDetailPanel: $showDetailPanel,
                projectViewMode: $projectViewMode,
                tagManager: tagManager
            )

            ScanStatusView()

            // 结果区域自己订阅结果对象：搜索变化只重算这一块，
            // 工具栏与扫描状态条不参与重绘。
            ProjectResultsRegion(
                results: results,
                selectedProjects: $selectedProjects,
                searchBarRef: $searchBarRef,
                projectViewMode: projectViewMode,
                sortOption: $sortOption,
                editorManager: editorManager,
                onShowProjectDetail: onShowProjectDetail,
                onTagSelected: onTagSelected,
                tagDisplayCache: tagDisplayCache
            )
        }
        .onReceive(tagManager.colorManager.$tagColors.removeDuplicates()) { _ in
            // 只有标签颜色真的变化才作废展示缓存。
            // 原先监听的是 `tagManager.objectWillChange`，项目扫描、选中变化、
            // Git 回填都会触发，等于每次把所有项目的标签缓存全清重算。
            tagDisplayCache.invalidateColors()
        }
        .onDrop(of: ["public.file-url"], isTargeted: nil) { providers in
            guard let provider = providers.first else { return false }

            _ = provider.loadObject(ofClass: NSURL.self) { (url, error) in
                if let fileURL = url as? URL {
                    var isDirectory: ObjCBool = false
                    if FileManager.default.fileExists(
                        atPath: fileURL.path, isDirectory: &isDirectory) && isDirectory.boolValue
                    {
                        DispatchQueue.main.async {
                            // 获取文件的修改时间
                            let modDate =
                                (try? URL(fileURLWithPath: fileURL.path).resourceValues(
                                    forKeys: [.contentModificationDateKey]
                                ).contentModificationDate) ?? Date()

                            let project = Project(
                                name: fileURL.lastPathComponent,
                                path: fileURL.path,
                                lastModified: modDate
                            )
                            tagManager.registerProject(project)
                        }
                    }
                }
            }
            return true
        }
    }
}

// MARK: - 结果区域
/// 唯一订阅搜索结果的视图。
/// 空状态与列表在这里切换：从无结果恢复到有结果时，网格区域本身不必
/// 重新计算，只需重新填充内容。
struct ProjectResultsRegion: View {
    @ObservedObject var results: ProjectResultsStore
    @Binding var selectedProjects: Set<UUID>
    @Binding var searchBarRef: SearchBar?
    let projectViewMode: ProjectViewMode
    @Binding var sortOption: SortOption
    @EnvironmentObject var tagManager: TagManager
    @ObservedObject var editorManager: EditorManager
    let onShowProjectDetail: (Project) -> Void
    let onTagSelected: (String) -> Void
    @ObservedObject var tagDisplayCache: ProjectTagDisplayCache

    var body: some View {
        let projects = results.projects
        Group {
            if projects.isEmpty {
                EmptyStateView(isSearching: results.isSearching)
            } else {
                switch projectViewMode {
                case .grid:
                    ProjectGridView(
                        filteredProjects: projects,
                        selectedProjects: $selectedProjects,
                        searchBarRef: $searchBarRef,
                        editorManager: editorManager,
                        onShowProjectDetail: onShowProjectDetail,
                        onTagSelected: onTagSelected,
                        tagDisplayCache: tagDisplayCache
                    )
                case .list:
                    ProjectListRowsView(
                        filteredProjects: projects,
                        selectedProjects: $selectedProjects,
                        sortOption: $sortOption,
                        editorManager: editorManager,
                        onShowProjectDetail: onShowProjectDetail,
                        onTagSelected: onTagSelected,
                        tagDisplayCache: tagDisplayCache
                    )
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - 详情面板容器
/// 单独订阅结果，避免搜索结果变化时让详情面板跟着重建。
struct ProjectDetailPanelContainer: View {
    @ObservedObject var results: ProjectResultsStore
    let selectedProjectIDs: Set<UUID>
    @Binding var currentProjectID: UUID?
    @Binding var isVisible: Bool
    @ObservedObject var tagManager: TagManager

    var body: some View {
        let targetID = DetailPanelPresentationLogic.targetProjectID(
            isPanelVisible: isVisible,
            currentProjectID: currentProjectID,
            selectedProjectIDs: selectedProjectIDs,
            visibleProjectIDs: results.projects.map(\.id)
        )
        if let id = targetID, let project = tagManager.projects[id] {
            ProjectDetailView(
                project: ProjectData(from: project),
                isVisible: $isVisible,
                tagManager: tagManager
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

// MARK: - 空状态视图
struct EmptyStateView: View {
    /// 搜索无结果与「筛选后为空」是两种不同处境，文案不能混用。
    var isSearching: Bool = false

    var body: some View {
        VStack(spacing: 20) {
            Spacer()

            Image(systemName: isSearching ? "magnifyingglass" : "doc.text.magnifyingglass")
                .font(.system(size: 36))
                .foregroundColor(.secondary)

            Text(isSearching ? "没有匹配的项目" : "当前筛选下没有项目")
                .font(.headline)

            Text(isSearching ? "换个关键词，或清空搜索框回到浏览" : "尝试清除标签、目录或日期筛选")
                .font(.subheadline)
                .foregroundColor(.secondary)

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - 项目网格视图
struct ProjectGridView: View {
    let filteredProjects: [Project]
    @Binding var selectedProjects: Set<UUID>
    @Binding var searchBarRef: SearchBar?
    @EnvironmentObject var tagManager: TagManager
    @ObservedObject var editorManager: EditorManager
    let onShowProjectDetail: (Project) -> Void
    let onTagSelected: (String) -> Void
    @ObservedObject var tagDisplayCache: ProjectTagDisplayCache

    // 弹层集中在网格层承载一份，而不是每张卡一份。
    //
    // 背景：每张卡原本各挂两个 `.sheet` 和一个 `.alert`。131 张卡就是 393 份
    // 平台弹层锦点，每次结果集整体替换都要重建。改为用 id 驱动单份弹层后，
    // 卡片不再需要 @State，`Equatable` 判定也不再被本地弹层状态干扰。
    @State private var editingTagsProject: Project?
    @State private var renamingProject: Project?
    @State private var portConflict: PortConflictRequest?

    private struct PortConflictRequest: Identifiable {
        let id = UUID()
        let project: Project
        let port: Int
    }
    
    var body: some View {
        // 网格的滚动与复用交给 `NSCollectionView`，卡片内容仍是原来的 `ProjectCard`。
        //
        // 原来这里是 `ScrollView` + `LazyVGrid`：卡片数量 == SwiftUI 视图树数量，
        // 结果集整体替换时 SwiftUI 要重算 view graph、窗口 minSize、AutoLayout 再 diff。
        // 同一套采样下网格模式输入到画面中位 136 ms，而列表模式只有 48.5 ms，
        // 差距不在过滤（约 0.08 ms），全部在渲染层。
        ProjectCardCollectionView(
            projects: filteredProjects,
            selectedIDs: selectedProjects,
            searchBarRef: $searchBarRef,
            tagManager: tagManager,
            tagDisplayCache: tagDisplayCache,
            editorManager: editorManager,
            onShowProjectDetail: onShowProjectDetail,
            onTagSelected: onTagSelected,
            onSelect: { project, usesModifier in
                handleProjectSelection(project, usesModifier: usesModifier)
            },
            onRequestEditTags: { editingTagsProject = $0 },
            onRequestRename: { renamingProject = $0 },
            onPortConflict: { project, port in
                portConflict = PortConflictRequest(project: project, port: port)
            },
            onClearSelection: {
                NSApp.keyWindow?.makeFirstResponder(nil)
                searchBarRef?.clearFocus()
                if !selectedProjects.isEmpty { selectedProjects.removeAll() }
            },
            onSelectionChange: { selectedProjects = $0 }
        )
        .sheet(item: $editingTagsProject) { project in
            TagEditorView(project: project, tagManager: tagManager)
                .dismissibleSheet(isPresented: Binding(get: { editingTagsProject != nil }, set: { if !$0 { editingTagsProject = nil } }))
        }
        .sheet(item: $renamingProject) { project in
            ProjectRenameDialog(
                project: project,
                isPresented: Binding(
                    get: { renamingProject != nil },
                    set: { if !$0 { renamingProject = nil } }
                ),
                tagManager: tagManager
            ) { _ in }
            .dismissibleSheet(isPresented: Binding(get: { renamingProject != nil }, set: { if !$0 { renamingProject = nil } }))
        }
        .alert(
            "端口冲突",
            isPresented: Binding(
                get: { portConflict != nil },
                set: { if !$0 { portConflict = nil } }
            ),
            presenting: portConflict
        ) { request in
            Button("终止占用进程并启动", role: .destructive) {
                _ = ProjectRunner.killProcessAndRun(request.project)
            }
            Button("使用随机端口启动") {
                _ = ProjectRunner.run(request.project, useRandomPort: true)
            }
            Button("取消", role: .cancel) { }
        } message: { request in
            Text("端口 \(request.port) 正在被使用。您想如何处理？")
        }
        // 空白处点击由 `NSCollectionView` 的 backgroundView 处理，
        // 不再额外叠一层 SwiftUI 手势 —— 那层会挡住容器自己的点击区。
    }

    private func handleProjectSelection(_ project: Project, usesModifier: Bool) {
        // 确保在点击卡片时，移除现有焦点
        NSApp.keyWindow?.makeFirstResponder(nil)

        if usesModifier {
            // Shift 或 Command 键按下时，切换选中状态
            if selectedProjects.contains(project.id) {
                selectedProjects.remove(project.id)
            } else {
                selectedProjects.insert(project.id)
            }
        } else {
            // 没有按下修饰键时，单选
            selectedProjects = [project.id]
        }
    }
}

#if DEBUG
struct MainContentView_Previews: PreviewProvider {
    static var previews: some View {
        MainContentView(
            searchInput: ProjectSearchInput(),
            results: ProjectResultsStore(),
            sortOption: .constant(.timeDescending),
            dateFilter: .constant(.all),
            selectedProjects: .constant([]),
            searchBarRef: .constant(nil),
            showDetailPanel: .constant(false),
            projectViewMode: .constant(.grid),
            editorManager: EditorManager(),
            onShowProjectDetail: { _ in },
            onTagSelected: { _ in }
        )
        .environmentObject({
            let container = TagManager()
            return TagManager()
        }())
    }
}
#endif 
