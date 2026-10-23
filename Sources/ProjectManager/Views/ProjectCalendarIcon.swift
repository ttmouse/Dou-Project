import SwiftUI

/// 与设计 playground 的 16 × 16 日历 SVG 共用几何尺寸。
struct ProjectCalendarIcon: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.addRoundedRect(in: CGRect(x: 2, y: 3, width: 12, height: 11), cornerSize: CGSize(width: 2, height: 2))
        for x: CGFloat in [5, 11] {
            path.move(to: CGPoint(x: x, y: 1))
            path.addLine(to: CGPoint(x: x, y: 5))
        }
        path.move(to: CGPoint(x: 2, y: 7))
        path.addLine(to: CGPoint(x: 14, y: 7))
        return path.applying(CGAffineTransform(scaleX: rect.width / 16, y: rect.height / 16))
            .applying(CGAffineTransform(translationX: rect.minX, y: rect.minY))
    }
}
