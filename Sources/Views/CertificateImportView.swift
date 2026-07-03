import SwiftUI
import UniformTypeIdentifiers
import Security

// ============================================================================
//  Import chứng chỉ ký iOS (.p12 + .mobileprovision) — giống ESign/KSign
//  Nhập chứng chỉ của CHÍNH BẠN từ Files/iCloud → lưu vào sandbox app →
//  nhập mật khẩu p12 (lưu Keychain) → kiểm tra hợp lệ + xem hạn dùng.
//  Dùng để chuẩn bị chứng chỉ cho bước ký IPA (engine ký chạy riêng).
// ============================================================================

// Thông tin đọc được từ chứng chỉ
struct CertInfo {
    var p12Name: String?
    var p12Size: Int = 0
    var provisionName: String?
    var provisionSize: Int = 0
    var passwordValid: Bool?          // nil = chưa kiểm tra / không xác minh được
    var p12Unverified = false         // .p12 mã hoá kiểu mới (OpenSSL 3) — iOS không đọc được để xác minh
    var certSubject: String?          // vd "iPhone Distribution: Tên (TEAMID)"
    var provisionTeam: String?
    var provisionExpiry: Date?        // hạn của .mobileprovision
    var deviceCount: Int?             // số UDID trong provision
}

@MainActor
final class CertificateStore: ObservableObject {
    @Published var info = CertInfo()
    @Published var message: String?
    @Published var checking = false

    private let kPassword = "cert_p12_password"
    private var docs: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
    }
    var p12URL: URL { docs.appendingPathComponent("cert.p12") }
    var provisionURL: URL { docs.appendingPathComponent("cert.mobileprovision") }

    var savedPassword: String {
        get { Keychain.load(kPassword) ?? "" }
        set { Keychain.save(kPassword, newValue) }
    }

    var hasP12: Bool { FileManager.default.fileExists(atPath: p12URL.path) }
    var hasProvision: Bool { FileManager.default.fileExists(atPath: provisionURL.path) }
    var isComplete: Bool { hasP12 && hasProvision }

    private func fileSize(_ url: URL) -> Int {
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: url.path),
              let n = attrs[.size] as? NSNumber else { return 0 }
        return n.intValue
    }

    // Nạp trạng thái file đã lưu khi mở màn hình
    func refresh() {
        var i = CertInfo()
        if hasP12 {
            i.p12Name = "cert.p12"
            i.p12Size = fileSize(p12URL)
        }
        if hasProvision {
            i.provisionName = "cert.mobileprovision"
            i.provisionSize = fileSize(provisionURL)
            applyProvision(&i)
        }
        info = i
    }

    // Copy các file vừa chọn vào sandbox (ghi đè file cũ)
    func importFiles(_ urls: [URL]) {
        message = nil
        let fm = FileManager.default
        var imported = 0
        for url in urls {
            let access = url.startAccessingSecurityScopedResource()
            defer { if access { url.stopAccessingSecurityScopedResource() } }
            let ext = url.pathExtension.lowercased()
            let dest: URL
            switch ext {
            case "p12", "pfx": dest = p12URL
            case "mobileprovision", "provisionprofile": dest = provisionURL
            default:
                message = "Bỏ qua file không hợp lệ: \(url.lastPathComponent)"
                continue
            }
            do {
                if fm.fileExists(atPath: dest.path) { try fm.removeItem(at: dest) }
                try fm.copyItem(at: url, to: dest)
                imported += 1
            } catch {
                message = "Lỗi lưu \(url.lastPathComponent): \(error.localizedDescription)"
            }
        }
        if imported > 0 { message = "Đã nạp \(imported) tệp vào ứng dụng." }
        refresh()
        if !savedPassword.isEmpty { validatePassword() }
    }

    // Kiểm tra mật khẩu p12 + đọc thông tin chứng chỉ
    func validatePassword() {
        guard hasP12 else { info.passwordValid = nil; return }
        checking = true
        defer { checking = false }
        guard let data = try? Data(contentsOf: p12URL) else {
            info.passwordValid = false; return
        }
        let opts: [String: Any] = [kSecImportExportPassphrase as String: savedPassword]
        var items: CFArray?
        let status = SecPKCS12Import(data as CFData, opts as CFDictionary, &items)
        if status == errSecSuccess,
           let arr = items as? [[String: Any]], let first = arr.first,
           let identityRef = first[kSecImportItemIdentity as String] {
            info.passwordValid = true
            info.p12Unverified = false
            let identity = identityRef as! SecIdentity
            var certRef: SecCertificate?
            if SecIdentityCopyCertificate(identity, &certRef) == errSecSuccess, let cert = certRef {
                info.certSubject = SecCertificateCopySubjectSummary(cert) as String?
            }
        } else if status == errSecDecode {
            info.passwordValid = false   // hỏng thật (không giải mã được cấu trúc ASN.1)
            info.p12Unverified = false
            info.certSubject = nil
        } else {
            // errSecAuthFailed (-25293) và các lỗi khác: KHÔNG kết luận sai chắc chắn —
            // iOS trả lỗi này cho CẢ mật khẩu sai LẪN .p12 mã hoá kiểu mới (OpenSSL 3:
            // AES-256 + MAC SHA-256) mà iOS không đọc được. Mật khẩu vẫn đã lưu (Keychain)
            // để eSign (OpenSSL đầy đủ) tự xác minh khi ký.
            info.passwordValid = nil
            info.p12Unverified = true
            info.certSubject = nil
        }
    }

    func clearAll() {
        let fm = FileManager.default
        try? fm.removeItem(at: p12URL)
        try? fm.removeItem(at: provisionURL)
        Keychain.delete(kPassword)
        info = CertInfo()
        message = "Đã xoá chứng chỉ khỏi ứng dụng."
    }

    // MARK: - Đọc thông tin .mobileprovision (plist nhúng trong file PKCS#7)
    private func applyProvision(_ i: inout CertInfo) {
        guard let data = try? Data(contentsOf: provisionURL),
              let plist = extractPlist(from: data) else { return }
        i.provisionName = (plist["Name"] as? String) ?? i.provisionName
        i.provisionTeam = (plist["TeamName"] as? String)
        i.provisionExpiry = plist["ExpirationDate"] as? Date
        if let devices = plist["ProvisionedDevices"] as? [String] {
            i.deviceCount = devices.count
        }
    }

    // Tách đoạn plist XML nằm giữa <plist ...> ... </plist> trong file mobileprovision
    private func extractPlist(from data: Data) -> [String: Any]? {
        guard let start = data.range(of: Data("<plist".utf8))?.lowerBound,
              let endRange = data.range(of: Data("</plist>".utf8)) else { return nil }
        let slice = data.subdata(in: start..<endRange.upperBound)
        return (try? PropertyListSerialization.propertyList(from: slice, options: [], format: nil)) as? [String: Any]
    }
}

struct CertificateImportView: View {
    @EnvironmentObject var store: AppStore
    @StateObject private var certs = CertificateStore()

    @State private var password = ""
    @State private var showImporter = false
    @State private var showClearConfirm = false

    private var allowedTypes: [UTType] {
        var t: [UTType] = [.pkcs12]
        if let mp = UTType(filenameExtension: "mobileprovision") { t.append(mp) }
        // Dự phòng: cho chọn mọi file (khi iOS không nhận đuôi .mobileprovision).
        // importFiles() vẫn tự lọc theo đuôi p12 / mobileprovision khi lưu.
        t.append(.data)
        return t
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    KHeroHeader(icon: "checkmark.seal.fill",
                                title: store.t("Chứng chỉ ký", "Signing Certificate"),
                                subtitle: store.t("Nhập .p12 + .mobileprovision để ký app",
                                                  "Import .p12 + .mobileprovision to sign apps"))
                        .listRowInsets(EdgeInsets()).listRowBackground(Color.clear)
                }

                Section("1. Nhập chứng chỉ") {
                    Button {
                        showImporter = true
                    } label: {
                        Label(store.t("Chọn file .p12 và .mobileprovision", "Pick .p12 and .mobileprovision"),
                              systemImage: "square.and.arrow.down.on.square")
                    }
                    Text(store.t("Chọn cả 2 file cùng lúc từ Tệp/iCloud. File được lưu an toàn trong ứng dụng.",
                                 "Pick both files from Files/iCloud. They're stored securely in the app."))
                        .font(.caption2).foregroundStyle(.secondary)
                }

                // Trạng thái file đã nạp
                Section("2. Trạng thái") {
                    statusRow(ok: certs.hasP12,
                              title: "cert.p12",
                              detail: certs.hasP12 ? humanSize(certs.info.p12Size) : "Chưa có")
                    statusRow(ok: certs.hasProvision,
                              title: "cert.mobileprovision",
                              detail: certs.hasProvision ? humanSize(certs.info.provisionSize) : "Chưa có")
                }

                // Mật khẩu p12
                if certs.hasP12 {
                    Section {
                        SecureField(store.t("Mật khẩu file .p12", "Password of .p12 file"), text: $password)
                            .textInputAutocapitalization(.never).autocorrectionDisabled()
                        Button {
                            certs.savedPassword = password
                            certs.validatePassword()
                        } label: {
                            HStack {
                                if certs.checking { ProgressView().padding(.trailing, 4) }
                                Text(store.t("Lưu & kiểm tra mật khẩu", "Save & verify password"))
                            }
                        }
                        .disabled(password.isEmpty || certs.checking)

                        if certs.info.passwordValid == true {
                            Label(store.t("Mật khẩu đúng — chứng chỉ hợp lệ", "Password OK — certificate valid"),
                                  systemImage: "checkmark.circle.fill")
                                .font(.caption.bold()).foregroundStyle(.green)
                        } else if certs.info.p12Unverified {
                            VStack(alignment: .leading, spacing: 4) {
                                Label(store.t("Đã lưu mật khẩu — app chưa xác minh được",
                                              "Password saved — app couldn't verify"),
                                      systemImage: "exclamationmark.triangle.fill")
                                    .font(.caption.bold()).foregroundStyle(.orange)
                                Text(store.t("File .p12 dùng mã hoá kiểu mới (OpenSSL 3) mà iOS không đọc được để kiểm tra — KHÔNG có nghĩa mật khẩu sai. Mật khẩu đã lưu; cứ ký/cài qua eSign, nếu eSign báo sai thì mới đổi mật khẩu.",
                                             "The .p12 uses new encryption (OpenSSL 3) iOS can't read to verify — it does NOT mean the password is wrong. It's saved; sign/install via eSign — only change it if eSign rejects it."))
                                    .font(.caption2).foregroundStyle(.secondary)
                            }
                        } else if certs.info.passwordValid == false {
                            Label(store.t("File .p12 hỏng hoặc không đọc được", "The .p12 file is corrupt or unreadable"),
                                  systemImage: "xmark.circle.fill")
                                .font(.caption.bold()).foregroundStyle(.red)
                        }
                    } header: {
                        Text("3. Mật khẩu chứng chỉ")
                    } footer: {
                        Text(store.t("Mật khẩu được lưu mã hoá trong Keychain của máy, không lưu ra ngoài.",
                                     "Password is stored encrypted in the device Keychain."))
                            .font(.caption2)
                    }
                }

                // Thông tin đọc được
                if certs.info.certSubject != nil || certs.info.provisionName != nil {
                    Section("Thông tin chứng chỉ") {
                        if let s = certs.info.certSubject {
                            infoRow("Chứng chỉ", s)
                        }
                        if let t = certs.info.provisionTeam {
                            infoRow("Team", t)
                        }
                        if let d = certs.info.provisionExpiry {
                            infoRow("Hạn provision", dateText(d), warn: d < Date())
                        }
                        if let n = certs.info.deviceCount {
                            infoRow("Số thiết bị (UDID)", "\(n)")
                        }
                    }
                }

                // Bước ký (engine riêng)
                if certs.isComplete {
                    Section {
                        Text(store.t("✅ Đã đủ chứng chỉ. Phần MÁY KÝ IPA (engine zsign) là thư viện C++ riêng, sẽ dùng đúng 2 file này cùng mật khẩu để ký file IPA của bạn.",
                                     "✅ Certificate ready. The IPA signing engine (zsign, native C++) will use these files + password to sign your IPA."))
                            .font(.caption).foregroundStyle(.secondary)
                    } header: { Text("4. Ký IPA") }
                }

                if certs.hasP12 || certs.hasProvision {
                    Section {
                        Button(role: .destructive) { showClearConfirm = true } label: {
                            Label(store.t("Xoá chứng chỉ đã nhập", "Remove imported certificate"),
                                  systemImage: "trash")
                        }
                    }
                }

                if let msg = certs.message {
                    Section { Text(msg).font(.caption).foregroundStyle(.secondary) }
                }
            }
            .navigationTitle(store.t("Chứng chỉ ký", "Signing Cert"))
            .navigationBarTitleDisplayMode(.inline)
            .onAppear {
                certs.refresh()
                password = certs.savedPassword
                if certs.hasP12 && !password.isEmpty { certs.validatePassword() }
            }
            // Dùng DocumentPicker (UIKit) thay .fileImporter: .fileImporter hay làm nút "Mở"
            // mờ với .p12/.mobileprovision → chọn được mà bấm Mở không lên.
            .sheet(isPresented: $showImporter) {
                DocumentPicker(contentTypes: allowedTypes, allowsMultipleSelection: true, asCopy: true) { urls in
                    certs.importFiles(urls)
                }.ignoresSafeArea()
            }
            .alert(store.t("Xoá chứng chỉ?", "Remove certificate?"), isPresented: $showClearConfirm) {
                Button(store.t("Xoá", "Remove"), role: .destructive) {
                    certs.clearAll(); password = ""
                }
                Button(store.t("Huỷ", "Cancel"), role: .cancel) {}
            } message: {
                Text(store.t("Xoá cả 2 file và mật khẩu khỏi ứng dụng.",
                             "Removes both files and the password from the app."))
            }
        }
    }

    private func statusRow(ok: Bool, title: String, detail: String) -> some View {
        HStack {
            Image(systemName: ok ? "checkmark.circle.fill" : "circle.dashed")
                .foregroundStyle(ok ? .green : .secondary)
            Text(title).font(.subheadline.monospaced())
            Spacer()
            Text(detail).font(.caption).foregroundStyle(.secondary)
        }
    }

    private func infoRow(_ label: String, _ value: String, warn: Bool = false) -> some View {
        HStack(alignment: .top) {
            Text(label).font(.caption).foregroundStyle(.secondary)
            Spacer()
            Text(value).font(.caption.bold())
                .foregroundStyle(warn ? .red : .primary)
                .multilineTextAlignment(.trailing)
        }
    }

    private func dateText(_ d: Date) -> String {
        let f = DateFormatter()
        f.dateStyle = .medium
        let base = f.string(from: d)
        return d < Date() ? base + " (hết hạn)" : base
    }

    private func humanSize(_ bytes: Int) -> String {
        let f = ByteCountFormatter()
        f.allowedUnits = [.useKB, .useMB]
        f.countStyle = .file
        return f.string(fromByteCount: Int64(bytes))
    }
}
