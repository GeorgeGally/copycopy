import Foundation
import ServiceManagement

enum LaunchAtLoginState: Equatable {
    case on
    case needsApproval
    case off
}

protocol LoginItemService {
    var state: LaunchAtLoginState { get }
    func register() throws
    func unregister() throws
}

struct SystemLoginItem: LoginItemService {
    /// macOS reports notFound for an app that has never registered itself, so
    /// both that and notRegistered mean off and worth a first register.
    var state: LaunchAtLoginState {
        switch SMAppService.mainApp.status {
        case .enabled: return .on
        case .requiresApproval: return .needsApproval
        default: return .off
        }
    }

    func register() throws { try SMAppService.mainApp.register() }
    func unregister() throws { try SMAppService.mainApp.unregister() }
}

/// Roger puts itself in Login Items on its first launch, once. A user who
/// turns it off here, or who removes it in System Settings, is not fought:
/// Roger never adds itself back.
final class LaunchAtLogin {
    static let askedKey = "openAtLoginAsked"
    static let turnedOffKey = "openAtLoginTurnedOff"
    static let settingsURL = URL(string: "x-apple.systempreferences:com.apple.LoginItems-Settings.extension")

    private let item: LoginItemService
    private let defaults: UserDefaults

    init(item: LoginItemService = SystemLoginItem(), defaults: UserDefaults = .standard) {
        self.item = item
        self.defaults = defaults
    }

    var state: LaunchAtLoginState { item.state }

    /// Pending approval still counts as wanted: macOS has the entry, it is
    /// only switched off until the user allows it.
    var isOn: Bool { state == .on || state == .needsApproval }

    var wasTurnedOff: Bool { defaults.bool(forKey: Self.turnedOffKey) }

    func registerOnLaunch() {
        guard !wasTurnedOff, !defaults.bool(forKey: Self.askedKey) else { return }
        if state == .off { register() }
        // A failed register is retried on the next launch; a success is asked once.
        if state != .off { defaults.set(true, forKey: Self.askedKey) }
    }

    func turnOn() {
        defaults.removeObject(forKey: Self.turnedOffKey)
        guard state == .off else { return }
        if register() { defaults.set(true, forKey: Self.askedKey) }
    }

    func turnOff() {
        defaults.set(true, forKey: Self.turnedOffKey)
        guard isOn else { return }
        do {
            try item.unregister()
        } catch {
            NSLog("Roger could not leave Login Items: %@", error.localizedDescription)
        }
    }

    @discardableResult
    private func register() -> Bool {
        do {
            try item.register()
            return true
        } catch {
            NSLog("Roger could not add itself to Login Items: %@", error.localizedDescription)
            return false
        }
    }
}
