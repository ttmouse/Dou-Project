import SwiftUI
import Combine

// MARK: - ColorManager协议 - 统一颜色管理接口
protocol ColorManager: ObservableObject {
    func getColor(for tag: String) -> Color?
    func setColor(_ color: Color, for tag: String)
    func removeColor(for tag: String)
    func getDefaultColor(for tag: String) -> Color
}

// MARK: - TagColorManager协议扩展
extension TagColorManager: ColorManager {
    
    // 获取标签的默认颜色（基于哈希值）
    func getDefaultColor(for tag: String) -> Color {
        // 为特殊标签返回固定颜色
        if tag == "全部" {
            return AppTheme.accent
        }
        
        if tag == "没有标签" {
            return AppTheme.accent.opacity(0.7)
        }
        
        // 使用标签名称的哈希值来确定性地选择颜色
        let hash = abs(tag.hashValue)
        let colorIndex = hash % AppTheme.tagPresetColors.count
        return AppTheme.tagPresetColors[colorIndex].color
    }
}