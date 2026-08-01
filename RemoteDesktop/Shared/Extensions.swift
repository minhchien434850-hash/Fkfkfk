import Foundation

// MARK: - Small, dependency-free helpers shared across layers.

extension Data {
    /// Lowercase hex string.
    var hexString: String { map { String(format: "%02x", $0) }.joined() }

    /// Init from a hex string (nil on malformed input).
    init?(hexString: String) {
        let chars = Array(hexString)
        guard chars.count % 2 == 0 else { return nil }
        var bytes = [UInt8]()
        bytes.reserveCapacity(chars.count / 2)
        var i = 0
        while i < chars.count {
            guard let b = UInt8(String(chars[i ... i + 1]), radix: 16) else { return nil }
            bytes.append(b); i += 2
        }
        self = Data(bytes)
    }
}

extension Task where Success == Never, Failure == Never {
    /// Sleep for a number of seconds (ignores cancellation errors).
    static func sleep(seconds: Double) async {
        try? await Task<Never, Never>.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
    }
}

extension Double {
    /// Clamp helper.
    func clamped(_ lo: Double, _ hi: Double) -> Double { Swift.min(Swift.max(self, lo), hi) }
}
