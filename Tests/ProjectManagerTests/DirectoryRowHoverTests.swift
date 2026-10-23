import AppKit
import SwiftUI
import XCTest
@testable import ProjectManager

final class DirectoryRowHoverTests: XCTestCase {
    @MainActor
    func testTrackingRejectsPointsInAnotherRowAndRechecksAfterResize() throws {
        _ = NSApplication.shared
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 260, height: 160),
                              styleMask: [.borderless], backing: .buffered, defer: false)
        let parent = NSView(frame: NSRect(x: 0, y: 0, width: 260, height: 160))
        window.contentView = parent
        let tracking = IconHoverTrackingView(frame: NSRect(x: 12, y: 40, width: 220, height: 24))
        parent.addSubview(tracking)
        var values: [Bool] = []
        tracking.onHover = { values.append($0) }

        func event(at point: NSPoint) throws -> NSEvent {
            try XCTUnwrap(NSEvent.mouseEvent(with: .mouseMoved, location: point,
                modifierFlags: [], timestamp: 0, windowNumber: window.windowNumber,
                context: nil, eventNumber: 0, clickCount: 0, pressure: 0))
        }
        let inside = try event(at: NSPoint(x: 180, y: 52))
        tracking.mouseEntered(with: inside)
        XCTAssertEqual(values, [true])
        tracking.mouseMoved(with: try event(at: NSPoint(x: 180, y: 77)))
        XCTAssertEqual(values, [true, false])
        tracking.mouseEntered(with: inside)
        tracking.frame.size.width = 100
        tracking.mouseMoved(with: inside)
        XCTAssertEqual(values, [true, false, true, false])
        tracking.frame.origin.y = 80
        tracking.mouseEntered(with: inside)
        XCTAssertEqual(values.last, false)
        tracking.mouseEntered(with: try event(at: NSPoint(x: 50, y: 92)))
        XCTAssertEqual(values.last, true)
    }

    @MainActor
    func testDirectoryHighlightCoversItsOwnPaddedRowAndClearsOnExit() throws {
        _ = NSApplication.shared
        var clicks = 0
        let root = VStack(spacing: 0) {
            DirectoryRow(name: "第一行", path: "/fixture/first", count: 3, isSelected: false) { clicks += 1 }
            DirectoryRow(name: "第二行", path: "/fixture/second", count: 5, isSelected: false) { clicks += 1 }
        }.frame(width: 220).background(AppTheme.sidebarBackground)
        let host = NSHostingView(rootView: root)
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 220, height: host.fittingSize.height),
                              styleMask: [.borderless], backing: .buffered, defer: false)
        window.contentView = host
        host.layoutSubtreeIfNeeded()

        func trackers(in view: NSView) -> [IconHoverTrackingView] {
            view.subviews.flatMap { child in
                if let tracking = child as? IconHoverTrackingView { return [tracking] }
                return trackers(in: child)
            }
        }
        let rows = trackers(in: host).sorted { $0.convert($0.bounds, to: host).minY < $1.convert($1.bounds, to: host).minY }
        XCTAssertEqual(rows.count, 2)
        guard rows.count == 2 else { return }
        let frames = rows.map { $0.convert($0.bounds, to: host) }
        XCTAssertEqual(frames[0].minX, 0, accuracy: 0.5)
        XCTAssertEqual(frames[0].width, 220, accuracy: 0.5)
        XCTAssertEqual(frames[0].maxY, frames[1].minY, accuracy: 0.5)
        let bitmap = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in: host.bounds))
        func brightness(row: Int) throws -> CGFloat {
            host.cacheDisplay(in: host.bounds, to: bitmap)
            let y = Int(frames[row].midY / host.bounds.height * CGFloat(bitmap.pixelsHigh))
            let color = try XCTUnwrap(bitmap.colorAt(x: 2, y: y)?.usingColorSpace(.deviceRGB))
            return color.redComponent
        }
        let firstIdle = try brightness(row: 0)
        let secondIdle = try brightness(row: 1)
        for index in rows.indices {
            let row = rows[index]
            let point = row.convert(NSPoint(x: 1, y: row.bounds.midY), to: nil)
            let event = try XCTUnwrap(NSEvent.enterExitEvent(with: .mouseEntered, location: point,
                modifierFlags: [], timestamp: 0, windowNumber: window.windowNumber, context: nil,
                eventNumber: 0, trackingNumber: 0, userData: nil))
            row.mouseEntered(with: event)
            RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.03))
            XCTAssertGreaterThan(try brightness(row: index), (index == 0 ? firstIdle : secondIdle) + 0.02)
            XCTAssertEqual(try brightness(row: 1 - index), index == 0 ? secondIdle : firstIdle, accuracy: 0.01)
            row.mouseExited(with: event)
            RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.03))
        }
        XCTAssertEqual(try brightness(row: 0), firstIdle, accuracy: 0.01)
        XCTAssertEqual(try brightness(row: 1), secondIdle, accuracy: 0.01)
        XCTAssertEqual(clicks, 0)
    }
}
