import SwiftUI

/// 设置面板主视图
struct SettingsView: View {
    @ObservedObject var editorManager = AppOpenHelper.editorManager
    @State private var selectedTab: SettingsTab = .editors
    @State private var showingAddEditor = false
    
    var body: some View {
        VStack(spacing: 0) {
            // 标题栏
            HStack {
                Text("偏好设置")
                    .font(.headline)
                    .fontWeight(.medium)
                
                Spacer()
            }
            .padding()
            .background(AppTheme.sidebarBackground)
            
            // 标签选择
            Picker("设置类别", selection: $selectedTab) {
                ForEach(SettingsTab.allCases, id: \.self) { tab in
                    Text(tab.displayName).tag(tab)
                }
            }
            .pickerStyle(SegmentedPickerStyle())
            .padding(.horizontal)
            .padding(.bottom)
            
            // 内容区域
            switch selectedTab {
            case .editors:
                EditorSettingsView(editorManager: editorManager, showingAddEditor: $showingAddEditor)
            case .general:
                GeneralSettingsView()
            }
            
            Spacer()
        }
        .frame(width: 600, height: 500)
        .background(AppTheme.background)
        .sheet(isPresented: $showingAddEditor) {
            AddEditorView(editorManager: editorManager)
        }
    }
}

/// 设置标签枚举
enum SettingsTab: String, CaseIterable {
    case editors = "editors"
    case general = "general"
    
    var displayName: String {
        switch self {
        case .editors:
            return "编辑器"
        case .general:
            return "通用"
        }
    }
}

#if DEBUG
struct SettingsView_Previews: PreviewProvider {
    static var previews: some View {
        SettingsView()
    }
}
#endif