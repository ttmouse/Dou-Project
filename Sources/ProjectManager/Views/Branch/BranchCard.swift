import SwiftUI

// MARK: - Branch Card Component
// 分支卡片组件 - 显示单个分支的信息和操作

struct BranchCard: View {
    let branch: BranchInfo
    let onOpen: () -> Void
    let onDelete: () -> Void
    let onMerge: (() -> Void)?
    let isSelectionMode: Bool
    let isSelected: Bool
    let onSelectionToggle: (() -> Void)?
    
    @State private var isHovered = false
    @ObservedObject private var editorManager = AppOpenHelper.editorManager
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // 分支头部信息
            HStack {
                // 选择模式下的复选框
                if isSelectionMode && !branch.isMain {
                    Button(action: { onSelectionToggle?() }) {
                        Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                            .foregroundColor(isSelected ? .blue : .secondary)
                            .font(.caption)
                    }
                    .buttonStyle(PlainButtonStyle())
                }
                
                // 分支名称和状态
                HStack(spacing: 6) {
                    statusIndicator
                    
                    VStack(alignment: .leading, spacing: 2) {
                        Text(branch.name)
                            .font(.headline)
                            .foregroundColor(.primary)
                            .lineLimit(1)
                        
                        if !branch.description.isEmpty {
                            Text(branch.description)
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .lineLimit(2)
                        }
                    }
                    
                    Spacer()
                }
                
                // 操作按钮区域（非选择模式时显示）
                if !isSelectionMode && (isHovered || branch.hasUncommittedChanges) {
                    actionButtons
                }
            }
            
            // 分支详细信息
            branchDetails
            
            // 统计信息
            if branch.hasUncommittedChanges || branch.diskSize != nil {
                statisticsSection
            }
        }
        .padding(12)
        .background(cardBackground)
        .cornerRadius(8)
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(borderColor, lineWidth: 1)
        )
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.2)) {
                isHovered = hovering
            }
        }
        .onTapGesture {
            if isSelectionMode && !branch.isMain {
                onSelectionToggle?()
            }
        }
        .contextMenu {
            // 选择模式下不显示上下文菜单
            if !isSelectionMode {
                contextMenuContent
            }
        }
    }
    
    // MARK: - View Components
    
    private var statusIndicator: some View {
        Circle()
            .fill(statusColor)
            .frame(width: 8, height: 8)
    }
    
    private var actionButtons: some View {
        HStack(spacing: 4) {
            // 打开按钮
            Button(action: {
                AppOpenHelper.openInDefaultEditor(path: branch.path)
            }) {
                Image(systemName: "folder.fill")
                    .foregroundColor(.blue)
            }
            .buttonStyle(PlainButtonStyle())
            .help("在编辑器中打开分支")
            
            // Ghostty 终端按钮
            Button(action: {
                openInGhostty()
            }) {
                Image(systemName: "terminal.fill")
                    .foregroundColor(.purple)
            }
            .buttonStyle(PlainButtonStyle())
            .help("在 Ghostty 终端中打开")
            
            // 合并按钮（仅非主分支显示）
            if !branch.isMain, let onMerge = onMerge {
                Button(action: onMerge) {
                    Image(systemName: "arrow.triangle.merge")
                        .foregroundColor(.green)
                }
                .buttonStyle(PlainButtonStyle())
                .help("合并到主分支")
            }
            
            // 删除按钮（仅非主分支显示）
            if !branch.isMain {
                Button(action: onDelete) {
                    Image(systemName: "trash.fill")
                        .foregroundColor(.red)
                }
                .buttonStyle(PlainButtonStyle())
                .help("删除分支")
            }
        }
    }
    
    private var branchDetails: some View {
        VStack(alignment: .leading, spacing: 4) {
            // 创建时间和最后使用时间
            HStack {
                Label {
                    Text(formatDate(branch.createdAt))
                        .font(.caption2)
                        .foregroundColor(.secondary)
                } icon: {
                    Image(systemName: "calendar.badge.plus")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                if let lastUsed = branch.lastUsed {
                    Label {
                        Text(formatRelativeDate(lastUsed))
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    } icon: {
                        Image(systemName: "clock")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                } else {
                    Text("从未使用")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }
            
            // 分支路径（截断显示）
            Text(abbreviatedPath)
                .font(.caption2)
                .foregroundColor(Color.secondary.opacity(0.7))
                .lineLimit(1)
        }
    }
    
    private var statisticsSection: some View {
        HStack {
            // 未提交更改
            if branch.hasUncommittedChanges {
                Label {
                    Text("\(branch.uncommittedChanges) 更改")
                        .font(.caption2)
                        .foregroundColor(.orange)
                } icon: {
                    Image(systemName: "exclamationmark.circle.fill")
                        .font(.caption2)
                        .foregroundColor(.orange)
                }
            }
            
            Spacer()
            
            // 磁盘大小
            if let diskSize = branch.diskSize {
                Text(branch.formattedDiskSize)
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
        }
    }
    
    private var contextMenuContent: some View {
        Group {
            // 打开方式菜单
            Menu("打开方式") {
                let sortedEditors = editorManager.editors.sorted { $0.displayOrder < $1.displayOrder }
                
                ForEach(sortedEditors, id: \.id) { editor in
                    Button(action: {
                        AppOpenHelper.openInEditor(editor, path: branch.path)
                    }) {
                        HStack {
                            Label(editor.name, systemImage: getEditorIcon(for: editor))
                            Spacer()
                            
                            // 状态指示器
                            if editor.isEnabled {
                                Image(systemName: "checkmark")
                                    .foregroundColor(.green)
                                    .font(.caption2)
                            } else {
                                Image(systemName: "exclamationmark.triangle")
                                    .foregroundColor(.orange)
                                    .font(.caption2)
                            }
                        }
                    }
                }
                
                Divider()
                
                Button("在访达中打开") {
                    AppOpenHelper.performSystemAction(.showInFinder, path: branch.path)
                }
                
                Divider()
                
                Button("在 Ghostty 中打开") {
                    openInGhostty()
                }
            }
            
            if !branch.isMain {
                Divider()
                
                if let onMerge = onMerge {
                    Button("合并到主分支", action: onMerge)
                }
                
                Button("删除分支", action: onDelete)
            }
            
            Divider()
            
            Button("复制路径") {
                AppOpenHelper.performSystemAction(.copyPath, path: branch.path)
            }
            
            Button("在访达中显示") {
                AppOpenHelper.performSystemAction(.showInFinder, path: branch.path)
            }
        }
    }
    
    // MARK: - Computed Properties
    
    private var statusColor: Color {
        switch branch.status {
        case .clean:
            return .green
        case .hasChanges:
            return .orange
        case .unknown:
            return .gray
        }
    }
    
    private var cardBackground: Color {
        if branch.isMain {
            return Color.blue.opacity(0.1)
        } else if isHovered {
            return Color.primary.opacity(0.05)
        } else {
            return Color.clear
        }
    }
    
    private var borderColor: Color {
        if isSelectionMode && isSelected {
            return Color.blue
        } else if branch.isMain {
            return Color.blue.opacity(0.3)
        } else if isHovered {
            return Color.primary.opacity(0.2)
        } else {
            return Color.primary.opacity(0.1)
        }
    }
    
    private var abbreviatedPath: String {
        let url = URL(fileURLWithPath: branch.path)
        let components = url.pathComponents
        
        if components.count > 3 {
            let start = components.prefix(2).joined(separator: "/")
            let end = components.suffix(2).joined(separator: "/")
            return "\(start)/…/\(end)"
        } else {
            return branch.path
        }
    }
    
    // MARK: - Helper Functions
    
    private func openInGhostty() {
        let task = Process()
        task.launchPath = "/usr/bin/open"
        task.arguments = ["-a", "Ghostty", branch.path]
        
        do {
            try task.run()
        } catch {
            print("Failed to open Ghostty: \(error)")
            // 如果 Ghostty 打开失败，尝试默认终端
            fallbackToDefaultTerminal()
        }
    }
    
    private func fallbackToDefaultTerminal() {
        let task = Process()
        task.launchPath = "/usr/bin/open"
        task.arguments = ["-a", "Terminal", branch.path]
        
        do {
            try task.run()
        } catch {
            print("Failed to open Terminal: \(error)")
        }
    }
    
    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .none
        return formatter.string(from: date)
    }
    
    private func formatRelativeDate(_ date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.dateTimeStyle = .named
        return formatter.localizedString(for: date, relativeTo: Date())
    }
    
    private func getEditorIcon(for editor: EditorConfig) -> String {
        switch editor.name.lowercased() {
        case "cursor":
            return "cursorarrow.rays"
        case "visual studio code", "vscode", "code":
            return "chevron.left.slash.chevron.right"
        case "sublime text":
            return "doc.text"
        case "ghostty":
            return "terminal.fill"
        default:
            return "app"
        }
    }
}

// MARK: - Preview

#Preview {
    VStack(spacing: 12) {
        // 主分支预览
        BranchCard(
            branch: BranchInfo(
                name: "main",
                path: "/Users/test/project/main",
                description: "主要开发分支",
                status: .clean,
                createdAt: Date().addingTimeInterval(-86400 * 30),
                lastUsed: Date().addingTimeInterval(-3600),
                uncommittedChanges: 0,
                diskSize: 1024 * 1024 * 50,
                isMain: true
            ),
            onOpen: {},
            onDelete: {},
            onMerge: nil,
            isSelectionMode: false,
            isSelected: false,
            onSelectionToggle: nil
        )
        
        // 功能分支预览
        BranchCard(
            branch: BranchInfo(
                name: "feature-login",
                path: "/Users/test/project/.trees/feature-login",
                description: "实现用户登录功能",
                status: .hasChanges,
                createdAt: Date().addingTimeInterval(-86400 * 7),
                lastUsed: Date().addingTimeInterval(-1800),
                uncommittedChanges: 3,
                diskSize: 1024 * 1024 * 45,
                isMain: false
            ),
            onOpen: {},
            onDelete: {},
            onMerge: {},
            isSelectionMode: true,
            isSelected: true,
            onSelectionToggle: {}
        )
        
        // 未知状态分支预览
        BranchCard(
            branch: BranchInfo(
                name: "experimental",
                path: "/Users/test/project/.trees/experimental",
                description: "",
                status: .unknown,
                createdAt: Date().addingTimeInterval(-86400 * 3),
                lastUsed: nil,
                uncommittedChanges: 0,
                diskSize: nil,
                isMain: false
            ),
            onOpen: {},
            onDelete: {},
            onMerge: {},
            isSelectionMode: false,
            isSelected: false,
            onSelectionToggle: nil
        )
    }
    .padding()
    .frame(width: 300)
}