import AppKit
import SwiftUI

class TagManager: ObservableObject {
    @Published var allTags: Set<String> = []
    @Published private(set) var projects: [UUID: Project] = [:]
    @Published private var tagUsageCount: [String: Int] = [:]
    @Published var tagColors: [String: Color] = [:]

    // 添加排序缓存
    private var sortedProjects: [Project] = []
    private var sortCriteria: SortCriteria = .lastModified
    private var isAscending: Bool = false
    private var tagLastUsed: [String: Date] = [:]
    private let cacheFileName = "project_cache.json"

    // 使用标准的 UserDefaults 和应用标识符
    private let defaults = UserDefaults.standard
    private let bundleId = Bundle.main.bundleIdentifier ?? "com.projectmanager"
    private var tagColorsKey: String {
        return "\(bundleId).TagColors"
    }

    enum SortCriteria {
        case name
        case lastModified
        case gitCommits
    }

    // MARK: - 初始化

    init() {
        // 先加载标签颜色
        loadTagColors()
        // 再加载系统标签
        loadSystemTags()
        // 最后加载项目缓存
        loadFromCache()
        updateSortedProjects()

        // 打印当前的配置信息
        print("应用标识符: \(bundleId)")
        print("标签颜色存储键: \(tagColorsKey)")
        print("当前 UserDefaults 所有键: \(Array(defaults.dictionaryRepresentation().keys))")
    }

    private func loadTagColors() {
        // 加载标签颜色
        print("开始从 UserDefaults 加载标签颜色 - Key: \(tagColorsKey)")
        if let colorData = defaults.object(forKey: tagColorsKey) as? Data {
            print("找到颜色数据，尝试解码...")
            do {
                let decodedColors = try JSONDecoder().decode([String: String].self, from: colorData)
                print("成功解码标签颜色: \(decodedColors)")
                tagColors = decodedColors.mapValues { Color(hex: $0) }
                print("当前加载的标签颜色: \(tagColors)")
            } catch {
                print("解码标签颜色失败: \(error)")
            }
        } else {
            print("UserDefaults 中未找到标签颜色数据")
        }
    }

    private func loadFromCache() {
        do {
            let data = try Data(contentsOf: cacheFileURL)
            let decoder = JSONDecoder()
            let cachedProjects = try decoder.decode([Project].self, from: data)
            print("从缓存加载 \(cachedProjects.count) 个项目")

            cachedProjects.forEach { project in
                projects[project.id] = project
                project.tags.forEach { tag in
                    addTag(tag)
                    incrementUsage(for: tag)
                }
            }
        } catch {
            print("加载缓存失败: \(error)")
        }
    }

    private func saveTagColors() {
        // 在主线程中执行保存操作
        DispatchQueue.main.async {
            do {
                let colorData = self.tagColors.compactMapValues { color -> String? in
                    // 将 Color 转换为 NSColor 然后获取 RGB 值
                    let nsColor = NSColor(color)
                    let red = Int(round(nsColor.redComponent * 255))
                    let green = Int(round(nsColor.greenComponent * 255))
                    let blue = Int(round(nsColor.blueComponent * 255))
                    let hexColor = String(format: "#%02X%02X%02X", red, green, blue)
                    return hexColor
                }

                let encoded = try JSONEncoder().encode(colorData)
                self.defaults.set(encoded, forKey: self.tagColorsKey)
                self.defaults.synchronize()

                // 立即验证保存
                if let savedData = self.defaults.object(forKey: self.tagColorsKey) as? Data,
                    let savedColors = try? JSONDecoder().decode(
                        [String: String].self, from: savedData)
                {
                    print("保存标签颜色成功，验证通过: \(savedColors)")
                } else {
                    print("警告：标签颜色保存后验证失败")
                }
            } catch {
                print("保存标签颜色失败: \(error)")
            }
        }
    }

    // MARK: - 项目排序

    private func updateSortedProjects() {
        let projectArray = Array(projects.values)
        sortedProjects = projectArray.sorted { p1, p2 in
            switch sortCriteria {
            case .lastModified:
                return isAscending
                    ? p1.lastModified < p2.lastModified : p1.lastModified > p2.lastModified
            case .name:
                return isAscending ? p1.name < p2.name : p1.name > p2.name
            case .gitCommits:
                let count1 = p1.gitInfo?.commitCount ?? 0
                let count2 = p2.gitInfo?.commitCount ?? 0
                return isAscending ? count1 < count2 : count1 > count2
            }
        }
    }

    func setSortCriteria(_ criteria: SortCriteria, ascending: Bool) {
        if sortCriteria != criteria || isAscending != ascending {
            sortCriteria = criteria
            isAscending = ascending
            updateSortedProjects()
        }
    }

    // 获取已排序的项目列表
    func getSortedProjects() -> [Project] {
        return sortedProjects
    }

    // 获取已排序并过滤的项目列表
    func getFilteredProjects(withTags tags: Set<String>, searchText: String = "") -> [Project] {
        let filtered = sortedProjects.filter { project in
            let matchesTags = tags.isEmpty || !tags.isDisjoint(with: project.tags)
            let matchesSearch =
                searchText.isEmpty || project.name.localizedCaseInsensitiveContains(searchText)
                || project.path.localizedCaseInsensitiveContains(searchText)
            return matchesTags && matchesSearch
        }
        return filtered
    }

    // MARK: - 缓存管理

    private var cacheFileURL: URL {
        let paths = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)
        return paths[0].appendingPathComponent("com.projectmanager").appendingPathComponent(
            cacheFileName)
    }

    // MARK: - 项目管理

    func removeProject(_ id: UUID) {
        if let project = projects[id] {
            project.tags.forEach { tag in
                decrementUsage(for: tag)
            }
            projects.removeValue(forKey: id)
            saveToCache()
        }
    }

    func clearProjects() {
        projects.removeAll()
        saveToCache()
    }

    // MARK: - 系统标签管理

    func loadSystemTags() {
        let workspace = NSWorkspace.shared
        let labels = workspace.fileLabels
        let colors = workspace.fileLabelColors

        for (index, label) in labels.enumerated() {
            allTags.insert(label)
            if index < colors.count {
                let color = Color(nsColor: colors[index])
                tagColors[label] = color
                print("加载系统标签: \(label), 颜色: \(colors[index])")
            }
        }
    }

    // MARK: - 项目标签管理

    func registerProject(_ project: Project) {
        print("注册项目: \(project.name), 标签: \(project.tags)")
        projects[project.id] = project
        project.tags.forEach { tag in
            addTag(tag)
            incrementUsage(for: tag)
        }

        // 使用二分查找插入新项目
        insertProjectInSortedArray(project)
        saveToCache()
    }

    private func insertProjectInSortedArray(_ project: Project) {
        let index = binarySearchInsertionIndex(for: project)
        sortedProjects.insert(project, at: index)
    }

    private func binarySearchInsertionIndex(for project: Project) -> Int {
        var left = 0
        var right = sortedProjects.count

        while left < right {
            let mid = (left + right) / 2
            if shouldInsertBefore(project, sortedProjects[mid]) {
                right = mid
            } else {
                left = mid + 1
            }
        }

        return left
    }

    private func shouldInsertBefore(_ p1: Project, _ p2: Project) -> Bool {
        switch sortCriteria {
        case .lastModified:
            return isAscending
                ? p1.lastModified < p2.lastModified : p1.lastModified > p2.lastModified
        case .name:
            return isAscending ? p1.name < p2.name : p1.name > p2.name
        case .gitCommits:
            let count1 = p1.gitInfo?.commitCount ?? 0
            let count2 = p2.gitInfo?.commitCount ?? 0
            return isAscending ? count1 < count2 : count1 > count2
        }
    }

    func updateProject(_ project: Project) {
        print("更新项目: \(project.name), 标签: \(project.tags)")
        projects[project.id] = project
    }

    func addTagToProject(projectId: UUID, tag: String) {
        print("尝试添加标签 '\(tag)' 到项目")
        guard var project = projects[projectId] else {
            print("未找到项目 ID: \(projectId)")
            return
        }

        if !project.tags.contains(tag) {
            print("项目原有标签: \(project.tags)")
            project.addTag(tag)
            print("添加标签后: \(project.tags)")
            projects[projectId] = project
            addTag(tag)
            incrementUsage(for: tag)
            print("标签添加完成")
        } else {
            print("项目已包含该标签")
        }
    }

    func removeTagFromProject(projectId: UUID, tag: String) {
        print("尝试从项目移除标签 '\(tag)'")
        guard var project = projects[projectId] else {
            print("未找到项目 ID: \(projectId)")
            return
        }

        if project.tags.contains(tag) {
            print("项目原有标签: \(project.tags)")
            project.removeTag(tag)
            print("移除标签后: \(project.tags)")
            projects[projectId] = project
            decrementUsage(for: tag)
            print("标签移除完成")
        } else {
            print("项目不包含该标签")
        }
    }

    // MARK: - 标签管理

    func addTag(_ tag: String) {
        print("添加标签到全局集合: \(tag)")
        allTags.insert(tag)
        if tagColors[tag] == nil {
            // 使用蓝色作为默认颜色
            tagColors[tag] = AppTheme.accent
            print("为标签 '\(tag)' 设置默认蓝色")
            saveTagColors()  // 只保存颜色数据
        }
    }

    func getColor(for tag: String) -> Color {
        // 为"全部"标签返回固定颜色
        if tag == "全部" {
            return AppTheme.accent
        }

        if let color = tagColors[tag] {
            return color
        }
        // 如果没有设置颜色，从预设颜色中随机选择一个
        let randomColor = AppTheme.tagPresetColors.randomElement()?.color ?? AppTheme.accent
        tagColors[tag] = randomColor
        saveTagColors()  // 只保存颜色数据
        return randomColor
    }

    func setColor(_ color: Color, for tag: String) {
        print("设置标签 '\(tag)' 的颜色")
        // 在主线程中执行颜色更新
        DispatchQueue.main.async {
            self.tagColors[tag] = color
            self.objectWillChange.send()
            // 延迟保存，避免频繁写入
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                self.saveTagColors()
            }
        }
    }

    // MARK: - 标签统计

    func getUsageCount(for tag: String) -> Int {
        return tagUsageCount[tag] ?? 0
    }

    // MARK: - 私有方法

    private func incrementUsage(for tag: String) {
        tagUsageCount[tag] = (tagUsageCount[tag] ?? 0) + 1
        tagLastUsed[tag] = Date()
        print("标签 '\(tag)' 使用次数: \(tagUsageCount[tag] ?? 0)")
    }

    private func decrementUsage(for tag: String) {
        if let count = tagUsageCount[tag] {
            if count > 1 {
                tagUsageCount[tag] = count - 1
            } else {
                tagUsageCount.removeValue(forKey: tag)
            }
        }
        print("标签 '\(tag)' 使用次数: \(tagUsageCount[tag] ?? 0)")
    }

    func removeTag(_ tag: String) {
        print("删除标签: \(tag)")
        // 从所有项目中移除该标签
        var updatedProjects: [UUID: Project] = [:]
        for (projectId, project) in projects {
            if project.tags.contains(tag) {
                var updatedProject = project
                updatedProject.removeTag(tag)
                updatedProjects[projectId] = updatedProject
            }
        }

        // 批量更新项目
        for (projectId, project) in updatedProjects {
            projects[projectId] = project
        }

        // 清理标签相关数据
        allTags.remove(tag)
        tagColors.removeValue(forKey: tag)
        tagUsageCount.removeValue(forKey: tag)
        tagLastUsed.removeValue(forKey: tag)

        // 保存更改
        saveToCache()
        saveTagColors()  // 保存颜色变更
    }

    func renameTag(_ oldName: String, to newName: String) {
        guard oldName != newName else { return }
        guard !allTags.contains(newName) else { return }

        // 保存旧标签的颜色和使用次数
        let oldColor = tagColors[oldName]
        let oldCount = tagUsageCount[oldName]

        // 从所有项目中更新标签
        for (projectId, project) in projects {
            if project.tags.contains(oldName) {
                var updatedProject = project
                updatedProject.removeTag(oldName)
                updatedProject.addTag(newName)
                projects[projectId] = updatedProject
            }
        }

        // 更新标签相关数据
        allTags.remove(oldName)
        allTags.insert(newName)

        if let color = oldColor {
            tagColors.removeValue(forKey: oldName)
            tagColors[newName] = color
        }

        if let count = oldCount {
            tagUsageCount.removeValue(forKey: oldName)
            tagUsageCount[newName] = count
        }

        // 保存更改
        saveToCache()
        saveTagColors()  // 保存颜色变更
    }

    private func saveToCache() {
        do {
            let encoder = JSONEncoder()
            let data = try encoder.encode(Array(projects.values))

            // 确保缓存目录存在
            let cacheDir = cacheFileURL.deletingLastPathComponent()
            try FileManager.default.createDirectory(at: cacheDir, withIntermediateDirectories: true)

            try data.write(to: cacheFileURL)
            print("项目缓存保存成功")
        } catch {
            print("保存缓存失败: \(error)")
        }
    }
}
