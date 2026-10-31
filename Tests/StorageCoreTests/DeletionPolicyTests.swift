import Foundation
import Testing
@testable import StorageCore

@Suite("Deletion safety policy")
struct DeletionPolicyTests {
    @Test func protectedSystemRootsAndCategoryRoots() {
        let home = URL(fileURLWithPath: "/Users/test")
        #expect(DeletionPolicy.isProtected(URL(fileURLWithPath: "/"), home: home, bundleURL: nil))
        #expect(DeletionPolicy.isProtected(URL(fileURLWithPath: "/System"), home: home, bundleURL: nil))
        #expect(DeletionPolicy.isProtected(home, home: home, bundleURL: nil))
        #expect(DeletionPolicy.isProtected(home.appendingPathComponent("Library/Containers"), home: home, bundleURL: nil))
        let bundle = URL(fileURLWithPath: "/tmp/Test.app", isDirectory: true)
        #expect(DeletionPolicy.isProtected(bundle.appendingPathComponent("Contents/MacOS/Test"), home: home, bundleURL: bundle))
    }

    @Test func nestedSelectionCollapsesDescendants() {
        let parent = FileNode(url: URL(fileURLWithPath: "/tmp/scope/parent"), kind: .directory, allocatedBytes: 100)
        let child = FileNode(url: URL(fileURLWithPath: "/tmp/scope/parent/child"), kind: .file, allocatedBytes: 60)
        let sibling = FileNode(url: URL(fileURLWithPath: "/tmp/scope/other"), kind: .file, allocatedBytes: 20)
        let normalized = DeletionPolicy.normalizeSelection([child, sibling, parent])
        #expect(Set(normalized.map(\.url.path)) == [parent.url.path, sibling.url.path])
        #expect(normalized.reduce(0) { $0 + $1.allocatedBytes } == 120)
    }

    @Test func validationRejectsScopeRootOutsidePathAndSwappedIdentity() throws {
        let scope = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: scope, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: scope) }
        let home = URL(fileURLWithPath: "/Users/test")
        #expect(!DeletionPolicy.validate(scope, within: scope, home: home, bundleURL: nil).allowed)
        #expect(!DeletionPolicy.validate(URL(fileURLWithPath: "/etc/hosts"), within: scope, home: home, bundleURL: nil).allowed)
        let item = scope.appendingPathComponent("item")
        #expect(FileManager.default.createFile(atPath: item.path, contents: Data()))
        let changed = DeletionPolicy.validate(item, within: scope, expectedIdentity: .init(volume: 999, inode: 999), home: home, bundleURL: nil)
        #expect(!changed.allowed)
        #expect(changed.reason?.contains("changed") == true)
    }
}
