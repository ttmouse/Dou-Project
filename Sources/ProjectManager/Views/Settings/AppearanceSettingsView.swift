import SwiftUI

struct AppearanceSettingsView: View {
    @AppStorage(TagAppearance.preferenceKey) private var appearance: TagAppearance = .colorful

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("标签的色系")
                        .font(.headline)
                        .foregroundColor(AppTheme.text)
                    Text("应用于卡片、列表、侧栏及标签编辑窗口，选择后立即生效。")
                        .font(AppTheme.captionFont)
                        .foregroundColor(AppTheme.secondaryText)
                }

                VStack(spacing: 10) {
                    ForEach(TagAppearance.allCases) { option in
                        Button { appearance = option } label: {
                            HStack(spacing: 14) {
                                Image(systemName: appearance == option ? "largecircle.fill.circle" : "circle")
                                    .font(.system(size: 16))
                                    .foregroundColor(appearance == option ? AppTheme.accent : AppTheme.secondaryText)
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(option.title)
                                        .font(.system(size: 13, weight: .medium))
                                        .foregroundColor(AppTheme.text)
                                    Text(option.detail)
                                        .font(AppTheme.captionFont)
                                        .foregroundColor(AppTheme.secondaryText)
                                }
                                Spacer(minLength: 12)
                                HStack(spacing: 6) {
                                    TagView(tag: "AI", color: .blue, fontSize: 12, appearanceOverride: option)
                                    TagView(tag: "进行中", color: .green, fontSize: 12, appearanceOverride: option)
                                }
                                .allowsHitTesting(false)
                                .accessibilityHidden(true)
                            }
                            .padding(16)
                            .background(AppTheme.secondaryBackground)
                            .cornerRadius(8)
                            .overlay(RoundedRectangle(cornerRadius: 8)
                                .strokeBorder(appearance == option ? AppTheme.accent.opacity(0.6) : AppTheme.divider, lineWidth: 1))
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(option.title)
                        .accessibilityValue(appearance == option ? "已选中" : "未选中")
                    }
                }

                Text("只改变显示样式，标签名称和已设置的颜色会保留。")
                    .font(AppTheme.captionFont)
                    .foregroundColor(AppTheme.secondaryText)
            }
            .padding(24)
        }
    }
}
