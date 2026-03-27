// MTPDevice.swift — Core device wrapper over libmtp
import Foundation
import CLibMTP

/// Wraps an MTP device connection via libmtp
public final class MTPDevice: @unchecked Sendable {
    /// The raw libmtp device pointer
    private let device: UnsafeMutablePointer<LIBMTP_mtpdevice_t>
    private let lock = NSLock()

    /// Private init — use `detectDevices()` to create instances
    private init(device: UnsafeMutablePointer<LIBMTP_mtpdevice_t>) {
        self.device = device
    }

    deinit {
        LIBMTP_Release_Device(device)
    }

    // MARK: - Static: Initialize & Detect

    /// Initialize libmtp (call once at app start)
    public static func initialize() {
        LIBMTP_Init()
    }

    /// Detect all connected MTP devices
    public static func detectDevices() throws -> [MTPDevice] {
        var rawDevices: UnsafeMutablePointer<LIBMTP_raw_device_struct>?
        var numDevices: Int32 = 0

        let err = LIBMTP_Detect_Raw_Devices(&rawDevices, &numDevices)

        guard err == LIBMTP_ERROR_NONE else {
            switch err {
            case LIBMTP_ERROR_NO_DEVICE_ATTACHED:
                throw MTPError.noDevicesFound
            default:
                throw MTPError.detectFailed("Error code: \(err.rawValue)")
            }
        }

        guard let rawDevices = rawDevices, numDevices > 0 else {
            throw MTPError.noDevicesFound
        }

        defer { free(rawDevices) }

        var devices: [MTPDevice] = []
        for i in 0..<Int(numDevices) {
            // Use uncached mode — critical for Samsung devices with many files
            guard let dev = LIBMTP_Open_Raw_Device_Uncached(&rawDevices[i]) else {
                continue
            }
            devices.append(MTPDevice(device: dev))
        }

        if devices.isEmpty {
            throw MTPError.deviceOpenFailed("Could not open any detected devices. Make sure no other app (e.g. Android File Transfer) is using the device.")
        }

        return devices
    }

    // MARK: - Device Info

    public func getDeviceInfo() -> MTPDeviceInfo {
        lock.lock()
        defer { lock.unlock() }

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

        let ret = LIBMTP_Get_Storage(device, Int32(LIBMTP_STORAGE_SORTBY_NOTSORTED))
        if ret != 0 {
            // Samsung devices sometimes need a retry
            Thread.sleep(forTimeInterval: 0.5)
            let ret2 = LIBMTP_Get_Storage(device, Int32(LIBMTP_STORAGE_SORTBY_NOTSORTED))
            if ret2 != 0 {
                throw MTPError.storageInfoError(drainErrorStack(device) ?? "Unknown error")
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

        // Use callback with context for progress reporting
        let context = ProgressContext(callback: progress)
        let contextPtr = Unmanaged.passRetained(context).toOpaque()
        defer { Unmanaged<ProgressContext>.fromOpaque(contextPtr).release() }

        let progressFunc: LIBMTP_progressfunc_t? = progress != nil ? { sent, total, ctx in
            guard let ctx = ctx else { return 0 }
            let context = Unmanaged<ProgressContext>.fromOpaque(ctx).takeUnretainedValue()
            if let cb = context.callback {
                return cb(Int64(sent), Int64(total)) ? 0 : 1
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
            let errMsg = drainErrorStack(device) ?? "Unknown download error"
            throw MTPError.fileTransferError(errMsg)
        }
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

        let fm = FileManager.default
        guard fm.fileExists(atPath: localPath) else {
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
                return cb(Int64(sent), Int64(total)) ? 0 : 1
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
            let errMsg = drainErrorStack(device) ?? "Unknown upload error"
            throw MTPError.sendObjectError(errMsg)
        }

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

        let nameCStr = strdup(name)
        defer { free(nameCStr) }

        let folderId = LIBMTP_Create_Folder(device, nameCStr, parentId, storageId)

        if folderId == 0 {
            let errMsg = drainErrorStack(device) ?? "Unknown error"
            throw MTPError.sendObjectError("Failed to create folder '\(name)': \(errMsg)")
        }

        return folderId
    }

    // MARK: - Delete

    /// Delete a file or folder from the device
    public func deleteObject(objectId: UInt32) throws {
        lock.lock()
        defer { lock.unlock() }

        let ret = LIBMTP_Delete_Object(device, objectId)
        if ret != 0 {
            let errMsg = drainErrorStack(device) ?? "Unknown error"
            throw MTPError.fileTransferError("Delete failed: \(errMsg)")
        }
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
