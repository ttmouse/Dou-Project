import AppKit
import SwiftUI
import XCTest
@testable import ProjectManager

final class TagAppearanceTests: XCTestCase {
    func testTextTagsHaveNoInsetsAndPillStylesKeepTheirInsets() {
        XCTAssertEqual(TagAppearance.text.horizontalPadding, 0)
        XCTAssertEqual(TagAppearance.text.verticalPadding, 0)
        for appearance in [TagAppearance.gray, .colorful] {
            XCTAssertEqual(appearance.horizontalPadding, 8)
            XCTAssertEqual(appearance.verticalPadding, 4)
        }
    }

    @MainActor
    func testSwiftUITextTagFitsItsTextWithoutExtraInsets() {
        _ = NSApplication.shared
        let tag = NSHostingView(rootView: TagView(tag: "yiwu", color: .blue, fontSize: 13, appearanceOverride: .text))
        let text = NSHostingView(rootView: Text("#yiwu").font(.system(size: 13)))
        XCTAssertEqual(tag.fittingSize.width, text.fittingSize.width, accuracy: 0.5)
        XCTAssertEqual(tag.fittingSize.height, text.fittingSize.height, accuracy: 0.5)
    }

    func testHashStyleOnlyChangesDisplayLabel() {
        XCTAssertEqual(TagAppearance.text.label(for: "AI"), "#AI")
        XCTAssertEqual(TagAppearance.text.label(for: "#已有前缀"), "#已有前缀")
        XCTAssertEqual(TagAppearance.gray.label(for: "AI"), "AI")
        XCTAssertEqual(TagAppearance.colorful.label(for: "AI"), "AI")
    }

    func testTextStyleHasNoBackgroundInAnyState() {
        for selected in [false, true] {
            for preview in [false, true] {
                XCTAssertEqual(TagAppearance.text.background(base: .green, selected: selected, preview: preview), .clear)
            }
        }
    }

    func testGrayStyleDoesNotUseTagColorAndColorfulRetainsIt() {
        for selected in [false, true] {
            XCTAssertEqual(TagAppearance.gray.background(base: .red, selected: selected), TagAppearance.gray.background(base: .blue, selected: selected))
            XCTAssertEqual(TagAppearance.gray.foreground(base: .red, selected: selected), TagAppearance.gray.foreground(base: .blue, selected: selected))
        }
        XCTAssertEqual(TagAppearance.colorful.background(base: .green), Color.green.opacity(0.2))
        XCTAssertEqual(TagAppearance.colorful.background(base: .green, selected: true), .green)
    }

    func testPreferenceDefaultsToColorfulAndPersistsSelection() throws {
        let defaults = try XCTUnwrap(UserDefaults(suiteName: "TagAppearanceTests.\(UUID().uuidString)"))
        let storage = AppStorage(wrappedValue: TagAppearance.colorful, TagAppearance.preferenceKey, store: defaults)
        XCTAssertEqual(storage.wrappedValue, .colorful)
        storage.wrappedValue = .text
        let restored = AppStorage(wrappedValue: TagAppearance.colorful, TagAppearance.preferenceKey, store: defaults)
        XCTAssertEqual(restored.wrappedValue, .text)
    }

    @MainActor
    func testNativeRowRefreshesStyleWithoutChangingTagActions() throws {
        _ = NSApplication.shared
        let row = NativeProjectListRow(frame: NSRect(x: 0, y: 0, width: 1000, height: 42))
        let project = ProjectFixtures.make(name: "example", path: "/fixture/example")
        let tags = [TagDisplayData(name: "AI", color: .blue)]
        var received: ProjectRowAction?
        row.onAction = { _, action in received = action }
        func tagButton(in view: NSView) -> NativeProjectTagButton? {
            if let button = view as? NativeProjectTagButton { return button }
            return view.subviews.compactMap { tagButton(in: $0) }.first
        }

        row.update(project: project, selected: false, tags: tags, appearance: .colorful)
        let original = try XCTUnwrap(tagButton(in: row))
        row.update(project: project, selected: false, tags: tags, appearance: .text)
        let text = try XCTUnwrap(tagButton(in: row))
        XCTAssertEqual(text.title, "#AI")
        XCTAssertLessThan(text.tagWidth, original.tagWidth)
        let expectedWidth = ceil(("#AI" as NSString).size(withAttributes: [.font: NSFont.systemFont(ofSize: 11)]).width)
        XCTAssertEqual(text.tagWidth, expectedWidth)
        text.performClick(nil)
        XCTAssertEqual(received, .tag("AI"))
        text.onRemove()
        XCTAssertEqual(received, .removeTag("AI"))

        row.update(project: project, selected: false, tags: tags, appearance: .gray)
        XCTAssertEqual(try XCTUnwrap(tagButton(in: row)).title, "AI")
        XCTAssertEqual(tags[0].color, .blue)
    }
}
