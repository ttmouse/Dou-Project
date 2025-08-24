import SwiftUI

/// 设置面板主视图
struct SettingsView: View {
    @ObservedObject var editorManager = AppOpenHelper.editorManager
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
            
              
            // 内容区域
            EditorSettingsView(editorManager: editorManager, showingAddEditor: $showingAddEditor)
            
            Spacer()
        }
        .frame(width: 600, height: 500)
        .background(AppTheme.background)
        .sheet(isPresented: $showingAddEditor) {
            AddEditorView(editorManager: editorManager)
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