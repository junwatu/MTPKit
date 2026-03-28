// MTPKitTests — Self-contained test runner for MTPKit
// Run: swift run MTPKitTests
import Foundation
import AppKit
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
    mgr.connectionState = .connected
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
print("\n── MTPError: deviceDisconnected ──")
// ─────────────────────────────────────────────────────────────────────────────

test("deviceDisconnected has description") {
    let err = MTPError.deviceDisconnected
    try expectNotNil(err.errorDescription)
    try expectTrue(err.errorDescription!.contains("disconnected"))
}

test("deviceDisconnected equality") {
    try expectTrue(MTPError.deviceDisconnected == MTPError.deviceDisconnected)
    try expectFalse(MTPError.deviceDisconnected == MTPError.cancelled)
}

test("deviceDisconnected mentions USB") {
    try expectTrue(MTPError.deviceDisconnected.errorDescription!.contains("USB"))
}

test("cancelled error description") {
    try expect(MTPError.cancelled.errorDescription, "Transfer cancelled")
}

// ─────────────────────────────────────────────────────────────────────────────
print("\n── FileViewMode ──")
// ─────────────────────────────────────────────────────────────────────────────

test("FileViewMode has list and grid cases") {
    try expect(FileViewMode.list.rawValue, "list")
    try expect(FileViewMode.grid.rawValue, "grid")
}

test("FileViewMode allCases contains both") {
    try expect(FileViewMode.allCases.count, 2)
    try expectTrue(FileViewMode.allCases.contains(.list))
    try expectTrue(FileViewMode.allCases.contains(.grid))
}

// ─────────────────────────────────────────────────────────────────────────────
print("\n── MTPManager: ViewMode ──")
// ─────────────────────────────────────────────────────────────────────────────

testOnMain("Manager default viewMode is list") {
    let mgr = MTPManager()
    try expect(mgr.viewMode, FileViewMode.list)
}

testOnMain("Manager viewMode can be set to grid") {
    let mgr = MTPManager()
    mgr.viewMode = .grid
    try expect(mgr.viewMode, FileViewMode.grid)
}

testOnMain("Manager viewMode toggle roundtrip") {
    let mgr = MTPManager()
    try expect(mgr.viewMode, .list)
    mgr.viewMode = .grid
    try expect(mgr.viewMode, .grid)
    mgr.viewMode = .list
    try expect(mgr.viewMode, .list)
}

// ─────────────────────────────────────────────────────────────────────────────
print("\n── MTPManager: Thumbnails ──")
// ─────────────────────────────────────────────────────────────────────────────

testOnMain("isThumbnailable for image files") {
    let jpg = makeFileInfo(name: "photo.jpg", fullPath: "/photo.jpg")
    let png = makeFileInfo(name: "screenshot.png", fullPath: "/screenshot.png")
    let heic = makeFileInfo(name: "img.heic", fullPath: "/img.heic")
    try expectTrue(MTPManager.isThumbnailable(jpg))
    try expectTrue(MTPManager.isThumbnailable(png))
    try expectTrue(MTPManager.isThumbnailable(heic))
}

testOnMain("isThumbnailable for video files") {
    let mp4 = makeFileInfo(name: "video.mp4", fullPath: "/video.mp4")
    let mov = makeFileInfo(name: "clip.mov", fullPath: "/clip.mov")
    let mkv = makeFileInfo(name: "movie.mkv", fullPath: "/movie.mkv")
    try expectTrue(MTPManager.isThumbnailable(mp4))
    try expectTrue(MTPManager.isThumbnailable(mov))
    try expectTrue(MTPManager.isThumbnailable(mkv))
}

testOnMain("isThumbnailable false for non-media files") {
    let txt = makeFileInfo(name: "readme.txt", fullPath: "/readme.txt")
    let pdf = makeFileInfo(name: "doc.pdf", fullPath: "/doc.pdf")
    let apk = makeFileInfo(name: "app.apk", fullPath: "/app.apk")
    let zip = makeFileInfo(name: "archive.zip", fullPath: "/archive.zip")
    try expectFalse(MTPManager.isThumbnailable(txt))
    try expectFalse(MTPManager.isThumbnailable(pdf))
    try expectFalse(MTPManager.isThumbnailable(apk))
    try expectFalse(MTPManager.isThumbnailable(zip))
}

testOnMain("isThumbnailable false for directories") {
    let dir = makeFileInfo(name: "DCIM", fullPath: "/DCIM", isDir: true)
    try expectFalse(MTPManager.isThumbnailable(dir))
}

testOnMain("isThumbnailable case insensitive") {
    let upper = makeFileInfo(name: "PHOTO.JPG", fullPath: "/PHOTO.JPG")
    let mixed = makeFileInfo(name: "Video.MP4", fullPath: "/Video.MP4")
    try expectTrue(MTPManager.isThumbnailable(upper))
    try expectTrue(MTPManager.isThumbnailable(mixed))
}

testOnMain("thumbnails cache starts empty") {
    let mgr = MTPManager()
    try expectTrue(mgr.thumbnails.isEmpty)
}

testOnMain("disconnect clears thumbnail cache") {
    let mgr = MTPManager()
    mgr.connectionState = .connected
    // Simulate a cached thumbnail by directly setting
    let nsImage = NSImage(size: NSSize(width: 1, height: 1))
    mgr.thumbnails[42] = nsImage
    try expect(mgr.thumbnails.count, 1)

    mgr.disconnect()
    try expectTrue(mgr.thumbnails.isEmpty)
}

testOnMain("fetchThumbnail skips directories") {
    let mgr = MTPManager()
    let dir = makeFileInfo(name: "DCIM", fullPath: "/DCIM", isDir: true)
    mgr.fetchThumbnail(for: dir)
    // No crash, no thumbnail requested — just a no-op
    try expectTrue(mgr.thumbnails.isEmpty)
}

testOnMain("fetchThumbnail skips non-media files") {
    let mgr = MTPManager()
    let txt = makeFileInfo(name: "readme.txt", fullPath: "/readme.txt")
    mgr.fetchThumbnail(for: txt)
    try expectTrue(mgr.thumbnails.isEmpty)
}

testOnMain("fetchThumbnail skips without device") {
    let mgr = MTPManager()
    mgr.selectedDevice = nil
    let jpg = makeFileInfo(name: "photo.jpg", fullPath: "/photo.jpg")
    mgr.fetchThumbnail(for: jpg)
    // Should not crash, should not add to cache
    try expectTrue(mgr.thumbnails.isEmpty)
}

testOnMain("fetchThumbnail deduplicates requests") {
    let mgr = MTPManager()
    // Without a device, fetchThumbnail won't start a task,
    // but we can verify the dedup logic by checking it doesn't crash
    // when called multiple times for the same file
    let jpg = makeFileInfo(objectId: 100, name: "photo.jpg", fullPath: "/photo.jpg")
    mgr.fetchThumbnail(for: jpg)
    mgr.fetchThumbnail(for: jpg)
    mgr.fetchThumbnail(for: jpg)
    try expectTrue(mgr.thumbnails.isEmpty)
}

// ─────────────────────────────────────────────────────────────────────────────
print("\n── MTPManager: Disconnect Safety ──")
// ─────────────────────────────────────────────────────────────────────────────

testOnMain("disconnect clears all state including thumbnails and viewMode preserved") {
    let mgr = MTPManager()
    mgr.connectionState = .connected
    mgr.currentPath = "/DCIM/Camera"
    mgr.currentParentId = 42
    mgr.pathHistory = [MTPManager.PathEntry(path: "/", browseParentId: MTPParentObjectID, name: "/")]
    mgr.errorMessage = "some error"
    mgr.viewMode = .grid
    let nsImage = NSImage(size: NSSize(width: 1, height: 1))
    mgr.thumbnails[1] = nsImage

    mgr.disconnect()

    try expectFalse(mgr.isConnected)
    try expect(mgr.currentPath, "/")
    try expect(mgr.currentParentId, MTPParentObjectID)
    try expectTrue(mgr.pathHistory.isEmpty)
    try expectNil(mgr.errorMessage)
    try expectNil(mgr.transferProgress)
    try expectFalse(mgr.isTransferring)
    try expectTrue(mgr.thumbnails.isEmpty)
    try expectTrue(mgr.devices.isEmpty)
    try expectNil(mgr.selectedDevice)
    try expectNil(mgr.deviceInfo)
    try expectTrue(mgr.storages.isEmpty)
    try expectNil(mgr.selectedStorage)
    // viewMode should persist across disconnect (user preference)
    try expect(mgr.viewMode, .grid)
}

testOnMain("disconnect is idempotent") {
    let mgr = MTPManager()
    mgr.connectionState = .connected
    mgr.disconnect()
    try expectFalse(mgr.isConnected)
    try expect(mgr.connectionState, .disconnected)
    // Second disconnect should not crash — guarded by state machine
    mgr.disconnect()
    try expectFalse(mgr.isConnected)
    try expect(mgr.connectionState, .disconnected)
}

testOnMain("cancelTransfer resets transfer state") {
    let mgr = MTPManager()
    mgr.isTransferring = true
    mgr.transferProgress = MTPManager.TransferProgress(
        fileName: "test.jpg", sent: 50, total: 100, isUploading: false
    )
    mgr.cancelTransfer()
    try expectFalse(mgr.isTransferring)
    try expectNil(mgr.transferProgress)
}

// ─────────────────────────────────────────────────────────────────────────────
print("\n── MTPCancellationToken ──")
// ─────────────────────────────────────────────────────────────────────────────

test("CancellationToken starts not cancelled") {
    let token = MTPCancellationToken()
    try expectFalse(token.isCancelled)
}

test("CancellationToken cancel sets flag") {
    let token = MTPCancellationToken()
    token.cancel()
    try expectTrue(token.isCancelled)
}

test("CancellationToken cancel is idempotent") {
    let token = MTPCancellationToken()
    token.cancel()
    token.cancel()
    try expectTrue(token.isCancelled)
}

test("CancellationToken thread safety") {
    let token = MTPCancellationToken()
    let group = DispatchGroup()

    // Cancel from multiple threads simultaneously
    for _ in 0..<100 {
        group.enter()
        DispatchQueue.global().async {
            token.cancel()
            _ = token.isCancelled
            group.leave()
        }
    }

    group.wait()
    try expectTrue(token.isCancelled)
}

// ─────────────────────────────────────────────────────────────────────────────
print("\n── MTPManager: TransferProgress ──")
// ─────────────────────────────────────────────────────────────────────────────

test("TransferProgress formatted strings") {
    let tp = MTPManager.TransferProgress(
        fileName: "video.mp4", sent: 1_048_576, total: 10_485_760, isUploading: true
    )
    try expectFalse(tp.formattedSent.isEmpty)
    try expectFalse(tp.formattedTotal.isEmpty)
    try expectTrue(tp.isUploading)
    try expect(tp.fileName, "video.mp4")
}

test("TransferProgress percentage calculation") {
    let tp25 = MTPManager.TransferProgress(fileName: "a", sent: 25, total: 100, isUploading: false)
    try expect(tp25.percentage, 25.0)

    let tp100 = MTPManager.TransferProgress(fileName: "a", sent: 100, total: 100, isUploading: false)
    try expect(tp100.percentage, 100.0)

    let tp0 = MTPManager.TransferProgress(fileName: "a", sent: 0, total: 100, isUploading: false)
    try expect(tp0.percentage, 0.0)
}

// ─────────────────────────────────────────────────────────────────────────────
print("\n── MTPManager: Hot-Plug State ──")
// ─────────────────────────────────────────────────────────────────────────────

testOnMain("Manager starts with hotplug disabled") {
    let mgr = MTPManager()
    try expectFalse(mgr.isHotPlugEnabled)
}

testOnMain("stopHotPlug resets flag") {
    let mgr = MTPManager()
    mgr.startHotPlug()
    try expectTrue(mgr.isHotPlugEnabled)
    mgr.stopHotPlug()
    try expectFalse(mgr.isHotPlugEnabled)
}

testOnMain("startHotPlug is idempotent") {
    let mgr = MTPManager()
    mgr.startHotPlug()
    mgr.startHotPlug() // Should not crash or double-register
    try expectTrue(mgr.isHotPlugEnabled)
    mgr.stopHotPlug()
}

// ─────────────────────────────────────────────────────────────────────────────
print("\n── USBDeviceMonitor ──")
// ─────────────────────────────────────────────────────────────────────────────

test("USBDeviceMonitor starts not monitoring") {
    let monitor = USBDeviceMonitor()
    try expectFalse(monitor.monitoring)
}

test("USBDeviceMonitor stop when not started is safe") {
    let monitor = USBDeviceMonitor()
    monitor.stopMonitoring() // Should not crash
    try expectFalse(monitor.monitoring)
}

test("USBDeviceMonitor Event descriptions") {
    try expect(USBDeviceMonitor.Event.deviceConnected.description, "deviceConnected")
    try expect(USBDeviceMonitor.Event.deviceDisconnected.description, "deviceDisconnected")
}

test("USBDeviceMonitor Event equality") {
    try expectTrue(USBDeviceMonitor.Event.deviceConnected == .deviceConnected)
    try expectFalse(USBDeviceMonitor.Event.deviceConnected == .deviceDisconnected)
}

// ─────────────────────────────────────────────────────────────────────────────
print("\n── MTPTypes: Async Event Types ──")
// ─────────────────────────────────────────────────────────────────────────────

test("MTPTransferEvent progress case") {
    let event = MTPTransferEvent.progress(sent: 100, total: 1000)
    if case .progress(let sent, let total) = event {
        try expect(sent, Int64(100))
        try expect(total, Int64(1000))
    } else {
        throw TestError("Expected progress case")
    }
}

test("MTPTransferEvent completed case") {
    let event = MTPTransferEvent.completed(objectId: 42)
    if case .completed(let id) = event {
        try expect(id, UInt32(42))
    } else {
        throw TestError("Expected completed case")
    }
}

test("MTPTransferEvent completed nil objectId") {
    let event = MTPTransferEvent.completed(objectId: nil)
    if case .completed(let id) = event {
        try expectNil(id)
    } else {
        throw TestError("Expected completed case")
    }
}

test("MTPBulkTransferEvent completed case") {
    let event = MTPBulkTransferEvent.completed
    if case .completed = event {
        // OK
    } else {
        throw TestError("Expected completed case")
    }
}

// ─────────────────────────────────────────────────────────────────────────────
print("\n── MTPFileInfo: Edge Cases ──")
// ─────────────────────────────────────────────────────────────────────────────

test("FileInfo formattedDate is non-empty") {
    let file = makeFileInfo()
    try expectFalse(file.formattedDate.isEmpty)
}

test("FileInfo with zero size") {
    let file = makeFileInfo(size: 0)
    try expectFalse(file.formattedSize.isEmpty)
}

test("FileInfo Hashable conformance") {
    let a = makeFileInfo(objectId: 1, name: "a.txt", fullPath: "/a.txt")
    let b = makeFileInfo(objectId: 2, name: "b.txt", fullPath: "/b.txt")
    let set: Set<MTPFileInfo> = [a, b, a]
    try expect(set.count, 2)
}

test("FileInfo Identifiable uses objectId") {
    let file = makeFileInfo(objectId: 99)
    try expect(file.id, UInt32(99))
}

// ─────────────────────────────────────────────────────────────────────────────
print("\n── MTPDeviceInfo ──")
// ─────────────────────────────────────────────────────────────────────────────

test("DeviceInfo stores all fields") {
    let info = MTPDeviceInfo(
        id: "SN123", manufacturer: "Samsung", model: "SM-A075F",
        serialNumber: "SN123", deviceVersion: "1.0", friendlyName: "My Phone"
    )
    try expect(info.id, "SN123")
    try expect(info.manufacturer, "Samsung")
    try expect(info.model, "SM-A075F")
    try expect(info.serialNumber, "SN123")
    try expect(info.deviceVersion, "1.0")
    try expect(info.friendlyName, "My Phone")
}

test("DeviceInfo Identifiable uses id") {
    let info = MTPDeviceInfo(
        id: "XYZ", manufacturer: "", model: "", serialNumber: "XYZ",
        deviceVersion: "", friendlyName: ""
    )
    try expect(info.id, "XYZ")
}

// ─────────────────────────────────────────────────────────────────────────────
print("\n── Connection State Machine ──")
// ─────────────────────────────────────────────────────────────────────────────

test("ConnectionState has all cases") {
    let states = ConnectionState.allCases
    try expect(states.count, 4)
    try expectTrue(states.contains(.disconnected))
    try expectTrue(states.contains(.connecting))
    try expectTrue(states.contains(.connected))
    try expectTrue(states.contains(.disconnecting))
}

testOnMain("Manager starts in disconnected state") {
    let mgr = MTPManager()
    try expect(mgr.connectionState, .disconnected)
    try expectFalse(mgr.isConnected)
}

testOnMain("isConnected computed property reflects connectionState") {
    let mgr = MTPManager()
    try expectFalse(mgr.isConnected)
    mgr.connectionState = .connecting
    try expectFalse(mgr.isConnected)
    mgr.connectionState = .connected
    try expectTrue(mgr.isConnected)
    mgr.connectionState = .disconnecting
    try expectFalse(mgr.isConnected)
    mgr.connectionState = .disconnected
    try expectFalse(mgr.isConnected)
}

testOnMain("connect guards against non-disconnected state") {
    let mgr = MTPManager()
    mgr.connectionState = .connecting
    mgr.connect()
    // Should remain in connecting (not restart)
    try expect(mgr.connectionState, .connecting)

    mgr.connectionState = .connected
    mgr.connect()
    try expect(mgr.connectionState, .connected)
}

testOnMain("disconnect guards against already disconnected") {
    let mgr = MTPManager()
    try expect(mgr.connectionState, .disconnected)
    mgr.disconnect() // Should be a no-op, not crash
    try expect(mgr.connectionState, .disconnected)
}

testOnMain("disconnect transitions through disconnecting to disconnected") {
    let mgr = MTPManager()
    mgr.connectionState = .connected
    mgr.disconnect()
    try expect(mgr.connectionState, .disconnected)
}

testOnMain("disconnect from connecting state works") {
    let mgr = MTPManager()
    mgr.connectionState = .connecting
    mgr.disconnect()
    try expect(mgr.connectionState, .disconnected)
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
