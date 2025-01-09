import SwiftUI

class TagColorManager: ObservableObject {
    @Published private(set) var tagColors: [String: Color] = [:]
    private let storage: TagStorage

    init(storage: TagStorage) {
        self.storage = storage
        self.tagColors = storage.loadTagColors()
    }

    func getColor(for tag: String) -> Color? {
        // 为"全部"标签返回固定颜色
        if tag == "全部" {
            return AppTheme.accent
        }

        return tagColors[tag]
    }

    func setColor(_ color: Color, for tag: String) {
        print("设置标签 '\(tag)' 的颜色")
        DispatchQueue.main.async {
            self.tagColors[tag] = color
            self.objectWillChange.send()
            // 延迟保存，避免频繁写入
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                self.saveColors()
            }
        }
    }

    private func saveColors() {
        storage.saveTagColors(tagColors)
    }

    func removeColor(for tag: String) {
        tagColors.removeValue(forKey: tag)
        saveColors()
    }
}
