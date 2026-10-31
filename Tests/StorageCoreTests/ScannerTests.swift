import Foundation
import Darwin
import Testing
@testable import StorageCore

@Suite("Filesystem scanner")
struct ScannerTests {
    private func fixture() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("MacStorageInspectorTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    @Test func nestedAggregationAndDescendingSort() async throws {
        let rootURL = try fixture(); defer { try? FileManager.default.removeItem(at: rootURL) }
        let small = rootURL.appendingPathComponent("small", isDirectory: true)
        let large = rootURL.appendingPathComponent("large", isDirectory: true)
        try FileManager.default.createDirectory(at: small, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: large, withIntermediateDirectories: true)
        try Data(repeating: 1, count: 8_192).write(to: small.appendingPathComponent("a.dat"))
        try Data(repeating: 2, count: 32_768).write(to: large.appendingPathComponent("b.dat"))
        let root = try #require(await FileSystemScanner().scan(root: rootURL).rootNode)
        #expect(root.fileCount == 2)
        #expect(root.logicalBytes == 40_960)
        #expect(root.children.first?.name == "large")
        #expect(root.children[0].allocatedBytes > root.children[1].allocatedBytes)
    }

    @Test func hardLinkIsCountedOnce() async throws {
        let rootURL = try fixture(); defer { try? FileManager.default.removeItem(at: rootURL) }
        let original = rootURL.appendingPathComponent("original.bin")
        let linked = rootURL.appendingPathComponent("linked.bin")
        try Data(repeating: 7, count: 65_536).write(to: original)
        #expect(link(original.path, linked.path) == 0)
        let root = try #require(await FileSystemScanner().scan(root: rootURL).rootNode)
        #expect(root.fileCount == 1)
        #expect(root.logicalBytes == 65_536)
        #expect(root.children.filter(\.isDuplicateHardLink).count == 1)
    }

    @Test func symlinkIsNotTraversed() async throws {
        let rootURL = try fixture(); defer { try? FileManager.default.removeItem(at: rootURL) }
        let directory = rootURL.appendingPathComponent("real", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try Data("payload".utf8).write(to: directory.appendingPathComponent("file"))
        #expect(symlink(rootURL.path, directory.appendingPathComponent("loop").path) == 0)
        let root = try #require(await FileSystemScanner().scan(root: rootURL).rootNode)
        #expect(root.flattened().filter { $0.kind == .symbolicLink }.count == 1)
        #expect(root.fileCount == 2)
    }

    @Test func sparseFileReportsLogicalAndAllocatedSeparately() async throws {
        let rootURL = try fixture(); defer { try? FileManager.default.removeItem(at: rootURL) }
        let sparse = rootURL.appendingPathComponent("sparse.img")
        #expect(FileManager.default.createFile(atPath: sparse.path, contents: nil))
        let handle = try FileHandle(forWritingTo: sparse)
        try handle.truncate(atOffset: 128 * 1_024 * 1_024); try handle.close()
        let root = try #require(await FileSystemScanner().scan(root: rootURL).rootNode)
        let node = try #require(root.children.first { $0.name == "sparse.img" })
        #expect(node.logicalBytes == 128 * 1_024 * 1_024)
        #expect(node.allocatedBytes < node.logicalBytes)
    }

    @Test func unicodeWhitespaceAndExclusion() async throws {
        let rootURL = try fixture(); defer { try? FileManager.default.removeItem(at: rootURL) }
        let excluded = rootURL.appendingPathComponent("skip me", isDirectory: true)
        try FileManager.default.createDirectory(at: excluded, withIntermediateDirectories: true)
        try Data("hello".utf8).write(to: excluded.appendingPathComponent("Grüße 世界.txt"))
        let snapshot = await FileSystemScanner().scan(root: rootURL, options: .init(excludedPaths: [excluded.path]))
        #expect(snapshot.rootNode?.fileCount == 0)
        #expect(snapshot.issues.contains { $0.path == excluded.path && $0.message.contains("Excluded") })
    }

    @Test func cancellationProducesCancelledResult() async throws {
        let rootURL = try fixture(); defer { try? FileManager.default.removeItem(at: rootURL) }
        for index in 0..<2_000 { FileManager.default.createFile(atPath: rootURL.appendingPathComponent("file-\(index)").path, contents: Data([0])) }
        let task = Task {
            await FileSystemScanner().scan(root: rootURL, options: .init(updateEvery: 1),
                onProgress: { _ in await Task.yield() })
        }
        task.cancel()
        let snapshot = await task.value
        #expect(snapshot.completeness == .cancelled)
        #expect(snapshot.progress.filesScanned < 2_000)
    }
}
