// MTPLogger.swift — Unified logging for MTPKit using os.Logger
//
// Logs are viewable in Console.app (filter by subsystem "com.andromac.MTPKit")
// or via: log stream --predicate 'subsystem == "com.andromac.MTPKit"'
import Foundation
import os

/// Centralized logging for MTPKit.
///
/// Uses Apple's unified logging system (`os.Logger`) which:
/// - Persists to disk for post-mortem debugging
/// - Is viewable in Console.app or `log stream` CLI
/// - Has zero cost when not actively observed (compiled out by the OS)
/// - Supports privacy-aware formatting
///
/// Log levels:
/// - `.debug`   — Verbose operation tracing (stripped in release unless streaming)
/// - `.info`    — Normal lifecycle events (connect, browse, transfer start)
/// - `.notice`  — Notable events worth reviewing (auto-reconnect, state transitions)
/// - `.error`   — Recoverable failures (transfer failed, device error)
/// - `.fault`   — Unexpected states that indicate bugs (should never happen)
public enum MTPLog {
    private static let subsystem = "com.andromac.MTPKit"

    /// Device detection, connection, and lifecycle events
    public static let device = Logger(subsystem: subsystem, category: "device")

    /// File operations: browse, upload, download, delete, rename, move
    public static let fileOps = Logger(subsystem: subsystem, category: "fileOps")

    /// USB hot-plug monitoring and auto-connect/disconnect
    public static let hotPlug = Logger(subsystem: subsystem, category: "hotPlug")

    /// Transfer progress and cancellation
    public static let transfer = Logger(subsystem: subsystem, category: "transfer")

    /// Connection state machine transitions
    public static let state = Logger(subsystem: subsystem, category: "state")
}
