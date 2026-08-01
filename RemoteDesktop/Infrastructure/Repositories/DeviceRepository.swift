import Foundation

/// `DeviceRepositoryProtocol` backed by the relay `/pc/mine`.
final class DeviceRepository: DeviceRepositoryProtocol {
    private let api: APIClient
    init(api: APIClient) { self.api = api }

    func discover() async throws -> [Device] {
        let dtos: [DeviceDTO] = try await api.get(Endpoints.devices, auth: true)
        return dtos.map { $0.toDomain() }
    }

    func remove(deviceId: String) async throws {
        try await api.delete(Endpoints.device(deviceId), auth: true)
    }
}
