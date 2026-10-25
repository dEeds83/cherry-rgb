import Foundation
import IOKit
import IOKit.hid

public enum HIDError: Error, CustomStringConvertible, Equatable {
    case notConnected
    case accessDenied
    case openFailed(IOReturn)
    case writeFailed(IOReturn)
    case timeout
    case deviceBusy

    public var description: String {
        switch self {
        case .notConnected: "Gerät nicht verbunden"
        case .accessDenied: "Zugriff verweigert – Eingabeüberwachung in den Systemeinstellungen erlauben"
        case .openFailed(let r): String(format: "Gerät öffnen fehlgeschlagen (0x%08x)", r)
        case .writeFailed(let r): String(format: "Senden fehlgeschlagen (0x%08x)", r)
        case .timeout: "Gerät antwortet nicht"
        case .deviceBusy: "Gerät meldet Fehler (schläft oder ist nicht bereit)"
        }
    }
}

/// Watches for one HID collection matching `matching` and exchanges 64 byte
/// output/input reports with it.
///
/// Device matching and input reports run on a private run loop thread;
/// requests go out on a serial queue and wait for the next input report.
public final class HIDConnection: @unchecked Sendable {
    public struct Info: Sendable {
        public let product: String
        public let productID: Int
    }

    /// Called on the main queue whenever a device is opened (non-nil) or removed (nil).
    public var onConnectionChange: ((Info?) -> Void)?
    /// Called on the main queue when a matched device could not be opened.
    public var onError: ((HIDError) -> Void)?
    public var log: (String) -> Void = { _ in }
    /// Every input report, including unsolicited ones (called on the HID thread).
    public var onInputReport: (([UInt8]) -> Void)?

    private let matching: [String: Any]
    private let reportSize: Int
    private let lock = NSLock()
    private let sendQueue: DispatchQueue
    private let responseReady = DispatchSemaphore(value: 0)
    private var response: [UInt8] = []
    private var runLoop: CFRunLoop!
    private var manager: IOHIDManager!
    private var device: IOHIDDevice?
    /// Matched but not opened (e.g. Input Monitoring not yet granted).
    private var pending: [IOHIDDevice] = []
    // Lives as long as the process; IOKit writes incoming reports into it.
    private let inputBuffer: UnsafeMutablePointer<UInt8>

    public init(name: String, matching: [String: Any], reportSize: Int = 64) {
        self.matching = matching
        self.reportSize = reportSize
        inputBuffer = .allocate(capacity: reportSize)
        sendQueue = DispatchQueue(label: "\(name).send")
        let ready = DispatchSemaphore(value: 0)
        let thread = Thread { [unowned self] in
            self.runLoop = CFRunLoopGetCurrent()
            self.setUpManager()
            ready.signal()
            // Keep the run loop alive even without sources.
            RunLoop.current.add(NSMachPort(), forMode: .default)
            while true { RunLoop.current.run(mode: .default, before: .distantFuture) }
        }
        thread.name = "\(name).HID"
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

    /// Retry opening devices that were matched earlier but could not be opened.
    public func retryPending() {
        CFRunLoopPerformBlock(runLoop, CFRunLoopMode.defaultMode.rawValue) { [self] in
            let devs = lock.withLock { let d = pending; pending = []; return d }
            devs.forEach(deviceAdded)
        }
        CFRunLoopWakeUp(runLoop)
    }

    /// Waits until a device is opened or the timeout elapses.
    public func waitForDevice(timeout: TimeInterval) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline && !isConnected {
            Thread.sleep(forTimeInterval: 0.05)
        }
        return isConnected
    }

    /// Sends output reports in order. After each one, waits up to `timeout`
    /// for an input report and returns all answers (empty array on timeout).
    public func exchange(_ reports: [[UInt8]], reportID: UInt8, timeout: DispatchTimeInterval = .milliseconds(200)) async throws -> [[UInt8]] {
        try await withCheckedThrowingContinuation { cont in
            sendQueue.async {
                cont.resume(with: Result { try self.exchangeSync(reports, reportID: reportID, timeout: timeout) })
            }
        }
    }

    /// Blocking variant for the CLI.
    public func exchangeBlocking(_ reports: [[UInt8]], reportID: UInt8, timeout: DispatchTimeInterval = .milliseconds(200)) throws -> [[UInt8]] {
        try sendQueue.sync { try exchangeSync(reports, reportID: reportID, timeout: timeout) }
    }

    // MARK: - HID thread

    private func setUpManager() {
        manager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
        IOHIDManagerSetDeviceMatching(manager, matching as CFDictionary)

        let ctx = Unmanaged.passUnretained(self).toOpaque()
        IOHIDManagerRegisterDeviceMatchingCallback(manager, { ctx, _, _, dev in
            Unmanaged<HIDConnection>.fromOpaque(ctx!).takeUnretainedValue().deviceAdded(dev)
        }, ctx)
        IOHIDManagerRegisterDeviceRemovalCallback(manager, { ctx, _, _, dev in
            Unmanaged<HIDConnection>.fromOpaque(ctx!).takeUnretainedValue().deviceRemoved(dev)
        }, ctx)
        IOHIDManagerScheduleWithRunLoop(manager, runLoop, CFRunLoopMode.defaultMode.rawValue)
        IOHIDManagerOpen(manager, IOOptionBits(kIOHIDOptionsTypeNone))
    }

    private func deviceAdded(_ dev: IOHIDDevice) {
        // Drive the first matching collection only.
        guard !isConnected else { return }
        let rc = IOHIDDeviceOpen(dev, IOOptionBits(kIOHIDOptionsTypeNone))
        guard rc == kIOReturnSuccess else {
            let err: HIDError = rc == kIOReturnNotPermitted ? .accessDenied : .openFailed(rc)
            lock.withLock { pending.append(dev) }
            log(err.description)
            let cb = onError
            DispatchQueue.main.async { cb?(err) }
            return
        }
        let ctx = Unmanaged.passUnretained(self).toOpaque()
        IOHIDDeviceRegisterInputReportCallback(dev, inputBuffer, reportSize, { ctx, _, _, _, _, report, len in
            let me = Unmanaged<HIDConnection>.fromOpaque(ctx!).takeUnretainedValue()
            let bytes = Array(UnsafeBufferPointer(start: report, count: len))
            me.lock.withLock { me.response = bytes }
            me.responseReady.signal()
            me.onInputReport?(bytes)
        }, ctx)
        lock.withLock { device = dev }

        let info = Info(product: IOHIDDeviceGetProperty(dev, kIOHIDProductKey as CFString) as? String ?? "?",
                        productID: IOHIDDeviceGetProperty(dev, kIOHIDProductIDKey as CFString) as? Int ?? 0)
        log(String(format: "Verbunden: %@ (PID 0x%04x)", info.product, info.productID))
        let cb = onConnectionChange
        DispatchQueue.main.async { cb?(info) }
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
        DispatchQueue.main.async { cb?(nil) }
    }

    // MARK: - Send queue

    private func exchangeSync(_ reports: [[UInt8]], reportID: UInt8, timeout: DispatchTimeInterval) throws -> [[UInt8]] {
        guard let device = lock.withLock({ device }) else { throw HIDError.notConnected }
        // Drop answers to earlier requests that arrived after their timeout.
        while responseReady.wait(timeout: .now()) == .success {}
        var answers: [[UInt8]] = []
        for report in reports {
            let rc = report.withUnsafeBufferPointer {
                IOHIDDeviceSetReport(device, kIOHIDReportTypeOutput, CFIndex(reportID), $0.baseAddress!, $0.count)
            }
            guard rc == kIOReturnSuccess else { throw HIDError.writeFailed(rc) }
            if responseReady.wait(timeout: .now() + timeout) == .success {
                answers.append(lock.withLock { response })
            }
        }
        return answers
    }
}
