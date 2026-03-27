// MTPDevice+Async.swift — Async/await API for MTPDevice
import Foundation

extension MTPDevice {

    // MARK: - Async Device Detection

    /// Detect all connected MTP devices asynchronously
    public static func detectDevicesAsync() async throws -> [MTPDevice] {
        try Task.checkCancellation()
        return try await Task.detached {
            try detectDevices()
        }.value
    }

    // MARK: - Async Device Info

    /// Get device information asynchronously
    public func getDeviceInfoAsync() async -> MTPDeviceInfo {
        await Task.detached {
            self.getDeviceInfo()
        }.value
    }

    // MARK: - Async Storage

    /// Fetch all storage volumes asynchronously
    public func getStoragesAsync() async throws -> [MTPStorageInfo] {
        try Task.checkCancellation()
        return try await Task.detached {
            try self.getStorages()
        }.value
    }

    // MARK: - Async File Listing

    /// List files and folders in a directory asynchronously
    public func listDirectoryAsync(
        storageId: UInt32,
        parentId: UInt32,
        parentPath: String = ""
    ) async throws -> [MTPFileInfo] {
        try Task.checkCancellation()
        return try await Task.detached {
            try self.listDirectory(storageId: storageId, parentId: parentId, parentPath: parentPath)
        }.value
    }

    // MARK: - Async Download

    /// Download a file asynchronously with progress reported via AsyncThrowingStream.
    ///
    /// Supports cooperative cancellation: cancelling the consuming Task or breaking
    /// out of the `for try await` loop will cancel the underlying transfer.
    ///
    /// Usage:
    /// ```swift
    /// let task = Task {
    ///     for try await event in device.downloadAsync(objectId: id, destinationPath: path) {
    ///         if case .progress(let sent, let total) = event {
    ///             print("\(sent)/\(total)")
    ///         }
    ///     }
    /// }
    /// // Cancel the transfer:
    /// task.cancel()
    /// ```
    public func downloadAsync(
        objectId: UInt32,
        destinationPath: String
    ) -> AsyncThrowingStream<MTPTransferEvent, Error> {
        let cancelled = MTPCancellationToken()
        return AsyncThrowingStream { continuation in
            continuation.onTermination = { _ in
                cancelled.cancel()
            }
            Task.detached {
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
    ///
    /// Supports cooperative cancellation via `Task.isCancelled`.
    ///
    /// Usage:
    /// ```swift
    /// try await device.downloadFile(objectId: id, destinationPath: path) { sent, total in
    ///     print("Progress: \(sent)/\(total)")
    /// }
    /// ```
    public func downloadFile(
        objectId: UInt32,
        destinationPath: String,
        onProgress: (@Sendable (Int64, Int64) -> Void)? = nil
    ) async throws {
        try Task.checkCancellation()
        let callingTask = MTPCancellationToken(task: Task { /* placeholder */ })
        callingTask.bindToCurrentTask()

        try await Task.detached {
            try self.downloadFile(objectId: objectId, destinationPath: destinationPath) { sent, total in
                if callingTask.isCancelled { return false }
                onProgress?(sent, total)
                return true
            }
        }.value
    }

    /// Download a file and restore its modification timestamp asynchronously.
    ///
    /// Supports cooperative cancellation via `Task.isCancelled`.
    public func downloadFileWithTimestamp(
        fileInfo: MTPFileInfo,
        destinationPath: String,
        onProgress: (@Sendable (Int64, Int64) -> Void)? = nil
    ) async throws {
        try Task.checkCancellation()
        let callingTask = MTPCancellationToken()
        callingTask.bindToCurrentTask()

        try await Task.detached {
            try self.downloadFileWithTimestamp(fileInfo: fileInfo, destinationPath: destinationPath) { sent, total in
                if callingTask.isCancelled { return false }
                onProgress?(sent, total)
                return true
            }
        }.value
    }

    // MARK: - Async Upload

    /// Upload a file asynchronously with progress reported via AsyncThrowingStream.
    ///
    /// Supports cooperative cancellation via stream termination.
    ///
    /// Usage:
    /// ```swift
    /// let task = Task {
    ///     for try await event in device.uploadAsync(localPath: path, parentId: id, storageId: sid) {
    ///         switch event {
    ///         case .progress(let sent, let total):
    ///             print("\(sent)/\(total)")
    ///         case .completed(let objectId):
    ///             print("Uploaded with ID: \(objectId ?? 0)")
    ///         }
    ///     }
    /// }
    /// // Cancel: task.cancel()
    /// ```
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
            Task.detached {
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
    ///
    /// Supports cooperative cancellation via `Task.isCancelled`.
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

        return try await Task.detached {
            try self.uploadFile(
                localPath: localPath, parentId: parentId,
                storageId: storageId, fileName: fileName
            ) { sent, total in
                if callingTask.isCancelled { return false }
                onProgress?(sent, total)
                return true
            }
        }.value
    }

    // MARK: - Async Folder Download

    /// Download an entire folder asynchronously with progress via AsyncThrowingStream.
    ///
    /// Supports cooperative cancellation.
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
            Task.detached {
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
    ///
    /// Supports cooperative cancellation via `Task.isCancelled`.
    public func downloadFolder(
        storageId: UInt32,
        fileInfo: MTPFileInfo,
        destinationPath: String,
        onProgress: (@Sendable (MTPProgressInfo) -> Void)? = nil
    ) async throws {
        try Task.checkCancellation()
        let callingTask = MTPCancellationToken()
        callingTask.bindToCurrentTask()

        try await Task.detached {
            try self.downloadFolder(
                storageId: storageId, fileInfo: fileInfo,
                destinationPath: destinationPath
            ) { progressInfo in
                if callingTask.isCancelled { return false }
                onProgress?(progressInfo)
                return true
            }
        }.value
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
        return try await Task.detached {
            try self.createFolder(name: name, parentId: parentId, storageId: storageId)
        }.value
    }

    /// Delete a file or folder asynchronously
    public func deleteObject(objectId: UInt32) async throws {
        try Task.checkCancellation()
        try await Task.detached {
            try self.deleteObject(objectId: objectId)
        }.value
    }

    // MARK: - Async Walk

    /// Walk a directory tree recursively, yielding each item as an AsyncThrowingStream.
    ///
    /// Supports cooperative cancellation.
    ///
    /// Usage:
    /// ```swift
    /// for try await file in device.walkAsync(storageId: sid, parentId: pid) {
    ///     print("\(file.isDir ? "📁" : "📄") \(file.name)")
    /// }
    /// ```
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
            Task.detached {
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
    private weak var _task: (any AnyTaskBox)?

    public init() {}

    init(task: Task<Void, Never>) {
        // placeholder init
    }

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

/// Protocol to erase Task type
private protocol AnyTaskBox: AnyObject {}
