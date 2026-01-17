import XCTest
@testable import ProjectManager

class BusinessTaggerTests: XCTestCase {

    func testVideoProjectMatching() {
        let content = """
        # Video Recorder App

        A powerful video recording application that supports live streaming and MP4 export.

        Features:
        - Real-time video recording
        - Live streaming to multiple platforms
        - FFmpeg integration for video processing
        - RTMP support for broadcasting

        This is a professional tool for video content creators.
        """

        let project = Project(
            id: UUID(),
            name: "VideoRecorder",
            path: "/test/video-recorder",
            tags: [],
            mtime: Date(),
            size: 1000,
            checksum: "abc",
            git_commits: 0,
            git_last_commit: Date.distantPast,
            git_daily: nil,
            startupCommand: nil,
            customPort: nil,
            created: Date(),
            checked: Date()
        )

        let result = BusinessTagger.applyBusinessTags(to: project)

        XCTAssertTrue(result.tags.contains("视频"), "应该匹配视频标签")
        XCTAssertTrue(result.tags.contains("多媒体"), "应该匹配多媒体标签")
    }

    func testInputMethodProjectMatching() {
        let content = """
        # Chinese Pinyin Input Method

        An intelligent pinyin input method for typing Chinese characters.

        Features:
        - Smart pinyin prediction
        - Chinese input support
        - IME keyboard integration
        - Customizable typing experience

        Best for users who type Chinese regularly.
        """

        let project = Project(
            id: UUID(),
            name: "PinyinIME",
            path: "/test/pinyin-ime",
            tags: [],
            mtime: Date(),
            size: 1000,
            checksum: "abc",
            git_commits: 0,
            git_last_commit: Date.distantPast,
            git_daily: nil,
            startupCommand: nil,
            customPort: nil,
            created: Date(),
            checked: Date()
        )

        let result = BusinessTagger.applyBusinessTags(to: project)

        XCTAssertTrue(result.tags.contains("输入法"), "应该匹配输入法标签")
        XCTAssertTrue(result.tags.contains("拼音"), "应该匹配拼音标签")
    }

    func testMobileAppProjectMatching() {
        let content = """
        # Mobile Shopping App

        A cross-platform mobile shopping application.

        Features:
        - iOS and Android support
        - React Native for cross-platform development
        - Mobile-first design
        - In-app purchases
        """

        let project = Project(
            id: UUID(),
            name: "MobileShop",
            path: "/test/mobile-shop",
            tags: [],
            mtime: Date(),
            size: 1000,
            checksum: "abc",
            git_commits: 0,
            git_last_commit: Date.distantPast,
            git_daily: nil,
            startupCommand: nil,
            customPort: nil,
            created: Date(),
            checked: Date()
        )

        let result = BusinessTagger.applyBusinessTags(to: project)

        XCTAssertTrue(result.tags.contains("移动端"), "应该匹配移动端标签")
    }

    func testAIBasedProjectMatching() {
        let content = """
        # AI-Powered Document Analyzer

        An intelligent document analysis tool using machine learning.

        Features:
        - AI-powered text extraction
        - Deep learning models for classification
        - Neural network for pattern recognition
        - LLM integration for summarization
        """

        let project = Project(
            id: UUID(),
            name: "AIAnalyzer",
            path: "/test/ai-analyzer",
            tags: [],
            mtime: Date(),
            size: 1000,
            checksum: "abc",
            git_commits: 0,
            git_last_commit: Date.distantPast,
            git_daily: nil,
            startupCommand: nil,
            customPort: nil,
            created: Date(),
            checked: Date()
        )

        let result = BusinessTagger.applyBusinessTags(to: project)

        XCTAssertTrue(result.tags.contains("AI"), "应该匹配 AI 标签")
        XCTAssertTrue(result.tags.contains("机器学习"), "应该匹配机器学习标签")
    }

    func testEcommerceProjectMatching() {
        let content = """
        # E-commerce Platform

        A complete online shopping solution with payment integration.

        Features:
        - Shopping cart functionality
        - Multiple payment gateways
        - Order management
        - E-commerce dashboard
        """

        let project = Project(
            id: UUID(),
            name: "EcommerceShop",
            path: "/test/ecommerce",
            tags: [],
            mtime: Date(),
            size: 1000,
            checksum: "abc",
            git_commits: 0,
            git_last_commit: Date.distantPast,
            git_daily: nil,
            startupCommand: nil,
            customPort: nil,
            created: Date(),
            checked: Date()
        )

        let result = BusinessTagger.applyBusinessTags(to: project)

        XCTAssertTrue(result.tags.contains("电商"), "应该匹配电商标签")
        XCTAssertTrue(result.tags.contains("购物"), "应该匹配购物标签")
    }

    func testTagsAreMergedNotOverwritten() {
        let content = """
        # Video Project

        A video recording application with live streaming.
        """

        let project = Project(
            id: UUID(),
            name: "VideoRecorder",
            path: "/test/video-recorder",
            tags: ["frontend", "React"],
            mtime: Date(),
            size: 1000,
            checksum: "abc",
            git_commits: 0,
            git_last_commit: Date.distantPast,
            git_daily: nil,
            startupCommand: nil,
            customPort: nil,
            created: Date(),
            checked: Date()
        )

        let result = BusinessTagger.applyBusinessTags(to: project, overwrite: false)

        XCTAssertTrue(result.tags.contains("frontend"), "应该保留原有标签")
        XCTAssertTrue(result.tags.contains("React"), "应该保留原有标签")
        XCTAssertTrue(result.tags.contains("视频"), "应该添加新业务标签")
    }

    func testTagsAreOverwrittenWhenRequested() {
        let content = """
        # Video Project

        A video recording application with live streaming.
        """

        let project = Project(
            id: UUID(),
            name: "VideoRecorder",
            path: "/test/video-recorder",
            tags: ["frontend", "React"],
            mtime: Date(),
            size: 1000,
            checksum: "abc",
            git_commits: 0,
            git_last_commit: Date.distantPast,
            git_daily: nil,
            startupCommand: nil,
            customPort: nil,
            created: Date(),
            checked: Date()
        )

        let result = BusinessTagger.applyBusinessTags(to: project, overwrite: true)

        XCTAssertFalse(result.tags.contains("frontend"), "覆盖模式下不应保留原有标签")
        XCTAssertFalse(result.tags.contains("React"), "覆盖模式下不应保留原有标签")
        XCTAssertTrue(result.tags.contains("视频"), "应该包含业务标签")
    }

    func testEmptyDocumentReturnsNoTags() {
        let content = ""

        let project = Project(
            id: UUID(),
            name: "EmptyProject",
            path: "/test/empty",
            tags: [],
            mtime: Date(),
            size: 1000,
            checksum: "abc",
            git_commits: 0,
            git_last_commit: Date.distantPast,
            git_daily: nil,
            startupCommand: nil,
            customPort: nil,
            created: Date(),
            checked: Date()
        )

        let result = BusinessTagger.applyBusinessTags(to: project)

        XCTAssertTrue(result.tags.isEmpty, "空文档不应该匹配任何标签")
    }

    func testDebugRulesReturnsMatchedRuleNames() {
        let content = """
        # Video Project

        A video recording application with live streaming.
        """

        let matchedRules = BusinessTagger.debugRules(for: "/test/video-recorder")

        XCTAssertFalse(matchedRules.isEmpty, "应该至少匹配一条规则")
    }
}
