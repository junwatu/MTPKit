// MTPDevice+Async.swift — Async/await API for MTPDevice
import Foundation

extension MTPDevice {

    // MARK: - Async Device Detection

    /// Detect all connected MTP devices asynchronously.
    /// Includes a timeout to prevent hanging when USB state is transitional.
    public static func detectDevicesAsync(timeout: TimeInterval = 10) async throws -> [MTPDevice] {
        try Task.checkCancellation()
        return try await withThrowingTaskGroup(of: [MTPDevice].self) { group in
            group.addTask {
                try detectDevices()
            }
            group.addTask {
                try await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
                throw MTPError.detectFailed("Device detection timed out after \(Int(timeout))s")
            }
            // Return whichever finishes first
            let result = try await group.next()!
            group.cancelAll()
            return result
        }
    }

    // MARK: - Async Device Info

    /// Get device information asynchronously (serialized on operation queue)
    public func getDeviceInfoAsync() async throws -> MTPDeviceInfo {
        try await serialized { try self.getDeviceInfo() }
    }

    // MARK: - Async Storage

    /// Fetch all storage volumes asynchronously (serialized on operation queue)
    public func getStoragesAsync() async throws -> [MTPStorageInfo] {
        try Task.checkCancellation()
        return try await serialized { try self.getStorages() }
    }

    // MARK: - Async File Listing

    /// List files and folders in a directory asynchronously (serialized on operation queue)
    public func listDirectoryAsync(
        storageId: UInt32,
        parentId: UInt32,
        parentPath: String = ""
    ) async throws -> [MTPFileInfo] {
        try Task.checkCancellation()
        return try await serialized {
            try self.listDirectory(storageId: storageId, parentId: parentId, parentPath: parentPath)
        }
    }

    // MARK: - Async Download

    /// Download a file asynchronously with progress reported via AsyncThrowingStream.
    ///
    /// Supports cooperative cancellation: cancelling the consuming Task or breaking
    /// out of the `for try await` loop will cancel the underlying transfer.
    public func downloadAsync(
        objectId: UInt32,
        destinationPath: String
    ) -> AsyncThrowingStream<MTPTransferEvent, Error> {
        let cancelled = MTPCancellationToken()
        return AsyncThrowingStream { continuation in
            continuation.onTermination = { _ in
                cancelled.cancel()
            }
            // Use the device's serial operation queue
            self.operationQueue.async {
                do {
                    try self.downloadFile(objectId: objectId, destinationPath: destinationPath) { sent, total in
                        if cancelled.isCancelled { return false }
                        continuation.yield(.progress(sent: sent, total: total))
                        return true
                    }
                    continuation.yield(.completed(objectId: nil))
                    continuation.finish()
                } catch {
                    if cancelled.isCancelled || error is MTPError && error as! MTPError == .cancelled {
                        continuation.finish(throwing: MTPError.cancelled)
                    } else {
                        continuation.finish(throwing: error)
                    }
                }
            }
        }
    }

    /// Download a file asynchronously using a simple progress closure.
    public func downloadFile(
        objectId: UInt32,
        destinationPath: String,
        onProgress: (@Sendable (Int64, Int64) -> Void)? = nil
    ) async throws {
        try Task.checkCancellation()
        let callingTask = MTPCancellationToken()
        callingTask.bindToCurrentTask()

        try await serialized {
            try self.downloadFile(objectId: objectId, destinationPath: destinationPath) { sent, total in
                if callingTask.isCancelled { return false }
                onProgress?(sent, total)
                return true
            }
        }
    }

    /// Download a file and restore its modification timestamp asynchronously.
    public func downloadFileWithTimestamp(
        fileInfo: MTPFileInfo,
        destinationPath: String,
        onProgress: (@Sendable (Int64, Int64) -> Void)? = nil
    ) async throws {
        try Task.checkCancellation()
        let callingTask = MTPCancellationToken()
        callingTask.bindToCurrentTask()

        try await serialized {
            try self.downloadFileWithTimestamp(fileInfo: fileInfo, destinationPath: destinationPath) { sent, total in
                if callingTask.isCancelled { return false }
                onProgress?(sent, total)
                return true
            }
        }
    }

    // MARK: - Async Upload

    /// Upload a file asynchronously with progress reported via AsyncThrowingStream.
    public func uploadAsync(
        localPath: String,
        parentId: UInt32,
        storageId: UInt32,
        fileName: String? = nil
    ) -> AsyncThrowingStream<MTPTransferEvent, Error> {
        let cancelled = MTPCancellationToken()
        return AsyncThrowingStream { continuation in
            continuation.onTermination = { _ in
                cancelled.cancel()
            }
            self.operationQueue.async {
                do {
                    let objectId = try self.uploadFile(
                        localPath: localPath, parentId: parentId,
                        storageId: storageId, fileName: fileName
                    ) { sent, total in
                        if cancelled.isCancelled { return false }
                        continuation.yield(.progress(sent: sent, total: total))
                        return true
                    }
                    continuation.yield(.completed(objectId: objectId))
                    continuation.finish()
                } catch {
                    if cancelled.isCancelled || error is MTPError && error as! MTPError == .cancelled {
                        continuation.finish(throwing: MTPError.cancelled)
                    } else {
                        continuation.finish(throwing: error)
                    }
                }
            }
        }
    }

    /// Upload a file asynchronously using a simple progress closure, returns new object ID.
    @discardableResult
    public func uploadFile(
        localPath: String,
        parentId: UInt32,
        storageId: UInt32,
        fileName: String? = nil,
        onProgress: (@Sendable (Int64, Int64) -> Void)? = nil
    ) async throws -> UInt32 {
        try Task.checkCancellation()
        let callingTask = MTPCancellationToken()
        callingTask.bindToCurrentTask()

        return try await serialized {
            try self.uploadFile(
                localPath: localPath, parentId: parentId,
                storageId: storageId, fileName: fileName
            ) { sent, total in
                if callingTask.isCancelled { return false }
                onProgress?(sent, total)
                return true
            }
        }
    }

    // MARK: - Async Folder Download

    /// Download an entire folder asynchronously with progress via AsyncThrowingStream.
    public func downloadFolderAsync(
        storageId: UInt32,
        fileInfo: MTPFileInfo,
        destinationPath: String
    ) -> AsyncThrowingStream<MTPBulkTransferEvent, Error> {
        let cancelled = MTPCancellationToken()
        return AsyncThrowingStream { continuation in
            continuation.onTermination = { _ in
                cancelled.cancel()
            }
            self.operationQueue.async {
                do {
                    try self.downloadFolder(
                        storageId: storageId, fileInfo: fileInfo,
                        destinationPath: destinationPath
                    ) { progressInfo in
                        if cancelled.isCancelled { return false }
                        continuation.yield(.progress(progressInfo))
                        return true
                    }
                    continuation.yield(.completed)
                    continuation.finish()
                } catch {
                    if cancelled.isCancelled || error is MTPError && error as! MTPError == .cancelled {
                        continuation.finish(throwing: MTPError.cancelled)
                    } else {
                        continuation.finish(throwing: error)
                    }
                }
            }
        }
    }

    /// Download an entire folder asynchronously with a simple progress closure.
    public func downloadFolder(
        storageId: UInt32,
        fileInfo: MTPFileInfo,
        destinationPath: String,
        onProgress: (@Sendable (MTPProgressInfo) -> Void)? = nil
    ) async throws {
        try Task.checkCancellation()
        let callingTask = MTPCancellationToken()
        callingTask.bindToCurrentTask()

        try await serialized {
            try self.downloadFolder(
                storageId: storageId, fileInfo: fileInfo,
                destinationPath: destinationPath
            ) { progressInfo in
                if callingTask.isCancelled { return false }
                onProgress?(progressInfo)
                return true
            }
        }
    }

    // MARK: - Async Folder Operations

    /// Create a new folder asynchronously, returns folder object ID
    @discardableResult
    public func createFolder(
        name: String,
        parentId: UInt32,
        storageId: UInt32
    ) async throws -> UInt32 {
        try Task.checkCancellation()
        return try await serialized {
            try self.createFolder(name: name, parentId: parentId, storageId: storageId)
        }
    }

    /// Delete a file or folder asynchronously
    public func deleteObject(objectId: UInt32) async throws {
        try Task.checkCancellation()
        try await serialized {
            try self.deleteObject(objectId: objectId)
        }
    }

    // MARK: - Async Rename & Move

    /// Rename a file or folder on the device asynchronously
    public func renameObject(objectId: UInt32, newName: String) async throws {
        try Task.checkCancellation()
        try await serialized {
            try self.renameObject(objectId: objectId, newName: newName)
        }
    }

    /// Move a file or folder to a different parent folder asynchronously
    public func moveObject(objectId: UInt32, storageId: UInt32, newParentId: UInt32) async throws {
        try Task.checkCancellation()
        try await serialized {
            try self.moveObject(objectId: objectId, storageId: storageId, newParentId: newParentId)
        }
    }

    // MARK: - Async Thumbnail

    /// Fetch the device-generated thumbnail for an object asynchronously (serialized).
    public func getThumbnailAsync(objectId: UInt32) async -> Data? {
        await serializedOptional { self.getThumbnail(objectId: objectId) }
    }

    // MARK: - Async Walk

    /// Walk a directory tree recursively, yielding each item as an AsyncThrowingStream.
    public func walkAsync(
        storageId: UInt32,
        parentId: UInt32,
        parentPath: String = "/"
    ) -> AsyncThrowingStream<MTPFileInfo, Error> {
        let cancelled = MTPCancellationToken()
        return AsyncThrowingStream { continuation in
            continuation.onTermination = { _ in
                cancelled.cancel()
            }
            self.operationQueue.async {
                do {
                    try self.walk(storageId: storageId, parentId: parentId, parentPath: parentPath) { fileInfo in
                        if cancelled.isCancelled {
                            throw MTPError.cancelled
                        }
                        continuation.yield(fileInfo)
                    }
                    continuation.finish()
                } catch {
                    if cancelled.isCancelled || error is MTPError && error as! MTPError == .cancelled {
                        continuation.finish(throwing: MTPError.cancelled)
                    } else {
                        continuation.finish(throwing: error)
                    }
                }
            }
        }
    }
}

// MARK: - Cancellation Token

/// Thread-safe cancellation token for bridging Swift Task cancellation to sync callbacks
public final class MTPCancellationToken: @unchecked Sendable {
    private let lock = NSLock()
    private var _isCancelled = false

    public init() {}

    /// Bind to the current structured task for cooperative cancellation
    func bindToCurrentTask() {
        // We'll check Task.isCancelled directly in isCancelled
    }

    public var isCancelled: Bool {
        lock.lock()
        defer { lock.unlock() }
        return _isCancelled || Task.isCancelled
    }

    public func cancel() {
        lock.lock()
        _isCancelled = true
        lock.unlock()
    }
}
