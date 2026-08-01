import SwiftUI
import UniformTypeIdentifiers

// ======================== GitHub — đăng nhập & tải file lên repo (kiểu app "Source") ========================

struct GHUser: Decodable {
    let login: String
    let avatar_url: String?
    let name: String?
}

struct GHRepo: Decodable, Identifiable, Hashable {
    let id: Int
    let name: String
    let full_name: String
    let `private`: Bool
    let default_branch: String?
    let html_url: String?
}

enum GitHubError: LocalizedError {
    case http(Int, String)
    var errorDescription: String? {
        switch self {
        case .http(let c, let m):
            if c == 401 { return "Token sai hoặc hết hạn (401). Tạo token mới với quyền 'repo'." }
            if c == 403 { return "Token thiếu quyền tạo repo (403). Tạo lại token và tick đủ quyền 'repo'." }
            if c == 422 && m.lowercased().contains("already exists") {
                return "Tên repo đã tồn tại trên tài khoản của bạn. Hãy đặt tên khác."
            }
            return "GitHub lỗi \(c): \(m.prefix(180))"
        }
    }
}

final class GitHubAPI {
    let token: String
    init(token: String) { self.token = token }

    private func request(_ path: String, method: String = "GET", body: Data? = nil) async throws -> Data {
        let urlStr = path.hasPrefix("http") ? path : "https://api.github.com" + path
        guard let url = URL(string: urlStr) else { throw GitHubError.http(0, "URL sai") }
        var r = URLRequest(url: url)
        r.httpMethod = method
        r.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        r.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        r.setValue("2022-11-28", forHTTPHeaderField: "X-GitHub-Api-Version")
        r.setValue("KENIOS-App", forHTTPHeaderField: "User-Agent")
        if let body {
            r.httpBody = body
            r.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        r.timeoutInterval = 60
        let (data, resp) = try await URLSession.shared.data(for: r)
        let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(code) else {
            throw GitHubError.http(code, String(data: data, encoding: .utf8) ?? "")
        }
        return data
    }

    func me() async throws -> GHUser {
        try JSONDecoder().decode(GHUser.self, from: try await request("/user"))
    }
    func repos() async throws -> [GHRepo] {
        try JSONDecoder().decode([GHRepo].self,
            from: try await request("/user/repos?per_page=100&sort=updated&affiliation=owner"))
    }
    func createRepo(name: String, isPrivate: Bool) async throws -> GHRepo {
        let body = try JSONSerialization.data(withJSONObject: [
            "name": name, "private": isPrivate, "auto_init": true])
        return try JSONDecoder().decode(GHRepo.self,
            from: try await request("/user/repos", method: "POST", body: body))
    }
    // Lấy 1 repo theo chủ sở hữu + tên (dùng khi repo đã tồn tại sẵn)
    func getRepo(owner: String, name: String) async throws -> GHRepo {
        try JSONDecoder().decode(GHRepo.self,
            from: try await request("/repos/\(owner)/\(name)"))
    }
    // Lấy sha nếu file đã tồn tại (để cập nhật thay vì lỗi)
    func existingSha(fullName: String, path: String, branch: String) async -> String? {
        let p = "/repos/\(fullName)/contents/\(path)?ref=\(branch)"
        guard let data = try? await request(p) else { return nil }
        struct C: Decodable { let sha: String }
        return (try? JSONDecoder().decode(C.self, from: data))?.sha
    }
    func uploadFile(fullName: String, path: String, contentBase64: String,
                    message: String, branch: String, sha: String?) async throws {
        var obj: [String: Any] = ["message": message, "content": contentBase64, "branch": branch]
        if let sha { obj["sha"] = sha }
        let body = try JSONSerialization.data(withJSONObject: obj)
        _ = try await request("/repos/\(fullName)/contents/\(path)", method: "PUT", body: body)
    }
    // Liệt kê file trong 1 thư mục của repo
    func listContents(fullName: String, path: String, branch: String) async throws -> [GHContent] {
        let p = path.isEmpty
            ? "/repos/\(fullName)/contents?ref=\(branch)"
            : "/repos/\(fullName)/contents/\(path)?ref=\(branch)"
        return try JSONDecoder().decode([GHContent].self, from: try await request(p))
    }
    // Xoá 1 file khỏi repo
    func deleteFile(fullName: String, path: String, message: String,
                    branch: String, sha: String) async throws {
        let body = try JSONSerialization.data(withJSONObject: [
            "message": message, "branch": branch, "sha": sha])
        _ = try await request("/repos/\(fullName)/contents/\(path)", method: "DELETE", body: body)
    }

    // ---- Build app qua GitHub Actions ----
    func triggerBuild(fullName: String, workflow: String, ref: String) async throws {
        let body = try JSONSerialization.data(withJSONObject: ["ref": ref])
        _ = try await request("/repos/\(fullName)/actions/workflows/\(workflow)/dispatches",
                              method: "POST", body: body)
    }
    func listRuns(fullName: String) async throws -> [GHRun] {
        struct Wrap: Decodable { let workflow_runs: [GHRun] }
        let data = try await request("/repos/\(fullName)/actions/runs?per_page=8")
        return try JSONDecoder().decode(Wrap.self, from: data).workflow_runs
    }
    func latestRelease(fullName: String) async -> GHRelease? {
        guard let data = try? await request("/repos/\(fullName)/releases/latest") else { return nil }
        return try? JSONDecoder().decode(GHRelease.self, from: data)
    }
}

struct GHContent: Decodable, Identifiable {
    var id: String { path }
    let name: String
    let path: String
    let type: String   // file | dir
    let sha: String
}

struct GHRun: Decodable, Identifiable {
    let id: Int
    let status: String?       // queued | in_progress | completed
    let conclusion: String?   // success | failure | cancelled...
    let html_url: String?
    let run_number: Int?
}
struct GHReleaseAsset: Decodable, Identifiable {
    var id: String { name }
    let name: String
    let browser_download_url: String
}
struct GHRelease: Decodable {
    let tag_name: String?
    let html_url: String?
    let assets: [GHReleaseAsset]
}
