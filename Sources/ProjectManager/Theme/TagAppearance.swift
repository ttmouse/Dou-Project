import SwiftUI

enum TagAppearance: String, CaseIterable, Identifiable {
    case gray
    case colorful
    case mutedColorful
    case text

    static let preferenceKey = "tagAppearance"
    var id: String { rawValue }
    var horizontalPadding: CGFloat { self == .text ? 0 : 8 }
    var verticalPadding: CGFloat { self == .text ? 0 : 4 }

    var title: String {
        switch self {
        case .gray: return "纯灰色"
        case .colorful: return "现有的彩色"
        case .mutedColorful: return "淡彩色"
        case .text: return "#文字"
        }
    }

    var detail: String {
        switch self {
        case .gray: return "灰色文字与浅灰背景"
        case .colorful: return "保留每个标签设置的颜色"
        case .mutedColorful: return "保留原有色相，文字与背景的不透明度减半"
        case .text: return "带 # 前缀的纯文字，无背景色"
        }
    }

    func label(for name: String) -> String {
        self == .text && !name.hasPrefix("#") ? "#" + name : name
    }

    func foreground(base: Color, selected: Bool = false, preview: Bool = false) -> Color {
        switch self {
        case .colorful: return selected ? .white : base.opacity(preview ? 1 : 0.9)
        case .mutedColorful: return TagAppearance.colorful.foreground(base: base, selected: selected, preview: preview).opacity(0.5)
        case .gray: return selected ? AppTheme.text : AppTheme.secondaryText
        case .text: return selected ? AppTheme.text : AppTheme.secondaryText
        }
    }

    func background(base: Color, selected: Bool = false, preview: Bool = false) -> Color {
        switch self {
        case .colorful: return selected ? base : base.opacity(preview ? 0.3 : 0.2)
        case .mutedColorful: return TagAppearance.colorful.background(base: base, selected: selected, preview: preview).opacity(0.5)
        case .gray: return Color.gray.opacity(selected ? 0.4 : 0.2)
        case .text: return .clear
        }
    }
}
