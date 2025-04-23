import SwiftUI

// ViewModifier方式获取视图引用
struct ViewReferenceSetter<T: View>: ViewModifier {
    @Binding var reference: T?
    
    func body(content: Content) -> some View {
        content
            .onAppear {
                // 当视图出现时保存引用
                reference = content as? T
            }
            .onDisappear {
                // 当视图消失时移除引用
                reference = nil
            }
    }
}

// 处理全选操作的类（必须是类才能使用@objc）
class SelectAllHandler: NSObject {
    var action: () -> Void
    var eventMonitor: Any?
    var originalSelector: Selector?
    
    // 保持一个全局引用以避免释放
    static var shared: SelectAllHandler?
    
    init(action: @escaping () -> Void) {
        self.action = action
        super.init()
    }
    
    // 设置全局键盘事件监听器
    func setupGlobalKeyMonitor() {
        // 移除现有监听器
        if let monitor = eventMonitor {
            NSEvent.removeMonitor(monitor)
            eventMonitor = nil
        }
        
        // 添加全局键盘监听
        eventMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            // 检测 ⌘A 快捷键
            if event.modifierFlags.contains(.command) && event.keyCode == 0 {
                // 检查第一响应者
                if let firstResponder = NSApp.keyWindow?.firstResponder {
                    let className = String(describing: type(of: firstResponder))
                    
                    // 如果焦点在文本控件上，不干扰原始事件
                    if className.contains("Text") || className.contains("Field") || 
                       className.contains("SearchField") || className.contains("TextView") ||
                       className.contains("Input") || className.contains("Editor") {
                        return event // 让事件继续传递
                    }
                }
                
                // 执行我们的全选动作
                self?.action()
                return nil // 事件已处理
            }
            return event // 让事件继续传递
        }
    }
    
    // 用于菜单项的动作
    @objc func menuItemPerformSelectAll(_ sender: Any?) {
        action()
    }
    
    // 用于全局事件的动作
    @objc func performSelectAll() {
        action()
    }
    
    deinit {
        if let monitor = eventMonitor {
            NSEvent.removeMonitor(monitor)
        }
    }
} 