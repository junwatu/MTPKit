// MTPUtils.swift
import Foundation

// MARK: - Path Utilities

/// Fix path slashes — ensure leading slash and clean path
public func mtpFixSlash(_ path: String) -> String {
    var p = path
    if !p.hasPrefix(MTPPathSep) {
        p = MTPPathSep + p
    }
    return cleanPath(p)
}

/// Combine parent path and filename into a full path
public func mtpGetFullPath(_ parentPath: String, _ filename: String) -> String {
    return mtpFixSlash("\(parentPath)\(MTPPathSep)\(filename)")
}

/// Clean a path string (resolve ., .., double slashes)
func cleanPath(_ path: String) -> String {
    if path.isEmpty { return "." }

    var components: [String] = []
    let isAbsolute = path.hasPrefix("/")
    let parts = path.split(separator: "/", omittingEmptySubsequences: true)

    for part in parts {
        switch part {
        case ".":
            continue
        case "..":
            if !components.isEmpty && components.last != ".." {
                components.removeLast()
            } else if !isAbsolute {
                components.append("..")
            }
        default:
            components.append(String(part))
        }
    }

    var result = components.joined(separator: "/")
    if isAbsolute { result = "/" + result }
    if result.isEmpty { return isAbsolute ? "/" : "." }
    return result
}

// MARK: - File Utilities

/// Extract file extension, with double-extension support (e.g. .tar.gz)
public func mtpFileExtension(_ filename: String, isDir: Bool) -> String {
    if isDir { return "" }

    let name = (filename as NSString).lastPathComponent
    let parts = name.split(separator: ".")
    guard parts.count > 1 else { return "" }

    if parts.count > 2 {
        let secondToLast = String(parts[parts.count - 2])
        if MTPAllowedSecondExtensions[secondToLast] != nil {
            return "\(secondToLast).\(parts.last!)"
        }
    }
    return String(parts.last!)
}

/// Check if a filename is in the disallowed list
public func mtpIsDisallowedFile(_ filename: String) -> Bool {
    MTPDisallowedFiles.contains(filename)
}

/// Calculate percentage
public func mtpPercent(_ partial: Float, _ total: Float) -> Float {
    guard total > 0 else { return 0 }
    return (partial / total) * 100
}
