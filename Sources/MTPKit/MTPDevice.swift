// MTPDevice.swift — Core device wrapper over libmtp
import Foundation
import CLibMTP
import os

/// Wraps an MTP device connection via libmtp
///
/// All operations are serialized through an internal dispatch queue to prevent
/// concurrent libmtp calls, which are not thread-safe per-device.
public final class MTPDevice: @unchecked Sendable {
    /// The raw libmtp device pointer
    private let device: UnsafeMutablePointer<LIBMTP_mtpdevice_t>
    private let lock = NSLock()
    private var released = false

    /// Serial queue for all libmtp operations on this device.
    /// libmtp is not thread-safe — all calls for a given device must be serialized.
    internal let operationQueue = DispatchQueue(label: "MTPKit.MTPDevice.operations")

    /// Private init — use `detectDevices()` to create instances
    private init(device: UnsafeMutablePointer<LIBMTP_mtpdevice_t>) {
        self.device = device
    }

    deinit {
        lock.lock()
        let alreadyReleased = released
        lock.unlock()
        if !alreadyReleased {
            // Synchronous — must complete before dealloc finishes
            operationQueue.sync {
                LIBMTP_Release_Device(device)
            }
        }
    }

    /// Release the underlying device connection early.
    /// After this call, all operations will throw `MTPError.deviceDisconnected`.
    /// The actual USB release happens on the operation queue to avoid blocking the caller
    /// (e.g. the main thread) if the USB handle is stale.
    public func releaseDevice() {
        lock.lock()
        guard !released else {
            lock.unlock()
            MTPLog.device.debug("releaseDevice() called but already released")
            return
        }
        released = true
        lock.unlock()
        MTPLog.device.info("Releasing MTP device (dispatched to operation queue)")
        // Capture device pointer before dispatching — safe because we own it
        let dev = device
        operationQueue.async {
            LIBMTP_Release_Device(dev)
            MTPLog.device.info("MTP device released (USB handle freed)")
        }
    }

    /// Check if device is still usable; throws if released
    private func ensureConnected() throws {
        if released {
            throw MTPError.deviceDisconnected
        }
    }

    // MARK: - Static: Initialize & Detect

    /// Initialize libmtp (call once at app start)
    public static func initialize() {
        MTPLog.device.info("Initializing libmtp")
        LIBMTP_Init()
    }

    /// Detect all connected MTP devices
    public static func detectDevices() throws -> [MTPDevice] {
        MTPLog.device.info("Detecting raw MTP devices...")
        var rawDevices: UnsafeMutablePointer<LIBMTP_raw_device_struct>?
        var numDevices: Int32 = 0

        let err = LIBMTP_Detect_Raw_Devices(&rawDevices, &numDevices)

        guard err == LIBMTP_ERROR_NONE else {
            switch err {
            case LIBMTP_ERROR_NO_DEVICE_ATTACHED:
                MTPLog.device.notice("No MTP devices attached")
                throw MTPError.noDevicesFound
            default:
                MTPLog.device.error("Raw device detection failed with code \(err.rawValue)")
                throw MTPError.detectFailed("Error code: \(err.rawValue)")
            }
        }

        guard let rawDevices = rawDevices, numDevices > 0 else {
            MTPLog.device.notice("No MTP devices found (empty list)")
            throw MTPError.noDevicesFound
        }

        defer { free(rawDevices) }

        MTPLog.device.info("Found \(numDevices) raw device(s), opening...")
        var devices: [MTPDevice] = []
        for i in 0..<Int(numDevices) {
            let raw = rawDevices[i]
            let vendorId = raw.device_entry.vendor_id
            let productId = raw.device_entry.product_id
            let vendor = String(cString: raw.device_entry.vendor)
            let product = String(cString: raw.device_entry.product)
            let busNo = raw.bus_location
            let devNo = raw.devnum
            MTPLog.device.info("Raw device[\(i, privacy: .public)]: \(vendor, privacy: .public) \(product, privacy: .public) (vid=\(vendorId, privacy: .public), pid=\(productId, privacy: .public), bus=\(busNo, privacy: .public), dev=\(devNo, privacy: .public))")

            // Use uncached mode — critical for Samsung devices with many files
            guard let dev = LIBMTP_Open_Raw_Device_Uncached(&rawDevices[i]) else {
                MTPLog.device.error("Failed to open raw device[\(i, privacy: .public)]: \(vendor, privacy: .public) \(product, privacy: .public) — USB interface may be claimed by another process or device not in MTP mode")
                continue
            }
            MTPLog.device.info("Opened MTP device[\(i, privacy: .public)]: \(vendor, privacy: .public) \(product, privacy: .public)")
            devices.append(MTPDevice(device: dev))
        }

        if devices.isEmpty {
            MTPLog.device.error("All \(numDevices) raw device(s) failed to open")

            // Check if ptpcamerad is claiming the USB interface
            let ptpcameraRunning = Self.isProcessRunning("ptpcamerad")
            let hint: String
            if ptpcameraRunning {
                MTPLog.device.error("ptpcamerad is running — likely claiming the USB device")
                hint = "macOS 'ptpcamerad' is blocking the USB connection. Go to System Settings → General → Login Items & Extensions → Extensions → Image Capture → Disable the extension, then unplug and re-plug your device. Alternatively, run: killall ptpcamerad"
            } else {
                hint = "Make sure no other app (e.g. Android File Transfer) is using the device, and that USB mode is set to 'File transfer / MTP'."
            }
            throw MTPError.deviceOpenFailed(hint)
        }

        MTPLog.device.info("Successfully opened \(devices.count) MTP device(s)")
        return devices
    }

    // MARK: - Device Info

    public func getDeviceInfo() throws -> MTPDeviceInfo {
        lock.lock()
        defer { lock.unlock() }
        try ensureConnected()
        MTPLog.device.debug("Getting device info")

        let manufacturer = getString(LIBMTP_Get_Manufacturername(device))
        let model = getString(LIBMTP_Get_Modelname(device))
        let serial = getString(LIBMTP_Get_Serialnumber(device))
        let version = getString(LIBMTP_Get_Deviceversion(device))
        let friendly = getString(LIBMTP_Get_Friendlyname(device))

        return MTPDeviceInfo(
            id: serial.isEmpty ? UUID().uuidString : serial,
            manufacturer: manufacturer,
            model: model,
            serialNumber: serial,
            deviceVersion: version,
            friendlyName: friendly
        )
    }

    // MARK: - Storage

    /// Fetch all storage volumes from the device
    public func getStorages() throws -> [MTPStorageInfo] {
        lock.lock()
        defer { lock.unlock() }
        try ensureConnected()

        let ret = LIBMTP_Get_Storage(device, Int32(LIBMTP_STORAGE_SORTBY_NOTSORTED))
        if ret != 0 {
            MTPLog.device.notice("Storage fetch failed, retrying (Samsung workaround)...")
            // Samsung devices sometimes need a retry
            Thread.sleep(forTimeInterval: 0.5)
            let ret2 = LIBMTP_Get_Storage(device, Int32(LIBMTP_STORAGE_SORTBY_NOTSORTED))
            if ret2 != 0 {
                let errMsg = drainErrorStack(device) ?? "Unknown error"
                MTPLog.device.error("Storage fetch failed after retry: \(errMsg)")
                throw MTPError.storageInfoError(errMsg)
            }
        }

        var results: [MTPStorageInfo] = []
        var storage = clibmtp_device_get_storage(device)

        while let s = storage {
            let desc = getStringNoCopy(s.pointee.StorageDescription)
            let volId = getStringNoCopy(s.pointee.VolumeIdentifier)

            results.append(MTPStorageInfo(
                id: s.pointee.id,
                description: desc.isEmpty ? "Storage \(s.pointee.id)" : desc,
                volumeIdentifier: volId,
                maxCapacity: s.pointee.MaxCapacity,
                freeSpace: s.pointee.FreeSpaceInBytes
            ))
            storage = s.pointee.next
        }

        if results.isEmpty {
            throw MTPError.noStorage
        }

        return results
    }

    // MARK: - File Listing

    /// List files and folders in a directory
    public func listDirectory(storageId: UInt32, parentId: UInt32, parentPath: String = "") throws -> [MTPFileInfo] {
        lock.lock()
        defer { lock.unlock() }
        try ensureConnected()

        MTPLog.fileOps.debug("Listing directory: storageId=\(storageId), parentId=\(parentId), path=\(parentPath)")
        let fileList = LIBMTP_Get_Files_And_Folders(device, storageId, parentId)

        var results: [MTPFileInfo] = []
        var current = fileList

        while let file = current {
            let f = file.pointee
            let name = getStringNoCopy(f.filename)
            let isDir = f.filetype == LIBMTP_FILETYPE_FOLDER
            let fixedParent = mtpFixSlash(parentPath)
            let fullPath = mtpGetFullPath(fixedParent, name)

            var size: Int64 = Int64(f.filesize)
            if !isDir && f.filesize == 0xFFFFFFFF {
                size = Int64(LIBMTP_Get_u64_From_Object(device, f.item_id,
                                                         LIBMTP_PROPERTY_ObjectSize, 0))
            }

            let info = MTPFileInfo(
                objectId: f.item_id,
                parentId: f.parent_id,
                storageId: f.storage_id,
                name: name,
                fullPath: fullPath,
                parentPath: fixedParent,
                fileExtension: mtpFileExtension(name, isDir: isDir),
                size: size,
                isDir: isDir,
                modTime: Date(timeIntervalSince1970: TimeInterval(f.modificationdate))
            )

            // Skip disallowed files
            if !mtpIsDisallowedFile(name) {
                results.append(info)
            }

            let next = file.pointee.next
            LIBMTP_destroy_file_t(file)
            current = next
        }

        // Sort: folders first, then by name
        results.sort { a, b in
            if a.isDir != b.isDir { return a.isDir }
            return a.name.localizedCaseInsensitiveCompare(b.name) == .orderedAscending
        }

        return results
    }

    // MARK: - Download

    /// Download a file from device to local path
    public func downloadFile(
        objectId: UInt32,
        destinationPath: String,
        progress: ((Int64, Int64) -> Bool)? = nil  // (sent, total) -> continue?
    ) throws {
        lock.lock()
        defer { lock.unlock() }
        try ensureConnected()
        MTPLog.transfer.info("Downloading objectId=\(objectId) to \(destinationPath)")

        // Use callback with context for progress reporting
        let context = ProgressContext(callback: progress)
        let contextPtr = Unmanaged.passRetained(context).toOpaque()
        defer { Unmanaged<ProgressContext>.fromOpaque(contextPtr).release() }

        let progressFunc: LIBMTP_progressfunc_t? = progress != nil ? { sent, total, ctx in
            guard let ctx = ctx else { return 0 }
            let context = Unmanaged<ProgressContext>.fromOpaque(ctx).takeUnretainedValue()
            if let cb = context.callback {
                let shouldContinue = cb(Int64(sent), Int64(total))
                if !shouldContinue {
                    context.wasCancelled = true
                    return 1
                }
            }
            return 0
        } : nil

        let ret = LIBMTP_Get_File_To_File(
            device,
            objectId,
            destinationPath,
            progressFunc,
            progress != nil ? contextPtr : nil
        )

        if ret != 0 {
            if context.wasCancelled {
                MTPLog.transfer.notice("Download cancelled for objectId=\(objectId)")
                // Clean up partial download
                try? FileManager.default.removeItem(atPath: destinationPath)
                throw MTPError.cancelled
            }
            let errMsg = drainErrorStack(device) ?? "Unknown download error"
            MTPLog.transfer.error("Download failed for objectId=\(objectId): \(errMsg)")
            throw MTPError.fileTransferError(errMsg)
        }
        MTPLog.transfer.info("Download complete for objectId=\(objectId)")
    }

    /// Download a file and restore its modification timestamp
    public func downloadFileWithTimestamp(
        fileInfo: MTPFileInfo,
        destinationPath: String,
        progress: ((Int64, Int64) -> Bool)? = nil
    ) throws {
        try downloadFile(objectId: fileInfo.objectId, destinationPath: destinationPath, progress: progress)

        // Restore modification timestamp
        let attrs: [FileAttributeKey: Any] = [
            .modificationDate: fileInfo.modTime
        ]
        try? FileManager.default.setAttributes(attrs, ofItemAtPath: destinationPath)
    }

    // MARK: - Upload

    /// Upload a local file to the device
    public func uploadFile(
        localPath: String,
        parentId: UInt32,
        storageId: UInt32,
        fileName: String? = nil,
        progress: ((Int64, Int64) -> Bool)? = nil
    ) throws -> UInt32 {
        lock.lock()
        defer { lock.unlock() }
        try ensureConnected()

        MTPLog.transfer.info("Uploading \(localPath) to parentId=\(parentId), storageId=\(storageId)")
        let fm = FileManager.default
        guard fm.fileExists(atPath: localPath) else {
            MTPLog.transfer.error("Local file not found: \(localPath)")
            throw MTPError.localFileError("Local file not found: \(localPath)")
        }

        let attrs = try fm.attributesOfItem(atPath: localPath)
        let fileSize = (attrs[.size] as? UInt64) ?? 0
        let name = fileName ?? (localPath as NSString).lastPathComponent

        // Create a new file_t struct
        guard let newFile = LIBMTP_new_file_t() else {
            throw MTPError.sendObjectError("Failed to allocate file struct")
        }
        defer { LIBMTP_destroy_file_t(newFile) }

        // Set file properties
        newFile.pointee.parent_id = parentId
        newFile.pointee.storage_id = storageId
        newFile.pointee.filesize = fileSize
        newFile.pointee.filetype = LIBMTP_FILETYPE_UNKNOWN
        newFile.pointee.filename = strdup(name)

        // Setup progress
        let context = ProgressContext(callback: progress)
        let contextPtr = Unmanaged.passRetained(context).toOpaque()
        defer { Unmanaged<ProgressContext>.fromOpaque(contextPtr).release() }

        let progressFunc: LIBMTP_progressfunc_t? = progress != nil ? { sent, total, ctx in
            guard let ctx = ctx else { return 0 }
            let context = Unmanaged<ProgressContext>.fromOpaque(ctx).takeUnretainedValue()
            if let cb = context.callback {
                let shouldContinue = cb(Int64(sent), Int64(total))
                if !shouldContinue {
                    context.wasCancelled = true
                    return 1
                }
            }
            return 0
        } : nil

        let ret = LIBMTP_Send_File_From_File(
            device,
            localPath,
            newFile,
            progressFunc,
            progress != nil ? contextPtr : nil
        )

        if ret != 0 {
            if context.wasCancelled {
                MTPLog.transfer.notice("Upload cancelled for \(localPath)")
                throw MTPError.cancelled
            }
            let errMsg = drainErrorStack(device) ?? "Unknown upload error"
            MTPLog.transfer.error("Upload failed for \(localPath): \(errMsg)")
            throw MTPError.sendObjectError(errMsg)
        }

        MTPLog.transfer.info("Upload complete: \(localPath) → objectId=\(newFile.pointee.item_id)")
        return newFile.pointee.item_id
    }

    // MARK: - Create Folder

    /// Create a new folder on the device
    public func createFolder(
        name: String,
        parentId: UInt32,
        storageId: UInt32
    ) throws -> UInt32 {
        lock.lock()
        defer { lock.unlock() }
        try ensureConnected()

        MTPLog.fileOps.info("Creating folder '\(name)' in parentId=\(parentId)")
        let nameCStr = strdup(name)
        defer { free(nameCStr) }

        let folderId = LIBMTP_Create_Folder(device, nameCStr, parentId, storageId)

        if folderId == 0 {
            let errMsg = drainErrorStack(device) ?? "Unknown error"
            MTPLog.fileOps.error("Create folder failed for '\(name)': \(errMsg)")
            throw MTPError.sendObjectError("Failed to create folder '\(name)': \(errMsg)")
        }

        MTPLog.fileOps.info("Created folder '\(name)' → folderId=\(folderId)")
        return folderId
    }

    // MARK: - Delete

    /// Delete a file or folder from the device
    public func deleteObject(objectId: UInt32) throws {
        lock.lock()
        defer { lock.unlock() }
        try ensureConnected()

        MTPLog.fileOps.info("Deleting objectId=\(objectId)")
        let ret = LIBMTP_Delete_Object(device, objectId)
        if ret != 0 {
            let errMsg = drainErrorStack(device) ?? "Unknown error"
            MTPLog.fileOps.error("Delete failed for objectId=\(objectId): \(errMsg)")
            throw MTPError.fileTransferError("Delete failed: \(errMsg)")
        }
        MTPLog.fileOps.info("Deleted objectId=\(objectId)")
    }

    // MARK: - Rename

    /// Rename a file or folder on the device
    ///
    /// - Parameters:
    ///   - objectId: The object to rename
    ///   - newName: The new filename (just the name, not a path)
    public func renameObject(objectId: UInt32, newName: String) throws {
        lock.lock()
        defer { lock.unlock() }
        try ensureConnected()

        MTPLog.fileOps.info("Renaming objectId=\(objectId) to '\(newName)'")
        let nameCStr = strdup(newName)
        defer { free(nameCStr) }

        let ret = LIBMTP_Set_Object_Filename(device, objectId, nameCStr)
        if ret != 0 {
            let errMsg = drainErrorStack(device) ?? "Unknown error"
            MTPLog.fileOps.error("Rename failed for objectId=\(objectId): \(errMsg)")
            throw MTPError.fileTransferError("Rename failed: \(errMsg)")
        }
        MTPLog.fileOps.info("Renamed objectId=\(objectId) → '\(newName)'")
    }

    // MARK: - Move

    /// Move a file or folder to a different parent folder
    ///
    /// - Parameters:
    ///   - objectId: The object to move
    ///   - storageId: The destination storage ID
    ///   - newParentId: The destination parent folder ID (use `MTPParentObjectID` for root)
    public func moveObject(objectId: UInt32, storageId: UInt32, newParentId: UInt32) throws {
        lock.lock()
        defer { lock.unlock() }
        try ensureConnected()

        MTPLog.fileOps.info("Moving objectId=\(objectId) to parentId=\(newParentId)")
        let ret = LIBMTP_Move_Object(device, objectId, storageId, newParentId)
        if ret != 0 {
            let errMsg = drainErrorStack(device) ?? "Unknown error"
            MTPLog.fileOps.error("Move failed for objectId=\(objectId): \(errMsg)")
            throw MTPError.fileTransferError("Move failed: \(errMsg)")
        }
        MTPLog.fileOps.info("Moved objectId=\(objectId) → parentId=\(newParentId)")
    }

    // MARK: - Thumbnail

    /// Fetch the device-generated thumbnail for an object (typically JPEG).
    ///
    /// Returns `nil` if the device does not have a thumbnail for this object.
    /// Most Android devices generate thumbnails for images and videos taken
    /// with the camera.
    public func getThumbnail(objectId: UInt32) -> Data? {
        lock.lock()
        defer { lock.unlock() }
        guard !released else { return nil }

        var dataPtr: UnsafeMutablePointer<UInt8>?
        var size: UInt32 = 0

        let ret = LIBMTP_Get_Thumbnail(device, objectId, &dataPtr, &size)

        guard ret == 0, let ptr = dataPtr, size > 0 else {
            // No thumbnail available — clear error stack silently
            LIBMTP_Clear_Errorstack(device)
            return nil
        }

        let data = Data(bytes: ptr, count: Int(size))
        free(ptr)
        return data
    }

    // MARK: - Recursive Walk

    /// Walk a directory tree recursively, calling callback for each item
    public func walk(
        storageId: UInt32,
        parentId: UInt32,
        parentPath: String = "/",
        callback: (MTPFileInfo) throws -> Void
    ) throws {
        let items = try listDirectory(storageId: storageId, parentId: parentId, parentPath: parentPath)

        for item in items {
            try callback(item)
            if item.isDir {
                try walk(
                    storageId: storageId,
                    parentId: item.objectId,
                    parentPath: item.fullPath,
                    callback: callback
                )
            }
        }
    }

    // MARK: - Bulk Download

    /// Download an entire folder recursively
    public func downloadFolder(
        storageId: UInt32,
        fileInfo: MTPFileInfo,
        destinationPath: String,
        progress: MTPProgressCallback? = nil
    ) throws {
        var pInfo = MTPProgressInfo()

        // First pass: count total files and size
        var totalFiles: Int64 = 0
        var totalSize: Int64 = 0
        try walk(storageId: storageId, parentId: fileInfo.objectId,
                 parentPath: fileInfo.fullPath) { item in
            if !item.isDir {
                totalFiles += 1
                totalSize += item.size
            }
        }

        pInfo.totalFiles = totalFiles
        pInfo.bulkFileSize.total = totalSize

        let state = DownloadState(pInfo: pInfo, bulkSizeSent: 0)

        // Second pass: actually download
        try downloadFolderRecursive(
            storageId: storageId,
            parentId: fileInfo.objectId,
            parentPath: fileInfo.fullPath,
            destinationBase: destinationPath,
            sourceFolderName: fileInfo.name,
            state: state,
            progress: progress
        )
    }

    private func downloadFolderRecursive(
        storageId: UInt32, parentId: UInt32, parentPath: String,
        destinationBase: String, sourceFolderName: String,
        state: DownloadState,
        progress: MTPProgressCallback?
    ) throws {
        let items = try listDirectory(storageId: storageId, parentId: parentId, parentPath: parentPath)

        for item in items {
            let destPath = destinationBase + "/" + item.name

            if item.isDir {
                try FileManager.default.createDirectory(
                    atPath: destPath, withIntermediateDirectories: true)
                try downloadFolderRecursive(
                    storageId: storageId, parentId: item.objectId,
                    parentPath: item.fullPath, destinationBase: destPath,
                    sourceFolderName: item.name,
                    state: state,
                    progress: progress
                )
            } else {
                state.pInfo.fileInfo = item
                state.pInfo.activeFileSize = MTPSizeProgress(total: item.size, sent: 0, progress: 0)
                state.pInfo.latestSentTime = Date()

                try downloadFileWithTimestamp(
                    fileInfo: item,
                    destinationPath: destPath
                ) { sent, total in
                    state.bulkSizeSent += sent
                    state.pInfo.activeFileSize.sent = sent
                    state.pInfo.activeFileSize.progress = mtpPercent(Float(sent), Float(total))
                    state.pInfo.bulkFileSize.sent = state.bulkSizeSent
                    state.pInfo.bulkFileSize.progress = mtpPercent(Float(state.bulkSizeSent), Float(state.pInfo.bulkFileSize.total))
                    return progress?(state.pInfo) ?? true
                }

                state.pInfo.filesSent += 1
                state.pInfo.filesSentProgress = mtpPercent(Float(state.pInfo.filesSent), Float(state.pInfo.totalFiles))
            }
        }
    }

    // MARK: - Process Detection

    /// Check if a process with the given name is currently running
    private static func isProcessRunning(_ name: String) -> Bool {
        let pipe = Pipe()
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/pgrep")
        process.arguments = ["-x", name]
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
            process.waitUntilExit()
            return process.terminationStatus == 0
        } catch {
            return false
        }
    }

    // MARK: - Serialized Execution

    /// Execute a blocking libmtp operation on the serial operation queue.
    /// This ensures all operations for this device are serialized and off the calling thread.
    internal func serialized<T>(_ work: @escaping () throws -> T) async throws -> T {
        try await withCheckedThrowingContinuation { continuation in
            operationQueue.async {
                do {
                    let result = try work()
                    continuation.resume(returning: result)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    /// Non-throwing variant for operations that return optional values
    internal func serializedOptional<T>(_ work: @escaping () -> T?) async -> T? {
        await withCheckedContinuation { continuation in
            operationQueue.async {
                continuation.resume(returning: work())
            }
        }
    }

    // MARK: - Helpers

    /// Safely convert a C string (malloc'd by libmtp) to Swift String, then free it
    private func getString(_ cStr: UnsafeMutablePointer<CChar>?) -> String {
        guard let cStr = cStr else { return "" }
        let result = String(cString: cStr)
        free(cStr)
        return result
    }

    /// Do not free variant — for strings owned by structs (const pointer)
    private func getStringNoCopy(_ cStr: UnsafePointer<CChar>?) -> String {
        guard let cStr = cStr else { return "" }
        return String(cString: cStr)
    }

    /// Do not free variant — for strings owned by structs (mutable pointer)
    private func getStringNoCopy(_ cStr: UnsafeMutablePointer<CChar>?) -> String {
        guard let cStr = cStr else { return "" }
        return String(cString: cStr)
    }
}

// MARK: - Progress Context

/// Context object for C callback trampolines
private final class ProgressContext {
    let callback: ((Int64, Int64) -> Bool)?
    var wasCancelled = false
    init(callback: ((Int64, Int64) -> Bool)?) {
        self.callback = callback
    }
}

/// Mutable state for recursive folder downloads (avoids inout capture issues)
private final class DownloadState {
    var pInfo: MTPProgressInfo
    var bulkSizeSent: Int64

    init(pInfo: MTPProgressInfo, bulkSizeSent: Int64) {
        self.pInfo = pInfo
        self.bulkSizeSent = bulkSizeSent
    }
}
