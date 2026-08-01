import Foundation

// MARK: - Domain interfaces (Protocol-Oriented, Dependency-Inversion boundary)
//
// Every capability the app needs is expressed as a protocol here. Concrete
// implementations live in `Infrastructure` / `Platform` and are wired by the
// DI container, so the Domain/Presentation layers never depend on frameworks.

// --- Authentication & security ---

protocol AuthServiceProtocol {
    /// Exchange credentials for a `User` + bearer token (OAuth2/JWT style).
    func login(username: String, password: String) async throws -> (user: User, token: String)
    /// Refresh an access token; returns the new token.
    func refresh(token: String) async throws -> String
}

protocol TokenStoreProtocol {
    func save(token: String) throws
    func load() -> String?
    func clear()
}

protocol BiometricAuthenticatorProtocol {
    var isAvailable: Bool { get }
    func authenticate(reason: String) async throws
}

protocol SecureCryptoProtocol {
    /// AES-256-GCM seal/open using a session key.
    func seal(_ plaintext: Data, key: Data) throws -> Data
    func open(_ ciphertext: Data, key: Data) throws -> Data
}

// --- Devices & session ---

protocol DeviceRepositoryProtocol {
    func discover() async throws -> [Device]
    func remove(deviceId: String) async throws
}

protocol SessionServiceProtocol {
    /// Fetch the latest preview frame from the relay (nil if none yet).
    func fetchFrame(deviceId: String) async throws -> VideoFrame?
    /// Send a single normalized input command to the device.
    func send(_ input: RemoteInput, to deviceId: String) async throws
}

// --- Streaming pipeline ---

protocol StreamServiceProtocol: AnyObject {
    /// A cold stream of frames for the given device; consuming starts polling.
    func frames(for deviceId: String) -> AsyncStream<VideoFrame>
    func stop()
}

protocol VideoDecoderProtocol: AnyObject {
    /// Decode a compressed frame into a displayable frame (VideoToolbox path).
    func decode(_ frame: VideoFrame) throws -> VideoFrame
}

protocol RendererProtocol: AnyObject {
    /// Present a displayable frame (Metal path).
    func render(_ frame: VideoFrame)
}

// --- Input ---

protocol InputServiceProtocol {
    func send(_ input: RemoteInput, to deviceId: String) async throws
}

// --- Clipboard / files / audio ---

protocol ClipboardServiceProtocol {
    func push(_ item: ClipboardItem, to deviceId: String) async throws
    func pull(from deviceId: String) async throws -> ClipboardItem?
}

protocol FileTransferServiceProtocol: AnyObject {
    func upload(_ fileURL: URL, to deviceId: String) -> AsyncStream<TransferProgress>
    func download(_ name: String, from deviceId: String) -> AsyncStream<TransferProgress>
}

protocol AudioServiceProtocol: AnyObject {
    var isRunning: Bool { get }
    func startTwoWayAudio(deviceId: String) throws
    func stop()
}
