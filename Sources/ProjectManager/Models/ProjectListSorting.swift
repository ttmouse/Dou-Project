enum ProjectListSortColumn: Equatable {
    case name
    case activity
    case commits
}

enum SortOption: Equatable {
    case nameAscending
    case nameDescending
    case timeAscending
    case timeDescending
    case commitCountAscending
    case commitCountDescending

    var column: ProjectListSortColumn {
        switch self {
        case .nameAscending, .nameDescending:
            return .name
        case .timeAscending, .timeDescending:
            return .activity
        case .commitCountAscending, .commitCountDescending:
            return .commits
        }
    }

    var isAscending: Bool {
        switch self {
        case .nameAscending, .timeAscending, .commitCountAscending:
            return true
        case .nameDescending, .timeDescending, .commitCountDescending:
            return false
        }
    }

    func toggled(for column: ProjectListSortColumn) -> SortOption {
        switch column {
        case .name:
            guard self.column == .name else { return .nameAscending }
            return isAscending ? .nameDescending : .nameAscending
        case .activity:
            guard self.column == .activity else { return .timeDescending }
            return isAscending ? .timeDescending : .timeAscending
        case .commits:
            guard self.column == .commits else { return .commitCountDescending }
            return isAscending ? .commitCountDescending : .commitCountAscending
        }
    }
}
