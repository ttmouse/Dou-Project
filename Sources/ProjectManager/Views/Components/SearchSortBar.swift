import SwiftUI

struct SearchSortBar: View {
    let searchInput: ProjectSearchInput
    @Binding var sortOption: SortOption
    @Binding var dateFilter: DateFilter
    @Binding var searchBarRef: SearchBar?
    @Binding var showDetailPanel: Bool
    @Binding var projectViewMode: ProjectViewMode
    
    var body: some View {
        HStack(spacing: AppTheme.searchToolbarItemSpacing) {
            // 搜索框占据中间剩余空间，避免右侧控件溢出
            SearchBar(input: searchInput)
                .modifier(ViewReferenceSetter(reference: $searchBarRef))
                .frame(maxWidth: .infinity)

            // 右侧筛选和排序
            DateFilterMenu(dateFilter: $dateFilter)
            SortButtons(sortOption: $sortOption)

            Button {
                projectViewMode = projectViewMode == .grid ? .list : .grid
            } label: {
                ToolbarIcon(systemName: projectViewMode.icon)
            }
            .buttonStyle(IconButtonStyle(iconSize: 16, buttonSize: AppTheme.searchBarControlHeight))
            .accessibilityLabel("切换视图，当前\(projectViewMode.title)")
            .help("切换到\(projectViewMode == .grid ? ProjectViewMode.list.title : ProjectViewMode.grid.title)")

            // 详情面板从右侧展开，开关固定在工具栏最右侧以保持空间映射。
            Button(action: {
                withAnimation(.easeInOut(duration: 0.2)) {
                    showDetailPanel.toggle()
                }
            }) {
                ToolbarIcon(systemName: "sidebar.trailing")
            }
            .buttonStyle(IconButtonStyle(isSelected: showDetailPanel, iconSize: 16, buttonSize: AppTheme.searchBarControlHeight))
            .help(showDetailPanel ? "隐藏详情面板" : "显示详情面板")
        }
        .padding(.leading, AppTheme.cardGridPadding)
        .padding(.vertical, AppTheme.searchBarAreaPadding)
        .padding(.trailing, AppTheme.searchBarAreaPadding)
        .frame(height: AppTheme.searchBarAreaHeight)
        .background(AppTheme.searchBarAreaBackground)
        .overlay(
            Rectangle()
                .fill(AppTheme.searchBarAreaBorder)
                .frame(height: 1),
            alignment: .bottom
        )
    }
}

// MARK: - 排序按钮组件
struct SortButtons: View {
    @Binding var sortOption: SortOption
    @State private var isShowingOptions = false

    private var currentSortLabel: String {
        switch sortOption.column {
        case .activity:
            return sortOption.isAscending ? "更新时间 · 最早优先" : "更新时间 · 最新优先"
        case .commits:
            return sortOption.isAscending ? "提交次数 · 少到多" : "提交次数 · 多到少"
        case .name:
            return sortOption.isAscending ? "项目名称 · A 到 Z" : "项目名称 · Z 到 A"
        }
    }

    var body: some View {
        Button {
            isShowingOptions.toggle()
        } label: {
            ToolbarIcon(systemName: "arrow.up.arrow.down")
        }
        .buttonStyle(IconButtonStyle(iconSize: 16, buttonSize: AppTheme.searchBarControlHeight))
        .popover(isPresented: $isShowingOptions, arrowEdge: .bottom) {
            VStack(alignment: .leading, spacing: 5) {
                sortSection("更新时间", options: [
                    ("最新优先", .timeDescending),
                    ("最早优先", .timeAscending)
                ])
                Divider()
                sortSection("提交次数", options: [
                    ("多到少", .commitCountDescending),
                    ("少到多", .commitCountAscending)
                ])
                Divider()
                sortSection("项目名称", options: [
                    ("A 到 Z", .nameAscending),
                    ("Z 到 A", .nameDescending)
                ])
            }
            .padding(7)
            .frame(width: 192)
        }
        .help("排序方式：\(currentSortLabel)")
        .accessibilityLabel("排序方式")
        .accessibilityValue(currentSortLabel)
    }

    private func sortSection(_ title: String, options: [(String, SortOption)]) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(AppTheme.secondaryText)
                .padding(.horizontal, 8)

            ForEach(Array(options.enumerated()), id: \.offset) { _, item in
                let (title, option) = item
                Button {
                    sortOption = option
                    isShowingOptions = false
                } label: {
                    HStack(spacing: 8) {
                        Text(title)
                        Spacer(minLength: 8)
                        if sortOption == option {
                            Image(systemName: "checkmark")
                                .font(.system(size: 11, weight: .semibold))
                        }
                    }
                    .font(.system(size: 12, weight: .regular))
                    .foregroundColor(AppTheme.text)
                    .padding(.horizontal, 8)
                    .frame(maxWidth: .infinity, minHeight: 27)
                    .contentShape(RoundedRectangle(cornerRadius: 6))
                    .background(
                        sortOption == option ? AppTheme.accent.opacity(0.18) : .clear,
                        in: RoundedRectangle(cornerRadius: 6)
                    )
                }
                .buttonStyle(.plain)
            }
        }
    }
}

#if DEBUG
struct SearchSortBar_Previews: PreviewProvider {
    static var previews: some View {
        SearchSortBar(
            searchInput: ProjectSearchInput(),
            sortOption: .constant(.timeDescending),
            dateFilter: .constant(.all),
            searchBarRef: .constant(nil),
            showDetailPanel: .constant(false),
            projectViewMode: .constant(.grid)
        )
    }
}
#endif

// MARK: - 日期筛选菜单
struct DateFilterMenu: View {
    @Binding var dateFilter: DateFilter
    @State private var isShowingOptions = false

    private var isFiltering: Bool { dateFilter != .all }
    
    var body: some View {
        Button {
            isShowingOptions.toggle()
        } label: {
            HStack(spacing: AppTheme.toolbarIconLabelSpacing) {
                ToolbarIcon(systemName: "calendar")
                Text(dateFilter.compactLabel)
                    .font(.system(size: 12, weight: .medium))
            }
        }
        .buttonStyle(IconButtonStyle(
            isSelected: isFiltering,
            iconSize: 16,
            buttonSize: AppTheme.searchBarControlHeight,
            buttonWidth: 62
        ))
        .popover(isPresented: $isShowingOptions, arrowEdge: .bottom) {
            VStack(alignment: .leading, spacing: 3) {
                ForEach(DateFilter.allCases, id: \.self) { option in
                    Button {
                        dateFilter = option
                        isShowingOptions = false
                    } label: {
                        HStack {
                            Text(option.title)
                            Spacer(minLength: 12)
                            if dateFilter == option {
                                Image(systemName: "checkmark")
                                    .font(.system(size: 12, weight: .semibold))
                            }
                        }
                        .font(.system(size: 13, weight: .regular))
                        .foregroundColor(AppTheme.text)
                        .padding(.horizontal, 9)
                        .frame(maxWidth: .infinity, minHeight: 30)
                        .contentShape(RoundedRectangle(cornerRadius: 6))
                        .background(
                            dateFilter == option ? AppTheme.accent.opacity(0.18) : .clear,
                            in: RoundedRectangle(cornerRadius: 6)
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(6)
            .frame(width: 152)
        }
        .accessibilityLabel("日期筛选")
        .accessibilityValue(dateFilter.title)
        .help("按日期筛选项目")
    }
}
