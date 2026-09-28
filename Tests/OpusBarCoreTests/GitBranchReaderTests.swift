import XCTest
@testable import OpusBarCore

final class GitBranchReaderTests: XCTestCase {
    private var root: URL!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appending(path: "opusbar-git-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
    }

    private func write(_ text: String, to path: String) throws {
        let url = root.appending(path: path)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try text.write(to: url, atomically: true, encoding: .utf8)
    }

    func testBranchFromHead() throws {
        try write("ref: refs/heads/feature/cat\n", to: "repo/.git/HEAD")
        try FileManager.default.createDirectory(at: root.appending(path: "repo/src/deep"), withIntermediateDirectories: true)
        XCTAssertEqual(GitBranchReader.branch(atPath: root.appending(path: "repo").path), "feature/cat")
        XCTAssertEqual(GitBranchReader.branch(atPath: root.appending(path: "repo/src/deep").path), "feature/cat")
    }

    func testDetachedHeadShortSha() throws {
        try write("08f6e89c0ffee1234567890abcdef1234567890\n", to: "repo/.git/HEAD")
        XCTAssertEqual(GitBranchReader.branch(atPath: root.appending(path: "repo").path), "08f6e89")
    }

    func testWorktreeGitFile() throws {
        try write("ref: refs/heads/wt-branch\n", to: "main/.git/worktrees/wt/HEAD")
        try write("gitdir: ../main/.git/worktrees/wt\n", to: "wt/.git")
        XCTAssertEqual(GitBranchReader.branch(atPath: root.appending(path: "wt").path), "wt-branch")
        let absolute = root.appending(path: "main/.git/worktrees/wt").path
        try write("gitdir: \(absolute)\n", to: "wt2/.git")
        XCTAssertEqual(GitBranchReader.branch(atPath: root.appending(path: "wt2").path), "wt-branch")
    }

    func testNoRepoNil() throws {
        try FileManager.default.createDirectory(at: root.appending(path: "plain"), withIntermediateDirectories: true)
        // temp dir lives outside any repo
        XCTAssertNil(GitBranchReader.branch(atPath: root.appending(path: "plain").path))
        XCTAssertNil(GitBranchReader.branch(atPath: root.appending(path: "missing/dir").path))
    }
}
