import SwiftUI
import UniformTypeIdentifiers

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
                            }
                            .padding(.vertical, 4)
                        }
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
            // Dùng DocumentPicker (UIKit) thay .fileImporter: .fileImporter hay bị "Mở" mờ,
            // chọn được file nhưng bấm Mở không lên. DocumentPicker asCopy hiện nút Mở dùng được.
            .sheet(isPresented: $showImporter) {
                DocumentPicker(contentTypes: allowedTypes, allowsMultipleSelection: true, asCopy: true) { urls in
                    ipa.importFiles(urls)
                }.ignoresSafeArea()
            }
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
}
