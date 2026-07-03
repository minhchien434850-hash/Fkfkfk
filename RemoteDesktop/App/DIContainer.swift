import SwiftUI

/// Dependency Injection container / composition root.
/// Constructs the whole object graph once and vends fully-wired screens. No
/// other type creates its own dependencies (Inversion of Control).
@MainActor
final class DIContainer: ObservableObject {

    // Shared singletons
    let authManager: AuthManager
    let deviceManager: DeviceManager

    // Infrastructure (retained for per-session factories)
    private let tokens: TokenStoreProtocol
    private let settings: UserDefaultsStore
    private let sessionService: SessionService          // SessionServiceProtocol + InputServiceProtocol
    private let decoder: VideoDecoderProtocol
    private let renderer: RendererProtocol

    init() {
        // --- Infrastructure ---
        let tokens = KeychainService()
        let settings = UserDefaultsStore()
        let api = APIClient(baseURL: AppConfig.serverBaseURL, tokenProvider: { tokens.load() })

        let authService = AuthService(api: api)
        let deviceRepo = DeviceRepository(api: api)
        let sessionService = SessionService(api: api)
        let biometrics = BiometricAuthenticator()

        // --- Application (managers) ---
        let authManager = AuthManager(
            loginUseCase: LoginUseCase(auth: authService, tokens: tokens),
            refreshUseCase: RefreshTokenUseCase(auth: authService, tokens: tokens),
            logoutUseCase: LogoutUseCase(tokens: tokens),
            biometrics: biometrics,
            tokens: tokens,
            settings: settings)
        let deviceManager = DeviceManager(
            discover: DiscoverDevicesUseCase(repo: deviceRepo),
            repository: deviceRepo)

        // --- Assign stored properties ---
        self.tokens = tokens
        self.settings = settings
        self.sessionService = sessionService
        self.decoder = VideoToolboxDecoder()
        self.renderer = MetalRenderer()
        self.authManager = authManager
        self.deviceManager = deviceManager
    }

    static func makeDefault() -> DIContainer { DIContainer() }

    // MARK: - Screen factories

    func makeLoginView() -> some View {
        LoginView(viewModel: LoginViewModel(auth: authManager), auth: authManager)
    }

    func makeDashboardView() -> some View {
        DashboardView(viewModel: DashboardViewModel(devices: deviceManager))
    }

    func makeSettingsView() -> some View {
        SettingsView(viewModel: SettingsViewModel(settings: settings, auth: authManager))
    }

    /// A remote session gets its own stream + managers so multiple sessions
    /// never share mutable streaming state.
    func makeSessionView(device: Device) -> some View {
        let stream = StreamService(session: sessionService)
        let streamManager = StreamManager(decoder: decoder, renderer: renderer)
        let sessionManager = SessionManager(
            connectUseCase: ConnectUseCase(),
            startStream: StartStreamUseCase(stream: stream),
            streamManager: streamManager)
        let inputManager = InputManager(sendInput: SendInputUseCase(input: sessionService))
        let vm = SessionViewModel(device: device, session: sessionManager, input: inputManager)
        return SessionView(viewModel: vm)
    }
}
