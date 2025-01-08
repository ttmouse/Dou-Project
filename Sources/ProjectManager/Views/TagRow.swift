import SwiftUI

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
            HStack {
                TagView(
                    tag: tag,
                    color: tagManager.getColor(for: tag),
                    fontSize: 13,
                    isSelected: isSelected
                )

                Spacer()

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
            .contentShape(Rectangle())
            .padding(.vertical, AppTheme.tagRowPaddingV)
            .padding(.horizontal, AppTheme.tagRowPaddingH)
        }
        .buttonStyle(.plain)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: AppTheme.tagRowCornerRadius)
                .fill(
                    isTargeted
                        ? AppTheme.accent.opacity(0.2)
                        : (isSelected ? AppTheme.sidebarSelectedBackground : Color.clear)
                )
        )
        .overlay(
            RoundedRectangle(cornerRadius: AppTheme.tagRowCornerRadius)
                .strokeBorder(
                    isTargeted ? AppTheme.accent : Color.clear,
                    lineWidth: 1
                )
        )
        .animation(.easeInOut(duration: 0.2), value: isTargeted)
        .contextMenu {
            Button(action: {
                onRename?()
            }) {
                Label("重命名", systemImage: "pencil")
            }

            Menu("设置颜色") {
                ForEach(AppTheme.tagPresetColors, id: \.name) { colorOption in
                    Button(action: {
                        tagManager.setColor(colorOption.color, for: tag)
                    }) {
                        HStack {
                            Circle()
                                .fill(colorOption.color)
                                .frame(width: 12, height: 12)
                            Text(colorOption.name)
                                .foregroundColor(.primary)
                            Spacer()
                            if tagManager.getColor(for: tag) == colorOption.color {
                                Image(systemName: "checkmark")
                                    .foregroundColor(.blue)
                            }
                        }
                        .frame(minWidth: 120)
                    }
                }
            }

            Divider()

            Button(
                role: .destructive,
                action: {
                    tagManager.removeTag(tag)
                }
            ) {
                Label("删除标签", systemImage: "trash")
            }
        }
        .onDrop(of: [.text], isTargeted: $isTargeted) { providers in
            guard let onDrop = onDrop,
                let first = providers.first
            else { return false }

            first.loadObject(ofClass: NSString.self) { string, error in
                if string is String {
                    DispatchQueue.main.async {
                        onDrop(tag)
                    }
                }
            }
            return true
        }
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
