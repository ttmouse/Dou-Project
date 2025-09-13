import SwiftUI
import UniformTypeIdentifiers

struct TagRow: View {
    let tag: String
    let isSelected: Bool
    let count: Int
    let action: () -> Void
    let onDrop: ((String) -> Void)?
    let onRename: (() -> Void)?
    @ObservedObject var tagManager: TagManager
    @State private var isTargeted = false
    @State private var showingContextMenu = false
    @State var isEditing = false
    @State var tempName = ""
    @State private var isHovered = false

    var body: some View {
        HStack {
            // 可点击的标签区域
            HStack(spacing: 4) {
                Text(tag)
                    .font(.system(size: 13))
                    .foregroundColor(textColor)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(tagBackgroundColor)
            )

            Spacer()

            if isEditing {
                TextField("重命名标签", text: $tempName)
            }

            Spacer()
            
            // 小眼睛隐藏按钮 - 独立处理点击
            Button {
                tagManager.toggleTagVisibility(tag)
            } label: {
                if tagManager.isTagHidden(tag) {
                    // 隐藏标签：始终显示eye.slash
                    Image(systemName: "eye.slash")
                        .foregroundColor(AppTheme.sidebarSecondaryText.opacity(0.6))
                        .font(.system(size: 11))
                        .frame(width: 14, height: 14)
                } else {
                    // 正常标签：悬停时显示eye，不悬停时透明占位
                    Image(systemName: "eye")
                        .foregroundColor(AppTheme.sidebarSecondaryText)
                        .font(.system(size: 11))
                        .frame(width: 14, height: 14)
                        .opacity(isHovered ? 0.8 : 0.0)
                }
            }
            .buttonStyle(.plain)
            .animation(.easeInOut(duration: 0.2), value: isHovered)
            
            Text("\(count)")
                .font(.caption)
                .foregroundColor(isSelected ? AppTheme.text : AppTheme.sidebarSecondaryText)
                .frame(minWidth: 24, alignment: .center) // 固定最小宽度，居中对齐
                .padding(.horizontal, AppTheme.tagCountPaddingH)
                .padding(.vertical, AppTheme.tagCountPaddingV)
                .background(
                    isSelected
                        ? AppTheme.accent.opacity(0.2)
                        : AppTheme.sidebarDirectoryBackground
                )
                .cornerRadius(AppTheme.tagCountCornerRadius)
        }
        .padding(.horizontal, AppTheme.tagRowPaddingH)
        .padding(.vertical, AppTheme.tagRowPaddingV)
        .background(
            RoundedRectangle(cornerRadius: AppTheme.tagRowCornerRadius)
                .fill(
                    isSelected ? AppTheme.sidebarSelectedBackground : 
                    (isHovered ? AppTheme.sidebarHoverBackground : Color.clear)
                )
        )
        .contentShape(Rectangle())
        .onTapGesture {
            print("🔥 TagRow onTapGesture triggered for tag: \(tag)")
            action()
        }
        .contextMenu { contextMenuContent }
        .onHover { hovering in
            self.isHovered = hovering
        }
        .onDrop(of: [.data], isTargeted: $isTargeted) { providers in
            handleDrop(providers: providers)
        }
        .id("\(tag)-\(tagManager.colorManager.getColor(for: tag)?.description ?? "")")
    }
    
    // 计算标签文字颜色
    private var textColor: Color {
        if isSelected {
            return .white
        } else {
            let color = tagManager.colorManager.getColor(for: tag) ?? AppTheme.tagPresetColors.randomElement()?.color ?? AppTheme.accent
            return color.opacity(0.9)
        }
    }
    
    // 计算标签背景颜色  
    private var tagBackgroundColor: Color {
        let color = tagManager.colorManager.getColor(for: tag) ?? AppTheme.tagPresetColors.randomElement()?.color ?? AppTheme.accent
        if isSelected {
            return color
        } else {
            return color.opacity(0.2)
        }
    }

    // MARK: - View Components

    private var contextMenuContent: some View {
        Group {
            Button(action: { onRename?() }) {
                Label("重命名", systemImage: "pencil")
            }

            Menu("设置颜色") {
                ForEach(AppTheme.tagPresetColors, id: \.name) { colorOption in
                    colorMenuItem(colorOption)
                }
            }

            Divider()

            Button(
                role: .destructive,
                action: { tagManager.removeTag(tag) }
            ) {
                Label("删除标签", systemImage: "trash")
            }
        }
    }

    private func colorMenuItem(_ colorOption: (name: String, color: Color)) -> some View {
        Button(action: {
            tagManager.colorManager.setColor(colorOption.color, for: tag)
        }) {
            HStack {
                Circle()
                    .fill(colorOption.color)
                    .frame(width: 12, height: 12)
                Text(colorOption.name)
                    .foregroundColor(.primary)
                Spacer()
                if tagManager.colorManager.getColor(for: tag) == colorOption.color {
                    Image(systemName: "checkmark")
                        .foregroundColor(.blue)
                }
            }
            .frame(minWidth: 120)
        }
    }

    // MARK: - Helper Functions

    private func handleDrop(providers: [NSItemProvider]) -> Bool {
        guard let onDrop = onDrop,
            let first = providers.first
        else { return false }

        first.loadDataRepresentation(forTypeIdentifier: UTType.data.identifier) { data, error in
            if let data = data,
                let projectIds = try? JSONDecoder().decode([UUID].self, from: data)
            {
                DispatchQueue.main.async {
                    for projectId in projectIds {
                        self.tagManager.addTagToProject(projectId: projectId, tag: self.tag)
                    }
                }
            }
        }
        return true
    }
}

#if DEBUG
    struct TagRow_Previews: PreviewProvider {
        static var previews: some View {
            VStack {
                TagRow(
                    tag: "SwiftUI",
                    isSelected: true,
                    count: 5,
                    action: {},
                    onDrop: nil,
                    onRename: {},
                    tagManager: {
                        let container = TagManager()
                        return TagManager()
                    }()
                )
                TagRow(
                    tag: "macOS",
                    isSelected: false,
                    count: 3,
                    action: {},
                    onDrop: nil,
                    onRename: {},
                    tagManager: {
                        let container = TagManager()
                        return TagManager()
                    }()
                )
            }
            .padding()
        }
    }
#endif
