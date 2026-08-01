import XCTest
@testable import RemoteDesktop

final class TouchEngineTests: XCTestCase {
    func testMoveAppliesSensitivity() {
        let engine = TouchEngine(sensitivity: 2)
        guard case let .move(dx, dy) = engine.move(dx: 10, dy: -5) else { return XCTFail() }
        XCTAssertEqual(dx, 20)
        XCTAssertEqual(dy, -10)
    }

    func testTapDetection() {
        let engine = TouchEngine()
        XCTAssertTrue(engine.isTap(totalDX: 2, totalDY: 2))
        XCTAssertFalse(engine.isTap(totalDX: 40, totalDY: 0))
    }

    func testInputPayloadSchema() {
        XCTAssertEqual(RemoteInput.click(.right).payload["b"] as? String, "right")
        XCTAssertEqual(RemoteInput.media(.mute).payload["a"] as? String, "mute")
    }
}

final class AdaptiveBitrateTests: XCTestCase {
    func testBacksOffOnLoss() {
        var abr = AdaptiveBitrate(startKbps: 4_000)
        let after = abr.update(latencyMs: 50, lossFraction: 0.10)
        XCTAssertLessThan(after, 4_000)
    }
    func testRampsUpOnGoodNetwork() {
        var abr = AdaptiveBitrate(startKbps: 4_000)
        let after = abr.update(latencyMs: 30, lossFraction: 0.0)
        XCTAssertGreaterThanOrEqual(after, 4_000)
    }
}

final class FrameQueueTests: XCTestCase {
    func testDropsOldestBeyondCapacity() async {
        let queue = FrameQueue(capacity: 2)
        for i in 0..<5 {
            await queue.enqueue(VideoFrame(data: Data([UInt8(i)]), timestamp: Double(i), width: 0, height: 0))
        }
        let count = await queue.count
        XCTAssertEqual(count, 2)
    }
}

final class CryptoServiceTests: XCTestCase {
    func testAESGCMRoundTrip() throws {
        let service = CryptoService()
        let key = CryptoService.randomKey()
        let plaintext = Data("top secret".utf8)
        let sealed = try service.seal(plaintext, key: key)
        let opened = try service.open(sealed, key: key)
        XCTAssertEqual(opened, plaintext)
        XCTAssertNotEqual(sealed, plaintext)
    }
}
