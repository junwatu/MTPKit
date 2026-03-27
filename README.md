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
├── MTPDevice.swift      — Core wrapper over libmtp C functions
└── MTPManager.swift     — SwiftUI ObservableObject with navigation & transfer management
```

## Running Tests

```bash
swift run MTPKitTests
```

Tests run as an executable target (no Xcode/XCTest required).

## Attribution

MTPKit is a **Swift port** of [go-mtpx](https://github.com/ganeshrvel/go-mtpx) by [@ganeshrvel](https://github.com/ganeshrvel), a Go library for MTP operations that wraps [go-mtpfs](https://github.com/hanwen/go-mtpfs). The core logic — path handling, device operations, Samsung workarounds, and progress tracking — was ported from Go to Swift with native C interop over [libmtp](https://github.com/libmtp/libmtp).

## License

MIT
