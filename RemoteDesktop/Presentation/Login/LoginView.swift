import SwiftUI

/// Secure sign-in screen (password + optional Face ID / Touch ID).
struct LoginView: View {
    @StateObject private var vm: LoginViewModel
    @ObservedObject private var auth: AuthManager

    init(viewModel: LoginViewModel, auth: AuthManager) {
        _vm = StateObject(wrappedValue: viewModel)
        self.auth = auth
    }

    var body: some View {
        VStack(spacing: 18) {
            Spacer()
            Image(systemName: "display.and.arrow.down")
                .font(.system(size: 56)).foregroundStyle(.tint)
            Text("RemoteDesktop").font(.largeTitle.bold())
            Text("Sign in to control your machines")
                .font(.subheadline).foregroundStyle(.secondary)

            VStack(spacing: 12) {
                TextField("Username", text: $vm.username)
                    .textInputAutocapitalization(.never).autocorrectionDisabled()
                    .textFieldStyle(.roundedBorder)
                SecureField("Password", text: $vm.password)
                    .textFieldStyle(.roundedBorder)
            }
            .padding(.horizontal)

            if let error = vm.errorMessage {
                Text(error).font(.caption).foregroundStyle(.red).multilineTextAlignment(.center)
            }

            Button {
                Task { await vm.signIn() }
            } label: {
                HStack { if vm.isBusy { ProgressView().tint(.white) }; Text("Sign In").bold() }
                    .frame(maxWidth: .infinity).frame(height: 48)
            }
            .buttonStyle(.borderedProminent)
            .disabled(!vm.canSubmit || vm.isBusy)
            .padding(.horizontal)

            if vm.biometricsAvailable {
                Button {
                    Task { await vm.signInWithBiometrics() }
                } label: {
                    Label("Unlock with Face ID / Touch ID", systemImage: "faceid")
                }
            }
            Spacer()
        }
        .padding()
    }
}
