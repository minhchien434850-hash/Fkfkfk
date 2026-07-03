import XCTest
@testable import RemoteDesktop

final class RetryPolicyTests: XCTestCase {
    func testDelayGrowsExponentially() {
        let policy = RetryPolicy(baseDelay: 1, maxDelay: 100, jitter: 0)
        XCTAssertEqual(policy.delay(forAttempt: 1), 1, accuracy: 0.0001)
        XCTAssertEqual(policy.delay(forAttempt: 2), 2, accuracy: 0.0001)
        XCTAssertEqual(policy.delay(forAttempt: 3), 4, accuracy: 0.0001)
    }

    func testRunSucceedsAfterRetries() async throws {
        final class Box: @unchecked Sendable { var n = 0 }
        let box = Box()
        let policy = RetryPolicy(maxAttempts: 3, baseDelay: 0.001, jitter: 0)
        let result = try await policy.run {
            box.n += 1
            if box.n < 2 { throw RemoteError.offline }
            return box.n
        }
        XCTAssertEqual(result, 2)
    }
}

final class JWTTests: XCTestCase {
    private func makeToken(_ payload: String) -> String {
        let b64 = Data(payload.utf8).base64EncodedString()
            .replacingOccurrences(of: "=", with: "")
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
        return "header.\(b64).signature"
    }
    func testDecodeAndExpiry() {
        let token = makeToken("{\"exp\":100,\"sub\":\"abc\"}")
        XCTAssertEqual(JWT.decodePayload(token)?["sub"] as? String, "abc")
        XCTAssertTrue(JWT.isExpired(token))
    }
}

final class OfflineCacheTests: XCTestCase {
    func testRoundTrip() {
        let cache = OfflineCache(namespace: "test-\(UUID().uuidString)")
        let devices = [Device(id: "1", name: "PC", os: "Windows", isOnline: true)]
        cache.save(devices, key: "devices")
        let loaded = cache.load([Device].self, key: "devices")
        XCTAssertEqual(loaded?.first?.name, "PC")
        cache.remove(key: "devices")
        XCTAssertNil(cache.load([Device].self, key: "devices"))
    }
}

final class PacketizerTests: XCTestCase {
    func testPacketizeReassemble() {
        let data = Data((0 ..< 5_000).map { UInt8($0 % 256) })
        let packets = Packetizer.packetize(data, frameId: 7)
        let depacketizer = Depacketizer()
        var result: Data?
        for packet in packets {
            if let parsed = Packetizer.parse(packet) { result = depacketizer.feed(parsed) }
        }
        XCTAssertEqual(result, data)
    }
}

final class DeviceDiscoveryIntegrationTests: XCTestCase {
    func testDiscoverUsesRepository() async throws {
        let repo = MockDeviceRepository()
        repo.devices = [Device(id: "a", name: "A", os: "Windows", isOnline: true)]
        let useCase = DiscoverDevicesUseCase(repo: repo)
        let list = try await useCase()
        XCTAssertEqual(list.count, 1)
        XCTAssertEqual(list.first?.id, "a")
    }
}
