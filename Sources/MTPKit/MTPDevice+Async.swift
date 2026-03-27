// MTPDevice+Async.swift — Async/await API for MTPDevice
import Foundation

extension MTPDevice {

    // MARK: - Async Device Detection

    /// Detect all connected MTP devices asynchronously
    public static func detectDevicesAsync() async throws -> [MTPDevice] {
        try await Task.detached {
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
        try await Task.detached {
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
        try await Task.detached {
            try self.listDirectory(storageId: storageId, parentId: parentId, parentPath: parentPath)
        }.value
    }

    // MARK: - Async Download

    /// Download a file asynchronously with progress reported via AsyncThrowingStream
    ///
    /// Usage:
    /// ```swift
    /// for try await event in device.downloadAsync(objectId: id, destinationPath: path) {
    ///     if case .progress(let sent, let total) = event {
    ///         print("\(sent)/\(total)")
    ///     }
    /// }
    /// ```
    public func downloadAsync(
        objectId: UInt32,
        destinationPath: String
    ) -> AsyncThrowingStream<MTPTransferEvent, Error> {
        AsyncThrowingStream { continuation in
            Task.detached {
                do {
                    try self.downloadFile(objectId: objectId, destinationPath: destinationPath) { sent, total in
                        continuation.yield(.progress(sent: sent, total: total))
                        return true
                    }
                    continuation.yield(.completed(objectId: nil))
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }

    /// Download a file asynchronously using a simple progress closure
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
        try await Task.detached {
            try self.downloadFile(objectId: objectId, destinationPath: destinationPath) { sent, total in
                onProgress?(sent, total)
                return true
            }
        }.value
    }

    /// Download a file and restore its modification timestamp asynchronously
    public func downloadFileWithTimestamp(
        fileInfo: MTPFileInfo,
        destinationPath: String,
        onProgress: (@Sendable (Int64, Int64) -> Void)? = nil
    ) async throws {
        try await Task.detached {
            try self.downloadFileWithTimestamp(fileInfo: fileInfo, destinationPath: destinationPath) { sent, total in
                onProgress?(sent, total)
                return true
            }
        }.value
    }

    // MARK: - Async Upload

    /// Upload a file asynchronously with progress reported via AsyncThrowingStream
    ///
    /// Usage:
    /// ```swift
    /// for try await event in device.uploadAsync(localPath: path, parentId: id, storageId: sid) {
    ///     switch event {
    ///     case .progress(let sent, let total):
    ///         print("\(sent)/\(total)")
    ///     case .completed(let objectId):
    ///         print("Uploaded with ID: \(objectId ?? 0)")
    ///     }
    /// }
    /// ```
    public func uploadAsync(
        localPath: String,
        parentId: UInt32,
        storageId: UInt32,
        fileName: String? = nil
    ) -> AsyncThrowingStream<MTPTransferEvent, Error> {
        AsyncThrowingStream { continuation in
            Task.detached {
                do {
                    let objectId = try self.uploadFile(
                        localPath: localPath, parentId: parentId,
                        storageId: storageId, fileName: fileName
                    ) { sent, total in
                        continuation.yield(.progress(sent: sent, total: total))
                        return true
                    }
                    continuation.yield(.completed(objectId: objectId))
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }

    /// Upload a file asynchronously using a simple progress closure, returns new object ID
    ///
    /// Usage:
    /// ```swift
    /// let objectId = try await device.uploadFile(localPath: path, parentId: pid, storageId: sid) { sent, total in
    ///     print("Progress: \(sent)/\(total)")
    /// }
    /// ```
    @discardableResult
    public func uploadFile(
        localPath: String,
        parentId: UInt32,
        storageId: UInt32,
        fileName: String? = nil,
        onProgress: (@Sendable (Int64, Int64) -> Void)? = nil
    ) async throws -> UInt32 {
        try await Task.detached {
            try self.uploadFile(
                localPath: localPath, parentId: parentId,
                storageId: storageId, fileName: fileName
            ) { sent, total in
                onProgress?(sent, total)
                return true
            }
        }.value
    }

    // MARK: - Async Folder Download

    /// Download an entire folder asynchronously with progress via AsyncThrowingStream
    public func downloadFolderAsync(
        storageId: UInt32,
        fileInfo: MTPFileInfo,
        destinationPath: String
    ) -> AsyncThrowingStream<MTPBulkTransferEvent, Error> {
        AsyncThrowingStream { continuation in
            Task.detached {
                do {
                    try self.downloadFolder(
                        storageId: storageId, fileInfo: fileInfo,
                        destinationPath: destinationPath
                    ) { progressInfo in
                        continuation.yield(.progress(progressInfo))
                        return true
                    }
                    continuation.yield(.completed)
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }

    /// Download an entire folder asynchronously with a simple progress closure
    public func downloadFolder(
        storageId: UInt32,
        fileInfo: MTPFileInfo,
        destinationPath: String,
        onProgress: (@Sendable (MTPProgressInfo) -> Void)? = nil
    ) async throws {
        try await Task.detached {
            try self.downloadFolder(
                storageId: storageId, fileInfo: fileInfo,
                destinationPath: destinationPath
            ) { progressInfo in
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
        try await Task.detached {
            try self.createFolder(name: name, parentId: parentId, storageId: storageId)
        }.value
    }

    /// Delete a file or folder asynchronously
    public func deleteObject(objectId: UInt32) async throws {
        try await Task.detached {
            try self.deleteObject(objectId: objectId)
        }.value
    }

    // MARK: - Async Walk

    /// Walk a directory tree recursively, yielding each item as an AsyncThrowingStream
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
        AsyncThrowingStream { continuation in
            Task.detached {
                do {
                    try self.walk(storageId: storageId, parentId: parentId, parentPath: parentPath) { fileInfo in
                        continuation.yield(fileInfo)
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }
}
