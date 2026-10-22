import XCTest
@testable import ProjectManager

/// 业务标签匹配测试
///
/// 症状背景（本次修正）：原用例把待分析内容写进局部变量 `content` 却从未使用 ——
/// `applyBusinessTags` 只从项目目录读 README，规则又来自用户磁盘上的当前配置，
/// 于是断言实际依赖「项目名恰好含关键词 + 用户当时的规则集」。
/// 后果：用户改过打标规则后用例就红（本机实测 2 条红），且用例名与真实被测行为不符。
///
/// 现在：README 落盘到临时目录、规则显式传入 `defaultRules`，断言只依赖被测逻辑本身。
final class BusinessTaggerTests: XCTestCase {

    private var tempDirs: [URL] = []

    override func tearDown() {
        tempDirs.forEach(TestHelper.cleanupTempDirectory)
        tempDirs.removeAll()
        super.tearDown()
    }

    // MARK: - 辅助

    /// 造一个真实可读的项目目录：README.md 的内容即待分析文档。
    /// 项目名固定为中性值，确保命中来自文档内容而不是目录名。
    private func makeProject(readme: String, existingTags: Set<String> = []) -> Project {
        let dir = TestHelper.createTempDirectory()
        tempDirs.append(dir)
        try! readme.write(
            to: dir.appendingPathComponent("README.md"),
            atomically: true,
            encoding: .utf8
        )
        return ProjectFixtures.make(name: "zzz-untitled", path: dir.path, tags: existingTags)
    }

    private func tag(_ project: Project, overwrite: Bool = false) -> Project {
        BusinessTagger.applyBusinessTags(
            to: project,
            overwrite: overwrite,
            rules: BusinessTagger.defaultRules
        )
    }

    // MARK: - 文档内容 → 标签

    func testVideoProjectMatching() {
        let project = makeProject(readme: """
        # Video Recorder App

        A powerful video recording application that supports live streaming and MP4 export.

        Features:
        - Real-time video recording
        - Live streaming to multiple platforms
        - FFmpeg integration for video processing
        - RTMP support for broadcasting
        """)

        let result = tag(project)

        XCTAssertTrue(result.tags.contains("视频"), "应该匹配视频标签")
        XCTAssertTrue(result.tags.contains("多媒体"), "应该匹配多媒体标签")
    }

    func testInputMethodProjectMatching() {
        let project = makeProject(readme: """
        # Chinese Pinyin Input Method

        An intelligent pinyin input method for typing Chinese characters.

        Features:
        - Smart pinyin prediction
        - Chinese input support
        - IME keyboard integration
        - Customizable typing experience
        """)

        let result = tag(project)

        XCTAssertTrue(result.tags.contains("输入法"), "应该匹配输入法标签")
        XCTAssertTrue(result.tags.contains("拼音"), "应该匹配拼音标签")
    }

    func testMobileAppProjectMatching() {
        let project = makeProject(readme: """
        # Mobile Shopping App

        A cross-platform mobile shopping application.

        Features:
        - iOS and Android support
        - React Native for cross-platform development
        - Mobile-first design
        """)

        let result = tag(project)

        XCTAssertTrue(result.tags.contains("移动端"), "应该匹配移动端标签")
    }

    func testAIBasedProjectMatching() {
        let project = makeProject(readme: """
        # AI-Powered Document Analyzer

        An intelligent document analysis tool using machine learning.

        Features:
        - AI-powered text extraction
        - Deep learning models for classification
        - LLM integration for summarization
        """)

        let result = tag(project)

        XCTAssertTrue(result.tags.contains("AI"), "应该匹配 AI 标签")
        XCTAssertTrue(result.tags.contains("机器学习"), "应该匹配机器学习标签")
    }

    func testEcommerceProjectMatching() {
        let project = makeProject(readme: """
        # E-commerce Platform

        A complete online shopping solution with payment integration.

        Features:
        - Shopping cart functionality
        - Multiple payment gateways
        - Order management
        """)

        let result = tag(project)

        XCTAssertTrue(result.tags.contains("电商"), "应该匹配电商标签")
        XCTAssertTrue(result.tags.contains("购物"), "应该匹配购物标签")
    }

    // MARK: - 标签合并语义

    func testTagsAreMergedNotOverwritten() {
        let project = makeProject(
            readme: "# Video Project\n\nA video recording application with live streaming.",
            existingTags: ["frontend", "React"]
        )

        let result = tag(project, overwrite: false)

        XCTAssertTrue(result.tags.contains("frontend"), "应该保留原有标签")
        XCTAssertTrue(result.tags.contains("React"), "应该保留原有标签")
        XCTAssertTrue(result.tags.contains("视频"), "应该添加新业务标签")
    }

    func testTagsAreOverwrittenWhenRequested() {
        let project = makeProject(
            readme: "# Video Project\n\nA video recording application with live streaming.",
            existingTags: ["frontend", "React"]
        )

        let result = tag(project, overwrite: true)

        XCTAssertFalse(result.tags.contains("frontend"), "覆盖模式下不应保留原有标签")
        XCTAssertFalse(result.tags.contains("React"), "覆盖模式下不应保留原有标签")
        XCTAssertTrue(result.tags.contains("视频"), "应该包含业务标签")
    }

    func testEmptyDocumentReturnsNoTags() {
        let project = makeProject(readme: "")

        let result = tag(project)

        XCTAssertTrue(result.tags.isEmpty, "空文档不应该匹配任何标签")
    }

    // MARK: - 规则调试

    func testDebugRulesReturnsMatchedRuleNames() {
        let project = makeProject(readme: """
        # Video Project

        A video recording application with live streaming.
        """)

        let matchedRules = BusinessTagger.debugRules(
            for: project.path,
            projectName: project.name,
            rules: BusinessTagger.defaultRules
        )

        XCTAssertTrue(matchedRules.contains("视频项目"), "视频文档应命中「视频项目」规则")
    }

    func testDebugRulesIgnoresUnrelatedDocument() {
        // 内容与项目名都避开所有默认关键词（"ipsum" 含 im、"notes" 含 note，不能用）
        let project = makeProject(readme: "lorem dolor amet")

        let matchedRules = BusinessTagger.debugRules(
            for: project.path,
            projectName: project.name,
            rules: BusinessTagger.defaultRules
        )

        XCTAssertTrue(matchedRules.isEmpty, "无关内容不应命中任何规则")
    }
}
