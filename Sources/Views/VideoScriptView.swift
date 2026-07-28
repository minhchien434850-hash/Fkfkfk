import SwiftUI
import UniformTypeIdentifiers

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
    @State private var showPicker = false

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
                        Text("AI sẽ XEM video rồi tự viết 1 kịch bản thuyết minh tiếng Việt để đọc. Dán link (TikTok/YouTube/FB…) hoặc chọn video từ máy.")
                            .font(.caption2).foregroundStyle(.secondary)

                        TextField("Dán link video…", text: $link)
                            .textInputAutocapitalization(.never).autocorrectionDisabled()
                            .keyboardType(.URL).font(.callout)
                            .padding(10).background(Color(.secondarySystemBackground))
                            .clipShape(RoundedRectangle(cornerRadius: 10))

                        HStack {
                            Button { Task { await generate(url: linkTrim, fileId: nil) } } label: {
                                HStack {
                                    if busy { ProgressView().padding(.trailing, 4) }
                                    Label(busy ? "Đang xử lý…" : "Tạo từ link", systemImage: "wand.and.stars")
                                        .frame(maxWidth: .infinity)
                                }
                            }.buttonStyle(.borderedProminent).tint(Theme.accent)
                                .disabled(busy || linkTrim.isEmpty)

                            Button { showPicker = true } label: {
                                Label("Từ máy", systemImage: "square.and.arrow.up")
                            }.buttonStyle(.bordered).disabled(busy)
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
        }
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
