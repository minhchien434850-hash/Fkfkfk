import SwiftUI

/// Application entry point.
/// Builds the Dependency Injection container once and injects the composition
/// root (`RootView`) with the shared `AuthManager` so the UI can react to the
/// authentication state (login ↔ dashboard).
@main
struct RemoteDesktopApp: App {

    /// The single DI container for the whole app lifetime.
    @StateObject private var container = DIContainer.makeDefault()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(container)
                .environmentObject(container.authManager)
        }
    }
}
