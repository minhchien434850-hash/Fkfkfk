import SwiftUI
import UniformTypeIdentifiers
import PhotosUI
import Photos

// AI XEM video (trích khung hình) → VIẾT KỊCH BẢN thuyết minh tiếng Việt → ĐỌC bằng giọng TTS.
// TTSEngine() tự nạp lại giọng/động cơ đã lưu → đọc ĐÚNG giọng người dùng chọn ở mục "Đọc (TTS)".
struct VideoScriptView: View {
    @EnvironmentObject var store: AppStore
    @StateObject private var tts = TTSEngine()

    @State private var link = ""
    @State private var style = "Thuyết minh tự nhiên, cuốn hút"
    @State private var busy = false
    @State private var status = ""
    @State private var script = ""
    @State private var errorMsg: String?
    @State private var showPicker = false            // bộ chọn TỆP (Files)
    @State private var photoItem: PhotosPickerItem?  // chọn từ THƯ VIỆN ảnh/video của máy
    @State private var showLibrary = false           // chọn video đã có trong Thư viện app
    @State private var libFiles: [FileItem] = []
    @State private var libLoading = false

    // ----- Lồng tiếng TOÀN BỘ video (khớp thời gian) + làm nét + lưu về máy -----
    @State private var lastSource: (url: String?, fileId: Int?) = (nil, nil)
    @State private var narHeight = 1080
    @State private var narSharpen = 0.8
    @State private var narDenoise = false
    @State private var narKeepOrig = true
    @State private var narOrigVol = 0.18
    @State private var narBusy = false
    @State private var narStep = ""
    @State private var narProgress = 0
    @State private var narError: String?
    @State private var narFileId: Int?
    @State private var narFilename = ""
    @State private var narSize = 0
    @State private var savingPhotos = false
    @State private var saveMsg: String?
    @State private var narTask: Task<Void, Never>?

    // ----- Khoá AI dùng chung (CHỈ ADMIN) — AI cần khoá này mới "xem" được video -----
    @State private var aiKeyDraft = ""
    @State private var aiKeySet = false
    @State private var aiKeyMasked = ""
    @State private var aiProvider = ""
    @State private var aiModel = ""
    @State private var aiKeyBusy = false
    @State private var aiKeyMsg: String?
    @State private var aiVisionReady = true

    private var linkTrim: String { link.trimmingCharacters(in: .whitespacesAndNewlines) }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    KHeroHeader(icon: "film.stack.fill",
                                title: "AI xem video · viết kịch bản",
                                subtitle: "Nhìn video → viết lời thoại → đọc bằng giọng TTS")

                    localSection("Nguồn video") {
                        Text("AI sẽ XEM video rồi tự viết 1 kịch bản thuyết minh tiếng Việt để đọc. Dán link (TikTok/YouTube/FB…), chọn video trong THƯ VIỆN máy, trong TỆP, hoặc video đã có trong Thư viện app.")
                            .font(.caption2).foregroundStyle(.secondary)

                        TextField("Dán link video…", text: $link)
                            .textInputAutocapitalization(.never).autocorrectionDisabled()
                            .keyboardType(.URL).font(.callout)
                            .padding(10).background(Color(.secondarySystemBackground))
                            .clipShape(RoundedRectangle(cornerRadius: 10))

                        Button { Task { await generate(url: linkTrim, fileId: nil) } } label: {
                            HStack {
                                if busy { ProgressView().padding(.trailing, 4) }
                                Label(busy ? "Đang xử lý…" : "Tạo từ link", systemImage: "wand.and.stars")
                                    .frame(maxWidth: .infinity)
                            }
                        }.buttonStyle(.borderedProminent).tint(Theme.accent)
                            .disabled(busy || linkTrim.isEmpty)

                        Text("Hoặc chọn video có sẵn").font(.caption).foregroundStyle(.secondary)
                        HStack(spacing: 8) {
                            // 1) THƯ VIỆN ảnh/video của máy (Photos)
                            PhotosPicker(selection: $photoItem, matching: .videos) {
                                Label("Thư viện máy", systemImage: "photo.stack.fill")
                                    .font(.caption).frame(maxWidth: .infinity)
                                    .padding(.vertical, 8)
                                    .background(Color(.secondarySystemBackground))
                                    .clipShape(RoundedRectangle(cornerRadius: 10))
                            }.disabled(busy)

                            // 2) Ứng dụng Tệp (Files / iCloud Drive)
                            Button { showPicker = true } label: {
                                Label("Tệp", systemImage: "folder.fill")
                                    .font(.caption).frame(maxWidth: .infinity)
                                    .padding(.vertical, 8)
                                    .background(Color(.secondarySystemBackground))
                                    .clipShape(RoundedRectangle(cornerRadius: 10))
                            }.buttonStyle(.plain).disabled(busy)

                            // 3) Video đã có trong Thư viện của app (đã tải/đã lưu)
                            Button { showLibrary = true; Task { await loadLibrary() } } label: {
                                Label("Thư viện app", systemImage: "tray.full.fill")
                                    .font(.caption).frame(maxWidth: .infinity)
                                    .padding(.vertical, 8)
                                    .background(Color(.secondarySystemBackground))
                                    .clipShape(RoundedRectangle(cornerRadius: 10))
                            }.buttonStyle(.plain).disabled(busy)
                        }

                        Text("Kiểu thuyết minh").font(.caption).foregroundStyle(.secondary)
                        TextField("VD: hài hước · review sản phẩm · kể chuyện…", text: $style)
                            .font(.callout)
                            .padding(10).background(Color(.secondarySystemBackground))
                            .clipShape(RoundedRectangle(cornerRadius: 10))

                        if !status.isEmpty {
                            Text(status).font(.caption2).foregroundStyle(.secondary)
                        }
                        if let errorMsg {
                            Text("⚠️ " + errorMsg).font(.caption2).foregroundStyle(.red)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }

                    // LỒNG TIẾNG TOÀN BỘ video (khớp thời gian) + làm nét + lưu về máy
                    narrateSection

                    // ADMIN: khoá AI dùng chung — AI phải có khoá này mới XEM được video.
                    if store.isAdmin { adminAIKeySection }

                    // CHỌN GIỌNG NGAY TẠI ĐÂY (đầy đủ giọng máy + ElevenLabs biểu cảm,
                    // admin nhập API key tại chỗ) — không cần vào mục "Đọc (TTS)".
                    TTSVoicePickerSection(tts: tts)

                    if !script.isEmpty {
                        localSection("Kịch bản (sửa được)") {
                            TextEditor(text: $script).frame(minHeight: 160)
                                .padding(6).background(Color(.secondarySystemBackground))
                                .clipShape(RoundedRectangle(cornerRadius: 10))
                            HStack {
                                Button { tts.speak(script) } label: {
                                    Label("Đọc bằng giọng TTS", systemImage: "play.circle.fill")
                                        .frame(maxWidth: .infinity)
                                }.buttonStyle(.borderedProminent).tint(.green)
                                Button { tts.stop() } label: {
                                    Label("Dừng", systemImage: "stop.circle.fill")
                                }.buttonStyle(.bordered).tint(.red)
                            }
                            Text("Đọc bằng giọng bạn chọn ở mục “Giọng đọc” phía trên (đổi được ngay tại đây).")
                                .font(.caption2).foregroundStyle(.secondary)
                        }
                    }
                }
                .padding()
            }
            .navigationTitle("AI xem video")
            .navigationBarTitleDisplayMode(.inline)
            .task { await refreshAIKey() }
            .sheet(isPresented: $showPicker) {
                DocumentPicker(contentTypes: [.movie, .video, .mpeg4Movie],
                               allowsMultipleSelection: false, asCopy: true) { urls in
                    guard let u = urls.first else { return }
                    Task { await uploadThenGenerate(u) }
                }.ignoresSafeArea()
            }
            // Chọn video từ THƯ VIỆN ảnh/video của máy → tải lên rồi cho AI xem.
            .onChange(of: photoItem) { item in
                guard let item else { return }
                Task { await handlePhotoPick(item) }
            }
            // Chọn video ĐÃ CÓ trong Thư viện app → dùng thẳng file_id (không cần tải lại).
            .sheet(isPresented: $showLibrary) { librarySheet }
        }
    }

    // ----- LỒNG TIẾNG CẢ VIDEO: cấu hình làm nét + tiến độ + lưu về máy -----
    @ViewBuilder private var narrateSection: some View {
        localSection("Lồng tiếng cả video (khớp thời gian)") {
            Text("AI xem hết video, viết lời bình THEO MỐC GIỜ rồi ghép giọng đọc vào đúng cảnh, xuất ra video mới để lưu về máy.")
                .font(.caption2).foregroundStyle(.secondary)

            // Độ nét / phân giải
            Text("Độ nét (phân giải)").font(.caption).foregroundStyle(.secondary)
            Picker("Độ nét", selection: $narHeight) {
                Text("720p").tag(720)
                Text("1080p (Full HD)").tag(1080)
                Text("2K").tag(1440)
                Text("4K").tag(2160)
            }.pickerStyle(.segmented)

            VStack(alignment: .leading, spacing: 2) {
                Text("Làm nét: \(String(format: "%.1f", narSharpen))\(narSharpen < 0.05 ? " (tắt)" : "")")
                    .font(.caption2).foregroundStyle(.secondary)
                Slider(value: $narSharpen, in: 0...1.6).tint(Theme.accent)
            }
            Toggle(isOn: $narDenoise) {
                Label("Khử nhiễu (video mờ/tối)", systemImage: "sparkles").font(.caption)
            }.tint(Theme.accent)
            Toggle(isOn: $narKeepOrig) {
                Label("Giữ tiếng gốc (nhỏ) dưới lời bình", systemImage: "waveform").font(.caption)
            }.tint(Theme.accent)
            if narKeepOrig {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Âm lượng tiếng gốc: \(Int(narOrigVol * 100))%")
                        .font(.caption2).foregroundStyle(.secondary)
                    Slider(value: $narOrigVol, in: 0...0.6).tint(Theme.accent)
                }
            }

            // Bắt đầu / tiến độ
            if narBusy {
                VStack(alignment: .leading, spacing: 6) {
                    ProgressView(value: Double(narProgress), total: 100).tint(Theme.accent)
                    HStack {
                        Text("\(narStep) (\(narProgress)%)").font(.caption2).foregroundStyle(.secondary)
                        Spacer()
                        Button("Huỷ") { narTask?.cancel(); narTask = nil; narBusy = false; narStep = "" }
                            .font(.caption2)
                    }
                    Text("Video dài có thể mất vài phút. Bạn cứ để màn hình này mở.")
                        .font(.caption2).foregroundStyle(.secondary)
                }
            } else {
                Button { startNarrate() } label: {
                    Label("Lồng tiếng cả video", systemImage: "waveform.badge.mic")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent).tint(.purple)
                .disabled(busy || (lastSource.url == nil && lastSource.fileId == nil))
                if lastSource.url == nil && lastSource.fileId == nil {
                    Text("Hãy chọn nguồn video ở trên trước (dán link hoặc chọn video).")
                        .font(.caption2).foregroundStyle(.secondary)
                }
            }

            if let narError {
                Text("⚠️ " + narError).font(.caption2).foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
            }

            // Kết quả → lưu về máy
            if let fid = narFileId {
                Divider()
                HStack(spacing: 6) {
                    Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                    VStack(alignment: .leading, spacing: 1) {
                        Text("Xong: \(narFilename)").font(.caption.bold()).lineLimit(1)
                        if narSize > 0 {
                            Text(byteText(narSize)).font(.caption2).foregroundStyle(.secondary)
                        }
                    }
                }
                Button { Task { await saveToPhotos(fid) } } label: {
                    HStack {
                        if savingPhotos { ProgressView().scaleEffect(0.7).padding(.trailing, 2) }
                        Label("Lưu video về máy", systemImage: "square.and.arrow.down.fill")
                            .frame(maxWidth: .infinity)
                    }
                }.buttonStyle(.borderedProminent).tint(.green).disabled(savingPhotos)
                if let saveMsg {
                    Text(saveMsg).font(.caption2)
                        .foregroundStyle(saveMsg.hasSuffix("✓") ? .green : .red)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private func startNarrate() {
        narError = nil; narFileId = nil; saveMsg = nil
        narBusy = true; narProgress = 0; narStep = "Đang gửi yêu cầu…"
        narTask = Task {
            do {
                let r = try await store.api.startVideoNarrate(
                    url: lastSource.url, fileId: lastSource.fileId, style: style,
                    height: narHeight, sharpen: narSharpen, denoise: narDenoise,
                    keepOriginal: narKeepOrig, origVolume: narOrigVol)
                // Hỏi tiến độ mỗi 2 giây cho tới khi xong/lỗi.
                while !Task.isCancelled {
                    try? await Task.sleep(nanoseconds: 2_000_000_000)
                    if Task.isCancelled { break }
                    let st = try await store.api.videoNarrateStatus(r.job_id)
                    narStep = st.step ?? ""
                    narProgress = st.progress ?? narProgress
                    if st.status == "done" {
                        narFileId = st.file_id
                        narFilename = st.filename ?? "video.mp4"
                        narSize = st.size ?? 0
                        if let s = st.script, !s.isEmpty { script = s }
                        narBusy = false; return
                    }
                    if st.status == "error" {
                        narError = st.error ?? "Lỗi không rõ."
                        narBusy = false; return
                    }
                }
            } catch {
                narError = error.localizedDescription
            }
            narBusy = false
        }
    }

    /// Tải video kết quả rồi LƯU VÀO THƯ VIỆN ẢNH của máy.
    private func saveToPhotos(_ fileId: Int) async {
        savingPhotos = true; saveMsg = nil
        do {
            let (tmpURL, filename) = try await store.api.downloadFileRaw(fileId)
            let cache = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            let dest = cache.appendingPathComponent(filename)
            try? FileManager.default.removeItem(at: dest)
            try FileManager.default.copyItem(at: tmpURL, to: dest)

            let status = await withCheckedContinuation { (c: CheckedContinuation<PHAuthorizationStatus, Never>) in
                PHPhotoLibrary.requestAuthorization(for: .addOnly) { c.resume(returning: $0) }
            }
            guard status == .authorized || status == .limited else {
                saveMsg = "Chưa được cấp quyền. Vào Cài đặt > KENIOS > Ảnh để bật."
                savingPhotos = false; return
            }
            try await PHPhotoLibrary.shared().performChanges {
                PHAssetCreationRequest.creationRequestForAssetFromVideo(atFileURL: dest)
            }
            try? FileManager.default.removeItem(at: dest)
            saveMsg = "Đã lưu video vào Thư viện máy ✓"
        } catch {
            saveMsg = "Lưu thất bại: \(error.localizedDescription)"
        }
        savingPhotos = false
    }

    // ----- ADMIN: nhập khoá AI dùng chung (bắt buộc để AI xem được video) -----
    @ViewBuilder private var adminAIKeySection: some View {
        localSection("Admin · Khoá AI (dùng chung)") {
            if aiKeySet {
                HStack(spacing: 6) {
                    Image(systemName: "checkmark.seal.fill").foregroundStyle(.green)
                    Text("Đã có khoá: \(aiKeyMasked)").font(.caption2).foregroundStyle(.green)
                }
                Text("Đang dùng: \(aiProvider.isEmpty ? "—" : aiProvider) · \(aiModel)")
                    .font(.caption2).foregroundStyle(.secondary)
                if !aiVisionReady {
                    Text("⚠️ Nhà cung cấp này thường KHÔNG xem được ảnh (vd Groq/llama) → “AI xem video” sẽ báo lỗi. Nên dùng khoá Gemini (miễn phí, xem ảnh tốt).")
                        .font(.caption2).foregroundStyle(.orange)
                        .fixedSize(horizontal: false, vertical: true)
                }
            } else {
                Text("⚠️ Chưa có khoá AI — tính năng “AI xem video” chưa chạy được. Dán khoá vào ô dưới.")
                    .font(.caption2).foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            }

            SecureField("Dán khoá AI (nên dùng Gemini: AIza… / AQ.…)", text: $aiKeyDraft)
                .font(.caption).autocorrectionDisabled().textInputAutocapitalization(.never)
                .padding(8).background(Color(.secondarySystemBackground))
                .clipShape(RoundedRectangle(cornerRadius: 8))

            HStack {
                Button { Task { await saveAIKey(aiKeyDraft.trimmingCharacters(in: .whitespacesAndNewlines)) } } label: {
                    HStack {
                        if aiKeyBusy { ProgressView().scaleEffect(0.7).padding(.trailing, 2) }
                        Label("Lưu & kiểm tra", systemImage: "checkmark.circle.fill").font(.caption)
                    }
                }
                .buttonStyle(.borderedProminent).tint(.green)
                .disabled(aiKeyBusy || aiKeyDraft.trimmingCharacters(in: .whitespaces).isEmpty)

                if aiKeySet {
                    Button { Task { await saveAIKey("") } } label: {
                        Label("Xoá", systemImage: "trash").font(.caption)
                    }.buttonStyle(.bordered).tint(.red).disabled(aiKeyBusy)
                }
            }

            if let aiKeyMsg {
                Text(aiKeyMsg).font(.caption2)
                    .foregroundStyle(aiKeyMsg.hasPrefix("✓") ? .green : .red)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Text("Khoá lưu trên máy chủ, KHÔNG hiện cho khách. Đặt 1 lần → mọi khách dùng được “AI xem video”. Lấy khoá Gemini miễn phí tại aistudio.google.com.")
                .font(.caption2).foregroundStyle(.secondary)
        }
    }

    private func refreshAIKey() async {
        guard store.isAdmin else { return }
        if let st = try? await store.api.aiKeyStatus() {
            aiKeySet = st.set; aiKeyMasked = st.masked
            aiProvider = st.provider; aiModel = st.model
            aiVisionReady = ["gemini", "anthropic", "openai"].contains(st.provider)
        }
    }

    private func saveAIKey(_ k: String) async {
        aiKeyBusy = true; aiKeyMsg = nil
        do {
            let r = try await store.api.setAIServerKey(k)
            aiKeyDraft = ""
            if k.isEmpty {
                aiKeyMsg = "✓ Đã xoá khoá AI."
            } else if r.test_ok == false {
                aiKeyMsg = "Khoá đã lưu nhưng gọi thử LỖI: \(r.test_msg ?? "không rõ")"
            } else {
                aiKeyMsg = "✓ Đã lưu & gọi thử OK (\(r.provider) · \(r.model))."
            }
            aiVisionReady = r.vision_ready ?? true
            await refreshAIKey()
        } catch {
            aiKeyMsg = error.localizedDescription
        }
        aiKeyBusy = false
    }

    @ViewBuilder private func localSection<C: View>(_ title: String, @ViewBuilder _ content: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title).font(.headline)
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .kCard(18)
    }

    // ----- Chọn video đã có trong THƯ VIỆN của app -----
    @ViewBuilder private var librarySheet: some View {
        NavigationStack {
            Group {
                if libLoading {
                    ProgressView("Đang tải danh sách…")
                } else if libFiles.isEmpty {
                    VStack(spacing: 8) {
                        Image(systemName: "tray").font(.largeTitle).foregroundStyle(.secondary)
                        Text("Chưa có video nào trong Thư viện app.")
                            .font(.caption).foregroundStyle(.secondary)
                        Text("Tải video về bằng mục Thư viện / Chuyển đổi, hoặc dùng “Thư viện máy”.")
                            .font(.caption2).foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }.padding()
                } else {
                    List(libFiles) { f in
                        Button {
                            showLibrary = false
                            Task { await generate(url: nil, fileId: f.id) }
                        } label: {
                            HStack(spacing: 10) {
                                Image(systemName: "film.fill").foregroundStyle(Theme.accent)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(f.name).font(.caption.bold()).lineLimit(1)
                                    if let s = f.size {
                                        Text(byteText(s)).font(.caption2).foregroundStyle(.secondary)
                                    }
                                }
                                Spacer()
                                Image(systemName: "chevron.right").font(.caption2).foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
            .navigationTitle("Chọn video trong app")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Đóng") { showLibrary = false }
                }
            }
        }
    }

    private func byteText(_ n: Int) -> String {
        let mb = Double(n) / 1_048_576.0
        return mb >= 1 ? String(format: "%.1f MB", mb) : String(format: "%.0f KB", Double(n) / 1024.0)
    }

    /// Lấy các file trong Thư viện app rồi LỌC theo đuôi video.
    private func loadLibrary() async {
        libLoading = true
        let exts = ["mp4", "mov", "m4v", "webm", "mkv", "avi", "3gp"]
        if let all = try? await store.api.listFiles(category: nil) {
            libFiles = all.filter { f in
                exts.contains((f.name as NSString).pathExtension.lowercased())
            }
        } else {
            libFiles = []
        }
        libLoading = false
    }

    /// Video chọn từ THƯ VIỆN máy → chép ra tệp tạm → tải lên (stream) → cho AI xem.
    private func handlePhotoPick(_ item: PhotosPickerItem) async {
        busy = true; errorMsg = nil; script = ""; status = "Đang đọc video từ thư viện máy…"
        defer { photoItem = nil }
        do {
            guard let movie = try await item.loadTransferable(type: EditMovie.self) else {
                busy = false; status = ""; errorMsg = "Không đọc được video đã chọn."; return
            }
            status = "Đang tải video lên máy chủ…"
            let up = try await store.api.uploadFileRaw(
                name: movie.url.lastPathComponent, category: "document", fileURL: movie.url)
            try? FileManager.default.removeItem(at: movie.url)   // dọn tệp tạm
            await generate(url: nil, fileId: up.id)
        } catch {
            busy = false; status = ""; errorMsg = error.localizedDescription
        }
    }

    private func uploadThenGenerate(_ fileURL: URL) async {
        busy = true; errorMsg = nil; script = ""; status = "Đang tải video lên máy chủ…"
        let access = fileURL.startAccessingSecurityScopedResource()
        defer { if access { fileURL.stopAccessingSecurityScopedResource() } }
        do {
            let up = try await store.api.uploadFileRaw(
                name: fileURL.lastPathComponent, category: "document", fileURL: fileURL)
            await generate(url: nil, fileId: up.id)
        } catch {
            busy = false; status = ""; errorMsg = error.localizedDescription
        }
    }

    private func generate(url: String?, fileId: Int?) async {
        busy = true; errorMsg = nil; script = ""
        lastSource = (url, fileId)   // nhớ nguồn để dùng cho "Lồng tiếng cả video"
        narFileId = nil; narError = nil; saveMsg = nil
        status = fileId != nil ? "AI đang xem video & viết kịch bản…" : "Đang tải & phân tích video…"
        do {
            let r = try await store.api.videoScript(url: url, fileId: fileId, style: style)
            script = r.script
            status = "Xong — AI đã xem \(r.frames) khung hình."
        } catch {
            errorMsg = error.localizedDescription
            status = ""
        }
        busy = false
    }
}
