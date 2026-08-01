import XCTest
@testable import RemoteDesktop

final class AuthUseCaseTests: XCTestCase {

    func testLoginReturnsUserAndPersistsToken() async throws {
        let store = MockTokenStore()
        let sut = LoginUseCase(auth: MockAuthService(), tokens: store)

        let user = try await sut(username: "alice", password: "secret")

        XCTAssertEqual(user.username, "alice")
        XCTAssertEqual(store.load(), "test-token")
    }

    func testRefreshThrowsWhenNoToken() async {
        let store = MockTokenStore()
        let sut = RefreshTokenUseCase(auth: MockAuthService(), tokens: store)

        do { try await sut(); XCTFail("Expected unauthorized") }
        catch { XCTAssertEqual(error as? RemoteError, .unauthorized) }
    }

    func testLogoutClearsToken() throws {
        let store = MockTokenStore()
        try store.save(token: "abc")
        LogoutUseCase(tokens: store)()
        XCTAssertNil(store.load())
    }
}
