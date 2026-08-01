import SwiftUI

/// Lists the user's devices and opens a remote session on tap.
struct DashboardView: View {
    @EnvironmentObject private var container: DIContainer
    @StateObject private var vm: DashboardViewModel

    init(viewModel: DashboardViewModel) { _vm = StateObject(wrappedValue: viewModel) }

    var body: some View {
        NavigationStack {
            List {
                if vm.isLoading && vm.deviceList.isEmpty {
                    ProgressView()
                } else if vm.deviceList.isEmpty {
                    ContentUnavailableView("No devices",
                        systemImage: "display",
                        description: Text("Run the Desktop Agent and sign in with the same account."))
                }
                ForEach(vm.deviceList) { device in
                    NavigationLink {
                        container.makeSessionView(device: device)
                    } label: {
                        DeviceRow(device: device)
                    }
                    .disabled(!device.isOnline)
                }
                .onDelete { indexSet in
                    let targets = indexSet.map { vm.deviceList[$0] }
                    Task { for d in targets { await vm.remove(d) } }
                }
            }
            .navigationTitle("Devices")
            .toolbar {
                Button { Task { await vm.load() } } label: { Image(systemName: "arrow.clockwise") }
            }
            .refreshable { await vm.load() }
            .task { await vm.load() }
            .overlay(alignment: .bottom) {
                if let error = vm.errorMessage {
                    Text(error).font(.caption).foregroundStyle(.red).padding()
                }
            }
        }
    }
}

private struct DeviceRow: View {
    let device: Device
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: device.os == "Darwin" ? "laptopcomputer" : "pc")
                .font(.title3).frame(width: 34)
            VStack(alignment: .leading, spacing: 2) {
                Text(device.name).font(.headline)
                HStack(spacing: 5) {
                    Circle().fill(device.isOnline ? .green : .orange).frame(width: 8, height: 8)
                    Text(device.isOnline ? "Online" : "Offline")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            Spacer()
        }
    }
}
