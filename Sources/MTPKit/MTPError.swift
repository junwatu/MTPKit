// MTPError.swift
import Foundation
import CLibMTP

/// MTP error types
public enum MTPError: Error, LocalizedError, Equatable {
    case detectFailed(String)
    case storageInfoError(String)
    case noStorage
    case localFileError(String)
    case invalidPath(String)
    case fileTransferError(String)
    case sendObjectError(String)
    case noDevicesFound
    case deviceOpenFailed(String)
    case cancelled

    public var errorDescription: String? {
        switch self {
        case .detectFailed(let msg): return "MTP detect failed: \(msg)"
        case .storageInfoError(let msg): return "Storage info error: \(msg)"
        case .noStorage: return "No storage found on device"
        case .localFileError(let msg): return "Local file error: \(msg)"
        case .invalidPath(let msg): return "Invalid path: \(msg)"
        case .fileTransferError(let msg): return "File transfer error: \(msg)"
        case .sendObjectError(let msg): return "Send object error: \(msg)"
        case .noDevicesFound:
            return "No MTP devices found. Make sure your Android device is connected via USB and set to 'File transfer / MTP' mode."
        case .deviceOpenFailed(let msg): return "Failed to open device: \(msg)"
        case .cancelled: return "Transfer cancelled"
        }
    }
}

/// Drain the libmtp error stack into a Swift string
public func drainErrorStack(_ device: UnsafeMutablePointer<LIBMTP_mtpdevice_t>) -> String? {
    var errors: [String] = []
    var err = LIBMTP_Get_Errorstack(device)
    while let e = err {
        if let text = e.pointee.error_text {
            errors.append(String(cString: text))
        }
        err = e.pointee.next
    }
    LIBMTP_Clear_Errorstack(device)
    return errors.isEmpty ? nil : errors.joined(separator: "; ")
}
