import SwiftUI

/// 与设计 playground 的 16 × 16 Git SVG 共用几何尺寸。
struct ProjectGitBranchIcon: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        for center in [CGPoint(x: 4, y: 3), CGPoint(x: 12, y: 3), CGPoint(x: 4, y: 13)] {
            path.addEllipse(in: CGRect(x: center.x - 1.5, y: center.y - 1.5, width: 3, height: 3))
        }
        path.move(to: CGPoint(x: 4, y: 4.5))
        path.addLine(to: CGPoint(x: 4, y: 11.5))
        path.move(to: CGPoint(x: 12, y: 4.5))
        path.addLine(to: CGPoint(x: 12, y: 5.5))
        path.addCurve(
            to: CGPoint(x: 8.5, y: 9),
            control1: CGPoint(x: 12, y: 7.4329966244),
            control2: CGPoint(x: 10.4329966244, y: 9)
        )
        path.addLine(to: CGPoint(x: 4, y: 9))
        return path.applying(CGAffineTransform(scaleX: rect.width / 16, y: rect.height / 16))
            .applying(CGAffineTransform(translationX: rect.minX, y: rect.minY))
    }
}
