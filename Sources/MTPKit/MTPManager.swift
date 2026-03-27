// MTPManager.swift — Async manager for SwiftUI, wraps MTPDevice
import Foundation
import Combine

/// Observable manager that drives the SwiftUI interface
@MainActor
public final class MTPManager: ObservableObject {
    // MARK: - Published State

    @Published public var isConnected = false
    @Published public var isLoading = false
    @Published public var devices: [MTPDevice] = []
    @Published public var selectedDevice: MTPDevice?
    @Published public var deviceInfo: MTPDeviceInfo?
    @Published public var storages: [MTPStorageInfo] = []
    @Published public var selectedStorage: MTPStorageInfo?
    @Published public var currentFiles: [MTPFileInfo] = []
    @Published public var currentPath: String = "/"
    @Published public var currentParentId: UInt32 = MTPParentObjectID
    @Published public var pathHistory: [PathEntry] = []
    @Published public var errorMessage: String?
    @Published public var transferProgress: TransferProgress?
    @Published public var isTransferring = false
    @Published public var isHotPlugEnabled = false

    /// The currently active transfer task (download or upload)
    private var activeTransferTask: Task<Void, Never>?

    /// Cancellation token shared with the active transfer
    private nonisolated(unsafe) var transferCancellation: MTPCancellationToken?

    /// The USB hot-plug monitor instance
    private let usbMonitor = USBDeviceMonitor()

    public struct PathEntry: Equatable {
        public let path: String
        public let browseParentId: UInt32  // the parentId passed to browse() to reconstruct this view
        public let name: String
    }

    public struct TransferProgress {
        public var fileName: String
        public var sent: Int64
        public var total: Int64
        public var isUploading: Bool

        public var percentage: Double {
            guard total > 0 else { return 0 }
            return Double(sent) / Double(total) * 100
        }

        public var formattedSent: String {
            ByteCountFormatter.string(fromByteCount: sent, countStyle: .file)
        }

        public var formattedTotal: String {
            ByteCountFormatter.string(fromByteCount: total, countStyle: .file)
        }
    }

    private nonisolated(unsafe) static var initialized = false

    /// Throttle: last time the progress UI was updated (avoid flooding main queue)
    private nonisolated(unsafe) static var lastProgressUpdate: CFAbsoluteTime = 0

    public init() {}

    // MARK: - USB Hot-Plug Monitoring

    /// Start monitoring USB device connect/disconnect events.
    ///
    /// When a USB device is connected, the manager will automatically attempt
    /// to detect and connect to MTP devices. When a device is disconnected
    /// and we have an active connection, the manager will disconnect.
    public func startHotPlug() {
        guard !isHotPlugEnabled else { return }
        isHotPlugEnabled = true

        usbMonitor.startMonitoring { [weak self] event in
            DispatchQueue.main.async {
                guard let self = self else { return }
                switch event {
                case .deviceConnected:
                    // Only auto-connect if not already connected
                    if !self.isConnected {
                        self.connect()
                    }
                case .deviceDisconnected:
                    // Only auto-disconnect if currently connected
                    if self.isConnected {
                        // Try to re-detect; if no devices found, disconnect
                        Task { [weak self] in
                            do {
                                let devices = try await MTPDevice.detectDevicesAsync()
                                if devices.isEmpty {
                                    self?.disconnect()
                                }
                            } catch {
                                self?.disconnect()
                            }
                        }
                    }
                }
            }
        }
    }

    /// Stop monitoring USB device events.
    public func stopHotPlug() {
        usbMonitor.stopMonitoring()
        isHotPlugEnabled = false
    }

    // MARK: - Transfer Cancellation

    /// Cancel the currently active upload or download transfer.
    ///
    /// The transfer will stop at the next progress callback (~30fps granularity).
    /// Partial downloads are cleaned up automatically.
    public func cancelTransfer() {
        transferCancellation?.cancel()
        activeTransferTask?.cancel()
        activeTransferTask = nil
        transferCancellation = nil
        transferProgress = nil
        isTransferring = false
    }

    // MARK: - Progress Helper

    /// Update transfer progress on the main thread, throttled to ~30fps.
    /// Explicitly reassigns the entire struct to guarantee @Published fires.
    private nonisolated static func updateProgress(
        on manager: MTPManager?,
        fileName: String,
        sent: Int64,
        total: Int64,
        isUploading: Bool,
        force: Bool = false
    ) {
        let now = CFAbsoluteTimeGetCurrent()
        // Throttle to ~30fps (every 33ms) unless forced
        guard force || (now - lastProgressUpdate) > 0.033 else { return }
        lastProgressUpdate = now

        DispatchQueue.main.async {
            manager?.transferProgress = TransferProgress(
                fileName: fileName, sent: sent, total: total, isUploading: isUploading
            )
        }
    }

    // MARK: - Connect / Disconnect

    public func connect() {
        errorMessage = nil
        isLoading = true

        Task { [weak self] in
            if !MTPManager.initialized {
                MTPDevice.initialize()
                MTPManager.initialized = true
            }

            do {
                let detectedDevices = try await MTPDevice.detectDevicesAsync()

                self?.devices = detectedDevices
                self?.selectedDevice = detectedDevices.first
                self?.isConnected = true
                self?.isLoading = false

                if let device = detectedDevices.first {
                    let info = await device.getDeviceInfoAsync()
                    self?.deviceInfo = info
                    await self?.fetchStorages()
                }
            } catch {
                self?.errorMessage = error.localizedDescription
                self?.isConnected = false
                self?.isLoading = false
            }
        }
    }

    public func disconnect() {
        // Cancel any active transfer before disconnecting
        cancelTransfer()
        devices = []
        selectedDevice = nil
        deviceInfo = nil
        storages = []
        selectedStorage = nil
        currentFiles = []
        currentPath = "/"
        currentParentId = MTPParentObjectID
        pathHistory = []
        isConnected = false
        errorMessage = nil
    }

    // MARK: - Fetch Storages

    public func fetchStorages() async {
        guard let device = selectedDevice else { return }

        do {
            let storageList = try await device.getStoragesAsync()
            self.storages = storageList
            if self.selectedStorage == nil {
                self.selectedStorage = storageList.first
            }
            // Auto-browse root
            if let storage = storageList.first {
                await browse(storageId: storage.id, parentId: MTPParentObjectID, path: "/", name: "/")
            }
        } catch {
            self.errorMessage = error.localizedDescription
        }
    }

    // MARK: - Browse

    public func browse(storageId: UInt32, parentId: UInt32, path: String, name: String) async {
        guard let device = selectedDevice else { return }

        self.isLoading = true

        do {
            let files = try await device.listDirectoryAsync(
                storageId: storageId,
                parentId: parentId,
                parentPath: path
            )
            self.currentFiles = files
            self.currentPath = path
            self.currentParentId = parentId
            self.isLoading = false
        } catch {
            self.errorMessage = error.localizedDescription
            self.isLoading = false
        }
    }

    public func navigateInto(file: MTPFileInfo) {
        guard file.isDir, let storage = selectedStorage else { return }

        // Push current view's browse parentId to history so we can reconstruct it on back
        // Note: we store currentParentId (the parentId we used to list the current directory),
        // NOT file.parentId (which may differ for root-level items where MTP parent_id=0
        // but LIBMTP_Get_Files_And_Folders expects 0xFFFFFFFF for root).
        pathHistory.append(PathEntry(
            path: currentPath,
            browseParentId: currentParentId,
            name: (currentPath as NSString).lastPathComponent
        ))

        let newPath = file.fullPath
        Task {
            await browse(storageId: storage.id, parentId: file.objectId, path: newPath, name: file.name)
        }
    }

    public func navigateUp() {
        guard !pathHistory.isEmpty, let storage = selectedStorage else { return }
        let previous = pathHistory.removeLast()

        Task {
            await browse(storageId: storage.id, parentId: previous.browseParentId,
                        path: previous.path, name: previous.name)
        }
    }

    public func navigateToRoot() {
        guard let storage = selectedStorage else { return }
        pathHistory = []
        currentParentId = MTPParentObjectID
        Task {
            await browse(storageId: storage.id, parentId: MTPParentObjectID, path: "/", name: "/")
        }
    }

    // MARK: - Download

    public func downloadFile(file: MTPFileInfo, to destinationURL: URL) {
        guard let device = selectedDevice else { return }

        // Cancel any existing transfer
        cancelTransfer()

        let destPath = destinationURL.appendingPathComponent(file.name).path
        let cancellation = MTPCancellationToken()
        self.transferCancellation = cancellation

        transferProgress = TransferProgress(
            fileName: file.name, sent: 0, total: file.size, isUploading: false
        )
        isTransferring = true

        let fileName = file.name
        activeTransferTask = Task { [weak self] in
            do {
                if file.isDir {
                    try FileManager.default.createDirectory(
                        atPath: destPath, withIntermediateDirectories: true
                    )
                    try await device.downloadFolder(
                        storageId: file.storageId,
                        fileInfo: file,
                        destinationPath: destPath
                    ) { progress in
                        if cancellation.isCancelled { return }
                        MTPManager.updateProgress(
                            on: self, fileName: fileName,
                            sent: progress.bulkFileSize.sent,
                            total: progress.bulkFileSize.total,
                            isUploading: false
                        )
                    }
                } else {
                    try await device.downloadFileWithTimestamp(
                        fileInfo: file,
                        destinationPath: destPath
                    ) { sent, total in
                        if cancellation.isCancelled { return }
                        MTPManager.updateProgress(
                            on: self, fileName: fileName,
                            sent: sent, total: total,
                            isUploading: false
                        )
                    }
                }

                self?.transferProgress = nil
                self?.isTransferring = false
            } catch let error as MTPError where error == .cancelled {
                self?.transferProgress = nil
                self?.isTransferring = false
                // Cancelled — no error message
            } catch {
                self?.errorMessage = "Download failed: \(error.localizedDescription)"
                self?.transferProgress = nil
                self?.isTransferring = false
            }
        }
    }

    // MARK: - Upload

    public func uploadFiles(urls: [URL], parentId: UInt32) {
        guard let device = selectedDevice, let storage = selectedStorage else { return }

        // Cancel any existing transfer
        cancelTransfer()

        let cancellation = MTPCancellationToken()
        self.transferCancellation = cancellation
        isTransferring = true

        activeTransferTask = Task { [weak self] in
            await Task.detached { [weak self] in
                // Pre-calculate total size for all files
                let fm = FileManager.default
                var totalSize: Int64 = 0
                var totalSent: Int64 = 0

                for url in urls {
                    var isDir: ObjCBool = false
                    fm.fileExists(atPath: url.path, isDirectory: &isDir)
                    if isDir.boolValue {
                        totalSize += Self.calculateDirectorySize(at: url.path)
                    } else {
                        totalSize += (try? fm.attributesOfItem(atPath: url.path)[.size] as? Int64) ?? 0
                    }
                }

                for url in urls {
                    // Check cancellation between files
                    if cancellation.isCancelled { break }

                    let fileName = url.lastPathComponent

                    MTPManager.updateProgress(
                        on: self, fileName: fileName,
                        sent: totalSent, total: totalSize,
                        isUploading: true, force: true
                    )

                    do {
                        var isDir: ObjCBool = false
                        fm.fileExists(atPath: url.path, isDirectory: &isDir)

                        if isDir.boolValue {
                            try Self.uploadFolderWithProgress(
                                device: device,
                                localPath: url.path,
                                parentId: parentId,
                                storageId: storage.id,
                                manager: self,
                                totalSize: totalSize,
                                totalSent: &totalSent,
                                cancellation: cancellation
                            )
                        } else {
                            let fileSize = (try? fm.attributesOfItem(atPath: url.path)[.size] as? Int64) ?? 0
                            let baseSent = totalSent
                            let _ = try device.uploadFile(
                                localPath: url.path,
                                parentId: parentId,
                                storageId: storage.id
                            ) { sent, _ in
                                if cancellation.isCancelled { return false }
                                MTPManager.updateProgress(
                                    on: self, fileName: fileName,
                                    sent: baseSent + sent, total: totalSize,
                                    isUploading: true
                                )
                                return true
                            }
                            totalSent += fileSize
                        }
                    } catch let error as MTPError where error == .cancelled {
                        break  // Cancelled — exit loop cleanly
                    } catch {
                        await MainActor.run {
                            self?.errorMessage = "Upload failed for \(fileName): \(error.localizedDescription)"
                        }
                    }
                }

                if !cancellation.isCancelled {
                    // Force final update before clearing
                    MTPManager.updateProgress(
                        on: self, fileName: "",
                        sent: totalSize, total: totalSize,
                        isUploading: true, force: true
                    )
                }

                await MainActor.run {
                    self?.transferProgress = nil
                    self?.isTransferring = false
                }

                // Refresh current directory after upload
                if let storage = await self?.selectedStorage {
                    let parentId = parentId
                    let path = await self?.currentPath ?? "/"
                    await self?.browse(storageId: storage.id, parentId: parentId, path: path, name: "")
                }
            }.value
        }
    }

    /// Recursively upload a folder with per-file progress tracking and cancellation support
    private nonisolated static func uploadFolderWithProgress(
        device: MTPDevice,
        localPath: String,
        parentId: UInt32,
        storageId: UInt32,
        manager: MTPManager?,
        totalSize: Int64,
        totalSent: inout Int64,
        cancellation: MTPCancellationToken? = nil
    ) throws {
        if cancellation?.isCancelled == true { throw MTPError.cancelled }

        let fm = FileManager.default
        let folderName = (localPath as NSString).lastPathComponent
        let folderId = try device.createFolder(name: folderName, parentId: parentId, storageId: storageId)

        let contents = try fm.contentsOfDirectory(atPath: localPath)
        for item in contents {
            if cancellation?.isCancelled == true { throw MTPError.cancelled }
            if mtpIsDisallowedFile(item) { continue }
            let itemPath = localPath + "/" + item

            var isDir: ObjCBool = false
            fm.fileExists(atPath: itemPath, isDirectory: &isDir)

            if isDir.boolValue {
                try uploadFolderWithProgress(
                    device: device, localPath: itemPath,
                    parentId: folderId, storageId: storageId,
                    manager: manager, totalSize: totalSize,
                    totalSent: &totalSent,
                    cancellation: cancellation
                )
            } else {
                let fileSize = (try? fm.attributesOfItem(atPath: itemPath)[.size] as? Int64) ?? 0
                let baseSent = totalSent

                MTPManager.updateProgress(
                    on: manager, fileName: item,
                    sent: baseSent, total: totalSize,
                    isUploading: true, force: true
                )

                let _ = try device.uploadFile(
                    localPath: itemPath,
                    parentId: folderId,
                    storageId: storageId
                ) { sent, _ in
                    if cancellation?.isCancelled == true { return false }
                    MTPManager.updateProgress(
                        on: manager, fileName: item,
                        sent: baseSent + sent, total: totalSize,
                        isUploading: true
                    )
                    return true
                }
                totalSent += fileSize
            }
        }
    }

    /// Calculate total size of a directory recursively
    private nonisolated static func calculateDirectorySize(at path: String) -> Int64 {
        let fm = FileManager.default
        guard let enumerator = fm.enumerator(atPath: path) else { return 0 }
        var total: Int64 = 0
        while let file = enumerator.nextObject() as? String {
            let fullPath = path + "/" + file
            if let attrs = try? fm.attributesOfItem(atPath: fullPath),
               let size = attrs[.size] as? Int64 {
                total += size
            }
        }
        return total
    }

    // MARK: - Delete

    public func deleteFile(_ file: MTPFileInfo) {
        guard let device = selectedDevice, let storage = selectedStorage else { return }

        Task { [weak self] in
            do {
                try await device.deleteObject(objectId: file.objectId)

                // Refresh
                let path = self?.currentPath ?? "/"
                let parentId = file.parentId
                await self?.browse(storageId: storage.id, parentId: parentId, path: path, name: "")
            } catch {
                self?.errorMessage = "Delete failed: \(error.localizedDescription)"
            }
        }
    }

    // MARK: - Create Folder

    public func createFolder(name: String, parentId: UInt32) {
        guard let device = selectedDevice, let storage = selectedStorage else { return }

        Task { [weak self] in
            do {
                try await device.createFolder(name: name, parentId: parentId, storageId: storage.id)

                // Refresh
                let path = self?.currentPath ?? "/"
                await self?.browse(storageId: storage.id, parentId: parentId, path: path, name: "")
            } catch {
                self?.errorMessage = "Create folder failed: \(error.localizedDescription)"
            }
        }
    }
}
