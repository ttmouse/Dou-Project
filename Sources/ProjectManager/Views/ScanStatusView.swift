import SwiftUI

struct ScanStatusView: View {
    @EnvironmentObject var tagManager: TagManager

    var body: some View {
        Group {
            switch tagManager.scanState {
            case .idle:
                EmptyView()
            case .scanning(let directory):
                statusBadge(
                    icon: "magnifyingglass",
                    title: "正在扫描",
                    accessibilityDetail: directory,
                    color: AppTheme.accent
                )
            case .completed(let directory, let discovered):
                statusBadge(
                    icon: "checkmark",
                    title: "已发现 \(discovered) 个项目",
                    accessibilityDetail: directory,
                    color: AppTheme.success
                )
            case .failed(let directory, let message):
                HStack(spacing: 8) {
                    statusBadge(
                        icon: "exclamationmark.triangle",
                        title: "扫描失败",
                        accessibilityDetail: "\(message)：\(directory)",
                        color: AppTheme.warning
                    )

                    Button("重试") {
                        tagManager.refreshProjects()
                    }
                    .buttonStyle(.plain)
                    .font(AppTheme.captionFont)
                    .foregroundColor(AppTheme.accent)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
                .background(.regularMaterial, in: Capsule())
            }
        }
        .transition(.opacity)
        .animation(.easeInOut(duration: 0.18), value: tagManager.scanState)
    }

    private func statusBadge(
        icon: String,
        title: String,
        accessibilityDetail: String,
        color: Color
    ) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .foregroundColor(color)
            Text(title)
                .font(AppTheme.captionFont)
                .foregroundColor(AppTheme.secondaryText)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(.regularMaterial, in: Capsule())
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title)，\(accessibilityDetail)")
    }
}
