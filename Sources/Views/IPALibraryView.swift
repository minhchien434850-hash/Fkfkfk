import SwiftUI
import UniformTypeIdentifiers
import UIKit

// ============================================================================
//  Kho IPA — gom file .ipa vào app, rồi mở sang ESign để KÝ + CÀI.
//  App làm nơi lưu/tải IPA; việc ký-cài để ESign lo (dùng chứng chỉ của bạn).
//  Không tự ký trong app (cần engine native riêng) — chỉ bàn giao IPA cho ESign.
// ============================================================================

struct IPAFile: Identifiable, Hashable {
    let id = UUID()
    let url: URL
    let name: String
    let size: Int
    let date: Date
}

@MainActor
final class IPAStore: ObservableObject {
    @Published var items: [IPAFile] = []
    @Published var message: String?
    @Published var downloading = false

    private var dir: URL {
        let d = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("IPAs", isDirectory: true)
        try? FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
        return d
    }

    func refresh() {
        let fm = FileManager.default
        let urls = (try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: [.fileSizeKey, .contentModificationDateKey])) ?? []
        items = urls
            .filter { $0.pathExtension.lowercased() == "ipa" }
            .map { url in
                let attrs = try? fm.attributesOfItem(atPath: url.path)
                let size = (attrs?[.size] as? NSNumber)?.intValue ?? 0
                let date = (attrs?[.modificationDate] as? Date) ?? Date()
                return IPAFile(url: url, name: url.lastPathComponent, size: size, date: date)
            }
            .sorted { $0.date > $1.date }
    }

    func importFiles(_ urls: [URL]) {
        let fm = FileManager.default
        var count = 0
        for url in urls {
            guard url.pathExtension.lowercased() == "ipa" else {
                message = "Bỏ qua (không phải .ipa): \(url.lastPathComponent)"; continue
            }
            let access = url.startAccessingSecurityScopedResource()
            defer { if access { url.stopAccessingSecurityScopedResource() } }
            let dest = uniqueDest(for: url.lastPathComponent)
            do { try fm.copyItem(at: url, to: dest); count += 1 }
            catch { message = "Lỗi lưu \(url.lastPathComponent): \(error.localizedDescription)" }
        }
        if count > 0 { message = "Đã thêm \(count) file IPA." }
        refresh()
    }

    func downloadFromURL(_ raw: String) async {
        let s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: s), url.scheme?.hasPrefix("http") == true else {
            message = "Link không hợp lệ."; return
        }
        downloading = true; message = nil
        defer { downloading = false }
        do {
            let (tmp, resp) = try await URLSession.shared.download(from: url)
            var name = url.lastPathComponent
            if !name.lowercased().hasSuffix(".ipa") {
                // Lấy tên từ header nếu có, không thì đặt mặc định
                if let http = resp as? HTTPURLResponse,
                   let disp = http.value(forHTTPHeaderField: "Content-Disposition"),
                   let r = disp.range(of: "filename=") {
                    name = String(disp[r.upperBound...]).trimmingCharacters(in: CharacterSet(charactersIn: "\"; "))
                }
                if !name.lowercased().hasSuffix(".ipa") {
                    name = "download_\(Int(Date().timeIntervalSince1970)).ipa"
                }
            }
            let dest = uniqueDest(for: name)
            try? FileManager.default.removeItem(at: dest)
            try FileManager.default.moveItem(at: tmp, to: dest)
            message = "Đã tải: \(dest.lastPathComponent)"
            refresh()
        } catch {
            message = "Tải thất bại: \(error.localizedDescription)"
        }
    }

    func delete(_ item: IPAFile) {
        try? FileManager.default.removeItem(at: item.url)
        refresh()
    }

    private func uniqueDest(for filename: String) -> URL {
        let fm = FileManager.default
        var dest = dir.appendingPathComponent(filename)
        if fm.fileExists(atPath: dest.path) {
            let base = (filename as NSString).deletingPathExtension
            let ext = (filename as NSString).pathExtension
            dest = dir.appendingPathComponent("\(base)_\(Int(Date().timeIntervalSince1970)).\(ext)")
        }
        return dest
    }
}

struct IPALibraryView: View {
    @EnvironmentObject var store: AppStore
    @StateObject private var ipa = IPAStore()

    @State private var showImporter = false
    @State private var downloadURL = ""
    // §IPA — ký ở máy chủ (zsign) + cài OTA
    @State private var signingId: UUID?
    @State private var signMsg: String?
    // Sheet ký: chọn tên app + định danh, ký xong mới hiện nút cài đặt
    @State private var signItem: IPAFile?
    @State private var signAppName = ""
    @State private var signBundleId = ""
    @State private var installURL: String?
    @State private var signIsError = false
    // Admin cấu hình domain HTTPS + trạng thái zsign
    @State private var ipaBase = ""
    @State private var hasZsign = false
    @State private var savingBase = false
    @State private var baseMsg: String?
    // §Phát hành: đặt bản ký làm bản cài công khai (trang /install cho khách)
    @State private var publishNext = true
    @State private var published: IPAPublishedStatus?
    @State private var lastPublicLink: String?
    @State private var linkCopied = false

    // Chứng chỉ đã nhập (ở màn "Chứng chỉ ký") — cùng app, cùng Documents.
    private var certDocs: URL { FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0] }
    private var certP12: URL { certDocs.appendingPathComponent("cert.p12") }
    private var certProvision: URL { certDocs.appendingPathComponent("cert.mobileprovision") }
    private var certPassword: String { Keychain.load("cert_p12_password") ?? "" }
    private var certReady: Bool {
        FileManager.default.fileExists(atPath: certP12.path)
            && FileManager.default.fileExists(atPath: certProvision.path)
            && !certPassword.isEmpty
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    KHeroHeader(icon: "shippingbox.fill",
                                title: store.t("Kho IPA", "IPA Library"),
                                subtitle: store.t("Gom IPA · Mở sang ESign để ký & cài",
                                                  "Collect IPAs · Open in ESign to sign & install"))
                        .listRowInsets(EdgeInsets()).listRowBackground(Color.clear)
                }

                Section("Thêm IPA") {
                    Button {
                        showImporter = true
                    } label: {
                        Label(store.t("Chọn file .ipa từ Tệp/iCloud", "Pick .ipa from Files/iCloud"),
                              systemImage: "square.and.arrow.down.on.square")
                    }
                    HStack {
                        TextField(store.t("Hoặc dán link .ipa để tải...", "Or paste .ipa link to download..."),
                                  text: $downloadURL)
                            .textInputAutocapitalization(.never).autocorrectionDisabled()
                        Button {
                            let u = downloadURL; downloadURL = ""
                            Task { await ipa.downloadFromURL(u) }
                        } label: {
                            if ipa.downloading { ProgressView() }
                            else { Image(systemName: "arrow.down.circle.fill") }
                        }
                        .disabled(ipa.downloading || downloadURL.isEmpty)
                    }
                }

                // Cấu hình ký ở máy chủ (chỉ admin) — cần domain HTTPS cho cài OTA
                if store.isAdmin {
                    Section {
                        HStack {
                            Image(systemName: hasZsign ? "checkmark.seal.fill" : "exclamationmark.triangle.fill")
                                .foregroundStyle(hasZsign ? .green : .orange)
                            Text(hasZsign ? store.t("Máy chủ đã có zsign", "Server has zsign")
                                          : store.t("Máy chủ chưa cài zsign (chạy capnhat-vps.sh)",
                                                    "Server missing zsign (run capnhat-vps.sh)")).font(.caption)
                        }
                        TextField("https://ten-mien-cua-ban.com", text: $ipaBase)
                            .textInputAutocapitalization(.never).autocorrectionDisabled().keyboardType(.URL)
                        Button {
                            Task { await saveBase() }
                        } label: {
                            HStack { if savingBase { ProgressView().padding(.trailing, 4) }
                                Text(store.t("Lưu domain HTTPS", "Save HTTPS domain")).bold() }
                        }.disabled(savingBase)
                        if let baseMsg { Text(baseMsg).font(.caption).foregroundStyle(.secondary) }
                    } header: {
                        Text(store.t("Ký ở máy chủ — cấu hình (Admin)", "Server signing — config (Admin)"))
                    } footer: {
                        Text(store.t("Cài OTA BẮT BUỘC domain HTTPS có chứng chỉ TLS thật (vd Let's Encrypt) trỏ về máy chủ KENIOS. IP thường không dùng được.",
                                     "OTA install REQUIRES an HTTPS domain with a real TLS cert (e.g. Let's Encrypt) pointing to the KENIOS server. A bare IP won't work."))
                            .font(.caption2)
                    }

                    // Phát hành cho khách — trang cài công khai /install
                    Section {
                        Toggle(isOn: $publishNext) {
                            Label(store.t("Phát hành cho khách khi ký", "Publish to customers when signing"),
                                  systemImage: "megaphone.fill")
                        }.tint(.green)
                        if let p = published, p.published {
                            HStack {
                                Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(store.t("Đang phát hành", "Live"))
                                        .font(.caption.bold()).foregroundStyle(.green)
                                    if let t = p.title, !t.isEmpty {
                                        Text(t + (p.version.map { " · \($0)" } ?? ""))
                                            .font(.caption2).foregroundStyle(.secondary)
                                    }
                                }
                            }
                            linkRow(p.publicUrl)
                            Button(role: .destructive) {
                                Task { try? await store.api.adminUnpublishIPA(); published = try? await store.api.adminGetPublishedIPA() }
                            } label: {
                                Label(store.t("Gỡ phát hành", "Unpublish"), systemImage: "xmark.circle")
                            }
                        } else if let link = lastPublicLink {
                            linkRow(link)
                        } else {
                            Text(store.t("Chưa phát hành bản nào. Bật công tắc rồi bấm 'Ký & cài trên máy chủ' ở một IPA để phát hành.",
                                         "Nothing published yet. Turn on the switch, then tap 'Sign & install on server' on an IPA to publish."))
                                .font(.caption2).foregroundStyle(.secondary)
                        }
                    } header: {
                        Text(store.t("Trang cài cho khách (Admin)", "Customer install page (Admin)"))
                    } footer: {
                        Text(store.t("Gửi link này cho khách — mở bằng Safari là cài được app lên màn hình chính, không cần App Store.",
                                     "Send this link to customers — open in Safari to install the app to the home screen, no App Store needed."))
                            .font(.caption2)
                    }
                }

                if ipa.items.isEmpty {
                    Section {
                        Text(store.t("Chưa có IPA nào. Thêm file .ipa ở trên để bắt đầu.",
                                     "No IPAs yet. Add an .ipa above to start."))
                            .font(.caption).foregroundStyle(.secondary)
                    }
                } else {
                    Section(store.t("IPA đã lưu", "Saved IPAs") + " (\(ipa.items.count))") {
                        ForEach(ipa.items) { item in
                            VStack(alignment: .leading, spacing: 8) {
                                HStack {
                                    Image(systemName: "app.badge.fill").foregroundStyle(Theme.accent)
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(item.name).font(.subheadline.bold()).lineLimit(1)
                                        Text("\(humanSize(item.size)) · \(item.date.formatted(date: .abbreviated, time: .shortened))")
                                            .font(.caption2).foregroundStyle(.secondary)
                                    }
                                }
                                HStack(spacing: 10) {
                                    ShareLink(item: item.url) {
                                        Label(store.t("Ký & cài bằng ESign", "Sign & install via ESign"),
                                              systemImage: "square.and.arrow.up")
                                            .font(.caption.bold())
                                            .frame(maxWidth: .infinity).frame(height: 38)
                                            .background(Theme.accent).foregroundStyle(.white)
                                            .clipShape(RoundedRectangle(cornerRadius: 9))
                                    }
                                    Button(role: .destructive) {
                                        ipa.delete(item)
                                    } label: {
                                        Image(systemName: "trash")
                                            .frame(width: 44, height: 38)
                                            .background(Color(.tertiarySystemBackground))
                                            .clipShape(RoundedRectangle(cornerRadius: 9))
                                    }
                                    .buttonStyle(.plain)
                                }
                                // Ký ngay ở máy chủ + cài OTA (không cần eSign) — mở sheet chọn tên/định danh
                                Button {
                                    signAppName = ""; signBundleId = ""
                                    installURL = nil; signMsg = nil; signIsError = false
                                    signItem = item
                                } label: {
                                    HStack {
                                        if signingId == item.id { ProgressView().tint(.white).padding(.trailing, 4) }
                                        Label(store.t("Ký & cài trên máy chủ (OTA)", "Sign & install on server (OTA)"),
                                              systemImage: "checkmark.seal.fill").font(.caption.bold())
                                    }
                                    .frame(maxWidth: .infinity).frame(height: 38)
                                    .background(certReady ? Color.green : Color.gray).foregroundStyle(.white)
                                    .clipShape(RoundedRectangle(cornerRadius: 9))
                                }
                                .buttonStyle(.plain)
                                .disabled(signingId != nil || !certReady)
                                if !certReady {
                                    Text(store.t("Cần nhập chứng chỉ ở 'Chứng chỉ ký' trước (p12 + provision + mật khẩu).",
                                                 "Import your cert in 'Signing Cert' first (p12 + provision + password)."))
                                        .font(.caption2).foregroundStyle(.orange)
                                }
                            }
                            .padding(.vertical, 4)
                        }
                    }
                    if let signMsg {
                        Section { Text(signMsg).font(.caption).foregroundStyle(.secondary) }
                    }
                }

                Section("Hướng dẫn") {
                    ForEach(Array(guideSteps.enumerated()), id: \.offset) { i, step in
                        HStack(alignment: .top, spacing: 10) {
                            Text("\(i + 1)").font(.caption.bold()).foregroundStyle(.white)
                                .frame(width: 22, height: 22).background(Theme.accent).clipShape(Circle())
                            Text(step).font(.caption).fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }

                if let msg = ipa.message {
                    Section { Text(msg).font(.caption).foregroundStyle(.secondary) }
                }
            }
            .navigationTitle(store.t("Kho IPA", "IPA Library"))
            .navigationBarTitleDisplayMode(.inline)
            .onAppear { ipa.refresh() }
            .task {
                if store.isAdmin, let s = try? await store.api.adminGetIpaBase() {
                    ipaBase = s.base; hasZsign = s.hasZsign
                }
                if store.isAdmin { published = try? await store.api.adminGetPublishedIPA() }
            }
            // Dùng DocumentPicker (UIKit) thay .fileImporter: .fileImporter hay bị "Mở" mờ,
            // chọn được file nhưng bấm Mở không lên. DocumentPicker asCopy hiện nút Mở dùng được.
            .sheet(isPresented: $showImporter) {
                DocumentPicker(contentTypes: allowedTypes, allowsMultipleSelection: true, asCopy: true) { urls in
                    ipa.importFiles(urls)
                }.ignoresSafeArea()
            }
            .sheet(item: $signItem) { item in signSheet(item) }
        }
    }

    // Sheet KÝ: nhập tên app + định danh (tuỳ chọn) → bấm ký → ký xong mới hiện nút Cài đặt.
    @ViewBuilder private func signSheet(_ item: IPAFile) -> some View {
        let signing = (signingId == item.id)
        NavigationStack {
            Form {
                Section {
                    Text(item.name).font(.subheadline.bold()).lineLimit(2)
                    Text(humanSize(item.size)).font(.caption2).foregroundStyle(.secondary)
                } header: { Text(store.t("File sẽ ký", "File to sign")) }

                Section {
                    TextField(store.t("Tên app (để trống = giữ nguyên)", "App name (blank = keep original)"),
                              text: $signAppName)
                        .disabled(signing)
                    TextField(store.t("Định danh / Bundle ID (để trống = giữ nguyên)", "Bundle ID (blank = keep original)"),
                              text: $signBundleId)
                        .textInputAutocapitalization(.never).autocorrectionDisabled().keyboardType(.URL)
                        .disabled(signing)
                } header: {
                    Text(store.t("Tuỳ chỉnh khi ký", "Customize when signing"))
                } footer: {
                    Text(store.t("Tên app hiện dưới biểu tượng. Bundle ID dạng com.tencongty.tenapp — đổi để cài song song nhiều bản mà không đè lên nhau.",
                                 "App name shows under the icon. Bundle ID like com.company.app — change it to install multiple copies side by side."))
                        .font(.caption2)
                }

                Section {
                    if installURL == nil {
                        Button {
                            Task { await signOnServer(item, appName: signAppName, bundleId: signBundleId) }
                        } label: {
                            HStack {
                                if signing { ProgressView().padding(.trailing, 6) }
                                Text(signing ? store.t("Đang tải lên & ký...", "Uploading & signing...")
                                             : store.t("Bắt đầu ký", "Start signing")).bold()
                            }.frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(signing || !certReady)
                    } else if let link = installURL, let u = URL(string: link) {
                        // Ký XONG → giờ mới hiện nút cài đặt (không tự mở).
                        Button {
                            UIApplication.shared.open(u)
                        } label: {
                            Label(store.t("Cài đặt lên máy này", "Install on this device"),
                                  systemImage: "arrow.down.app.fill").bold()
                                .frame(maxWidth: .infinity)
                        }.buttonStyle(.borderedProminent).tint(.green)
                        Button {
                            signItem = nil
                        } label: {
                            Text(store.t("Xong", "Done")).frame(maxWidth: .infinity)
                        }.buttonStyle(.bordered)
                    }
                    if let signMsg {
                        Text(signMsg).font(.caption).foregroundStyle(signIsError ? .red : .green)
                    }
                    if !certReady {
                        Text(store.t("Cần nhập chứng chỉ ở 'Chứng chỉ ký' trước (p12 + provision + mật khẩu).",
                                     "Import your cert in 'Signing Cert' first (p12 + provision + password)."))
                            .font(.caption2).foregroundStyle(.orange)
                    }
                }

                if store.isAdmin, let link = lastPublicLink, installURL != nil {
                    Section(store.t("Link cho khách", "Customer link")) { linkRow(link) }
                }
            }
            .navigationTitle(store.t("Ký & cài", "Sign & install"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(store.t("Đóng", "Close")) { signItem = nil }.disabled(signing)
                }
            }
            .interactiveDismissDisabled(signing)
        }
    }

    private var allowedTypes: [UTType] {
        var t: [UTType] = []
        if let ipaType = UTType(filenameExtension: "ipa") { t.append(ipaType) }
        t.append(.data)   // dự phòng để luôn chọn được; import tự lọc đuôi .ipa
        return t
    }

    private let guideSteps: [String] = [
        "Thêm file .ipa vào kho (chọn từ Tệp hoặc dán link tải về).",
        "Bấm 'Ký & cài bằng ESign' — bảng chia sẻ hiện ra.",
        "Chọn ESign (hoặc 'Sao chép vào ESign'). ESign mở lên kèm file IPA.",
        "Trong ESign: chọn chứng chỉ đã mua của anh → Ký → Cài đặt. Xong!",
    ]

    private func humanSize(_ bytes: Int) -> String {
        let f = ByteCountFormatter()
        f.allowedUnits = [.useKB, .useMB, .useGB]
        f.countStyle = .file
        return f.string(fromByteCount: Int64(bytes))
    }

    private func saveBase() async {
        savingBase = true; baseMsg = nil
        defer { savingBase = false }
        do {
            let s = try await store.api.adminSetIpaBase(ipaBase.trimmingCharacters(in: .whitespaces))
            ipaBase = s.base; hasZsign = s.hasZsign
            baseMsg = s.base.hasPrefix("https://") ? store.t("Đã lưu ✅", "Saved ✅")
                                                   : store.t("Cần địa chỉ bắt đầu bằng https://", "Address must start with https://")
        } catch { baseMsg = error.localizedDescription }
    }

    // Một hàng hiện link trang cài công khai + nút Sao chép / Mở.
    @ViewBuilder private func linkRow(_ link: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(link).font(.caption.monospaced()).foregroundStyle(.blue).lineLimit(2)
            HStack(spacing: 10) {
                Button {
                    UIPasteboard.general.string = link
                    linkCopied = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { linkCopied = false }
                } label: {
                    Label(linkCopied ? store.t("Đã sao chép ✓", "Copied ✓") : store.t("Sao chép link", "Copy link"),
                          systemImage: "doc.on.doc")
                        .font(.caption.bold())
                }.buttonStyle(.bordered)
                if let u = URL(string: link) {
                    ShareLink(item: u) {
                        Label(store.t("Gửi khách", "Share"), systemImage: "square.and.arrow.up").font(.caption.bold())
                    }.buttonStyle(.bordered)
                }
            }
        }
    }

    // Ký IPA ở máy chủ (dùng chứng chỉ đã nhập). KHÔNG tự mở cài đặt —
    // ký xong lưu link vào installURL để sheet hiện nút "Cài đặt".
    private func signOnServer(_ item: IPAFile, appName: String, bundleId: String) async {
        guard certReady else {
            signIsError = true
            signMsg = store.t("Chưa có chứng chỉ. Vào 'Chứng chỉ ký' nhập p12 + provision + mật khẩu.",
                              "No certificate. Go to 'Signing Cert' and import p12 + provision + password.")
            return
        }
        signingId = item.id; signIsError = false
        signMsg = store.t("Đang tải lên & ký ở máy chủ...", "Uploading & signing on server...")
        defer { signingId = nil }
        do {
            let r = try await store.api.signIPAOnServer(
                ipa: item.url, p12: certP12, password: certPassword, provision: certProvision,
                publish: store.isAdmin && publishNext,
                appName: appName.trimmingCharacters(in: .whitespaces),
                bundleId: bundleId.trimmingCharacters(in: .whitespaces))
            installURL = r.installUrl        // ký xong → sheet hiện nút Cài đặt
            signIsError = false
            if let pub = r.publicUrl, r.published == true {
                lastPublicLink = pub
                published = try? await store.api.adminGetPublishedIPA()
                signMsg = store.t("Ký xong & ĐÃ PHÁT HÀNH: \(r.title). Bấm 'Cài đặt' để cài, hoặc gửi link cho khách.",
                                  "Signed & PUBLISHED: \(r.title). Tap 'Install' or share the link with customers.")
            } else {
                signMsg = store.t("Ký xong: \(r.title). Bấm 'Cài đặt lên máy này' để cài.",
                                  "Signed: \(r.title). Tap 'Install on this device'.")
            }
        } catch {
            signIsError = true
            signMsg = store.t("Ký thất bại: ", "Sign failed: ") + error.localizedDescription
        }
    }
}
