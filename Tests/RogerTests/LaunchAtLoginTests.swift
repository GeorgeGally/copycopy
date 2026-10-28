import Foundation
import Testing
@testable import RogerCore

@Suite(.serialized)
@MainActor
struct LaunchAtLoginTests {
    private final class FakeLoginItem: LoginItemService {
        var state: LaunchAtLoginState
        var registers = 0
        var unregisters = 0

        init(state: LaunchAtLoginState = .off) {
            self.state = state
        }

        func register() throws {
            registers += 1
            state = .on
        }

        func unregister() throws {
            unregisters += 1
            state = .off
        }
    }

    private func scratchDefaults() throws -> (defaults: UserDefaults, name: String) {
        let name = "RogerTests-\(UUID().uuidString)"
        return (try #require(UserDefaults(suiteName: name)), name)
    }

    @Test func firstLaunchAddsRogerToLoginItemsOnce() throws {
        let (defaults, name) = try scratchDefaults()
        defer { defaults.removePersistentDomain(forName: name) }
        let item = FakeLoginItem()
        let login = LaunchAtLogin(item: item, defaults: defaults)
        login.registerOnLaunch()
        #expect(item.registers == 1)
        #expect(login.state == .on)
        login.registerOnLaunch()
        #expect(item.registers == 1)
    }

    @Test func aUserWhoTurnsItOffIsNeverRegisteredAgain() throws {
        let (defaults, name) = try scratchDefaults()
        defer { defaults.removePersistentDomain(forName: name) }
        let item = FakeLoginItem(state: .on)
        let login = LaunchAtLogin(item: item, defaults: defaults)
        login.turnOff()
        #expect(item.unregisters == 1)
        #expect(login.wasTurnedOff)
        login.registerOnLaunch()
        #expect(item.registers == 0)
        #expect(defaults.bool(forKey: LaunchAtLogin.turnedOffKey))
    }

    @Test func turningItBackOnClearsTheOptOut() throws {
        let (defaults, name) = try scratchDefaults()
        defer { defaults.removePersistentDomain(forName: name) }
        let item = FakeLoginItem(state: .on)
        let login = LaunchAtLogin(item: item, defaults: defaults)
        login.turnOff()
        login.turnOn()
        #expect(item.registers == 1)
        #expect(!login.wasTurnedOff)
        #expect(login.isOn)
    }

    /// Removing Roger in System Settings leaves it off; Roger does not put
    /// itself back on the next launch.
    @Test func removingItInSystemSettingsIsNotUndone() throws {
        let (defaults, name) = try scratchDefaults()
        defer { defaults.removePersistentDomain(forName: name) }
        let item = FakeLoginItem()
        let login = LaunchAtLogin(item: item, defaults: defaults)
        login.registerOnLaunch()
        #expect(item.registers == 1)
        item.state = .off
        login.registerOnLaunch()
        #expect(item.registers == 1)
    }

    @Test func pendingApprovalCountsAsWanted() throws {
        let (defaults, name) = try scratchDefaults()
        defer { defaults.removePersistentDomain(forName: name) }
        let item = FakeLoginItem(state: .needsApproval)
        let login = LaunchAtLogin(item: item, defaults: defaults)
        #expect(login.isOn)
        login.registerOnLaunch()
        #expect(item.registers == 0)
        #expect(item.state == .needsApproval)
    }

    @Test func turningOffSomethingNeverRegisteredStillRemembers() throws {
        let (defaults, name) = try scratchDefaults()
        defer { defaults.removePersistentDomain(forName: name) }
        let item = FakeLoginItem(state: .off)
        let login = LaunchAtLogin(item: item, defaults: defaults)
        login.turnOff()
        #expect(item.unregisters == 0)
        login.registerOnLaunch()
        #expect(item.registers == 0)
    }

    @Test func aFailedRegisterIsTriedAgainNextLaunch() throws {
        let (defaults, name) = try scratchDefaults()
        defer { defaults.removePersistentDomain(forName: name) }
        let item = FailingLoginItem()
        let login = LaunchAtLogin(item: item, defaults: defaults)
        login.registerOnLaunch()
        #expect(item.attempts == 1)
        login.registerOnLaunch()
        #expect(item.attempts == 2)
        #expect(!defaults.bool(forKey: LaunchAtLogin.askedKey))
    }

    private final class FailingLoginItem: LoginItemService {
        var state: LaunchAtLoginState = .off
        var attempts = 0

        struct Refused: Error {}

        func register() throws {
            attempts += 1
            throw Refused()
        }

        func unregister() throws {}
    }
}
