import SwiftUI

// MARK: - Merge Confirmation Dialog
// 分支合并确认对话框 - 显示合并预检查信息和选项

struct MergeConfirmationView: View {
    @Binding var isPresented: Bool
    let branch: BranchInfo
    let projectPath: String
    let onConfirmMerge: (MergeStrategy) -> Void
    
    @State private var mergeability: MergeabilityCheck?
    @State private var diffStats: BranchDiffStats?
    @State private var selectedStrategy: MergeStrategy = .recursive
    @State private var isLoading = true
    @State private var targetBranch = "main"
    
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            // 对话框标题
            header
            
            if isLoading {
                loadingView
            } else {
                VStack(alignment: .leading, spacing: 16) {
                    // 合并信息概览
                    mergeOverview
                    
                    // 差异统计
                    if let stats = diffStats {
                        diffStatsView(stats)
                    }
                    
                    // 预检查结果
                    if let check = mergeability {
                        mergeabilityView(check)
                    }
                    
                    // 合并策略选择
                    strategySelector
                }
            }
            
            // 按钮区域
            actionButtons
        }
        .padding(24)
        .frame(width: 500)
        .background(Color(NSColor.windowBackgroundColor))
        .cornerRadius(12)
        .shadow(radius: 10)
        .onAppear {
            loadMergeInformation()
        }
    }
    
    // MARK: - View Components
    
    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Image(systemName: "arrow.triangle.merge")
                    .foregroundColor(.blue)
                    .font(.title2)
                
                Text("合并分支")
                    .font(.title2)
                    .fontWeight(.semibold)
            }
            
            Text("将分支 \"\(branch.name)\" 合并到 \"\(targetBranch)\"")
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }
    
    private var loadingView: some View {
        VStack(spacing: 12) {
            ProgressView()
                .scaleEffect(0.8)
            Text("分析分支差异...")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .frame(height: 100)
    }
    
    private var mergeOverview: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("合并概览", systemImage: "info.circle")
                .font(.headline)
                .foregroundColor(.primary)
            
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text("源分支:")
                        .foregroundColor(.secondary)
                    Text(branch.name)
                        .fontWeight(.medium)
                        .foregroundColor(.primary)
                    
                    Spacer()
                    
                    statusBadge(branch.status)
                }
                
                HStack {
                    Text("目标分支:")
                        .foregroundColor(.secondary)
                    Text(targetBranch)
                        .fontWeight(.medium)
                        .foregroundColor(.primary)
                }
                
                if branch.hasUncommittedChanges {
                    HStack {
                        Image(systemName: "exclamationmark.triangle")
                            .foregroundColor(.orange)
                        Text("源分支有 \(branch.uncommittedChanges) 个未提交更改")
                            .foregroundColor(.orange)
                            .font(.caption)
                    }
                }
            }
            .padding(12)
            .background(Color(NSColor.controlBackgroundColor).opacity(0.5))
            .cornerRadius(8)
        }
    }
    
    private func diffStatsView(_ stats: BranchDiffStats) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("差异统计", systemImage: "chart.bar")
                .font(.headline)
                .foregroundColor(.primary)
            
            VStack(alignment: .leading, spacing: 6) {
                diffStatRow("提交", "\(stats.commitsAhead)", .blue)
                diffStatRow("文件", "\(stats.filesChanged)", .green)
                
                if stats.insertions > 0 || stats.deletions > 0 {
                    HStack {
                        diffStatRow("新增", "\(stats.insertions)", .green)
                        diffStatRow("删除", "\(stats.deletions)", .red)
                    }
                }
                
                Text("总计: \(stats.summary)")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .padding(.top, 4)
            }
            .padding(12)
            .background(Color(NSColor.controlBackgroundColor).opacity(0.5))
            .cornerRadius(8)
        }
    }
    
    private func diffStatRow(_ label: String, _ value: String, _ color: Color) -> some View {
        HStack {
            Text("\(label):")
                .foregroundColor(.secondary)
                .font(.caption)
            Text(value)
                .fontWeight(.semibold)
                .foregroundColor(color)
                .font(.caption)
        }
    }
    
    private func mergeabilityView(_ check: MergeabilityCheck) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label("合并检查", systemImage: check.canMerge ? "checkmark.circle" : "exclamationmark.triangle")
                    .font(.headline)
                    .foregroundColor(check.canMerge ? .green : .orange)
                
                Spacer()
                
                Text(check.canMerge ? "可以合并" : "需要注意")
                    .font(.caption)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 2)
                    .background(check.canMerge ? Color.green.opacity(0.2) : Color.orange.opacity(0.2))
                    .foregroundColor(check.canMerge ? .green : .orange)
                    .cornerRadius(4)
            }
            
            VStack(alignment: .leading, spacing: 8) {
                // 冲突文件
                if !check.conflicts.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundColor(.red)
                            Text("潜在冲突文件:")
                                .fontWeight(.medium)
                                .foregroundColor(.red)
                        }
                        
                        ForEach(check.conflicts.prefix(5), id: \.self) { conflict in
                            Text("• \(conflict)")
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .padding(.leading, 20)
                        }
                        
                        if check.conflicts.count > 5 {
                            Text("...还有 \(check.conflicts.count - 5) 个文件")
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .padding(.leading, 20)
                        }
                    }
                }
                
                // 警告信息
                if !check.warnings.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Image(systemName: "exclamationmark.circle")
                                .foregroundColor(.orange)
                            Text("注意事项:")
                                .fontWeight(.medium)
                                .foregroundColor(.orange)
                        }
                        
                        ForEach(check.warnings, id: \.self) { warning in
                            Text("• \(warning)")
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .padding(.leading, 20)
                        }
                    }
                }
                
                // 建议
                if !check.recommendations.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Image(systemName: "lightbulb")
                                .foregroundColor(.blue)
                            Text("建议:")
                                .fontWeight(.medium)
                                .foregroundColor(.blue)
                        }
                        
                        ForEach(check.recommendations, id: \.self) { recommendation in
                            Text("• \(recommendation)")
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .padding(.leading, 20)
                        }
                    }
                }
            }
            .padding(12)
            .background(Color(NSColor.controlBackgroundColor).opacity(0.5))
            .cornerRadius(8)
        }
    }
    
    private var strategySelector: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("合并策略", systemImage: "gear")
                .font(.headline)
                .foregroundColor(.primary)
            
            VStack(alignment: .leading, spacing: 8) {
                ForEach([MergeStrategy.recursive, .noFastForward, .ours, .theirs], id: \.self) { strategy in
                    HStack {
                        Button(action: { selectedStrategy = strategy }) {
                            HStack {
                                Image(systemName: selectedStrategy == strategy ? "checkmark.circle.fill" : "circle")
                                    .foregroundColor(selectedStrategy == strategy ? .blue : .secondary)
                                
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(strategyName(strategy))
                                        .fontWeight(.medium)
                                        .foregroundColor(.primary)
                                    Text(strategyDescription(strategy))
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                                
                                Spacer()
                            }
                        }
                        .buttonStyle(PlainButtonStyle())
                    }
                }
            }
            .padding(12)
            .background(Color(NSColor.controlBackgroundColor).opacity(0.5))
            .cornerRadius(8)
        }
    }
    
    private var actionButtons: some View {
        HStack {
            Button("取消") {
                isPresented = false
            }
            .keyboardShortcut(.escape)
            
            Spacer()
            
            if let check = mergeability, !check.canMerge && !check.conflicts.isEmpty {
                Button("强制合并") {
                    onConfirmMerge(selectedStrategy)
                    isPresented = false
                }
                .buttonStyle(.bordered)
                .foregroundColor(.orange)
            }
            
            Button("合并") {
                onConfirmMerge(selectedStrategy)
                isPresented = false
            }
            .buttonStyle(.borderedProminent)
            .disabled(isLoading || (mergeability?.canMerge == false))
            .keyboardShortcut(.return)
        }
    }
    
    private func statusBadge(_ status: BranchStatus) -> some View {
        HStack(spacing: 4) {
            Circle()
                .fill(statusColor(status))
                .frame(width: 6, height: 6)
            Text(status.displayName)
                .font(.caption)
                .foregroundColor(statusColor(status))
        }
    }
    
    // MARK: - Helper Functions
    
    private func loadMergeInformation() {
        isLoading = true
        
        DispatchQueue.global(qos: .userInitiated).async {
            // 加载差异统计
            let stats = BranchLogic.getBranchDiff(
                source: branch.name,
                target: targetBranch,
                projectPath: projectPath
            )
            
            // 加载合并可行性检查
            let check = BranchLogic.checkMergeability(
                source: branch.name,
                target: targetBranch,
                projectPath: projectPath
            )
            
            DispatchQueue.main.async {
                self.diffStats = stats
                self.mergeability = check
                self.isLoading = false
            }
        }
    }
    
    private func statusColor(_ status: BranchStatus) -> Color {
        switch status {
        case .clean: return .green
        case .hasChanges: return .orange
        case .unknown: return .gray
        }
    }
    
    private func strategyName(_ strategy: MergeStrategy) -> String {
        switch strategy {
        case .recursive: return "递归合并"
        case .ours: return "使用我们的版本"
        case .theirs: return "使用他们的版本"
        case .noFastForward: return "创建合并提交"
        }
    }
    
    private func strategyDescription(_ strategy: MergeStrategy) -> String {
        switch strategy {
        case .recursive: return "标准的三路合并策略，适合大多数情况"
        case .ours: return "冲突时保留目标分支的版本"
        case .theirs: return "冲突时保留源分支的版本"
        case .noFastForward: return "总是创建合并提交，保留分支历史"
        }
    }
}

// MARK: - Preview

#Preview {
    MergeConfirmationView(
        isPresented: .constant(true),
        branch: BranchInfo(
            name: "feature-login",
            path: "/Users/test/project/.trees/feature-login",
            description: "用户登录功能实现",
            status: .hasChanges,
            uncommittedChanges: 3
        ),
        projectPath: "/Users/test/project",
        onConfirmMerge: { strategy in
            print("合并使用策略: \(strategy)")
        }
    )
}