// MTPKitTests — Self-contained test runner for MTPKit
// Run: swift run MTPKitTests
import Foundation
@testable import MTPKit

// MARK: - Test Framework

var totalTests = 0
var passedTests = 0
var failedTests: [(String, String)] = []

func test(_ name: String, _ body: () throws -> Void) {
    totalTests += 1
    do {
        try body()
        passedTests += 1
        print("  ✅ \(name)")
    } catch {
        failedTests.append((name, "\(error)"))
        print("  ❌ \(name): \(error)")
    }
}

func expect<T: Equatable>(_ actual: T, _ expected: T, _ message: String = "", file: String = #file, line: Int = #line) throws {
    guard actual == expected else {
        let msg = message.isEmpty ? "" : " (\(message))"
        throw TestError("Expected \(expected), got \(actual)\(msg) at \(file):\(line)")
    }
}

func expectTrue(_ condition: Bool, _ message: String = "", file: String = #file, line: Int = #line) throws {
    guard condition else {
        throw TestError("Expected true\(message.isEmpty ? "" : ": \(message)") at \(file):\(line)")
    }
}

func expectFalse(_ condition: Bool, _ message: String = "", file: String = #file, line: Int = #line) throws {
    guard !condition else {
        throw TestError("Expected false\(message.isEmpty ? "" : ": \(message)") at \(file):\(line)")
    }
}

func expectNil<T>(_ value: T?, file: String = #file, line: Int = #line) throws {
    guard value == nil else {
        throw TestError("Expected nil, got \(value!) at \(file):\(line)")
    }
}

func expectNotNil<T>(_ value: T?, file: String = #file, line: Int = #line) throws {
    guard value != nil else {
        throw TestError("Expected non-nil at \(file):\(line)")
    }
}

struct TestError: Error, CustomStringConvertible {
    let description: String
    init(_ msg: String) { description = msg }
}

func testOnMain(_ name: String, _ body: @MainActor @Sendable () throws -> Void) {
    totalTests += 1
    do {
        try MainActor.assumeIsolated {
            try body()
        }
        passedTests += 1
        print("  ✅ \(name)")
    } catch {
        failedTests.append((name, "\(error)"))
        print("  ❌ \(name): \(error)")
    }
}

// MARK: - Helpers

func makeFileInfo(
    objectId: UInt32 = 1, parentId: UInt32 = 0, storageId: UInt32 = 1,
    name: String = "test.txt", fullPath: String = "/test.txt",
    size: Int64 = 1024, isDir: Bool = false, modTime: Date = Date()
) -> MTPFileInfo {
    MTPFileInfo(
        objectId: objectId, parentId: parentId, storageId: storageId,
        name: name, fullPath: fullPath, parentPath: "/",
        fileExtension: mtpFileExtension(name, isDir: isDir),
        size: size, isDir: isDir, modTime: modTime
    )
}

func makeStorage(id: UInt32 = 1) -> MTPStorageInfo {
    MTPStorageInfo(id: id, description: "Internal", volumeIdentifier: "", maxCapacity: 100, freeSpace: 50)
}

// ============================================================================
// TESTS
// ============================================================================

print("\n🧪 MTPKit Test Suite\n")

// ─────────────────────────────────────────────────────────────────────────────
print("── MTPConstants ──")
// ─────────────────────────────────────────────────────────────────────────────

test("ParentObjectID is 0xFFFFFFFF") {
    try expect(MTPParentObjectID, UInt32(0xFFFFFFFF))
}

test("PathSep is /") {
    try expect(MTPPathSep, "/")
}

test("DisallowedFiles contains .DS_Store") {
    try expectTrue(MTPDisallowedFiles.contains(".DS_Store"))
}

test("AllowedSecondExtensions contains tar") {
    try expectNotNil(MTPAllowedSecondExtensions["tar"])
}

// ─────────────────────────────────────────────────────────────────────────────
print("\n── MTPUtils: fixSlash ──")
// ─────────────────────────────────────────────────────────────────────────────

test("fixSlash adds leading slash") {
    try expect(mtpFixSlash("DCIM"), "/DCIM")
}

test("fixSlash preserves existing slash") {
    try expect(mtpFixSlash("/DCIM"), "/DCIM")
}

test("fixSlash cleans double slashes") {
    try expect(mtpFixSlash("//DCIM//Camera"), "/DCIM/Camera")
}

test("fixSlash resolves ..") {
    try expect(mtpFixSlash("/DCIM/Camera/.."), "/DCIM")
}

test("fixSlash resolves .") {
    try expect(mtpFixSlash("/DCIM/./Camera"), "/DCIM/Camera")
}

test("fixSlash root path") {
    try expect(mtpFixSlash("/"), "/")
}

test("fixSlash empty string") {
    try expect(mtpFixSlash(""), "/")
}

// ─────────────────────────────────────────────────────────────────────────────
print("\n── MTPUtils: getFullPath ──")
// ─────────────────────────────────────────────────────────────────────────────

test("getFullPath basic") {
    try expect(mtpGetFullPath("/DCIM", "Camera"), "/DCIM/Camera")
}

test("getFullPath root parent") {
    try expect(mtpGetFullPath("/", "DCIM"), "/DCIM")
}

test("getFullPath nested") {
    try expect(mtpGetFullPath("/DCIM/Camera", "photo.jpg"), "/DCIM/Camera/photo.jpg")
}

test("getFullPath cleans result") {
    try expect(mtpGetFullPath("/DCIM/", "Camera"), "/DCIM/Camera")
}

// ─────────────────────────────────────────────────────────────────────────────
print("\n── MTPUtils: cleanPath ──")
// ─────────────────────────────────────────────────────────────────────────────

test("cleanPath removes trailing slash") {
    try expect(cleanPath("/DCIM/Camera/"), "/DCIM/Camera")
}

test("cleanPath removes double slash") {
    try expect(cleanPath("/DCIM//Camera"), "/DCIM/Camera")
}

test("cleanPath resolves ..") {
    try expect(cleanPath("/DCIM/Camera/../Photos"), "/DCIM/Photos")
}

test("cleanPath root") {
    try expect(cleanPath("/"), "/")
}

test("cleanPath empty returns .") {
    try expect(cleanPath(""), ".")
}

test("cleanPath /.. stays at root") {
    try expect(cleanPath("/.."), "/")
}

// ─────────────────────────────────────────────────────────────────────────────
print("\n── MTPUtils: fileExtension ──")
// ─────────────────────────────────────────────────────────────────────────────

test("extension simple file") {
    try expect(mtpFileExtension("photo.jpg", isDir: false), "jpg")
}

test("extension tar.gz double extension") {
    try expect(mtpFileExtension("archive.tar.gz", isDir: false), "tar.gz")
}

test("extension no extension") {
    try expect(mtpFileExtension("README", isDir: false), "")
}

test("extension dir returns empty") {
    try expect(mtpFileExtension("DCIM", isDir: true), "")
}

test("extension dotfile") {
    try expect(mtpFileExtension(".gitignore", isDir: false), "")
}

test("extension multiple dots") {
    try expect(mtpFileExtension("my.cool.file.txt", isDir: false), "txt")
}

// ─────────────────────────────────────────────────────────────────────────────
print("\n── MTPUtils: disallowed ──")
// ─────────────────────────────────────────────────────────────────────────────

test(".DS_Store is disallowed") {
    try expectTrue(mtpIsDisallowedFile(".DS_Store"))
}

test("normal file is allowed") {
    try expectFalse(mtpIsDisallowedFile("photo.jpg"))
}

// ─────────────────────────────────────────────────────────────────────────────
print("\n── MTPUtils: percent ──")
// ─────────────────────────────────────────────────────────────────────────────

test("percent basic") {
    try expect(mtpPercent(50, 100), Float(50.0))
}

test("percent full") {
    try expect(mtpPercent(100, 100), Float(100.0))
}

test("percent zero") {
    try expect(mtpPercent(0, 100), Float(0.0))
}

test("percent total zero returns 0") {
    try expect(mtpPercent(50, 0), Float(0.0))
}

// ─────────────────────────────────────────────────────────────────────────────
print("\n── MTPTypes: FileInfo ──")
// ─────────────────────────────────────────────────────────────────────────────

test("FileInfo isDir flag") {
    try expectTrue(makeFileInfo(isDir: true).isDir)
    try expectFalse(makeFileInfo(isDir: false).isDir)
}

test("FileInfo formattedSize for file") {
    let file = makeFileInfo(size: 1_048_576, isDir: false)
    try expectFalse(file.formattedSize.isEmpty)
    try expectTrue(file.formattedSize != "--")
}

test("FileInfo formattedSize for dir is --") {
    try expect(makeFileInfo(isDir: true).formattedSize, "--")
}

test("FileInfo id equals objectId") {
    let file = makeFileInfo(objectId: 42)
    try expect(file.id, UInt32(42))
    try expect(file.id, file.objectId)
}

// ─────────────────────────────────────────────────────────────────────────────
print("\n── MTPTypes: StorageInfo ──")
// ─────────────────────────────────────────────────────────────────────────────

test("StorageInfo usedPercentage") {
    let s = MTPStorageInfo(id: 1, description: "Int", volumeIdentifier: "", maxCapacity: 100, freeSpace: 25)
    try expectTrue(abs(s.usedPercentage - 75.0) < 0.01)
}

test("StorageInfo usedPercentage zero capacity") {
    let s = MTPStorageInfo(id: 1, description: "Int", volumeIdentifier: "", maxCapacity: 0, freeSpace: 0)
    try expect(s.usedPercentage, 0.0)
}

test("StorageInfo usedPercentage full") {
    let s = MTPStorageInfo(id: 1, description: "Int", volumeIdentifier: "", maxCapacity: 100, freeSpace: 0)
    try expectTrue(abs(s.usedPercentage - 100.0) < 0.01)
}

test("StorageInfo formatted strings") {
    let s = MTPStorageInfo(id: 1, description: "Int", volumeIdentifier: "", maxCapacity: 128_000_000_000, freeSpace: 64_000_000_000)
    try expectFalse(s.formattedCapacity.isEmpty)
    try expectFalse(s.formattedFreeSpace.isEmpty)
}

// ─────────────────────────────────────────────────────────────────────────────
print("\n── MTPTypes: Progress ──")
// ─────────────────────────────────────────────────────────────────────────────

test("SizeProgress defaults") {
    let p = MTPSizeProgress()
    try expect(p.total, Int64(0))
    try expect(p.sent, Int64(0))
}

test("ProgressInfo defaults") {
    let p = MTPProgressInfo()
    try expectNil(p.fileInfo)
    try expect(p.filesSent, Int64(0))
}

// ─────────────────────────────────────────────────────────────────────────────
print("\n── MTPError ──")
// ─────────────────────────────────────────────────────────────────────────────

test("Error descriptions are non-empty") {
    let errors: [MTPError] = [
        .detectFailed("x"), .storageInfoError("x"), .noStorage,
        .localFileError("x"), .invalidPath("x"), .fileTransferError("x"),
        .sendObjectError("x"), .noDevicesFound, .deviceOpenFailed("x"),
        .cancelled,
    ]
    for err in errors {
        try expectNotNil(err.errorDescription)
        try expectFalse(err.errorDescription!.isEmpty, "\(err)")
    }
}

test("Error equality") {
    try expectTrue(MTPError.noDevicesFound == MTPError.noDevicesFound)
    try expectTrue(MTPError.noStorage == MTPError.noStorage)
    try expectFalse(MTPError.noDevicesFound == MTPError.noStorage)
}

test("noDevicesFound mentions MTP") {
    try expectTrue(MTPError.noDevicesFound.errorDescription!.contains("MTP"))
}

// ─────────────────────────────────────────────────────────────────────────────
print("\n── MTPManager: Navigation ──")
// ─────────────────────────────────────────────────────────────────────────────

testOnMain("Manager initial state") {
    let mgr = MTPManager()
    try expectFalse(mgr.isConnected)
    try expect(mgr.currentPath, "/")
    try expect(mgr.currentParentId, MTPParentObjectID)
    try expectTrue(mgr.pathHistory.isEmpty)
    try expectNil(mgr.errorMessage)
}

testOnMain("navigateInto pushes currentParentId, NOT file.parentId") {
    let mgr = MTPManager()
    mgr.selectedStorage = makeStorage()
    mgr.currentPath = "/"
    mgr.currentParentId = MTPParentObjectID

    // Samsung root-level folder: parentId=0 (NOT 0xFFFFFFFF!)
    let dcim = makeFileInfo(objectId: 10, parentId: 0, name: "DCIM", fullPath: "/DCIM", isDir: true)
    mgr.navigateInto(file: dcim)

    try expect(mgr.pathHistory.count, 1)
    try expect(mgr.pathHistory[0].browseParentId, MTPParentObjectID,
        "MUST be 0xFFFFFFFF (currentParentId), NOT 0 (Samsung file.parentId)")
}

testOnMain("navigateInto skips non-directory files") {
    let mgr = MTPManager()
    mgr.selectedStorage = makeStorage()
    let file = makeFileInfo(isDir: false)
    mgr.navigateInto(file: file)
    try expectTrue(mgr.pathHistory.isEmpty)
}

testOnMain("navigateInto skips when no storage") {
    let mgr = MTPManager()
    mgr.selectedStorage = nil
    let folder = makeFileInfo(isDir: true)
    mgr.navigateInto(file: folder)
    try expectTrue(mgr.pathHistory.isEmpty)
}

testOnMain("Deep navigation: root -> DCIM -> Camera -> 2024 history chain") {
    let mgr = MTPManager()
    mgr.selectedStorage = makeStorage()
    mgr.currentPath = "/"
    mgr.currentParentId = MTPParentObjectID

    mgr.navigateInto(file: makeFileInfo(objectId: 10, parentId: 0, name: "DCIM", fullPath: "/DCIM", isDir: true))
    mgr.currentPath = "/DCIM"
    mgr.currentParentId = 10

    mgr.navigateInto(file: makeFileInfo(objectId: 20, parentId: 10, name: "Camera", fullPath: "/DCIM/Camera", isDir: true))
    mgr.currentPath = "/DCIM/Camera"
    mgr.currentParentId = 20

    mgr.navigateInto(file: makeFileInfo(objectId: 30, parentId: 20, name: "2024", fullPath: "/DCIM/Camera/2024", isDir: true))

    try expect(mgr.pathHistory.count, 3)
    try expect(mgr.pathHistory[0].browseParentId, MTPParentObjectID)
    try expect(mgr.pathHistory[1].browseParentId, UInt32(10))
    try expect(mgr.pathHistory[2].browseParentId, UInt32(20))
}

testOnMain("navigateUp pops history") {
    let mgr = MTPManager()
    mgr.selectedStorage = makeStorage()
    mgr.pathHistory = [
        MTPManager.PathEntry(path: "/", browseParentId: MTPParentObjectID, name: "/"),
        MTPManager.PathEntry(path: "/DCIM", browseParentId: 10, name: "DCIM"),
    ]
    mgr.navigateUp()
    try expect(mgr.pathHistory.count, 1)
}

testOnMain("navigateUp empty history does nothing") {
    let mgr = MTPManager()
    mgr.selectedStorage = makeStorage()
    mgr.pathHistory = []
    mgr.navigateUp()
    try expectTrue(mgr.pathHistory.isEmpty)
}

testOnMain("navigateUp without storage does nothing") {
    let mgr = MTPManager()
    mgr.selectedStorage = nil
    mgr.pathHistory = [
        MTPManager.PathEntry(path: "/", browseParentId: MTPParentObjectID, name: "/")
    ]
    mgr.navigateUp()
    try expect(mgr.pathHistory.count, 1)
}

testOnMain("navigateToRoot clears history and resets parentId") {
    let mgr = MTPManager()
    mgr.selectedStorage = makeStorage()
    mgr.pathHistory = [
        MTPManager.PathEntry(path: "/", browseParentId: MTPParentObjectID, name: "/"),
        MTPManager.PathEntry(path: "/DCIM", browseParentId: 10, name: "DCIM"),
    ]
    mgr.currentParentId = 20
    mgr.navigateToRoot()
    try expectTrue(mgr.pathHistory.isEmpty)
    try expect(mgr.currentParentId, MTPParentObjectID)
}

testOnMain("navigateToRoot without storage does nothing") {
    let mgr = MTPManager()
    mgr.selectedStorage = nil
    mgr.pathHistory = [
        MTPManager.PathEntry(path: "/", browseParentId: MTPParentObjectID, name: "/")
    ]
    mgr.navigateToRoot()
    try expect(mgr.pathHistory.count, 1)
}

testOnMain("disconnect resets all state") {
    let mgr = MTPManager()
    mgr.isConnected = true
    mgr.currentPath = "/DCIM"
    mgr.currentParentId = 20
    mgr.pathHistory = [MTPManager.PathEntry(path: "/", browseParentId: MTPParentObjectID, name: "/")]
    mgr.errorMessage = "err"
    mgr.disconnect()
    try expectFalse(mgr.isConnected)
    try expect(mgr.currentPath, "/")
    try expect(mgr.currentParentId, MTPParentObjectID)
    try expectTrue(mgr.pathHistory.isEmpty)
    try expectNil(mgr.errorMessage)
    try expectNil(mgr.transferProgress)
}

testOnMain("REGRESSION: full round-trip back navigation uses correct parentIds") {
    let mgr = MTPManager()
    mgr.selectedStorage = makeStorage()
    mgr.currentPath = "/"
    mgr.currentParentId = MTPParentObjectID

    mgr.navigateInto(file: makeFileInfo(objectId: 10, parentId: 0, name: "DCIM", fullPath: "/DCIM", isDir: true))
    mgr.currentPath = "/DCIM"; mgr.currentParentId = 10

    mgr.navigateInto(file: makeFileInfo(objectId: 20, parentId: 10, name: "Camera", fullPath: "/DCIM/Camera", isDir: true))
    mgr.currentPath = "/DCIM/Camera"; mgr.currentParentId = 20

    let pop1 = mgr.pathHistory.last!
    try expect(pop1.browseParentId, UInt32(10))
    mgr.pathHistory.removeLast()

    let pop2 = mgr.pathHistory.last!
    try expect(pop2.browseParentId, MTPParentObjectID,
        "Back from DCIM MUST use 0xFFFFFFFF, NOT Samsung's parent_id=0")
    mgr.pathHistory.removeLast()

    try expectTrue(mgr.pathHistory.isEmpty)
}

test("TransferProgress percentage") {
    let tp = MTPManager.TransferProgress(fileName: "test.jpg", sent: 50, total: 100, isUploading: false)
    try expect(tp.percentage, 50.0)
}

test("TransferProgress zero total") {
    let tp = MTPManager.TransferProgress(fileName: "test.jpg", sent: 50, total: 0, isUploading: true)
    try expect(tp.percentage, 0.0)
}

// ─────────────────────────────────────────────────────────────────────────────
print("\n── Async Types ──")
// ─────────────────────────────────────────────────────────────────────────────

test("MTPTransferEvent progress case") {
    let event = MTPTransferEvent.progress(sent: 500, total: 1000)
    if case .progress(let sent, let total) = event {
        try expect(sent, Int64(500))
        try expect(total, Int64(1000))
    } else {
        throw TestError("Expected .progress case")
    }
}

test("MTPTransferEvent completed case with objectId") {
    let event = MTPTransferEvent.completed(objectId: 42)
    if case .completed(let objId) = event {
        try expect(objId, UInt32(42))
    } else {
        throw TestError("Expected .completed case")
    }
}

test("MTPTransferEvent completed case with nil objectId") {
    let event = MTPTransferEvent.completed(objectId: nil)
    if case .completed(let objId) = event {
        try expectNil(objId)
    } else {
        throw TestError("Expected .completed case")
    }
}

test("MTPBulkTransferEvent progress case") {
    var pInfo = MTPProgressInfo()
    pInfo.totalFiles = 10
    pInfo.filesSent = 5
    let event = MTPBulkTransferEvent.progress(pInfo)
    if case .progress(let info) = event {
        try expect(info.totalFiles, Int64(10))
        try expect(info.filesSent, Int64(5))
    } else {
        throw TestError("Expected .progress case")
    }
}

test("MTPBulkTransferEvent completed case") {
    let event = MTPBulkTransferEvent.completed
    if case .completed = event {
        // pass
    } else {
        throw TestError("Expected .completed case")
    }
}

test("MTPFileInfo is Sendable") {
    let file = makeFileInfo()
    // Verify it can be passed to a Sendable closure
    let closure: @Sendable () -> String = { file.name }
    try expect(closure(), "test.txt")
}

test("MTPStorageInfo is Sendable") {
    let storage = makeStorage()
    let closure: @Sendable () -> UInt32 = { storage.id }
    try expect(closure(), UInt32(1))
}

test("MTPDeviceInfo is Sendable") {
    let info = MTPDeviceInfo(id: "123", manufacturer: "Samsung", model: "Galaxy", serialNumber: "123", deviceVersion: "1.0", friendlyName: "Phone")
    let closure: @Sendable () -> String = { info.manufacturer }
    try expect(closure(), "Samsung")
}

test("MTPProgressInfo is Sendable") {
    var pInfo = MTPProgressInfo()
    pInfo.totalFiles = 5
    let closure: @Sendable () -> Int64 = { pInfo.totalFiles }
    try expect(closure(), Int64(5))
}

test("MTPSizeProgress is Sendable") {
    let sp = MTPSizeProgress(total: 100, sent: 50, progress: 50.0)
    let closure: @Sendable () -> Int64 = { sp.total }
    try expect(closure(), Int64(100))
}

// ─────────────────────────────────────────────────────────────────────────────
print("\n── USBDeviceMonitor ──")
// ─────────────────────────────────────────────────────────────────────────────

test("USBDeviceMonitor initial state") {
    let monitor = USBDeviceMonitor()
    try expectFalse(monitor.monitoring)
}

test("USBDeviceMonitor start sets monitoring true") {
    let monitor = USBDeviceMonitor()
    monitor.startMonitoring { _ in }
    // Give the background thread a moment to start
    Thread.sleep(forTimeInterval: 0.1)
    try expectTrue(monitor.monitoring)
    monitor.stopMonitoring()
}

test("USBDeviceMonitor stop sets monitoring false") {
    let monitor = USBDeviceMonitor()
    monitor.startMonitoring { _ in }
    Thread.sleep(forTimeInterval: 0.1)
    monitor.stopMonitoring()
    try expectFalse(monitor.monitoring)
}

test("USBDeviceMonitor double start is safe") {
    let monitor = USBDeviceMonitor()
    monitor.startMonitoring { _ in }
    monitor.startMonitoring { _ in }  // should not crash
    Thread.sleep(forTimeInterval: 0.1)
    try expectTrue(monitor.monitoring)
    monitor.stopMonitoring()
}

test("USBDeviceMonitor double stop is safe") {
    let monitor = USBDeviceMonitor()
    monitor.startMonitoring { _ in }
    Thread.sleep(forTimeInterval: 0.1)
    monitor.stopMonitoring()
    monitor.stopMonitoring()  // should not crash
    try expectFalse(monitor.monitoring)
}

test("USBDeviceMonitor deinit stops monitoring") {
    var monitor: USBDeviceMonitor? = USBDeviceMonitor()
    monitor?.startMonitoring { _ in }
    Thread.sleep(forTimeInterval: 0.1)
    monitor = nil  // should not crash, deinit calls stopMonitoring
    try expectTrue(true)  // if we got here, no crash
}

test("USBDeviceMonitor.Event descriptions") {
    let connect = USBDeviceMonitor.Event.deviceConnected
    let disconnect = USBDeviceMonitor.Event.deviceDisconnected
    try expect(connect.description, "deviceConnected")
    try expect(disconnect.description, "deviceDisconnected")
}

test("USBDeviceMonitor.Event equality") {
    try expectTrue(USBDeviceMonitor.Event.deviceConnected == .deviceConnected)
    try expectTrue(USBDeviceMonitor.Event.deviceDisconnected == .deviceDisconnected)
    try expectFalse(USBDeviceMonitor.Event.deviceConnected == .deviceDisconnected)
}

test("USBDeviceMonitor debounceInterval default") {
    let monitor = USBDeviceMonitor()
    try expectTrue(abs(monitor.debounceInterval - 0.5) < 0.01)
}

test("USBDeviceMonitor debounceInterval configurable") {
    let monitor = USBDeviceMonitor()
    monitor.debounceInterval = 1.0
    try expectTrue(abs(monitor.debounceInterval - 1.0) < 0.01)
}

testOnMain("MTPManager hot-plug initial state") {
    let mgr = MTPManager()
    try expectFalse(mgr.isHotPlugEnabled)
}

testOnMain("MTPManager startHotPlug enables monitoring") {
    let mgr = MTPManager()
    mgr.startHotPlug()
    try expectTrue(mgr.isHotPlugEnabled)
    mgr.stopHotPlug()
}

testOnMain("MTPManager stopHotPlug disables monitoring") {
    let mgr = MTPManager()
    mgr.startHotPlug()
    mgr.stopHotPlug()
    try expectFalse(mgr.isHotPlugEnabled)
}

testOnMain("MTPManager double startHotPlug is safe") {
    let mgr = MTPManager()
    mgr.startHotPlug()
    mgr.startHotPlug()  // should not crash
    try expectTrue(mgr.isHotPlugEnabled)
    mgr.stopHotPlug()
}

// ─────────────────────────────────────────────────────────────────────────────
print("\n── Transfer Cancellation ──")
// ─────────────────────────────────────────────────────────────────────────────

test("MTPError.cancelled description") {
    let err = MTPError.cancelled
    try expectNotNil(err.errorDescription)
    try expectTrue(err.errorDescription!.contains("cancelled"))
}

test("MTPError.cancelled equality") {
    try expectTrue(MTPError.cancelled == MTPError.cancelled)
    try expectFalse(MTPError.cancelled == MTPError.noStorage)
}

test("MTPCancellationToken initial state") {
    let token = MTPCancellationToken()
    try expectFalse(token.isCancelled)
}

test("MTPCancellationToken cancel sets isCancelled") {
    let token = MTPCancellationToken()
    token.cancel()
    try expectTrue(token.isCancelled)
}

test("MTPCancellationToken double cancel is safe") {
    let token = MTPCancellationToken()
    token.cancel()
    token.cancel()
    try expectTrue(token.isCancelled)
}

test("MTPCancellationToken is thread-safe") {
    let token = MTPCancellationToken()
    let group = DispatchGroup()

    // Cancel from one thread, check from another
    for _ in 0..<100 {
        group.enter()
        DispatchQueue.global().async {
            _ = token.isCancelled
            group.leave()
        }
    }
    group.enter()
    DispatchQueue.global().async {
        token.cancel()
        group.leave()
    }
    group.wait()
    try expectTrue(token.isCancelled)
}

testOnMain("MTPManager cancelTransfer resets state") {
    let mgr = MTPManager()
    mgr.transferProgress = MTPManager.TransferProgress(
        fileName: "test.jpg", sent: 50, total: 100, isUploading: true
    )
    mgr.isTransferring = true
    mgr.cancelTransfer()
    try expectNil(mgr.transferProgress)
    try expectFalse(mgr.isTransferring)
}

testOnMain("MTPManager cancelTransfer when no transfer is safe") {
    let mgr = MTPManager()
    mgr.cancelTransfer()  // should not crash
    try expectFalse(mgr.isTransferring)
    try expectNil(mgr.transferProgress)
}

testOnMain("MTPManager disconnect cancels active transfer") {
    let mgr = MTPManager()
    mgr.transferProgress = MTPManager.TransferProgress(
        fileName: "test.jpg", sent: 50, total: 100, isUploading: false
    )
    mgr.isTransferring = true
    mgr.disconnect()
    try expectFalse(mgr.isTransferring)
    try expectNil(mgr.transferProgress)
}

testOnMain("MTPManager isTransferring initial state") {
    let mgr = MTPManager()
    try expectFalse(mgr.isTransferring)
}

// ─────────────────────────────────────────────────────────────────────────────
print("\n── Rename & Move ──")
// ─────────────────────────────────────────────────────────────────────────────

testOnMain("MTPManager renameFile does nothing without device") {
    let mgr = MTPManager()
    mgr.selectedDevice = nil
    let file = makeFileInfo(name: "old.txt")
    mgr.renameFile(file, newName: "new.txt")
    // Should not crash; no device means no-op
    try expectNil(mgr.errorMessage)
}

testOnMain("MTPManager renameFile does nothing without storage") {
    let mgr = MTPManager()
    mgr.selectedStorage = nil
    let file = makeFileInfo(name: "old.txt")
    mgr.renameFile(file, newName: "new.txt")
    try expectNil(mgr.errorMessage)
}

testOnMain("MTPManager moveFile does nothing without device") {
    let mgr = MTPManager()
    mgr.selectedDevice = nil
    let file = makeFileInfo(name: "photo.jpg")
    mgr.moveFile(file, toParentId: 100)
    try expectNil(mgr.errorMessage)
}

testOnMain("MTPManager moveFile does nothing without storage") {
    let mgr = MTPManager()
    mgr.selectedStorage = nil
    let file = makeFileInfo(name: "photo.jpg")
    mgr.moveFile(file, toParentId: 100)
    try expectNil(mgr.errorMessage)
}

// ============================================================================
// SUMMARY
// ============================================================================

print("\n" + String(repeating: "─", count: 60))
if failedTests.isEmpty {
    print("✅ All \(totalTests) tests passed!")
} else {
    print("❌ \(failedTests.count) of \(totalTests) tests FAILED:")
    for (name, msg) in failedTests {
        print("   • \(name): \(msg)")
    }
}
print(String(repeating: "─", count: 60))

exit(failedTests.isEmpty ? 0 : 1)
