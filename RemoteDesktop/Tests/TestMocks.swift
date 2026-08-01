import Foundation
@testable import RemoteDesktop

// Test doubles used across the suite.

final class MockAuthService: AuthServiceProtocol {
    var loginCalled = false
    func login(username: String, password: String) async throws -> (user: User, token: String) {
        loginCalled = true
        return (User(id: "1", username: username, displayName: username), "test-token")
    }
    func refresh(token: String) async throws -> String { token }
}

final class MockTokenStore: TokenStoreProtocol {
    private(set) var stored: String?
    func save(token: String) throws { stored = token }
    func load() -> String? { stored }
    func clear() { stored = nil }
}

final class MockDeviceRepository: DeviceRepositoryProtocol {
    var devices: [Device] = []
    func discover() async throws -> [Device] { devices }
    func remove(deviceId: String) async throws { devices.removeAll { $0.id == deviceId } }
}

final class MockInputService: InputServiceProtocol {
    private(set) var sent: [RemoteInput] = []
    func send(_ input: RemoteInput, to deviceId: String) async throws { sent.append(input) }
}
