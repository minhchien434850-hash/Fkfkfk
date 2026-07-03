import Foundation

/// Splits large frames into MTU-sized packets and reassembles them.
/// Wire header (little-endian): [frameId: UInt32][seq: UInt16][count: UInt16].
enum Packetizer {
    static let headerSize = 8
    static let maxPayload = 1_200   // conservative UDP-safe payload

    struct Packet { let frameId: UInt32; let seq: UInt16; let count: UInt16; let payload: Data }

    static func packetize(_ data: Data, frameId: UInt32) -> [Data] {
        let chunks = stride(from: 0, to: data.count, by: maxPayload).map {
            data.subdata(in: $0 ..< min($0 + maxPayload, data.count))
        }
        let count = UInt16(max(1, chunks.count))
        return chunks.enumerated().map { idx, chunk in
            var out = Data(capacity: headerSize + chunk.count)
            out.appendLE(frameId)
            out.appendLE(UInt16(idx))
            out.appendLE(count)
            out.append(chunk)
            return out
        }
    }

    static func parse(_ packet: Data) -> Packet? {
        guard packet.count >= headerSize else { return nil }
        let frameId = packet.readLE(at: 0) as UInt32
        let seq = packet.readLE(at: 4) as UInt16
        let count = packet.readLE(at: 6) as UInt16
        return Packet(frameId: frameId, seq: seq, count: count,
                      payload: packet.subdata(in: headerSize ..< packet.count))
    }
}

/// Reassembles packets belonging to the same frame id.
final class Depacketizer {
    private var buckets: [UInt32: [UInt16: Data]] = [:]

    func feed(_ packet: Packetizer.Packet) -> Data? {
        buckets[packet.frameId, default: [:]][packet.seq] = packet.payload
        guard let parts = buckets[packet.frameId], parts.count == Int(packet.count) else { return nil }
        buckets[packet.frameId] = nil
        return (0 ..< Int(packet.count)).reduce(into: Data()) { acc, i in
            if let p = parts[UInt16(i)] { acc.append(p) }
        }
    }
}

// Little-endian helpers.
private extension Data {
    mutating func appendLE<T: FixedWidthInteger>(_ value: T) {
        var v = value.littleEndian
        Swift.withUnsafeBytes(of: &v) { append(contentsOf: $0) }
    }
    func readLE<T: FixedWidthInteger>(at offset: Int) -> T {
        subdata(in: offset ..< offset + MemoryLayout<T>.size)
            .withUnsafeBytes { $0.loadUnaligned(as: T.self).littleEndian }
    }
}
