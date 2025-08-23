import SwiftUI

struct SearchSortBar: View {
    @Binding var searchText: String
    @Binding var sortOption: ProjectListView.SortOption
    @Binding var searchBarRef: SearchBar?
    
    var body: some View {
        HStack(spacing: 8) {
            SearchBar(text: $searchText)
                .modifier(ViewReferenceSetter(reference: $searchBarRef))
            
            SortButtons(sortOption: $sortOption)
        }
        .padding(AppTheme.searchBarAreaPadding)
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
    @Binding var sortOption: ProjectListView.SortOption
    
    var body: some View {
        HStack(spacing: 8) {
            // 时间排序按钮
            Button(action: {
                switch sortOption {
                case .timeDesc: sortOption = .timeAsc
                case .timeAsc: sortOption = .timeDesc
                case .commitCount: sortOption = .timeDesc
                }
            }) {
                Image(systemName: sortOption == .timeAsc ? "arrow.up.circle.fill" : "arrow.down.circle.fill")
                    .foregroundColor(sortOption == .commitCount ? AppTheme.titleBarIcon : AppTheme.accent)
                    .font(.system(size: 20))
            }
            .buttonStyle(.plain)
            .help(sortOption == .timeAsc ? "最早的在前" : "最新的在前")

            // 提交次数排序按钮
            Button(action: {
                sortOption = .commitCount
            }) {
                Image(systemName: "number.circle.fill")
                    .foregroundColor(sortOption == .commitCount ? AppTheme.accent : AppTheme.titleBarIcon)
                    .font(.system(size: 20))
            }
            .buttonStyle(.plain)
            .help("按提交次数排序")
        }
    }
}

#if DEBUG
struct SearchSortBar_Previews: PreviewProvider {
    static var previews: some View {
        SearchSortBar(
            searchText: .constant(""),
            sortOption: .constant(.timeDesc),
            searchBarRef: .constant(nil)
        )
    }
}
#endif 