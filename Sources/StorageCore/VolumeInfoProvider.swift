import Foundation

public protocol VolumeInfoProviding: Sendable {
    func capacity(for url: URL) throws -> VolumeCapacity
}

public struct VolumeInfoProvider: VolumeInfoProviding {
    public init() {}
    public func capacity(for url: URL) throws -> VolumeCapacity {
        let values = try url.resourceValues(forKeys: [.volumeTotalCapacityKey, .volumeAvailableCapacityForImportantUsageKey, .volumeAvailableCapacityKey])
        let total = values.volumeTotalCapacity.map(Int64.init)
        let available = values.volumeAvailableCapacityForImportantUsage ?? values.volumeAvailableCapacity.map(Int64.init)
        return VolumeCapacity(total: total, available: available)
    }
}
