import Foundation

/// 统一日志工具：分级输出
/// - debug：逐项目/逐目录等高频调试日志，Release 构建自动消除（`#if DEBUG`）
/// - info：操作统计、状态变化，始终输出
/// - error：错误信息，始终输出
///
/// 背景：此前大量 print 直接输出导致日志可达 50KB+，
/// 现收敛为仅保留操作级信息，循环内高频日志随 Release 打包消失。
enum Log {

    /// 调试级：Release 构建（打包产物）不输出
    static func debug(_ message: @autoclosure () -> String) {
        #if DEBUG
        print("[DBG] \(message())")
        #endif
    }

    /// 信息级：操作统计、状态变化（一次操作最多几行）
    static func info(_ message: String) {
        print("[INFO] \(message)")
    }

    /// 错误级：始终输出
    static func error(_ message: String) {
        print("[ERROR] \(message)")
    }
}
