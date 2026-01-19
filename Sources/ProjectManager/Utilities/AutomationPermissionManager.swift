import Foundation
import AppKit
import ApplicationServices

enum AutomationPermissionStatus {
    case unknown
    case authorized
    case denied
    case notDetermined
    
    var localizedDescription: String {
        switch self {
        case .authorized:
            return "已授权"
        case .denied:
            return "已拒绝"
        case .notDetermined:
            return "尚未请求"
        case .unknown:
            return "未知"
        }
    }
    
    var systemImageName: String {
        switch self {
        case .authorized:
            return "checkmark.seal.fill"
        case .denied:
            return "xmark.octagon.fill"
        case .notDetermined:
            return "questionmark.circle"
        case .unknown:
            return "questionmark.circle.dashed"
        }
    }
}

enum AutomationPermissionManager {
    private static let terminalBundleId = "com.apple.Terminal"
    
    static func terminalPermissionStatus(promptIfNeeded: Bool = false) -> AutomationPermissionStatus {
        let descriptor = NSAppleEventDescriptor(bundleIdentifier: terminalBundleId)
        
        let status = AEDeterminePermissionToAutomateTarget(
            descriptor.aeDesc,
            typeWildCard,
            typeWildCard,
            promptIfNeeded
        )
        
        switch Int(status) {
        case Int(noErr):
            return .authorized
        case Int(errAEEventNotPermitted):
            return .denied
        case Int(errAEEventWouldRequireUserConsent):
            return .notDetermined
        default:
            return .unknown
        }
    }
}
