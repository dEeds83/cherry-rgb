import DeskGearKit
import SwiftUI

/// State of the ASUS mouse. The mouse stores everything itself, so nothing is
/// persisted here; the editor works on a draft that is written on demand.
@MainActor
final class MouseController: ObservableObject {
    @Published private(set) var connectedName: String?
    @Published private(set) var model: AsusMouseModel?
    /// What the mouse reported last
    @Published private(set) var current: MouseState?
    /// Edited copy, written with `commit()`
    @Published var draft = MouseState()
    @Published private(set) var busy = false
    @Published private(set) var lastError: String?
    /// The 2.4 GHz dongle answers `ff aa` while the mouse sleeps.
    @Published private(set) var asleep = false

    let mouse = AsusMouse()
    private var retryTimer: Timer?
    private var powerTimer: Timer?

    var hasChanges: Bool { current != nil && draft != current }

    init() {
        mouse.connection.log = { NSLog("AsusMouse: %@", $0) }
        mouse.connection.onConnectionChange = { [weak self] info in
            guard let self else { return }
            if let info {
                connectedName = info.product
                model = AsusMouseModel.forProductID(info.productID) ?? .chakram
                Task { await self.reload() }
            } else {
                connectedName = nil
                current = nil
                stopTimers()
            }
        }
        mouse.connection.onError = { [weak self] err in self?.lastError = err.description }
    }

    func reload() async {
        guard let model, mouse.isConnected else { return }
        busy = true
        defer { busy = false }
        do {
            let s = try await mouse.readState(model)
            current = s
            draft = s
            asleep = false
            lastError = nil
            stopRetry()
            startPowerPolling()
        } catch HIDError.deviceBusy, HIDError.timeout {
            asleep = true
            startRetry()
        } catch {
            lastError = "\(error)"
        }
    }

    func commit() async {
        guard let model, let current else { return }
        busy = true
        defer { busy = false }
        do {
            try await mouse.write(draft, over: current, model: model)
            lastError = nil
        } catch HIDError.deviceBusy {
            lastError = "Maus schläft – kurz bewegen und erneut versuchen"
        } catch {
            lastError = "\(error)"
        }
        await reload()
    }

    func switchProfile(_ index: Int) async {
        guard let model else { return }
        do {
            try await mouse.switchProfile(index, model: model)
        } catch {
            lastError = "\(error)"
        }
        await reload()
    }

    func discardChanges() {
        if let current { draft = current }
    }

    // MARK: - Timers

    private func startRetry() {
        guard retryTimer == nil else { return }
        retryTimer = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] _ in
            Task { @MainActor in await self?.reload() }
        }
    }

    private func stopRetry() {
        retryTimer?.invalidate()
        retryTimer = nil
    }

    private func startPowerPolling() {
        guard powerTimer == nil else { return }
        powerTimer = Timer.scheduledTimer(withTimeInterval: 300, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self, let power = try? await self.mouse.readPower() else { return }
                self.current?.power = power
                self.draft.power = power
            }
        }
    }

    private func stopTimers() {
        stopRetry()
        powerTimer?.invalidate()
        powerTimer = nil
    }
}
