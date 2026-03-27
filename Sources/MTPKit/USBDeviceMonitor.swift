// USBDeviceMonitor.swift — USB hot-plug monitoring via IOKit
import Foundation
import IOKit
import IOKit.usb

/// Monitors USB device connect/disconnect events in real-time via IOKit notifications.
///
/// Usage with callback:
/// ```swift
/// let monitor = USBDeviceMonitor()
/// monitor.startMonitoring { event in
///     switch event {
///     case .deviceConnected:
///         print("USB device connected")
///     case .deviceDisconnected:
///         print("USB device disconnected")
///     }
/// }
/// // Later...
/// monitor.stopMonitoring()
/// ```
///
/// Usage with AsyncStream:
/// ```swift
/// let monitor = USBDeviceMonitor()
/// for await event in monitor.events() {
///     print("USB event: \(event)")
/// }
/// ```
public final class USBDeviceMonitor: @unchecked Sendable {

    // MARK: - Types

    /// USB device event types
    public enum Event: Sendable, Equatable, CustomStringConvertible {
        /// A USB device was connected
        case deviceConnected
        /// A USB device was disconnected
        case deviceDisconnected

        public var description: String {
            switch self {
            case .deviceConnected: return "deviceConnected"
            case .deviceDisconnected: return "deviceDisconnected"
            }
        }
    }

    /// Callback type for event notifications
    public typealias EventHandler = @Sendable (Event) -> Void

    // MARK: - State

    private let lock = NSLock()
    private var notificationPort: IONotificationPortRef?
    private var addedIterator: io_iterator_t = 0
    private var removedIterator: io_iterator_t = 0
    private var monitorThread: Thread?
    private var runLoopRef: CFRunLoop?
    private var handler: EventHandler?
    private var isMonitoring = false

    /// Debounce interval to coalesce rapid USB events (e.g. composite devices)
    public var debounceInterval: TimeInterval = 0.5

    private var lastConnectTime: CFAbsoluteTime = 0
    private var lastDisconnectTime: CFAbsoluteTime = 0

    public init() {}

    deinit {
        stopMonitoring()
    }

    // MARK: - Public API

    /// Whether the monitor is currently active
    public var monitoring: Bool {
        lock.lock()
        defer { lock.unlock() }
        return isMonitoring
    }

    /// Start monitoring USB device events with a callback handler.
    ///
    /// Events are delivered on a background thread. Use `DispatchQueue.main.async`
    /// or `@MainActor` to update UI.
    ///
    /// - Parameter handler: Called when a USB device is connected or disconnected.
    public func startMonitoring(handler: @escaping EventHandler) {
        lock.lock()
        guard !isMonitoring else {
            lock.unlock()
            return
        }
        self.handler = handler
        self.isMonitoring = true
        lock.unlock()

        let thread = Thread { [weak self] in
            self?.runMonitorLoop()
        }
        thread.name = "MTPKit.USBDeviceMonitor"
        thread.qualityOfService = .utility

        lock.lock()
        self.monitorThread = thread
        lock.unlock()

        thread.start()
    }

    /// Stop monitoring USB device events and release IOKit resources.
    public func stopMonitoring() {
        lock.lock()
        guard isMonitoring else {
            lock.unlock()
            return
        }
        isMonitoring = false
        let rl = runLoopRef
        lock.unlock()

        // Stop the RunLoop to exit the monitor thread
        if let rl = rl {
            CFRunLoopStop(rl)
        }

        lock.lock()
        cleanup()
        lock.unlock()
    }

    /// Returns an AsyncStream of USB device events.
    ///
    /// The stream starts monitoring on first iteration and stops when cancelled.
    ///
    /// ```swift
    /// for await event in monitor.events() {
    ///     // handle event
    /// }
    /// ```
    public func events() -> AsyncStream<Event> {
        AsyncStream { continuation in
            continuation.onTermination = { [weak self] _ in
                self?.stopMonitoring()
            }
            startMonitoring { event in
                continuation.yield(event)
            }
        }
    }

    // MARK: - Private Implementation

    private func runMonitorLoop() {
        let currentRunLoop = CFRunLoopGetCurrent()

        lock.lock()
        self.runLoopRef = currentRunLoop
        lock.unlock()

        guard let port = IONotificationPortCreate(kIOMainPortDefault) else {
            lock.lock()
            isMonitoring = false
            lock.unlock()
            return
        }

        lock.lock()
        self.notificationPort = port
        lock.unlock()

        let runLoopSource = IONotificationPortGetRunLoopSource(port).takeUnretainedValue()
        CFRunLoopAddSource(currentRunLoop, runLoopSource, .defaultMode)

        // Match any USB device
        guard let matchingAdd = IOServiceMatching(kIOUSBDeviceClassName),
              let matchingRemove = IOServiceMatching(kIOUSBDeviceClassName) else {
            lock.lock()
            isMonitoring = false
            lock.unlock()
            return
        }

        let selfPtr = Unmanaged.passUnretained(self).toOpaque()

        // Register for device connected notifications
        var addIter: io_iterator_t = 0
        let addResult = IOServiceAddMatchingNotification(
            port,
            kIOFirstMatchNotification,
            matchingAdd,
            usbDeviceConnectedCallback,
            selfPtr,
            &addIter
        )

        if addResult == KERN_SUCCESS {
            // Drain existing devices (required by IOKit to arm the notification)
            drainIterator(addIter)
            lock.lock()
            self.addedIterator = addIter
            lock.unlock()
        }

        // Register for device disconnected notifications
        var removeIter: io_iterator_t = 0
        let removeResult = IOServiceAddMatchingNotification(
            port,
            kIOTerminatedNotification,
            matchingRemove,
            usbDeviceDisconnectedCallback,
            selfPtr,
            &removeIter
        )

        if removeResult == KERN_SUCCESS {
            // Drain existing (required to arm the notification)
            drainIterator(removeIter)
            lock.lock()
            self.removedIterator = removeIter
            lock.unlock()
        }

        // Run until stopped
        CFRunLoopRun()

        // Cleanup after RunLoop exits
        CFRunLoopRemoveSource(currentRunLoop, runLoopSource, .defaultMode)
    }

    /// Drain an IOKit iterator (required to arm future notifications)
    private func drainIterator(_ iterator: io_iterator_t) {
        while case let service = IOIteratorNext(iterator), service != 0 {
            IOObjectRelease(service)
        }
    }

    fileprivate func handleConnect() {
        drainIterator(addedIterator)

        let now = CFAbsoluteTimeGetCurrent()
        guard (now - lastConnectTime) > debounceInterval else { return }
        lastConnectTime = now

        lock.lock()
        let h = handler
        lock.unlock()
        h?(.deviceConnected)
    }

    fileprivate func handleDisconnect() {
        drainIterator(removedIterator)

        let now = CFAbsoluteTimeGetCurrent()
        guard (now - lastDisconnectTime) > debounceInterval else { return }
        lastDisconnectTime = now

        lock.lock()
        let h = handler
        lock.unlock()
        h?(.deviceDisconnected)
    }

    private func cleanup() {
        if addedIterator != 0 {
            IOObjectRelease(addedIterator)
            addedIterator = 0
        }
        if removedIterator != 0 {
            IOObjectRelease(removedIterator)
            removedIterator = 0
        }
        if let port = notificationPort {
            IONotificationPortDestroy(port)
            notificationPort = nil
        }
        handler = nil
        monitorThread = nil
        runLoopRef = nil
    }
}

// MARK: - IOKit C Callbacks

/// C callback for USB device connected — trampolines to USBDeviceMonitor
private func usbDeviceConnectedCallback(
    _ refcon: UnsafeMutableRawPointer?,
    _ iterator: io_iterator_t
) {
    guard let refcon = refcon else { return }
    let monitor = Unmanaged<USBDeviceMonitor>.fromOpaque(refcon).takeUnretainedValue()
    monitor.handleConnect()
}

/// C callback for USB device disconnected — trampolines to USBDeviceMonitor
private func usbDeviceDisconnectedCallback(
    _ refcon: UnsafeMutableRawPointer?,
    _ iterator: io_iterator_t
) {
    guard let refcon = refcon else { return }
    let monitor = Unmanaged<USBDeviceMonitor>.fromOpaque(refcon).takeUnretainedValue()
    monitor.handleDisconnect()
}
