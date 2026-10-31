import Foundation

public enum StorageFormatting {
    public static let bytes: ByteCountFormatter = {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        formatter.allowedUnits = [.useKB, .useMB, .useGB, .useTB]
        formatter.isAdaptive = true
        return formatter
    }()
    public static func byteCount(_ value: Int64?) -> String {
        guard let value else { return "Unavailable" }
        return bytes.string(fromByteCount: value)
    }
}
