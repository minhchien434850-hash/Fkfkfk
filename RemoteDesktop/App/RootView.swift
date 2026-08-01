import SwiftUI

/// Composition root / app shell.
/// Switches between the authentication flow and the main app depending on the
/// observed authentication state. All child screens are created through the DI
/// container so no view constructs its own dependencies (Dependency Inversion).
struct RootView: View {
    @EnvironmentObject private var container: DIContainer
    @EnvironmentObject private var auth: AuthManager

    var body: some View {
        Group {
            switch auth.state {
            case .unknown:
                ProgressView("…")
            case .signedOut:
                container.makeLoginView()
            case .signedIn:
                MainTabView()
            }
        }
        .task { await auth.restoreSession() }
    }
}

/// Primary navigation once authenticated: device dashboard + settings.
private struct MainTabView: View {
    @EnvironmentObject private var container: DIContainer

    var body: some View {
        TabView {
            container.makeDashboardView()
                .tabItem { Label("Devices", systemImage: "display") }
            container.makeSettingsView()
                .tabItem { Label("Settings", systemImage: "gearshape") }
        }
    }
}
