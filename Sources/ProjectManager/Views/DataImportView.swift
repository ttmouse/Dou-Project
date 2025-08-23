import SwiftUI
import UniformTypeIdentifiers

/// DataImportView - 数据导入界面
/// 
/// 提供用户友好的数据导入界面，支持文件选择、导入选项配置和结果展示
struct DataImportView: View {
    @EnvironmentObject private var tagManager: TagManager
    @Environment(\.dismiss) private var dismiss
    
    // MARK: - 状态
    
    @State private var selectedFileURL: URL?
    @State private var selectedFileName: String = ""
    
    @State private var importStrategy: DataImporter.ImportStrategy = .merge
    @State private var conflictResolution: DataImporter.ConflictResolution = .mergeData
    
    @State private var isImporting: Bool = false
    @State private var importResult: String?
    @State private var showingFileImporter: Bool = false
    
    // MARK: - 计算属性
    
    private var canImport: Bool {
        selectedFileURL != nil && !isImporting
    }
    
    private var resultColor: Color {
        guard let result = importResult else { return .primary }
        if result.contains("成功") {
            return .green
        } else if result.contains("未实现") {
            return .orange
        } else {
            return .red
        }
    }
    
    // MARK: - 视图
    
    var body: some View {
        NavigationView {
            VStack(spacing: 20) {
                headerView
                fileSelectionView
                importOptionsView
                
                if let result = importResult {
                    resultView(result)
                }
                
                Spacer()
                actionButtonsView
            }
            .padding(20)
            .navigationTitle("数据导入")
            .toolbar {
                ToolbarItem(placement: .automatic) {
                    Button("取消") {
                        dismiss()
                    }
                }
            }
        }
        .fileImporter(
            isPresented: $showingFileImporter,
            allowedContentTypes: [UTType.json],
            allowsMultipleSelection: false
        ) { result in
            handleFileSelection(result)
        }
        .frame(minWidth: 500, minHeight: 400)
    }
    
    // MARK: - 子视图
    
    private var headerView: some View {
        VStack(spacing: 8) {
            Image(systemName: "square.and.arrow.down")
                .font(.system(size: 40))
                .foregroundColor(.accentColor)
            
            Text("导入项目数据")
                .font(.title2)
                .fontWeight(.semibold)
            
            Text("从备份的JSON文件恢复项目和标签数据")
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }
    
    private var fileSelectionView: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("选择备份文件", systemImage: "doc.badge.plus")
                .font(.headline)
            
            HStack {
                if selectedFileName.isEmpty {
                    Text("未选择文件")
                        .foregroundColor(.secondary)
                } else {
                    HStack {
                        Image(systemName: "doc.text")
                            .foregroundColor(.accentColor)
                        Text(selectedFileName)
                            .fontWeight(.medium)
                    }
                }
                
                Spacer()
                
                Button("选择文件") {
                    showingFileImporter = true
                }
                .buttonStyle(.bordered)
            }
            .padding()
            .background(Color(NSColor.controlBackgroundColor))
            .cornerRadius(8)
        }
    }
    
    private var importOptionsView: some View {
        VStack(alignment: .leading, spacing: 16) {
            Label("导入选项", systemImage: "gearshape")
                .font(.headline)
            
            VStack(spacing: 12) {
                // 导入策略选择
                VStack(alignment: .leading, spacing: 8) {
                    Text("导入策略")
                        .font(.subheadline)
                        .fontWeight(.medium)
                    
                    Picker("导入策略", selection: $importStrategy) {
                        Text("合并数据").tag(DataImporter.ImportStrategy.merge)
                        Text("替换数据").tag(DataImporter.ImportStrategy.replace)
                        Text("跳过已存在").tag(DataImporter.ImportStrategy.skipExisting)
                    }
                    .pickerStyle(.segmented)
                }
                
                // 冲突解决策略
                VStack(alignment: .leading, spacing: 8) {
                    Text("冲突处理")
                        .font(.subheadline)
                        .fontWeight(.medium)
                    
                    Picker("冲突处理", selection: $conflictResolution) {
                        Text("保留现有").tag(DataImporter.ConflictResolution.keepExisting)
                        Text("使用导入").tag(DataImporter.ConflictResolution.useImported)
                        Text("智能合并").tag(DataImporter.ConflictResolution.mergeData)
                    }
                    .pickerStyle(.segmented)
                }
                
                // 策略说明
                strategyDescriptionView
            }
            .padding()
            .background(Color(NSColor.controlBackgroundColor))
            .cornerRadius(8)
        }
    }
    
    private var strategyDescriptionView: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("说明:")
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundColor(.secondary)
            
            Text(getStrategyDescription())
                .font(.caption)
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.top, 4)
    }
    
    private var actionButtonsView: some View {
        HStack {
            if importResult != nil {
                Button("重新导入") {
                    resetImport()
                }
                .buttonStyle(.bordered)
            }
            
            Spacer()
            
            Button("开始导入") {
                startImport()
            }
            .buttonStyle(.borderedProminent)
            .disabled(!canImport)
            
            if isImporting {
                ProgressView()
                    .scaleEffect(0.8)
                    .padding(.leading, 8)
            }
        }
    }
    
    private func resultView(_ result: String) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("导入结果", systemImage: result.contains("成功") ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                .font(.headline)
                .foregroundColor(resultColor)
            
            Text(result)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.leading)
        }
        .padding()
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(8)
    }
    
    private func resultStatRow(_ label: String, value: String, color: Color = .primary) -> some View {
        HStack {
            Text(label)
                .foregroundColor(.secondary)
            Spacer()
            Text(value)
                .fontWeight(.semibold)
                .foregroundColor(color)
        }
        .font(.caption)
    }
    
    private func errorDetailsView(_ errors: [DataImporter.ImportError]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("错误详情:")
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundColor(.red)
            
            ScrollView(.vertical) {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(Array(errors.enumerated()), id: \.offset) { index, error in
                        Text("• \(error.localizedDescription)")
                            .font(.caption)
                            .foregroundColor(.red)
                    }
                }
                .padding(.leading, 8)
            }
            .frame(maxHeight: 100)
        }
    }
    
    private func newTagsView(_ tags: Set<String>) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("新增标签:")
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundColor(.purple)
            
            ScrollView(.horizontal, showsIndicators: false) {
                HStack {
                    ForEach(Array(tags.sorted()), id: \.self) { tag in
                        Text(tag)
                            .font(.caption)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Color.purple.opacity(0.1))
                            .foregroundColor(.purple)
                            .cornerRadius(4)
                    }
                }
                .padding(.leading, 8)
            }
        }
    }
    
    // MARK: - 方法
    
    private func handleFileSelection(_ result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            if let url = urls.first {
                selectedFileURL = url
                selectedFileName = url.lastPathComponent
                importResult = nil // 清除之前的结果
            }
        case .failure(let error):
            print("文件选择失败: \(error)")
        }
    }
    
    private func startImport() {
        guard let fileURL = selectedFileURL else { return }
        
        isImporting = true
        
        // 在后台线程执行导入
        DispatchQueue.global(qos: .userInitiated).async {
            let strategyString: String
            switch importStrategy {
            case .merge:
                strategyString = "merge"
            case .replace:
                strategyString = "replace"
            case .skipExisting:
                strategyString = "skipExisting"
            }
            
            let conflictString: String
            switch conflictResolution {
            case .keepExisting:
                conflictString = "keepExisting"
            case .useImported:
                conflictString = "useImported"
            case .mergeData:
                conflictString = "mergeData"
            }
            
            let result = tagManager.importData(
                from: fileURL,
                strategy: strategyString,
                conflictResolution: conflictString
            )
            
            DispatchQueue.main.async {
                self.importResult = result
                self.isImporting = false
            }
        }
    }
    
    private func resetImport() {
        importResult = nil
        selectedFileURL = nil
        selectedFileName = ""
    }
    
    private func getStrategyDescription() -> String {
        let strategyDesc: String
        switch importStrategy {
        case .merge:
            strategyDesc = "合并：保留现有项目，添加新项目"
        case .replace:
            strategyDesc = "替换：清除现有数据，导入备份数据"
        case .skipExisting:
            strategyDesc = "跳过：仅导入不存在的项目"
        }
        
        let conflictDesc: String
        switch conflictResolution {
        case .keepExisting:
            conflictDesc = "冲突时保留现有项目数据"
        case .useImported:
            conflictDesc = "冲突时使用导入的项目数据"
        case .mergeData:
            conflictDesc = "冲突时智能合并标签和Git信息"
        }
        
        return "\(strategyDesc)，\(conflictDesc)。"
    }
}

// MARK: - 预览

struct DataImportView_Previews: PreviewProvider {
    static var previews: some View {
        DataImportView()
            .environmentObject(TagManager())
    }
}