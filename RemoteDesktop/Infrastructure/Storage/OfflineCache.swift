import Foundation

/// Simple JSON disk cache for offline availability (e.g. last device list).
/// Values are `Codable`; files live in the caches directory.
final class OfflineCache {
    private let directory: URL
    private let fileManager = FileManager.default

    init(namespace: String = "remotedesktop") {
        let caches = fileManager.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        directory = caches.appendingPathComponent(namespace, isDirectory: true)
        try? fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    private func url(_ key: String) -> URL { directory.appendingPathComponent("\(key).json") }

    func save<T: Encodable>(_ value: T, key: String) {
        guard let data = try? JSONEncoder().encode(value) else { return }
        try? data.write(to: url(key), options: .atomic)
    }

    func load<T: Decodable>(_ type: T.Type, key: String) -> T? {
        guard let data = try? Data(contentsOf: url(key)) else { return nil }
        return try? JSONDecoder().decode(T.self, from: data)
    }

    func remove(key: String) { try? fileManager.removeItem(at: url(key)) }
}
