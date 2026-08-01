import Foundation

/// Captures uncaught Objective-C exceptions and persists a crash report with
/// the latest log breadcrumbs. Signal-based crashes need a dedicated reporter;
/// this covers the NSException path and is the integration point for one.
final class CrashLogger {
    static let shared = CrashLogger()

    private var reportURL: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("last_crash.log")
    }

    func install() {
        NSSetUncaughtExceptionHandler { exception in
            let breadcrumbs = AppLog.shared.recentBreadcrumbs().joined(separator: "\n")
            let report = """
            CRASH: \(exception.name.rawValue)
            Reason: \(exception.reason ?? "-")

            Stack:
            \(exception.callStackSymbols.joined(separator: "\n"))

            Breadcrumbs:
            \(breadcrumbs)
            """
            CrashLogger.shared.write(report)
        }
    }

    private func write(_ report: String) { try? report.write(to: reportURL, atomically: true, encoding: .utf8) }

    func lastCrash() -> String? { try? String(contentsOf: reportURL, encoding: .utf8) }
    func clear() { try? FileManager.default.removeItem(at: reportURL) }
}
