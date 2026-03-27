// MTPConstants.swift
import Foundation
import CLibMTP

/// Root parent object ID (0xFFFFFFFF)
public let MTPParentObjectID: UInt32 = 0xFFFFFFFF

/// Path separator
public let MTPPathSep = "/"

/// Files to skip during transfers
public let MTPDisallowedFiles: [String] = [".DS_Store"]

/// Allowed double extensions (e.g. .tar.gz)
public let MTPAllowedSecondExtensions: [String: String] = ["tar": "tar"]
