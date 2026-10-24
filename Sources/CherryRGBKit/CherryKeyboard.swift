import Foundation
import IOKit
import IOKit.hid

public enum CherryError: Error, CustomStringConvertible {
    case notConnected
    case accessDenied
    case openFailed(IOReturn)
    case writeFailed(IOReturn)

    public var description: String {
        switch self {
        case .notConnected: "Keine Cherry-RGB-Tastatur gefunden"
        case .accessDenied: "Zugriff verweigert – Eingabeüberwachung in den Systemeinstellungen erlauben"
        case .openFailed(let r): String(format: "Gerät öffnen fehlgeschlagen (0x%08x)", r)
        case .writeFailed(let r): String(format: "Senden fehlgeschlagen (0x%08x)", r)
        }
    }
}

/// Talks to the vendor control collection (usage page 0xFF1C) of Cherry RGB keyboards.
///
/// Device matching and input reports run on a private run loop thread;
/// packets go out on a serial queue and wait for the keyboard's answer.
public final class CherryKeyboard: @unchecked Sendable {
    public static let vendorID = 0x046A
    static let usagePage = 0xFF1C
    static let ackTimeout: DispatchTimeInterval = .milliseconds(200)

    /// Called on the main queue whenever a keyboard is opened (true) or removed (false).
    public var onConnectionChange: ((Bool, String?) -> Void)?
    /// Called on the main queue when a matched keyboard could not be opened.
    public var onError: ((CherryError) -> Void)?
    public var log: (String) -> Void = { _ in }

    private let lock = NSLock()
    private let sendQueue = DispatchQueue(label: "CherryRGB.send")
    private let ack = DispatchSemaphore(value: 0)
    private var runLoop: CFRunLoop!
    private var manager: IOHIDManager!
    private var device: IOHIDDevice?
    /// Matched but not opened (e.g. Input Monitoring not yet granted).
    private var pending: [IOHIDDevice] = []
    // Lives as long as the process; IOKit writes incoming reports into it.
    private let inputBuffer = UnsafeMutablePointer<UInt8>.allocate(capacity: 64)

    public init() {
        let ready = DispatchSemaphore(value: 0)
        let thread = Thread { [unowned self] in
            self.runLoop = CFRunLoopGetCurrent()
            self.setUpManager()
            ready.signal()
            // Keep the run loop alive even without sources.
            RunLoop.current.add(NSMachPort(), forMode: .default)
            while true { RunLoop.current.run(mode: .default, before: .distantFuture) }
        }
        thread.name = "CherryRGB.HID"
        thread.start()
        ready.wait()
    }

    // MARK: - Permission

    public static var hasInputMonitoringAccess: Bool {
        IOHIDCheckAccess(kIOHIDRequestTypeListenEvent) == kIOHIDAccessTypeGranted
    }

    /// Triggers the system prompt (only the first time) and returns the current state.
    @discardableResult
    public static func requestInputMonitoringAccess() -> Bool {
        IOHIDRequestAccess(kIOHIDRequestTypeListenEvent)
    }

    // MARK: - Public API

    public var isConnected: Bool { lock.withLock { device != nil } }

    /// Retry opening keyboards that were matched earlier but could not be opened.
    public func retryPending() {
        CFRunLoopPerformBlock(runLoop, CFRunLoopMode.defaultMode.rawValue) { [self] in
            let devs = lock.withLock { let d = pending; pending = []; return d }
            devs.forEach(deviceAdded)
        }
        CFRunLoopWakeUp(runLoop)
    }

    /// Sends the packets in order, waiting for each acknowledgement.
    public func send(_ payloads: [Payload]) async throws {
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            sendQueue.async {
                cont.resume(with: Result { try self.sendSync(payloads) })
            }
        }
    }

    /// Blocking variant for the CLI.
    public func sendBlocking(_ payloads: [Payload]) throws {
        try sendQueue.sync { try sendSync(payloads) }
    }

    /// Waits until a device is opened or the timeout elapses.
    public func waitForDevice(timeout: TimeInterval) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline && !isConnected {
            Thread.sleep(forTimeInterval: 0.05)
        }
        return isConnected
    }

    // MARK: - HID thread

    private func setUpManager() {
        manager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
        let match: [String: Any] = [
            kIOHIDVendorIDKey: Self.vendorID,
            kIOHIDDeviceUsagePageKey: Self.usagePage,
        ]
        IOHIDManagerSetDeviceMatching(manager, match as CFDictionary)

        let ctx = Unmanaged.passUnretained(self).toOpaque()
        IOHIDManagerRegisterDeviceMatchingCallback(manager, { ctx, _, _, dev in
            Unmanaged<CherryKeyboard>.fromOpaque(ctx!).takeUnretainedValue().deviceAdded(dev)
        }, ctx)
        IOHIDManagerRegisterDeviceRemovalCallback(manager, { ctx, _, _, dev in
            Unmanaged<CherryKeyboard>.fromOpaque(ctx!).takeUnretainedValue().deviceRemoved(dev)
        }, ctx)
        IOHIDManagerScheduleWithRunLoop(manager, runLoop, CFRunLoopMode.defaultMode.rawValue)
        IOHIDManagerOpen(manager, IOOptionBits(kIOHIDOptionsTypeNone))
    }

    private func deviceAdded(_ dev: IOHIDDevice) {
        // A keyboard exposes exactly one vendor collection; drive the first one.
        guard !isConnected else { return }
        let rc = IOHIDDeviceOpen(dev, IOOptionBits(kIOHIDOptionsTypeNone))
        guard rc == kIOReturnSuccess else {
            let err: CherryError = rc == kIOReturnNotPermitted ? .accessDenied : .openFailed(rc)
            lock.withLock { pending.append(dev) }
            log(err.description)
            let cb = onError
            DispatchQueue.main.async { cb?(err) }
            return
        }
        let ctx = Unmanaged.passUnretained(self).toOpaque()
        IOHIDDeviceRegisterInputReportCallback(dev, inputBuffer, 64, { ctx, _, _, _, _, _, _ in
            Unmanaged<CherryKeyboard>.fromOpaque(ctx!).takeUnretainedValue().ack.signal()
        }, ctx)
        lock.withLock { device = dev }

        let name = IOHIDDeviceGetProperty(dev, kIOHIDProductKey as CFString) as? String
        let pid = IOHIDDeviceGetProperty(dev, kIOHIDProductIDKey as CFString) as? Int ?? 0
        log(String(format: "Verbunden: %@ (PID 0x%04x)", name ?? "?", pid))
        let cb = onConnectionChange
        DispatchQueue.main.async { cb?(true, name) }
    }

    private func deviceRemoved(_ dev: IOHIDDevice) {
        let wasOurs = lock.withLock {
            pending.removeAll { $0 == dev }
            guard device == dev else { return false }
            device = nil
            return true
        }
        guard wasOurs else { return }
        log("Getrennt")
        let cb = onConnectionChange
        DispatchQueue.main.async { cb?(false, nil) }
    }

    // MARK: - Send queue

    private func sendSync(_ payloads: [Payload]) throws {
        guard let device = lock.withLock({ device }) else { throw CherryError.notConnected }
        // Drop answers to earlier packets that arrived after their timeout.
        while ack.wait(timeout: .now()) == .success {}
        for payload in payloads {
            let bytes = Packet.encode(payload)
            let rc = bytes.withUnsafeBufferPointer {
                IOHIDDeviceSetReport(device, kIOHIDReportTypeOutput, CFIndex(Packet.reportID), $0.baseAddress!, $0.count)
            }
            guard rc == kIOReturnSuccess else { throw CherryError.writeFailed(rc) }
            // Not every packet is answered by every firmware; just pace on timeout.
            _ = ack.wait(timeout: .now() + Self.ackTimeout)
        }
    }
}
