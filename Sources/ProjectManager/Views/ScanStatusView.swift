import SwiftUI

struct ScanStatusView: View {
    @EnvironmentObject var tagManager: TagManager

    var body: some View {
        Group {
            switch tagManager.scanState {
            case .idle:
                EmptyView()
            case .scanning(let directory):
                statusRow(
                    icon: "magnifyingglass",
                    title: "正在扫描项目",
                    detail: directory,
                    showsProgress: true,
                    color: AppTheme.accent
                )
            case .completed(let directory, let discovered):
                statusRow(
                    icon: "checkmark.circle",
                    title: "已发现 \(discovered) 个项目",
                    detail: directory,
                    showsProgress: false,
                    color: AppTheme.success
                )
            case .failed(let directory, let message):
                HStack(spacing: 12) {
                    statusRow(
                        icon: "exclamationmark.triangle",
                        title: "扫描失败",
                        detail: "\(message)：\(directory)",
                        showsProgress: false,
                        color: AppTheme.warning
                    )

                    Button("重试") {
                        tagManager.refreshProjects()
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(AppTheme.secondaryBackground)
    }

    private func statusRow(
        icon: String,
        title: String,
        detail: String,
        showsProgress: Bool,
        color: Color
    ) -> some View {
        HStack(spacing: 8) {
            if showsProgress {
                ProgressView()
                    .controlSize(.small)
            } else {
                Image(systemName: icon)
                    .foregroundColor(color)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(AppTheme.captionFont)
                    .foregroundColor(AppTheme.text)
                Text(detail)
                    .font(.system(size: 11))
                    .foregroundColor(AppTheme.secondaryText)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            Spacer()
        }
        .accessibilityElement(children: .combine)
    }
}
