import SwiftUI

extension Color {
    init(hex: UInt, alpha: Double = 1.0) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xff) / 255,
            green: Double((hex >> 8) & 0xff) / 255,
            blue: Double(hex & 0xff) / 255,
            opacity: alpha
        )
    }

    init(hex string: String, alpha: Double = 1.0) {
        var string = string.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
        if string.hasPrefix("#") {
            string = String(string.dropFirst())
        }

        // Convert hex string to an integer
        let scanner = Scanner(string: string)
        var color: UInt64 = 0
        scanner.scanHexInt64(&color)

        self.init(
            .sRGB,
            red: Double((color >> 16) & 0xff) / 255,
            green: Double((color >> 8) & 0xff) / 255,
            blue: Double(color & 0xff) / 255,
            opacity: alpha
        )
    }
}

/// 应用程序主题配置
enum AppTheme {
    // MARK: - 字体样式
    /// 标题字体 - 18号
    static let titleFont = Font.system(size: 18, weight: .semibold)
    /// 副标题字体 - 16号
    static let subtitleFont = Font.system(size: 16, weight: .medium)
    /// 正文字体 - 14号
    static let bodyFont = Font.system(size: 14)
    /// 小字体 - 12号
    static let captionFont = Font.system(size: 12)
    /// 标签字体 - 13号
    static let tagFont = Font.system(size: 13)
    /// 侧边栏标题字体 - 15号
    static let sidebarTitleFont = Font.system(size: 15, weight: .semibold)
    /// 侧边栏标签字体 - 13号
    static let sidebarTagFont = Font.system(size: 13)
    /// 搜索栏字体 - 14号
    static let searchBarFont = Font.system(size: 14)

    // MARK: - 基础颜色
    /// 主背景色 - #171717
    static let background = Color(hex: "#171717")
    /// 次要背景色 - #1A1A1A
    static let secondaryBackground = Color(hex: "#1A1A1A")
    /// 强调色 - 蓝色
    static let accent = Color(hex: "#453BE7")
    /// 主文本色 - 白色，不透明度90%
    static let text = Color(hex: "#FFFFFF", alpha: 0.9)
    /// 次要文本色 - 白色，不透明度60%
    static let secondaryText = Color(hex: "#FFFFFF", alpha: 0.6)
    /// 边框色 - 白色，不透明度10%
    static let border = Color(hex: "#FFFFFF", alpha: 0.1)

    // MARK: - 标题栏样式
    /// 标题栏背景色 - #1A1A1A
    static let titleBarBackground = Color(hex: "#171717")
    /// 标题栏边框色 - #2D2D2D
    static let titleBarBorder = Color(hex: "#2D2D2D")
    /// 标题栏文本色 - 白色，不透明度90%
    static let titleBarText = Color(hex: "#FFFFFF", alpha: 0.9)
    /// 标题栏图标色 - 白色，不透明度60%
    static let titleBarIcon = Color(hex: "#FFFFFF", alpha: 0.6)
    /// 标题栏按钮悬停背景色
    static let titleBarButtonHover = Color(hex: "#FFFFFF", alpha: 0.1)

    // MARK: - 侧边栏样式
    /// 侧边栏背景色 - #1A1A1A
    static let sidebarBackground = Color(hex: "#1A1A1A")
    /// 侧边栏边框色 - #2D2D2D
    static let sidebarBorder = Color(hex: "#2D2D2D")
    /// 侧边栏标题色 - 白色，不透明度90%
    static let sidebarTitle = Color(hex: "#FFFFFF", alpha: 0.9)
    /// 侧边栏次要文本色 - 白色，不透明度60%
    static let sidebarSecondaryText = Color(hex: "#FFFFFF", alpha: 0.6)
    /// 侧边栏选中背景色
    static let sidebarSelectedBackground = Color(hex: "#3B82F6", alpha: 0.2)
    /// 侧边栏悬停背景色
    static let sidebarHoverBackground = Color(hex: "#FFFFFF", alpha: 0.05)
    /// 侧边栏目录按钮背景色
    static let sidebarDirectoryBackground = Color(hex: "#1C1C1C")
    /// 侧边栏目录按钮边框色
    static let sidebarDirectoryBorder = Color(hex: "#2D2D2D")

    // MARK: - 卡片样式
    /// 卡片背景色 - #1B1B1B
    static let cardBackground = Color(hex: "#1B1B1B")
    /// 卡片描边色 - #2D2D2D
    static let cardBorder = Color(hex: "#2D2D2D")
    /// 卡片阴影色 - 黑色，不透明度30%
    static let cardShadow = Color(hex: "#000000", alpha: 0.0)
    /// 卡片悬停色 - 白色，不透明度8%
    static let cardHover = Color(hex: "#FFFFFF", alpha: 0.08)
    /// 卡片选中背景色
    static let cardSelectedBackground = accent.opacity(0.2)
    /// 卡片选中边框色
    static let cardSelectedBorder = accent.opacity(0.85)
    /// 卡片选中边框宽度
    static let cardSelectedBorderWidth: CGFloat = 2
    /// 卡片选中阴影色
    static let cardSelectedShadow = accent.opacity(0.2)
    /// 卡片选中阴影半径
    static let cardSelectedShadowRadius: CGFloat = 8
    /// 卡片内边距
    static let cardPadding: CGFloat = 16
    /// 卡片圆角
    static let cardCornerRadius: CGFloat = 12
    /// 卡片边框宽度
    static let cardBorderWidth: CGFloat = 1
    /// 卡片高度
    static let cardHeight: CGFloat = 135

    // MARK: - 卡片网格样式
    /// 卡片网格水平间距
    static let cardGridSpacingH: CGFloat = 16
    /// 卡片网格垂直间距
    static let cardGridSpacingV: CGFloat = 16
    /// 卡片网格内边距
    static let cardGridPadding: CGFloat = 16
    /// 卡片最小宽度
    static let cardMinWidth: CGFloat = 250
    /// 卡片最大宽度
    static let cardMaxWidth: CGFloat = 400

    // MARK: - 标签样式
    /// 标签背景色 - 白色，不透明度8%
    static let tagBackground = Color(hex: "#FFFFFF", alpha: 0.08)
    /// 标签文本色 - 白色，不透明度90%
    static let tagText = Color(hex: "#FFFFFF", alpha: 0.9)
    /// 标签选中背景色
    static let tagSelectedBackground = Color(hex: "#3B82F6", alpha: 0.2)
    /// 标签计数背景色
    static let tagCountBackground = Color(hex: "#FFFFFF", alpha: 0.1)

    // MARK: - 按钮样式
    /// 按钮背景色 - 白色，不透明度8%
    static let buttonBackground = Color(hex: "#FFFFFF", alpha: 0.08)
    /// 按钮悬停色 - 白色，不透明度12%
    static let buttonHover = Color(hex: "#FFFFFF", alpha: 0.12)
    /// 主要按钮背景色
    static let primaryButtonBackground = Color(hex: "#3B82F6")
    /// 主要按钮悬停色
    static let primaryButtonHover = Color(hex: "#2563EB")

    // MARK: - 图标颜色
    /// 主要图标色
    static let icon = Color(hex: "#FFFFFF", alpha: 0.9)
    /// 次要图标色
    static let secondaryIcon = Color(hex: "#FFFFFF", alpha: 0.6)
    /// Git 图标色
    static let gitIcon = Color(hex: "#3B82F6")
    /// 文件夹图标色
    static let folderIcon = Color(hex: "#3B82F6")

    // MARK: - 搜索栏
    /// 搜索栏背景色
    static let searchBarBackground = Color(hex: "#1B1B1B")
    /// 搜索栏边框色
    static let searchBarBorder = Color(hex: "#2D2D2D")
    /// 搜索栏文本色
    static let searchBarText = Color(hex: "#FFFFFF", alpha: 0.9)
    /// 搜索栏占位符文本色
    static let searchBarPlaceholder = Color(hex: "#FFFFFF", alpha: 0.4)
    /// 搜索栏激活时边框色
    static let searchBarActiveBorder = Color(hex: "#3B82F6")
    /// 搜索栏激活时图标色
    static let searchBarActiveIcon = Color(hex: "#3B82F6")
    /// 搜索栏激活时背景色
    static let searchBarActiveBackground = Color(hex: "#1D1D1D")
    /// 搜索栏光标颜色
    static let searchBarCursor = Color(hex: "#3B82F6")
    /// 搜索栏区域背景色
    static let searchBarAreaBackground = Color(hex: "#171717")
    /// 搜索栏区域边框色
    static let searchBarAreaBorder = Color(hex: "#171717")
    /// 搜索栏区域内边距
    static let searchBarAreaPadding: CGFloat = 8
    /// 搜索栏区域高度
    static let searchBarAreaHeight: CGFloat = 45

    // MARK: - 霓虹色系
    /// 霓虹蓝 - #6366F1
    static let neonBlue = Color(hex: "#6366F1")
    /// 霓虹绿 - #10B981
    static let neonGreen = Color(hex: "#10B981")
    /// 霓虹紫 - #8B5CF6
    static let neonPurple = Color(hex: "#8B5CF6")

    // MARK: - 状态颜色
    /// 成功状态色
    static let success = Color(hex: "#10B981")
    /// 警告状态色
    static let warning = Color(hex: "#F59E0B")
    /// 错误状态色
    static let error = Color(hex: "#EF4444")
    /// 信息状态色
    static let info = Color(hex: "#3B82F6")

    // MARK: - 分割线
    /// 分割线颜色
    static let divider = Color(hex: "#FFFFFF", alpha: 0.1)

    // MARK: - 滚动条
    /// 滚动条颜色
    static let scrollBar = Color(hex: "#FFFFFF", alpha: 0.2)
    /// 滚动条悬停色
    static let scrollBarHover = Color(hex: "#FFFFFF", alpha: 0.3)

    // MARK: - 标签列表样式
    /// 标签列表整体间距
    static let tagListSpacing: CGFloat = 8
    /// 标签行之间的间距
    static let tagRowSpacing: CGFloat = 2
    /// 标签行内边距 - 水平
    static let tagRowPaddingH: CGFloat = 8
    /// 标签行内边距 - 垂直
    static let tagRowPaddingV: CGFloat = 4
    /// 标签行圆角
    static let tagRowCornerRadius: CGFloat = 0
    /// 标签计数背景圆角
    static let tagCountCornerRadius: CGFloat = 4
    /// 标签计数内边距 - 水平
    static let tagCountPaddingH: CGFloat = 8
    /// 标签计数内边距 - 垂直
    static let tagCountPaddingV: CGFloat = 2
    /// 标签列表头部内边距 - 水平
    static let tagListHeaderPaddingH: CGFloat = 12
    /// 标签列表头部内边距 - 垂直
    static let tagListHeaderPaddingV: CGFloat = 4
    /// 标签列表内容区域内边距 - 垂直
    static let tagListContentPaddingV: CGFloat = 4

    // MARK: - 标签预设颜色
    /// 标签预设颜色列表
    static let tagPresetColors: [(name: String, color: Color)] = [
        ("无颜色", Color(hex: "#4DABF7")),  // 默认蓝色
        ("红色", Color(hex: "#FF6B6B")),
        ("橙色", Color(hex: "#FFA94D")),
        ("黄色", Color(hex: "#FFD43B")),
        ("绿色", Color(hex: "#69DB7C")),
        ("蓝色", Color(hex: "#4DABF7")),
        ("紫色", Color(hex: "#DA77F2")),
    ]
}
