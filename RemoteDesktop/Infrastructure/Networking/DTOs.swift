import Foundation

// MARK: - Data Transfer Objects (wire shapes). Mapped to domain models in repos.

struct APIEmpty: Decodable {}

struct UserDTO: Decodable {
    let id: Int?
    let username: String?
}

struct LoginResponseDTO: Decodable {
    let token: String
    let user: UserDTO?
}

struct DeviceDTO: Decodable {
    let agentId: String
    let name: String
    let os: String
    let online: Bool

    func toDomain() -> Device {
        Device(id: agentId, name: name, os: os, isOnline: online)
    }
}

struct ScreenDTO: Decodable {
    let jpg: String
    let ts: Int
    let online: Bool
}
