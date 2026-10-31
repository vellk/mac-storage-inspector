import Foundation
import Darwin
import StorageCore

@main
struct StorageCoreCheck {
    static func main() async {
        var failures: [String] = []
        func check(_ condition: @autoclosure () -> Bool, _ message: String) {
            if !condition() { failures.append(message) }
        }
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("MacStorageInspectorCheck-\(UUID().uuidString)", isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
            defer { try? FileManager.default.removeItem(at: root) }
            let small = root.appendingPathComponent("small", isDirectory: true)
            let large = root.appendingPathComponent("large", isDirectory: true)
            try FileManager.default.createDirectory(at: small, withIntermediateDirectories: true)
            try FileManager.default.createDirectory(at: large, withIntermediateDirectories: true)
            try Data(repeating: 1, count: 8_192).write(to: small.appendingPathComponent("a"))
            let original = large.appendingPathComponent("original")
            try Data(repeating: 2, count: 65_536).write(to: original)
            check(link(original.path, large.appendingPathComponent("hard link").path) == 0, "hard-link fixture creation")
            check(symlink(root.path, large.appendingPathComponent("loop").path) == 0, "symlink fixture creation")
            let sparse = root.appendingPathComponent("sparse.img")
            check(FileManager.default.createFile(atPath: sparse.path, contents: nil), "sparse fixture creation")
            let handle = try FileHandle(forWritingTo: sparse)
            try handle.truncate(atOffset: 128 * 1_024 * 1_024); try handle.close()

            let snapshot = await FileSystemScanner().scan(root: root)
            guard let node = snapshot.rootNode else { throw CheckError.missingRoot }
            check(node.fileCount == 4, "file count includes unique regular files plus symlink")
            check(node.flattened().filter(\.isDuplicateHardLink).count == 1, "hard link counted once")
            check(node.flattened().filter { $0.kind == .symbolicLink }.count == 1, "symlink not traversed")
            if let sparseNode = node.flattened().first(where: { $0.name == "sparse.img" }) {
                check(sparseNode.logicalBytes > sparseNode.allocatedBytes, "sparse logical and allocated sizes differ")
            } else { failures.append("sparse file appears in tree") }

            let parent = FileNode(url: root.appendingPathComponent("parent"), kind: .directory, allocatedBytes: 100)
            let child = FileNode(url: root.appendingPathComponent("parent/child"), kind: .file, allocatedBytes: 50)
            check(DeletionPolicy.normalizeSelection([child, parent]).count == 1, "nested selection collapse")
            check(!DeletionPolicy.validate(root, within: root, home: URL(fileURLWithPath: "/Users/test"), bundleURL: nil).allowed, "scope root rejection")
            check(DeletionPolicy.isProtected(URL(fileURLWithPath: "/System"), home: URL(fileURLWithPath: "/Users/test"), bundleURL: nil), "system root protection")
        } catch {
            failures.append("unexpected error: \(error)")
        }

        if failures.isEmpty {
            print("StorageCoreCheck: all integration checks passed")
        } else {
            for failure in failures { fputs("FAIL: \(failure)\n", stderr) }
            exit(EXIT_FAILURE)
        }
    }
    enum CheckError: Error { case missingRoot }
}
