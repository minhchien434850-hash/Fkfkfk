import SwiftUI

/// Live diagnostics: FPS, memory, log breadcrumbs and the last crash report.
struct DiagnosticsView: View {
    @StateObject private var vm = DiagnosticsViewModel()

    var body: some View {
        List {
            Section("Performance") {
                LabeledContent("FPS", value: "\(vm.fps)")
                LabeledContent("Memory", value: "\(vm.memoryMB) MB")
            }
            Section("Recent log") {
                if vm.breadcrumbs.isEmpty {
                    Text("No events yet.").foregroundStyle(.secondary)
                }
                ForEach(Array(vm.breadcrumbs.enumerated()), id: \.offset) { _, line in
                    Text(line).font(.caption.monospaced())
                }
            }
            Section("Last crash") {
                if let crash = vm.lastCrash {
                    Text(crash).font(.caption2.monospaced())
                    Button("Clear", role: .destructive) { vm.clearCrash() }
                } else {
                    Text("No crash on record.").foregroundStyle(.secondary)
                }
            }
        }
        .navigationTitle("Diagnostics")
        .accessibilityLabel("Diagnostics and performance metrics")
        .onAppear { vm.start() }
        .onDisappear { vm.stop() }
    }
}
