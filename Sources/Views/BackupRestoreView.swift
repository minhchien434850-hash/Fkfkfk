import SwiftUI
import UniformTypeIdentifiers

// ======================== Sao lưu & Khôi phục (chỉ admin) ========================
struct BackupRestoreView: View {
    @EnvironmentObject var store: AppStore
    @State private var cfg = BackupConfig()
    @State private var loading = true
    @State private var busy = false
    @State private var busyText = ""
    @State private var status: String?
    @State private var statusIsError = false
    @State private var chatDraft = ""
    @State private var showPicker = false
    @State private var pendingRestore: URL?
    @State private var showRestoreConfirm = false

    var body: some View {
        List {
            // ---- Trạng thái ----
            Section {
                HStack(spacing: 12) {
                    Image(systemName: "externaldrive.fill.badge.timemachine")
                        .font(.title2).foregroundStyle(Theme.accent)
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Sao lưu toàn bộ dữ liệu").font(.subheadline.bold())
                        Text(cfg.lastDate.isEmpty
                             ? "Chưa có bản sao lưu tự động nào."
                             : "Lần gửi Telegram gần nhất: \(cfg.lastDate)")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }.padding(.vertical, 2)
            } footer: {
                Text("Bản sao lưu gồm toàn bộ database (người dùng, sản phẩm, đơn hàng, cấu hình, bot…) và khóa mã hóa để khôi phục nguyên vẹn.")
            }

            // ---- Tải về máy ----
            Section {
                Button { Task { await downloadToDevice() } } label: {
                    Label("Tải bản sao lưu về máy", systemImage: "square.and.arrow.down.fill")
                }.disabled(busy)
            } header: { Text("Lưu về máy") } footer: {
                Text("Tạo file .zip và mở bảng Chia sẻ để bạn lưu vào Tệp / iCloud / gửi cho chính mình.")
            }

            // ---- Telegram tự động ----
            Section {
                Toggle(isOn: $cfg.dailyOn) {
                    Label("Tự gửi 1 lần/ngày về Telegram", systemImage: "paperplane.fill")
                }
                .tint(Theme.accent)
                .onChange(of: cfg.dailyOn) { v in
                    Task { try? await store.api.setBackupConfig(dailyOn: v) }
                }
                TextField("Chat ID nhận (trống = dùng chat admin bot)", text: $chatDraft)
                    .keyboardType(.numbersAndPunctuation).autocorrectionDisabled()
                Button { Task { await saveChat() } } label: {
                    Label("Lưu Chat ID", systemImage: "checkmark.circle.fill")
                }.disabled(busy)
                Button { Task { await backupNow() } } label: {
                    Label("Gửi bản sao lưu NGAY", systemImage: "paperplane.circle.fill")
                }.disabled(busy)
            } header: { Text("Sao lưu tự động qua Telegram") } footer: {
                if cfg.hasBot {
                    Text("Mỗi ngày backend tự gói dữ liệu và gửi vào Telegram. Bạn tải file đó về giữ riêng. Cần đã cấu hình Bot Telegram (ở mục Bot Telegram hỗ trợ).")
                } else {
                    Text("⚠️ Chưa cấu hình Bot Telegram. Vào 'Bot Telegram hỗ trợ' đặt Token & Chat ID admin trước, rồi bật lại đây.")
                }
            }

            // ---- Khôi phục ----
            Section {
                Button(role: .destructive) { showPicker = true } label: {
                    Label("Khôi phục từ file .zip…", systemImage: "arrow.uturn.backward.circle.fill")
                }.disabled(busy)
            } header: { Text("Khôi phục") } footer: {
                Text("Chọn 1 file sao lưu (.zip) đã lưu. Máy chủ sẽ THAY dữ liệu hiện tại bằng bản đó rồi tự khởi động lại (~10 giây). Dữ liệu hiện tại sẽ bị ghi đè — hãy tải bản sao lưu mới trước khi khôi phục.")
            }

            if let status {
                Section {
                    Label(status, systemImage: statusIsError ? "exclamationmark.triangle.fill" : "checkmark.seal.fill")
                        .font(.footnote)
                        .foregroundStyle(statusIsError ? .red : .green)
                }
            }
        }
        .navigationTitle("Sao lưu & Khôi phục")
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
        .overlay {
            if busy {
                ZStack {
                    Color.black.opacity(0.25).ignoresSafeArea()
                    VStack(spacing: 10) {
                        ProgressView()
                        Text(busyText).font(.caption).foregroundStyle(.secondary)
                    }
                    .padding(20).background(.regularMaterial)
                    .clipShape(RoundedRectangle(cornerRadius: 14))
                }
            }
        }
        .sheet(isPresented: $showPicker) {
            DocumentPicker(contentTypes: [.zip, .archive, .data],
                           allowsMultipleSelection: false, asCopy: true) { urls in
                if let u = urls.first { pendingRestore = u; showRestoreConfirm = true }
            }
        }
        .alert("Khôi phục dữ liệu?", isPresented: $showRestoreConfirm) {
            Button("Khôi phục", role: .destructive) { Task { await doRestore() } }
            Button("Huỷ", role: .cancel) { pendingRestore = nil }
        } message: {
            Text("Toàn bộ dữ liệu hiện tại sẽ bị THAY bằng file này và máy chủ khởi động lại (~10 giây). Không thể hoàn tác. Tiếp tục?")
        }
    }

    // ---- Actions ----
    private func load() async {
        if let c = try? await store.api.backupConfig() {
            cfg = c; chatDraft = c.chatId
        }
        loading = false
    }

    private func downloadToDevice() async {
        busy = true; busyText = "Đang tạo bản sao lưu…"; status = nil
        do {
            let (url, name) = try await store.api.downloadBackup()
            busy = false
            keniosPresentShare([url])
            setStatus("Đã tạo \(name) — chọn nơi lưu trong bảng Chia sẻ.", error: false)
        } catch {
            busy = false
            setStatus("Tải sao lưu lỗi: \(error.localizedDescription)", error: true)
        }
    }

    private func saveChat() async {
        busy = true; busyText = "Đang lưu…"
        do {
            try await store.api.setBackupConfig(chatId: chatDraft.trimmingCharacters(in: .whitespaces))
            cfg.chatId = chatDraft
            setStatus("Đã lưu Chat ID nhận sao lưu.", error: false)
        } catch { setStatus("Lưu lỗi: \(error.localizedDescription)", error: true) }
        busy = false
    }

    private func backupNow() async {
        busy = true; busyText = "Đang gửi về Telegram…"; status = nil
        do {
            let r = try await store.api.backupNow()
            setStatus(r.message, error: false)
            await load()
        } catch { setStatus("Gửi lỗi: \(error.localizedDescription)", error: true) }
        busy = false
    }

    private func doRestore() async {
        guard let url = pendingRestore else { return }
        busy = true; busyText = "Đang tải lên & khôi phục…"; status = nil
        defer { pendingRestore = nil }
        do {
            let r = try await store.api.restoreBackup(fileURL: url)
            busy = false
            setStatus(r.message + " Chờ ~10 giây rồi mở lại app.", error: false)
        } catch {
            busy = false
            setStatus("Khôi phục lỗi: \(error.localizedDescription)", error: true)
        }
    }

    private func setStatus(_ s: String, error: Bool) {
        status = s; statusIsError = error
    }
}
