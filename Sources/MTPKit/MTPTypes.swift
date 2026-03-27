// MTPTypes.swift
import Foundation
import CLibMTP

/// Represents a file or folder on the MTP device
public struct MTPFileInfo: Identifiable, Hashable, Sendable {
    public let id: UInt32  // objectId
    public let objectId: UInt32
    public let parentId: UInt32
    public let storageId: UInt32
    public let name: String
    public let fullPath: String
    public let parentPath: String
    public let fileExtension: String
    public let size: Int64
    public let isDir: Bool
    public let modTime: Date

    public init(
        objectId: UInt32, parentId: UInt32, storageId: UInt32,
        name: String, fullPath: String, parentPath: String,
        fileExtension: String, size: Int64, isDir: Bool, modTime: Date
    ) {
        self.id = objectId
        self.objectId = objectId
        self.parentId = parentId
        self.storageId = storageId
        self.name = name
        self.fullPath = fullPath
        self.parentPath = parentPath
        self.fileExtension = fileExtension
        self.size = size
        self.isDir = isDir
        self.modTime = modTime
    }

    public var formattedSize: String {
        if isDir { return "--" }
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter.string(fromByteCount: size)
    }

    public var formattedDate: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        return formatter.string(from: modTime)
    }
}

// MARK: - StorageInfo

/// Represents a storage volume on the MTP device
public struct MTPStorageInfo: Identifiable, Hashable, Sendable {
    public let id: UInt32
    public let description: String
    public let volumeIdentifier: String
    public let maxCapacity: UInt64
    public let freeSpace: UInt64

    public var formattedCapacity: String {
        ByteCountFormatter.string(fromByteCount: Int64(maxCapacity), countStyle: .file)
    }

    public var formattedFreeSpace: String {
        ByteCountFormatter.string(fromByteCount: Int64(freeSpace), countStyle: .file)
    }

    public var usedPercentage: Double {
        guard maxCapacity > 0 else { return 0 }
        return Double(maxCapacity - freeSpace) / Double(maxCapacity) * 100
    }
}

// MARK: - DeviceInfo

/// Basic device information
public struct MTPDeviceInfo: Identifiable, Sendable {
    public let id: String  // serial number
    public let manufacturer: String
    public let model: String
    public let serialNumber: String
    public let deviceVersion: String
    public let friendlyName: String
}

// MARK: - Progress

/// Transfer progress for bulk folder operations
public struct MTPProgressInfo: Sendable {
    public var fileInfo: MTPFileInfo?
    public var activeFileSize: MTPSizeProgress = .init()
    public var bulkFileSize: MTPSizeProgress = .init()
    public var filesSent: Int64 = 0
    public var totalFiles: Int64 = 0
    public var filesSentProgress: Float = 0
    public var latestSentTime: Date = Date()
}

public struct MTPSizeProgress: Sendable {
    public var total: Int64 = 0
    public var sent: Int64 = 0
    public var progress: Float = 0
}

/// Progress callback: return false to cancel
public typealias MTPProgressCallback = (MTPProgressInfo) -> Bool

// MARK: - Async Transfer Events

/// Events emitted during async file transfers
public enum MTPTransferEvent: Sendable {
    /// Progress update with bytes sent and total
    case progress(sent: Int64, total: Int64)
    /// Transfer completed successfully (objectId is set for uploads)
    case completed(objectId: UInt32?)
}

/// Events emitted during async bulk (folder) transfers
public enum MTPBulkTransferEvent: Sendable {
    /// Progress update for the overall bulk operation
    case progress(MTPProgressInfo)
    /// Bulk transfer completed
    case completed
}
