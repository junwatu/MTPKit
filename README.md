# MTPKit

A Swift library for communicating with Android devices over **MTP (Media Transfer Protocol)**, built on top of [libmtp](https://github.com/libmtp/libmtp). Browse, upload, download, and manage files on any MTP-compatible device — including Samsung — from macOS.

## Features

- **Device detection** — auto-detect connected MTP devices via USB
- **File browsing** — list directories with full metadata (size, date, type)
- **Upload & download** — transfer files and entire folders with progress callbacks
- **Folder operations** — create and delete folders
- **Samsung support** — uncached mode, storage retry, root parent ID mapping, >4GB file handling
- **SwiftUI ready** — includes `MTPManager`, an `@MainActor ObservableObject` with `@Published` state
- **Progress tracking** — throttled UI updates at ~30fps via `DispatchQueue.main.async`
- **Async/await native API** — `async throws` methods and `AsyncThrowingStream` progress streams for modern Swift concurrency
- **Sendable types** — all model types conform to `Sendable` for safe cross-isolation usage

## Requirements

- macOS 13.0+
- Swift 5.9+
- [libmtp](https://github.com/libmtp/libmtp) installed via Homebrew

```bash
brew install libmtp
```

## Installation

### Swift Package Manager

Add MTPKit to your `Package.swift`:

```swift
dependencies: [
    .package(url: "https://github.com/junwatu/MTPKit.git", from: "1.0.0")
]
```

Then add `"MTPKit"` to your target's dependencies:

```swift
.target(
    name: "YourApp",
    dependencies: ["MTPKit"]
)
```

## Usage

### Basic — Detect and List Files

```swift
import MTPKit

// Initialize libmtp (call once)
MTPDevice.initialize()

// Detect connected devices
let devices = try MTPDevice.detectDevices()
let device = devices[0]

// Get device info
let info = device.getDeviceInfo()
print("\(info.manufacturer) \(info.model)")

// Get storages
let storages = try device.getStorages()
let storage = storages[0]

// List root directory
let files = try device.listDirectory(
    storageId: storage.id,
    parentId: MTPParentObjectID,  // 0xFFFFFFFF = root
    parentPath: "/"
)

for file in files {
    print("\(file.isDir ? "📁" : "📄") \(file.name) — \(file.formattedSize)")
}
```

### Upload a File

```swift
let objectId = try device.uploadFile(
    localPath: "/Users/me/photo.jpg",
    parentId: MTPParentObjectID,
    storageId: storage.id
) { sent, total in
    print("Progress: \(sent)/\(total)")
    return true  // return false to cancel
}
```

### Download a File

```swift
try device.downloadFile(
    objectId: file.objectId,
    destinationPath: "/Users/me/Downloads/photo.jpg"
) { sent, total in
    print("Progress: \(sent)/\(total)")
    return true
}
```

### Create & Delete

```swift
// Create folder
let folderId = try device.createFolder(
    name: "NewFolder",
    parentId: MTPParentObjectID,
    storageId: storage.id
)

// Delete file or folder
try device.deleteObject(objectId: file.objectId)
```

### Async/Await API

All device operations have native `async throws` variants that run off the main thread:

```swift
// Async device detection and listing
let devices = try await MTPDevice.detectDevicesAsync()
let device = devices[0]
let storages = try await device.getStoragesAsync()
let files = try await device.listDirectoryAsync(
    storageId: storages[0].id,
    parentId: MTPParentObjectID,
    parentPath: "/"
)

// Async upload with progress closure
let objectId = try await device.uploadFile(
    localPath: "/Users/me/photo.jpg",
    parentId: MTPParentObjectID,
    storageId: storages[0].id
) { sent, total in
    print("Progress: \(sent)/\(total)")
}

// Async download with progress closure
try await device.downloadFile(
    objectId: file.objectId,
    destinationPath: "/Users/me/Downloads/photo.jpg"
) { sent, total in
    print("Progress: \(sent)/\(total)")
}
```

#### Stream-Based Progress

For SwiftUI or reactive patterns, use `AsyncThrowingStream` variants:

```swift
// Stream-based upload with for-await
for try await event in device.uploadAsync(
    localPath: "/Users/me/photo.jpg",
    parentId: MTPParentObjectID,
    storageId: storage.id
) {
    switch event {
    case .progress(let sent, let total):
        print("\(sent)/\(total)")
    case .completed(let objectId):
        print("Done! ID: \(objectId ?? 0)")
    }
}

// Stream-based recursive directory walk
for try await file in device.walkAsync(storageId: storage.id, parentId: MTPParentObjectID) {
    print("\(file.isDir ? "📁" : "📄") \(file.name)")
}
```

### SwiftUI — Using MTPManager

```swift
import SwiftUI
import MTPKit

@main
struct MyApp: App {
    @StateObject private var manager = MTPManager()

    var body: some Scene {
        WindowGroup {
            VStack {
                if manager.isConnected {
                    List(manager.currentFiles) { file in
                        Text(file.name)
                    }
                } else {
                    Button("Connect") { manager.connect() }
                }
            }
            .environmentObject(manager)
        }
    }
}
```

`MTPManager` provides `@Published` properties for all UI state:

| Property | Type | Description |
|----------|------|-------------|
| `isConnected` | `Bool` | Device connection status |
| `isLoading` | `Bool` | Loading indicator |
| `devices` | `[MTPDevice]` | Detected devices |
| `deviceInfo` | `MTPDeviceInfo?` | Manufacturer, model, serial |
| `storages` | `[MTPStorageInfo]` | Storage volumes |
| `currentFiles` | `[MTPFileInfo]` | Files in current directory |
| `currentPath` | `String` | Current browsing path |
| `transferProgress` | `TransferProgress?` | Active transfer progress |
| `errorMessage` | `String?` | Last error message |

## Architecture

```
MTPKit/
├── MTPConstants.swift   — Root ID, path separator, disallowed files
├── MTPTypes.swift       — MTPFileInfo, MTPStorageInfo, MTPDeviceInfo, progress types
├── MTPError.swift       — Error enum with localized descriptions
├── MTPUtils.swift       — Path utilities, file extension parsing
├── MTPDevice.swift       — Core wrapper over libmtp C functions
├── MTPDevice+Async.swift — Async/await extensions with AsyncThrowingStream support
└── MTPManager.swift      — SwiftUI ObservableObject with navigation & transfer management
```

## Running Tests

```bash
swift run MTPKitTests
```

Tests run as an executable target (no Xcode/XCTest required).

## Roadmap

Planned enhancements for MTPKit. Check marks indicate implemented features.

### High Impact

- [x] **Async/await native API** — Replace completion handlers with `async throws` methods for modern Swift concurrency
- [ ] **USB hot-plug monitoring** — Detect device connect/disconnect events in real-time via IOKit notifications
- [ ] **Transfer cancellation** — Support cooperative cancellation of uploads/downloads via `Task.isCancelled`
- [ ] **Rename/Move files** — Add `renameObject()` and `moveObject()` wrappers over `LIBMTP_Set_Object_Filename`

### Medium Impact

- [ ] **Swift Actor instead of NSLock** — Replace manual locking with a `MTPDeviceActor` for safer concurrency
- [ ] **Thumbnail support** — Retrieve device-generated thumbnails via `LIBMTP_Get_Thumbnail`
- [ ] **Storage refresh after transfers** — Auto-refresh storage info (free space) after upload/download/delete
- [ ] **Batch delete** — Delete multiple objects in a single call with rollback on partial failure
- [ ] **DocC documentation** — Add full DocC-compatible documentation with code examples

### Nice to Have

- [ ] **Reconnection handling** — Auto-reconnect when a device is temporarily disconnected
- [ ] **File type mapping** — Map file extensions to MTP file types for better device compatibility
- [ ] **CI with GitHub Actions** — Automated build and test pipeline on macOS runners
- [ ] **Swift 6 strict concurrency** — Full `Sendable` compliance and data-race safety
- [ ] **SPM plugin for code signing** — Build tool plugin to automate ad-hoc signing of bundled dylibs

## Changelog

### v1.1.0 — 2026-03-27

- **Async/await native API** — All `MTPDevice` methods now have `async throws` counterparts that run off the main thread via `Task.detached`, eliminating the need for manual `Task.detached` wrappers in calling code.
- **`AsyncThrowingStream` progress streams** — `downloadAsync()`, `uploadAsync()`, `downloadFolderAsync()`, and `walkAsync()` return `AsyncThrowingStream` for reactive `for try await` consumption.
- **`MTPTransferEvent` & `MTPBulkTransferEvent`** — New enums for stream-based progress reporting with `.progress(sent:total:)` and `.completed(objectId:)` cases.
- **Sendable conformance** — `MTPFileInfo`, `MTPStorageInfo`, `MTPDeviceInfo`, `MTPProgressInfo`, and `MTPSizeProgress` now conform to `Sendable` for safe cross-isolation usage.
- **MTPManager modernized** — `connect()`, `fetchStorages()`, `browse()`, `deleteFile()`, and `createFolder()` now use async device APIs directly, removing `MainActor.run {}` boilerplate.
- **10 new tests** (60 → 70 total) covering async event types and Sendable conformance.

### v1.0.0 — 2026-03-26

- Initial release with `MTPDevice` (sync API), `MTPManager` (SwiftUI), Samsung workarounds, and progress tracking.

## Attribution

MTPKit is a **Swift port** of [go-mtpx](https://github.com/ganeshrvel/go-mtpx) by [@ganeshrvel](https://github.com/ganeshrvel), a Go library for MTP operations that wraps [go-mtpfs](https://github.com/hanwen/go-mtpfs). The core logic — path handling, device operations, Samsung workarounds, and progress tracking — was ported from Go to Swift with native C interop over [libmtp](https://github.com/libmtp/libmtp).

## License

MIT
