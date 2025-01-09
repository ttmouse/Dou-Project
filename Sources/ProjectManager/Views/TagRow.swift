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

    var body: some View {
        Button(action: action) {
            rowContent
        }
        .buttonStyle(.plain)
        .frame(maxWidth: .infinity)
        .background(backgroundShape)
        .overlay(overlayShape)
        .animation(.easeInOut(duration: 0.2), value: isTargeted)
        .contextMenu { contextMenuContent }
        .onDrop(of: [.data], isTargeted: $isTargeted) { providers in
            handleDrop(providers: providers)
        }
    }

    // MARK: - View Components

    private var rowContent: some View {
        HStack {
            TagView(
                tag: tag,
                color: tagManager.colorManager.getColor(for: tag) ?? AppTheme.tagPresetColors
                    .randomElement()?.color ?? AppTheme.accent,
                fontSize: 13,
                isSelected: isSelected
            )

            Spacer()

            tagCountView
        }
        .contentShape(Rectangle())
        .padding(.vertical, AppTheme.tagRowPaddingV)
        .padding(.horizontal, AppTheme.tagRowPaddingH)
    }

    private var tagCountView: some View {
        Text("\(count)")
            .font(.caption)
            .foregroundColor(isSelected ? AppTheme.text : AppTheme.sidebarSecondaryText)
            .padding(.horizontal, AppTheme.tagCountPaddingH)
            .padding(.vertical, AppTheme.tagCountPaddingV)
            .background(
                isSelected
                    ? AppTheme.accent.opacity(0.2)
                    : AppTheme.sidebarDirectoryBackground
            )
            .cornerRadius(AppTheme.tagCountCornerRadius)
    }

    private var backgroundShape: some View {
        RoundedRectangle(cornerRadius: AppTheme.tagRowCornerRadius)
            .fill(
                isTargeted
                    ? AppTheme.accent.opacity(0.2)
                    : (isSelected ? AppTheme.sidebarSelectedBackground : Color.clear)
            )
    }

    private var overlayShape: some View {
        RoundedRectangle(cornerRadius: AppTheme.tagRowCornerRadius)
            .strokeBorder(
                isTargeted ? AppTheme.accent : Color.clear,
                lineWidth: 1
            )
    }

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
                    tagManager: TagManager()
                )
                TagRow(
                    tag: "macOS",
                    isSelected: false,
                    count: 3,
                    action: {},
                    onDrop: nil,
                    onRename: {},
                    tagManager: TagManager()
                )
            }
            .padding()
        }
    }
#endif
