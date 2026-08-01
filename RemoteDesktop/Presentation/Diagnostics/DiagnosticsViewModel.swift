import Foundation
import Combine

/// Surfaces live performance metrics and the last crash report.
@MainActor
final class DiagnosticsViewModel: ObservableObject {
    private let perf = PerformanceMonitor()
    private let crash = CrashLogger.shared
    private var cancellable: AnyCancellable?

    init() {
        cancellable = perf.objectWillChange.sink { [weak self] _ in self?.objectWillChange.send() }
    }

    var fps: Int { perf.fps }
    var memoryMB: Int { perf.memoryMB }
    var lastCrash: String? { crash.lastCrash() }
    var breadcrumbs: [String] { AppLog.shared.recentBreadcrumbs().suffix(30).reversed() }

    func start() { perf.start() }
    func stop() { perf.stop() }
    func clearCrash() { crash.clear(); objectWillChange.send() }
}
