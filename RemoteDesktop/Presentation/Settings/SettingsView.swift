import SwiftUI

/// Settings & diagnostics.
struct SettingsView: View {
    @StateObject private var vm: SettingsViewModel
    init(viewModel: SettingsViewModel) { _vm = StateObject(wrappedValue: viewModel) }

    var body: some View {
        NavigationStack {
            Form {
                Section("Account") {
                    LabeledContent("Signed in as", value: vm.username)
                    Button("Sign Out", role: .destructive) { vm.signOut() }
                }
                Section("Streaming") {
                    Picker("Quality", selection: $vm.quality) {
                        ForEach(StreamQuality.allCases, id: \.self) { Text($0.displayName).tag($0) }
                    }
                }
                Section("Security") {
                    Toggle("Unlock with Face ID / Touch ID", isOn: $vm.biometricEnabled)
                }
                Section("Diagnostics") {
                    LabeledContent("Version", value: vm.appVersion)
                    LabeledContent("Server", value: vm.serverURL)
                }
            }
            .navigationTitle("Settings")
        }
    }
}
