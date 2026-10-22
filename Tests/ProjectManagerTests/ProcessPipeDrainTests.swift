import XCTest
@testable import ProjectManager

/// 进程执行器的管道读取顺序回归护栏（性能审计后续 #5）
///
/// 症状背景：`ShellExecutor.executeGitCommand` 与 `PortManager.runProcess`
/// 原先都是 `run()` → `waitUntilExit()` → `readDataToEndOfFile()`。
/// 管道缓冲区约 64KB，子进程写满后阻塞在 write()，父进程阻塞在 wait，
/// 双方互等 —— 大仓库的 `git diff` / 连接很多的 `lsof` 会永久卡住。
///
/// 本文件锁住三件事：
///   1. 远超管道容量的 stdout + stderr 都能被完整读回，且不卡死（超时即失败）；
///   2. 只有一路输出、另一路沉默时也不会卡住；
///   3. 读取顺序改动后 success / combinedOutput 语义不变。
final class ProcessPipeDrainTests: XCTestCase {

    /// 每条路 2MB，远高于 64KB 管道缓冲；旧实现会在这里死锁。
    private let bigOutputBytes = 2 * 1024 * 1024

    /// 卡死即失败：正常工作只需几十毫秒，10 秒足够覆盖慢机器。
    private let timeout: TimeInterval = 10

    /// 用 /bin/sh 往 stdout 与 stderr 各写一大段内容，退出码 0。
    private var bigBothStreamsCommand: [String] {
        ["-c", "head -c \(bigOutputBytes) /dev/zero | tr '\\0' 'a'; head -c \(bigOutputBytes) /dev/zero | tr '\\0' 'b' >&2; exit 0"]
    }

    /// 在限定时间内完成 block；超时即报失败，而不是让整轮测试挂住。
    private func runWithDeadline(
        _ label: String,
        file: StaticString = #filePath,
        line: UInt = #line,
        block: @escaping () -> Void
    ) {
        let done = expectation(description: label)
        DispatchQueue.global(qos: .userInitiated).async {
            block()
            done.fulfill()
        }
        wait(for: [done], timeout: timeout)
    }

    // MARK: - ShellExecutor

    func testShellExecutorDrainsBigStdoutAndStderrBeforeWaiting() {
        var output = ""
        var success = false
        runWithDeadline("ShellExecutor 大输出双管道") {
            let result = ShellExecutor.execute(
                executable: "/bin/sh",
                args: self.bigBothStreamsCommand,
                workingDir: NSTemporaryDirectory()
            )
            output = result.output
            success = result.success
        }
        XCTAssertTrue(success, "退出码 0 应判成功")
        XCTAssertEqual(output.count, bigOutputBytes, "成功时只返回 stdout，且必须完整")
    }

    func testShellExecutorFailureKeepsStdoutAndStderrSemantics() {
        var output = ""
        var success = true
        runWithDeadline("ShellExecutor 失败语义") {
            let result = ShellExecutor.execute(
                executable: "/bin/sh",
                args: ["-c", "printf 'out-line'; printf 'err-line' >&2; exit 3"],
                workingDir: NSTemporaryDirectory()
            )
            output = result.output
            success = result.success
        }
        XCTAssertFalse(success, "非零退出码应判失败")
        XCTAssertTrue(output.contains("out-line"), "失败时也要保留 stdout: \(output)")
        XCTAssertTrue(output.contains("err-line"), "失败时必须带 stderr: \(output)")
    }

    func testShellExecutorWithSilentStderrDoesNotBlock() {
        var output = ""
        runWithDeadline("ShellExecutor stderr 沉默") {
            let result = ShellExecutor.execute(
                executable: "/bin/sh",
                args: ["-c", "head -c \(self.bigOutputBytes) /dev/zero | tr '\\0' 'c'"],
                workingDir: NSTemporaryDirectory()
            )
            output = result.output
        }
        XCTAssertEqual(output.count, bigOutputBytes, "stderr 无输出时 stdout 仍要读全")
    }

    /// 真实 git 路径：`git show`/`git diff` 在大输出时曾走同一条死锁路径。
    func testExecuteGitCommandReadsLargeOutput() throws {
        let repo = try makeScratchRepo()
        defer { try? FileManager.default.removeItem(at: repo) }

        var output = ""
        var success = false
        runWithDeadline("git 大输出") {
            let result = ShellExecutor.executeGitCommand(
                args: ["log", "--stat", "--all", "-p"],
                workingDir: repo.path
            )
            output = result.output
            success = result.success
        }
        XCTAssertTrue(success, "git log 应成功: \(output.prefix(200))")
        // 夹具提交了 4MB 随机文本，stat/patch 输出远超管道容量。
        XCTAssertGreaterThan(output.count, 4 * 1024 * 1024, "大输出必须完整读回")
    }

    // MARK: - PortManager

    func testPortManagerDrainsBigOutputBeforeWaiting() {
        var output = ""
        var success = false
        runWithDeadline("PortManager 大输出双管道") {
            let result = PortManager.runProcess(
                executable: "/bin/sh",
                arguments: self.bigBothStreamsCommand
            )
            output = result.output
            success = result.success
        }
        XCTAssertTrue(success, "退出码 0 应判成功")
        XCTAssertEqual(output.count, bigOutputBytes, "成功时只返回 stdout，且必须完整")
    }

    func testPortManagerFailureIncludesBothStreams() {
        var output = ""
        var success = true
        runWithDeadline("PortManager 失败语义") {
            let result = PortManager.runProcess(
                executable: "/bin/sh",
                arguments: ["-c", "printf 'pid-line'; printf 'permission denied' >&2; exit 1"]
            )
            output = result.output
            success = result.success
        }
        XCTAssertFalse(success)
        XCTAssertTrue(output.contains("pid-line"))
        XCTAssertTrue(output.contains("permission denied"))
    }

    func testPortManagerMissingExecutableReportsFailureWithoutHanging() {
        var output = ""
        var success = true
        runWithDeadline("PortManager 可执行文件缺失") {
            let result = PortManager.runProcess(
                executable: "/nonexistent/definitely-not-here",
                arguments: []
            )
            output = result.output
            success = result.success
        }
        XCTAssertFalse(success, "启动失败应返回失败而不是崩溃")
        XCTAssertTrue(output.contains("执行命令失败"), "应保留原有错误文案: \(output)")
    }

    // MARK: - 夹具

    /// 造一个含超大单文件提交的临时仓库；不用真实项目，也不碰用户数据。
    private func makeScratchRepo() throws -> URL {
        let repo = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("PipeDrain-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: repo, withIntermediateDirectories: true)

        let blob = repo.appendingPathComponent("blob.txt")
        let filler = String(repeating: "x", count: 64 * 1024)
        var content = ""
        content.reserveCapacity(4 * 1024 * 1024 + 1024)
        for index in 0..<64 {
            content += "line-\(index)-\(filler)\n"
        }
        try content.write(to: blob, atomically: true, encoding: .utf8)

        let git = { (args: [String]) in
            _ = ShellExecutor.execute(executable: "/usr/bin/git", args: args, workingDir: repo.path)
        }
        git(["init", "-q"])
        git(["config", "user.email", "test@example.com"])
        git(["config", "user.name", "Pipe Drain Test"])
        git(["add", "blob.txt"])
        git(["commit", "-q", "-m", "fixture: large blob"])

        return repo
    }
}
