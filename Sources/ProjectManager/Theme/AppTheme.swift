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
    // MARK: - 基础颜色
    /// 主背景色 - #171717
    static let background = Color(hex: "#171717")
    /// 次要背景色 - #1A1A1A
    static let secondaryBackground = Color(hex: "#1A1A1A")
    /// 强调色 - 纯白色
    static let accent = Color(hex: "#FFFFFF")
    /// 主文本色 - 白色，不透明度90%
    static let text = Color(hex: "#FFFFFF", alpha: 0.9)
    /// 次要文本色 - 白色，不透明度60%
    static let secondaryText = Color(hex: "#FFFFFF", alpha: 0.6)
    /// 边框色 - 白色，不透明度10%
    static let border = Color(hex: "#FFFFFF", alpha: 0.1)
    
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
    static let searchBarBackground = Color(hex: "#1C1C1C")
    /// 搜索栏边框色
    static let searchBarBorder = Color(hex: "#FFFFFF", alpha: 0.1)
    /// 搜索栏文本色
    static let searchBarText = Color(hex: "#FFFFFF", alpha: 0.9)
    /// 搜索栏占位符文本色
    static let searchBarPlaceholder = Color(hex: "#FFFFFF", alpha: 0.4)
    
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
} 
