import Foundation
import Testing
@testable import StorageCore

@Suite("Incremental file tree updates")
struct FileTreeUpdaterTests {
    @Test func removingLeafRecomputesOnlyAncestorAggregates() throws {
        let base = URL(fileURLWithPath: "/tmp/scan", isDirectory: true)
        let removed = FileNode(url: base.appendingPathComponent("folder/removed.bin"), kind: .file,
            logicalBytes: 300, allocatedBytes: 256, fileCount: 1)
        let kept = FileNode(url: base.appendingPathComponent("folder/kept.bin"), kind: .file,
            logicalBytes: 100, allocatedBytes: 80, fileCount: 1)
        let folder = FileNode(url: base.appendingPathComponent("folder"), kind: .directory,
            logicalBytes: 400, allocatedBytes: 336, fileCount: 2, children: [removed, kept])
        let root = FileNode(url: base, kind: .directory, logicalBytes: 400,
            allocatedBytes: 336, fileCount: 2, children: [folder])

        let updated = try #require(FileTreeUpdater.removing([removed.url], from: root))
        #expect(updated.fileCount == 1)
        #expect(updated.logicalBytes == 100)
        #expect(updated.allocatedBytes == 80)
        #expect(updated.flattened().map(\.url.path).contains(kept.url.path))
        #expect(!updated.flattened().map(\.url.path).contains(removed.url.path))
    }

    @Test func removingFolderDropsItsWholeSubtree() throws {
        let base = URL(fileURLWithPath: "/tmp/scan", isDirectory: true)
        let child = FileNode(url: base.appendingPathComponent("folder/child"), kind: .file,
            logicalBytes: 50, allocatedBytes: 40, fileCount: 1)
        let folder = FileNode(url: base.appendingPathComponent("folder"), kind: .directory,
            logicalBytes: 50, allocatedBytes: 40, fileCount: 1, children: [child])
        let kept = FileNode(url: base.appendingPathComponent("kept"), kind: .file,
            logicalBytes: 10, allocatedBytes: 8, fileCount: 1)
        let root = FileNode(url: base, kind: .directory, logicalBytes: 60,
            allocatedBytes: 48, fileCount: 2, children: [folder, kept])

        let updated = try #require(FileTreeUpdater.removing([folder.url], from: root))
        #expect(updated.children.map(\.name) == ["kept"])
        #expect(updated.fileCount == 1)
        #expect(updated.allocatedBytes == 8)
    }

    @Test func remainingHardLinkIsPromotedWhenCountedLinkIsRemoved() throws {
        let base = URL(fileURLWithPath: "/tmp/scan", isDirectory: true)
        let identity = FileIdentity(volume: 1, inode: 42)
        let counted = FileNode(url: base.appendingPathComponent("counted"), kind: .file,
            identity: identity, logicalBytes: 100, allocatedBytes: 80, fileCount: 1)
        let duplicate = FileNode(url: base.appendingPathComponent("duplicate"), kind: .file,
            identity: identity, isDuplicateHardLink: true)
        let root = FileNode(url: base, kind: .directory, logicalBytes: 100,
            allocatedBytes: 80, fileCount: 1, children: [counted, duplicate])

        let updated = try #require(FileTreeUpdater.removing([counted.url], from: root))
        let remaining = try #require(updated.children.first)
        #expect(!remaining.isDuplicateHardLink)
        #expect(remaining.logicalBytes == 100)
        #expect(remaining.allocatedBytes == 80)
        #expect(updated.fileCount == 1)
    }
}
