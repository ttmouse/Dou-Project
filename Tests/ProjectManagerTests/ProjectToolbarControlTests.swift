import AppKit
import SwiftUI
import XCTest
@testable import ProjectManager

final class ProjectToolbarControlTests: XCTestCase {
    @MainActor
    func testHoverChangesBackgroundWithoutClickingOrActivatingWindow() throws {
        _ = NSApplication.shared
        var clickCount = 0
        let root = Button { clickCount += 1 } label: { ToolbarIcon(systemName: "arrow.up.arrow.down") }
            .buttonStyle(IconButtonStyle(iconSize: 16, buttonSize: AppTheme.searchBarControlHeight))
            .background(AppTheme.background)
        let host = NSHostingView(rootView: root)
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 32, height: 32),
                              styleMask: [.borderless], backing: .buffered, defer: false)
        window.contentView = host
        host.frame = NSRect(x: 0, y: 0, width: 32, height: 32)
        host.layoutSubtreeIfNeeded()

        func tracker(in view: NSView) -> IconHoverTrackingView? {
            if let tracking = view as? IconHoverTrackingView { return tracking }
            return view.subviews.compactMap { tracker(in: $0) }.first
        }
        let tracking = try XCTUnwrap(tracker(in: host))
        tracking.updateTrackingAreas()
        XCTAssertTrue(tracking.trackingAreas.contains { $0.options.contains(.activeAlways) })
        XCTAssertNil(tracking.hitTest(.zero))
        XCTAssertFalse(window.isKeyWindow)

        func brightness() throws -> CGFloat {
            let bitmap = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in: host.bounds))
            host.cacheDisplay(in: host.bounds, to: bitmap)
            let color = try XCTUnwrap(bitmap.colorAt(x: bitmap.pixelsWide / 8, y: bitmap.pixelsHigh / 2)?.usingColorSpace(.deviceRGB))
            return (color.redComponent + color.greenComponent + color.blueComponent) / 3
        }
        let idle = try brightness()
        let enter = try XCTUnwrap(NSEvent.enterExitEvent(with: .mouseEntered, location: NSPoint(x: 16, y: 16),
            modifierFlags: [], timestamp: 0, windowNumber: window.windowNumber, context: nil,
            eventNumber: 0, trackingNumber: 0, userData: nil))
        tracking.mouseEntered(with: enter)
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.2))
        XCTAssertGreaterThan(try brightness(), idle + 0.1)
        XCTAssertEqual(clickCount, 0)
        XCTAssertFalse(window.isKeyWindow)
        tracking.mouseExited(with: enter)
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.2))
        XCTAssertEqual(try brightness(), idle, accuracy: 0.02)
        XCTAssertEqual(clickCount, 0)
    }

    @MainActor
    func testDateFilterHasToolbarHeightForEveryFilter() {
        _ = NSApplication.shared
        for filter in DateFilter.allCases {
            let control = NSHostingView(rootView: DateFilterMenu(dateFilter: .constant(filter)))
            XCTAssertEqual(control.fittingSize.height, AppTheme.searchBarControlHeight, accuracy: 0.5)
            XCTAssertEqual(control.fittingSize.width, 62, accuracy: 0.5)
        }
    }

    @MainActor
    func testSortButtonHasToolbarHeight() {
        _ = NSApplication.shared
        let control = NSHostingView(rootView: SortButtons(sortOption: .constant(.timeDescending)))
        XCTAssertEqual(control.fittingSize.height, AppTheme.searchBarControlHeight, accuracy: 0.5)
        XCTAssertEqual(control.fittingSize.width, AppTheme.searchBarControlHeight, accuracy: 0.5)
    }
}
