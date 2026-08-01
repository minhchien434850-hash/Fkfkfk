import Foundation
import os

/// Central structured logger built on `os.Logger` with severity levels and
/// subsystem/category routing. Also keeps a small in-memory breadcrumb ring for
/// crash reports and the diagnostics screen.
final class AppLog: @unchecked Sendable {
    static let shared = AppLog()

    enum Level: String { case debug, info, warning, error }

    private let subsystem = Bundle.main.bundleIdentifier ?? "com.kenios.remotedesktop"
    private let lock = NSLock()
    private var breadcrumbs: [String] = []
    private let maxBreadcrumbs = 200

    private func logger(_ category: String) -> Logger { Logger(subsystem: subsystem, category: category) }

    func log(_ level: Level, _ message: String, category: String = "app") {
        let line = "[\(level.rawValue.uppercased())] \(message)"
        lock.lock(); breadcrumbs.append(line)
        if breadcrumbs.count > maxBreadcrumbs { breadcrumbs.removeFirst(breadcrumbs.count - maxBreadcrumbs) }
        lock.unlock()
        let l = logger(category)
        switch level {
        case .debug:   l.debug("\(message, privacy: .public)")
        case .info:    l.info("\(message, privacy: .public)")
        case .warning: l.warning("\(message, privacy: .public)")
        case .error:   l.error("\(message, privacy: .public)")
        }
    }

    func debug(_ m: String, category: String = "app") { log(.debug, m, category: category) }
    func info(_ m: String, category: String = "app") { log(.info, m, category: category) }
    func warning(_ m: String, category: String = "app") { log(.warning, m, category: category) }
    func error(_ m: String, category: String = "app") { log(.error, m, category: category) }

    func recentBreadcrumbs() -> [String] {
        lock.lock(); defer { lock.unlock() }; return breadcrumbs
    }
}
