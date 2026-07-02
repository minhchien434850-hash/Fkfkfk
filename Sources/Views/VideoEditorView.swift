import SwiftUI
import AVFoundation
import AVKit
import PhotosUI
import Photos
import CoreImage
import CoreImage.CIFilterBuiltins
import UniformTypeIdentifiers
import Vision
import Speech

// Một dòng phụ đề: thời điểm bắt đầu/kết thúc + ảnh chữ đã render sẵn (nền pill mờ).
struct CaptionSeg: Identifiable {
    let id = UUID()
    let start: Double
    let end: Double
    let text: String
    let image: CIImage
}

// §3.2 — Điểm cắt để ghép nối đoạn: vị trí (giây) + hiệu ứng chuyển cảnh + độ dài chuyển cảnh.
struct SplitPoint: Identifiable {
    let id = UUID()
    var time: Double
    var transition: Int = 1   // chỉ số trong transitionNames (1 = Mờ đen)
    var dur: Double = 0.6     // độ dài hiệu ứng chuyển cảnh (giây)
}

// Bọc video chọn từ thư viện thành Transferable (chép ra file tạm để xử lý)
struct EditMovie: Transferable {
    let url: URL
    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(contentType: .movie) { movie in
            SentTransferredFile(movie.url)
        } importing: { received in
            let dest = FileManager.default.temporaryDirectory
                .appendingPathComponent("kenios_in_\(UUID().uuidString).mov")
            try? FileManager.default.removeItem(at: dest)
            try FileManager.default.copyItem(at: received.file, to: dest)
            return EditMovie(url: dest)
        }
    }
}

// ======================== Sửa video cơ bản: cắt · lọc màu · sáng · xuất MP4 ========================
struct VideoEditorView: View {
    private static let ciCtx = CIContext()

    @State private var picker: PhotosPickerItem?
    @State private var inputURL: URL?
    @State private var duration: Double = 0
    // Timeline UI: trình phát xem trước + dải thumbnail
    @State private var player: AVPlayer?
    @State private var thumbnails: [UIImage] = []
    @State private var trimStart: Double = 0
    @State private var trimEnd: Double = 0
    @State private var filter = 0          // 0 gốc,1 rực rỡ,2 đen trắng,3 ấm,4 lạnh,5 cổ điển
    @State private var brightness = 0.0    // -0.3 ... 0.3
    @State private var saturation = 1.0    // 0 ... 2
    // §3.2 — Color grading đầy đủ
    @State private var contrast = 1.0      // 0.5 ... 1.5
    @State private var hue = 0.0           // -3.14 ... 3.14 (radian)
    @State private var highlights = 1.0    // 0 ... 1 (1 = giữ nguyên)
    @State private var shadows = 0.0       // -1 ... 1 (0 = giữ nguyên)
    // Công cụ nâng cao: làm nét (deblur) + giảm nhiễu — CHỌN MỨC (không kéo thanh)
    @State private var sharpen = 0.0       // 0 ... 2 (0 = không làm nét)
    @State private var denoise = 0.0       // 0 ... 1 (0 = không giảm nhiễu)
    // Độ phân giải xuất: 0 = giữ nguyên; 720/1080/1440/2160 = cạnh dài mục tiêu (px)
    @State private var outRes = 0
    @State private var naturalSize: CGSize = .zero   // kích thước gốc của video (để scale độ phân giải)
    // §3.2 — Cắt nhiều đoạn + chuyển cảnh (kiểu CapCut): mỗi điểm cắt có 1 hiệu ứng chuyển cảnh
    @State private var splits: [SplitPoint] = []
    @State private var speed = 1.0         // 0.25 ... 4 (tốc độ phát; 1 = giữ nguyên)
    @State private var removeBg = false    // Xoá nền/tách người → làm mờ phông (Vision)
    @State private var fadeInOut = false   // Chuyển cảnh: mờ dần vào/ra (fade in/out)
    @State private var zoomMotion = false  // Chuyển động phóng to dần (Ken Burns / keyframe)
    // Nhạc nền
    @State private var musicURL: URL?
    @State private var musicName = ""
    @State private var musicVolume = 0.6
    @State private var originalVolume = 1.0
    @State private var showMusicPicker = false
    // Lớp chữ/tiêu đề trên video (Text overlay)
    @State private var overlayText = ""
    @State private var overlayPosY = 0.82   // 0 = đáy, 1 = đỉnh
    // Phụ đề tự động (Auto Captions)
    @State private var captions: [CaptionSeg] = []
    @State private var burnCaptions = true
    @State private var generatingCaptions = false
    @State private var captionMsg: String?
    @State private var loading = false
    @State private var exporting = false
    @State private var outputURL: URL?
    @State private var info: String?
    @State private var error: String?
    @State private var savingToPhotos = false
    @State private var saveMsg: String?

    private let filterNames = ["Gốc", "Rực rỡ", "Đen trắng", "Ấm", "Lạnh", "Cổ điển",
                               "Điện ảnh", "Kịch tính", "Mơ màng", "Xanh ngọc", "Nắng vàng", "Tương phản"]
    // Mức Làm nét / Giảm nhiễu (bỏ thanh kéo → chọn mức cho dễ)
    private let sharpenLevels: [(String, Double)] = [("Tắt", 0), ("Nhẹ", 0.5), ("Vừa", 1.0), ("Mạnh", 1.5), ("Tối đa", 2.0)]
    private let denoiseLevels: [(String, Double)] = [("Tắt", 0), ("Nhẹ", 0.25), ("Vừa", 0.5), ("Mạnh", 0.75), ("Tối đa", 1.0)]
    private let resLevels: [(String, Int)] = [("Giữ nguyên", 0), ("720p", 720), ("1080p", 1080), ("2K", 1440), ("4K", 2160)]
    // Hiệu ứng chuyển cảnh tại điểm cắt (index → tên) — chọn ngay dấu tích trên khung
    private let transitionNames = ["Không", "Mờ đen", "Chớp trắng", "Hòa tan", "Phóng to",
                                   "Trượt ngang", "Xoay", "Nhiễu số", "Nhòe mờ", "Lật", "Thu nhỏ"]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                PhotosPicker(selection: $picker, matching: .videos) {
                    Label(inputURL == nil ? "Chọn video" : "Đổi video khác",
                          systemImage: "film.stack")
                        .frame(maxWidth: .infinity).frame(height: 48)
                        .background(Theme.accent).foregroundStyle(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                }

                if loading { ProgressView("Đang nạp video...").frame(maxWidth: .infinity) }

                if inputURL != nil {
                    // Trình phát xem trước (Preview)
                    if let player {
                        VideoPlayer(player: player)
                            .frame(height: 220)
                            .clipShape(RoundedRectangle(cornerRadius: 14))
                    }

                    // Dải Timeline có thumbnail + KÉO TAY để cắt (kiểu CapCut)
                    if !thumbnails.isEmpty {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Timeline").font(.subheadline.bold())
                            trimTimeline
                            Text("Kéo 2 tay nắm vàng để chọn đoạn giữ lại. Vùng tối = bị cắt bỏ.")
                                .font(.caption2).foregroundStyle(.secondary)
                        }
                        .padding().kCard(16)

                        // §3.2 — Ghép đoạn & chuyển cảnh (kiểu CapCut)
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Ghép đoạn & chuyển cảnh").font(.subheadline.bold())
                            Button { addSplitAtPlayhead() } label: {
                                Label("Cắt đoạn tại vị trí đang xem", systemImage: "scissors")
                                    .font(.subheadline.bold()).frame(maxWidth: .infinity).frame(height: 42)
                                    .background(Theme.accent).foregroundStyle(.white)
                                    .clipShape(RoundedRectangle(cornerRadius: 10))
                            }
                            Text("Tạm dừng đúng khung muốn cắt rồi bấm nút trên. Bấm DẤU TÍCH trên đường cắt để chọn hiệu ứng chuyển cảnh.")
                                .font(.caption2).foregroundStyle(.secondary)
                            if splits.isEmpty {
                                Text("Chưa có điểm cắt nào.").font(.caption2).foregroundStyle(.secondary)
                            } else {
                                ForEach(splits) { sp in
                                    HStack {
                                        Image(systemName: "scissors").foregroundStyle(Theme.gold)
                                        Text(timeStr(sp.time)).font(.caption.monospaced())
                                        Spacer()
                                        Menu {
                                            Picker("Chuyển cảnh", selection: bindingForSplit(sp.id)) {
                                                ForEach(0..<transitionNames.count, id: \.self) { i in
                                                    Text(transitionNames[i]).tag(i)
                                                }
                                            }
                                        } label: {
                                            Label(transitionNames[min(sp.transition, transitionNames.count - 1)],
                                                  systemImage: "wand.and.stars").font(.caption.bold())
                                        }
                                        Button(role: .destructive) { removeSplit(sp.id) } label: {
                                            Image(systemName: "trash").font(.caption)
                                        }.buttonStyle(.plain)
                                    }
                                    .padding(8).background(Color(.secondarySystemBackground))
                                    .clipShape(RoundedRectangle(cornerRadius: 8))
                                }
                            }
                        }
                        .padding().kCard(16)
                    }

                    // Cắt video
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Cắt video").font(.subheadline.bold())
                        HStack { Text("Bắt đầu"); Spacer(); Text(timeStr(trimStart)).foregroundStyle(.secondary) }
                        Slider(value: $trimStart, in: 0...max(0.1, duration)) { editing in
                            clampTrim(); seekPreview(trimStart); _ = editing
                        }
                        HStack { Text("Kết thúc"); Spacer(); Text(timeStr(trimEnd)).foregroundStyle(.secondary) }
                        Slider(value: $trimEnd, in: 0...max(0.1, duration)) { editing in
                            clampTrim(); seekPreview(trimEnd); _ = editing
                        }
                        Text("Độ dài sau cắt: \(timeStr(max(0, trimEnd - trimStart)))")
                            .font(.caption).foregroundStyle(.green)
                    }
                    .padding().kCard(16)

                    // Bộ lọc màu
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Bộ lọc").font(.subheadline.bold())
                        // Nhiều bộ lọc → hàng chip cuộn ngang cho dễ chọn (thay segmented chật).
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 6) {
                                ForEach(0..<filterNames.count, id: \.self) { i in
                                    Button(filterNames[i]) { filter = i }
                                        .font(.caption2.bold())
                                        .buttonStyle(.bordered)
                                        .tint(filter == i ? Theme.accent : .gray)
                                }
                            }
                        }

                        HStack { Text("Độ sáng (Brightness)"); Spacer(); Text(String(format: "%.0f%%", brightness*100)) }
                            .font(.caption)
                        Slider(value: $brightness, in: -0.3...0.3)
                        HStack { Text("Độ tương phản (Contrast)"); Spacer(); Text(String(format: "%.2f", contrast)) }
                            .font(.caption)
                        Slider(value: $contrast, in: 0.5...1.5)
                        HStack { Text("Độ bão hòa (Saturation)"); Spacer(); Text(String(format: "%.1f", saturation)) }
                            .font(.caption)
                        Slider(value: $saturation, in: 0...2)
                        HStack { Text("Tông màu (Hue)"); Spacer(); Text(String(format: "%.0f°", hue*180/Double.pi)) }
                            .font(.caption)
                        Slider(value: $hue, in: -Double.pi...Double.pi)
                        HStack { Text("Vùng sáng (Highlights)"); Spacer(); Text(String(format: "%.2f", highlights)) }
                            .font(.caption)
                        Slider(value: $highlights, in: 0...1)
                        HStack { Text("Vùng tối (Shadows)"); Spacer(); Text(String(format: "%.2f", shadows)) }
                            .font(.caption)
                        Slider(value: $shadows, in: -1...1)
                        Button("Đặt lại màu") {
                            brightness = 0; contrast = 1; saturation = 1; hue = 0; highlights = 1; shadows = 0
                        }.font(.caption).buttonStyle(.bordered)
                    }
                    .padding().kCard(16)

                    // Công cụ nâng cao: làm nét · giảm nhiễu · độ phân giải (CHỌN MỨC, không kéo thanh)
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Nâng cao").font(.subheadline.bold())

                        // Độ phân giải xuất — phóng to để nét hơn / thu nhỏ cho gọn nhẹ
                        Text("Độ phân giải (làm nét khung hình)").font(.caption).foregroundStyle(.secondary)
                        levelChips(resLevels, isOn: { $0 == outRes }) { outRes = $0 }
                        if outRes > 0, let t = resolvedRenderSize() {
                            Text("Khung xuất: \(Int(t.width))×\(Int(t.height)) px")
                                .font(.caption2).foregroundStyle(.green)
                        }

                        // Làm nét — chọn mức
                        Text("Làm nét").font(.caption).foregroundStyle(.secondary)
                        levelChips(sharpenLevels, isOn: { abs($0 - sharpen) < 0.01 }) { sharpen = $0 }

                        // Giảm nhiễu — chọn mức
                        Text("Giảm nhiễu").font(.caption).foregroundStyle(.secondary)
                        levelChips(denoiseLevels, isOn: { abs($0 - denoise) < 0.01 }) { denoise = $0 }

                        HStack { Text("Tốc độ (Speed)"); Spacer(); Text(String(format: "%.2fx", speed)) }
                            .font(.caption)
                        HStack(spacing: 6) {
                            ForEach([0.5, 1.0, 1.5, 2.0, 3.0], id: \.self) { s in
                                Button(String(format: "%.1fx", s)) { speed = s }
                                    .font(.caption2)
                                    .buttonStyle(.bordered)
                                    .tint(abs(speed - s) < 0.01 ? Theme.accent : .gray)
                            }
                        }
                        Slider(value: $speed, in: 0.25...4)

                        Toggle(isOn: $removeBg) {
                            VStack(alignment: .leading, spacing: 1) {
                                Text("Xoá nền / tách người").font(.caption)
                                Text("Không cần phông xanh — tự làm mờ phông sau lưng người")
                                    .font(.caption2).foregroundStyle(.secondary)
                            }
                        }
                        Toggle(isOn: $fadeInOut) {
                            VStack(alignment: .leading, spacing: 1) {
                                Text("Chuyển cảnh mờ dần (Fade)").font(.caption)
                                Text("Mở đầu & kết thúc video mờ dần vào/ra")
                                    .font(.caption2).foregroundStyle(.secondary)
                            }
                        }
                        Toggle(isOn: $zoomMotion) {
                            VStack(alignment: .leading, spacing: 1) {
                                Text("Chuyển động phóng to (Ken Burns)").font(.caption)
                                Text("Tự phóng to dần theo thời gian cho video sống động")
                                    .font(.caption2).foregroundStyle(.secondary)
                            }
                        }
                        Text("Chọn 'Độ phân giải' cao để phóng to cho nét (4K = rõ nhất); 'Làm nét' tăng chi tiết cạnh; 'Giảm nhiễu' làm mịn hạt. Áp dụng khi xuất video.")
                            .font(.caption2).foregroundStyle(.secondary)
                    }
                    .padding().kCard(16)

                    // Phụ đề tự động (Auto Captions)
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Phụ đề tự động").font(.subheadline.bold())
                        Button { Task { await generateCaptions() } } label: {
                            HStack {
                                if generatingCaptions { ProgressView().padding(.trailing, 4) }
                                Label(generatingCaptions ? "Đang nhận diện lời thoại..." : "Tạo phụ đề từ giọng nói",
                                      systemImage: "captions.bubble")
                            }
                        }.disabled(generatingCaptions)
                        if !captions.isEmpty {
                            Toggle("Khắc phụ đề lên video khi xuất", isOn: $burnCaptions)
                                .font(.caption)
                            Text("Đã có \(captions.count) dòng phụ đề.").font(.caption2).foregroundStyle(.green)
                        }
                        if let captionMsg {
                            Text(captionMsg).font(.caption2)
                                .foregroundStyle(captionMsg.contains("Đã") ? .green : .orange)
                        }
                        Text("Nhận diện lời thoại tiếng Việt trong video → tạo phụ đề. Độ chính xác phụ thuộc chất lượng âm thanh & giọng đọc.")
                            .font(.caption2).foregroundStyle(.secondary)
                    }
                    .padding().kCard(16)

                    // Nhạc nền (Background music)
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Nhạc nền").font(.subheadline.bold())
                        Button { showMusicPicker = true } label: {
                            Label(musicURL == nil ? "Chọn nhạc nền" : "Đổi nhạc: \(musicName)",
                                  systemImage: "music.note.list")
                        }
                        if musicURL != nil {
                            HStack { Text("Âm lượng nhạc"); Spacer(); Text("\(Int(musicVolume*100))%") }.font(.caption)
                            Slider(value: $musicVolume, in: 0...1)
                            HStack { Text("Âm lượng gốc (video)"); Spacer(); Text("\(Int(originalVolume*100))%") }.font(.caption)
                            Slider(value: $originalVolume, in: 0...1)
                            Button("Bỏ nhạc nền") { musicURL = nil; musicName = "" }
                                .font(.caption).foregroundStyle(.red)
                        }
                        Text("Nhạc tự lặp cho vừa độ dài video. Kéo âm lượng gốc về 0 nếu chỉ muốn nghe nhạc.")
                            .font(.caption2).foregroundStyle(.secondary)
                    }
                    .padding().kCard(16)

                    // Lớp chữ / tiêu đề trên video (Text overlay)
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Chữ trên video").font(.subheadline.bold())
                        TextField("Nhập tiêu đề / chữ hiện trên video...", text: $overlayText, axis: .vertical)
                            .lineLimit(1...3)
                            .padding(10).background(Color(.secondarySystemBackground))
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                        if !overlayText.trimmingCharacters(in: .whitespaces).isEmpty {
                            HStack { Text("Vị trí dọc"); Spacer(); Text("\(Int(overlayPosY*100))%") }.font(.caption)
                            Slider(value: $overlayPosY, in: 0...1)
                        }
                        Text("Chữ hiện suốt video (khắc khi xuất). Kéo 'Vị trí dọc' để đặt trên/dưới.")
                            .font(.caption2).foregroundStyle(.secondary)
                    }
                    .padding().kCard(16)

                    // Xuất
                    Button { Task { await export() } } label: {
                        HStack {
                            if exporting { ProgressView().tint(.white) }
                            Image(systemName: "square.and.arrow.up.on.square.fill")
                            Text(exporting ? "Đang xuất video..." : "Xuất video MP4").bold()
                        }
                        .frame(maxWidth: .infinity).frame(height: 50)
                        .background(exporting ? Color.gray : Theme.purple).foregroundStyle(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                    }.disabled(exporting)

                    if let info { Text(info).font(.caption).foregroundStyle(.green) }

                    if let outputURL {
                        VStack(spacing: 10) {
                            ShareLink(item: outputURL) {
                                Label("Chia sẻ / Lưu file", systemImage: "square.and.arrow.up")
                                    .frame(maxWidth: .infinity).frame(height: 44)
                                    .background(Color(.secondarySystemBackground))
                                    .clipShape(RoundedRectangle(cornerRadius: 12))
                            }
                            Button { Task { await saveToPhotos(outputURL) } } label: {
                                HStack {
                                    if savingToPhotos { ProgressView().tint(.white) }
                                    Image(systemName: "square.and.arrow.down.fill")
                                    Text(savingToPhotos ? "Đang lưu..." : "Lưu vào Thư viện máy")
                                }
                                .font(.subheadline.bold()).foregroundStyle(.white)
                                .frame(maxWidth: .infinity).frame(height: 44)
                                .background(savingToPhotos ? Color.gray : Theme.accent)
                                .clipShape(RoundedRectangle(cornerRadius: 12))
                            }.disabled(savingToPhotos)
                            if let saveMsg {
                                Text(saveMsg).font(.caption)
                                    .foregroundStyle(saveMsg.contains("✓") ? .green : .red)
                            }
                        }
                    }
                }

                if let error { Text(error).foregroundStyle(.red).font(.caption) }

                Text("ℹ️ Sửa video cơ bản: cắt, lọc màu, chỉnh sáng. Xuất MP4 giữ độ phân giải gốc (tối đa 4K nếu nguồn 4K). Không nâng được lên 8K — đó là giới hạn thật của thiết bị.")
                    .font(.caption2).foregroundStyle(.secondary)
            }
            .padding()
        }
        .navigationTitle("Sửa video")
        .onChange(of: picker) { _ in loadPicked() }
        .sheet(isPresented: $showMusicPicker) {
            DocumentPicker(contentTypes: [.audio, .mp3, .mpeg4Audio], allowsMultipleSelection: false, asCopy: true) { urls in
                if let u = urls.first { musicURL = u; musicName = u.lastPathComponent }
            }.ignoresSafeArea()
        }
    }

    // MARK: - Helpers
    private func timeStr(_ s: Double) -> String {
        let t = Int(s.rounded())
        return String(format: "%02d:%02d", t / 60, t % 60)
    }
    private func clampTrim() {
        if trimEnd < trimStart + 0.3 { trimEnd = min(duration, trimStart + 0.3) }
    }

    private func loadPicked() {
        guard let picker else { return }
        loading = true; error = nil; outputURL = nil; info = nil
        Task {
            do {
                if let movie = try await picker.loadTransferable(type: EditMovie.self) {
                    let asset = AVURLAsset(url: movie.url)
                    let d = try await asset.load(.duration)
                    inputURL = movie.url
                    duration = max(0.1, d.seconds)
                    trimStart = 0; trimEnd = duration
                    splits = []   // video mới → xoá điểm cắt cũ
                    // Kích thước hiển thị thật (sau khi áp preferredTransform) → dùng cho scale độ phân giải.
                    if let vTrack = try? await asset.loadTracks(withMediaType: .video).first {
                        let ns = (try? await vTrack.load(.naturalSize)) ?? .zero
                        let tf = (try? await vTrack.load(.preferredTransform)) ?? .identity
                        let r = ns.applying(tf)
                        naturalSize = CGSize(width: abs(r.width), height: abs(r.height))
                    }
                    player = AVPlayer(url: movie.url)
                    thumbnails = []
                    await generateThumbnails(asset, duration: duration)
                } else {
                    error = "Không đọc được video."
                }
            } catch { self.error = error.localizedDescription }
            loading = false
        }
    }

    // Sinh ~12 thumbnail dọc theo video cho dải timeline.
    private func generateThumbnails(_ asset: AVAsset, duration: Double) async {
        let gen = AVAssetImageGenerator(asset: asset)
        gen.appliesPreferredTrackTransform = true
        gen.maximumSize = CGSize(width: 160, height: 160)
        let count = 12
        var imgs: [UIImage] = []
        for i in 0..<count {
            let t = CMTime(seconds: duration * Double(i) / Double(count), preferredTimescale: 600)
            if let cg = try? await gen.image(at: t).image {
                imgs.append(UIImage(cgImage: cg))
            }
        }
        thumbnails = imgs
    }

    // Dải timeline có 2 tay nắm kéo để cắt trực tiếp (thay thanh trượt).
    private var trimTimeline: some View {
        GeometryReader { geo in
            let w = max(1, geo.size.width)
            let dur = max(0.1, duration)
            let sX = CGFloat(trimStart / dur) * w
            let eX = CGFloat(trimEnd / dur) * w
            let handleW: CGFloat = 14
            ZStack(alignment: .leading) {
                // Dải thumbnail lấp đầy chiều rộng
                HStack(spacing: 0) {
                    ForEach(Array(thumbnails.enumerated()), id: \.offset) { _, im in
                        Image(uiImage: im).resizable().scaledToFill()
                            .frame(width: w / CGFloat(thumbnails.count), height: 60).clipped()
                    }
                }
                .frame(width: w, height: 60)
                .clipShape(RoundedRectangle(cornerRadius: 8))

                // Vùng bị cắt (tối) ở 2 đầu
                Rectangle().fill(.black.opacity(0.55)).frame(width: sX, height: 60)
                Rectangle().fill(.black.opacity(0.55)).frame(width: max(0, w - eX), height: 60)
                    .offset(x: eX)

                // Khung đoạn giữ lại
                RoundedRectangle(cornerRadius: 6).stroke(Theme.gold, lineWidth: 3)
                    .frame(width: max(0, eX - sX), height: 60).offset(x: sX)

                // Tay nắm trái (Bắt đầu)
                handleBar.frame(width: handleW, height: 60).offset(x: max(0, sX - handleW/2))
                    .gesture(DragGesture(coordinateSpace: .named("strip")).onChanged { v in
                        let t = Double(min(max(0, v.location.x), w) / w) * dur
                        trimStart = min(max(0, t), trimEnd - 0.3)
                        seekPreview(trimStart)   // xem ngay khung bắt đầu
                    })
                // Tay nắm phải (Kết thúc)
                handleBar.frame(width: handleW, height: 60).offset(x: min(w - handleW, eX - handleW/2))
                    .gesture(DragGesture(coordinateSpace: .named("strip")).onChanged { v in
                        let t = Double(min(max(0, v.location.x), w) / w) * dur
                        trimEnd = max(min(dur, t), trimStart + 0.3)
                        seekPreview(trimEnd)     // xem ngay khung kết thúc
                    })

                // §3.2 — Điểm cắt: đường cắt + DẤU TÍCH bấm để chọn chuyển cảnh (như CapCut)
                ForEach(splits) { sp in
                    let cx = CGFloat(min(max(0, sp.time / dur), 1)) * w
                    // Đường cắt dọc trên khung hình
                    Rectangle().fill(.white).frame(width: 2, height: 60)
                        .offset(x: max(0, cx - 1))
                    // Dấu tích tròn ngay đường cắt → menu chọn hiệu ứng chuyển cảnh
                    Menu {
                        Picker("Chuyển cảnh", selection: bindingForSplit(sp.id)) {
                            ForEach(0..<transitionNames.count, id: \.self) { i in
                                Text(transitionNames[i]).tag(i)
                            }
                        }
                        Button("Xoá điểm cắt", role: .destructive) { removeSplit(sp.id) }
                    } label: {
                        transitionBadge(sp.transition)
                    }
                    .offset(x: max(0, cx - 13))
                }
            }
            .coordinateSpace(name: "strip")
        }
        .frame(height: 60)
    }

    private var handleBar: some View {
        RoundedRectangle(cornerRadius: 4).fill(Theme.gold)
            .overlay(Image(systemName: "line.3.horizontal").font(.system(size: 9, weight: .bold)).foregroundStyle(.black))
    }

    // Hàng nút "chọn mức" chung (thay cho thanh kéo) — dùng cho độ phân giải / làm nét / giảm nhiễu.
    @ViewBuilder private func levelChips<T: Equatable>(_ options: [(String, T)],
                                                       isOn: @escaping (T) -> Bool,
                                                       set: @escaping (T) -> Void) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(Array(options.enumerated()), id: \.offset) { _, opt in
                    Button(opt.0) { set(opt.1) }
                        .font(.caption2.bold())
                        .buttonStyle(.bordered)
                        .tint(isOn(opt.1) ? Theme.accent : .gray)
                }
            }
        }
    }

    // Kéo tay nắm/thanh cắt tới đâu → preview NHẢY tới đúng khung đó (frame-accurate).
    private func seekPreview(_ seconds: Double) {
        guard let player else { return }
        player.pause()
        let t = CMTime(seconds: max(0, min(duration, seconds)), preferredTimescale: 600)
        player.seek(to: t, toleranceBefore: .zero, toleranceAfter: .zero)
    }

    // §3.2 — Dấu tích tròn tại điểm cắt (đổi màu/biểu tượng theo có chọn chuyển cảnh hay chưa).
    private func transitionBadge(_ t: Int) -> some View {
        Circle().fill(t > 0 ? Theme.accent : Color.black.opacity(0.6))
            .frame(width: 26, height: 26)
            .overlay(Circle().stroke(.white, lineWidth: 2))
            .overlay(Image(systemName: t > 0 ? "checkmark" : "wand.and.stars")
                        .font(.system(size: 11, weight: .heavy)).foregroundStyle(.white))
            .shadow(radius: 3)
    }

    // Binding tới hiệu ứng chuyển cảnh của 1 điểm cắt (để Picker trong Menu chỉnh trực tiếp).
    private func bindingForSplit(_ id: UUID) -> Binding<Int> {
        Binding(
            get: { splits.first(where: { $0.id == id })?.transition ?? 0 },
            set: { nv in if let i = splits.firstIndex(where: { $0.id == id }) { splits[i].transition = nv } }
        )
    }

    private func removeSplit(_ id: UUID) {
        splits.removeAll { $0.id == id }
    }

    // Cắt 1 đoạn tại vị trí đang xem trong preview (thêm điểm cắt + chuyển cảnh mặc định).
    private func addSplitAtPlayhead() {
        let t = player?.currentTime().seconds ?? trimStart
        let ct = min(max(trimStart + 0.15, t), trimEnd - 0.15)
        guard ct.isFinite, !splits.contains(where: { abs($0.time - ct) < 0.2 }) else { return }
        splits.append(SplitPoint(time: ct))
        splits.sort { $0.time < $1.time }
    }

    private func makeComposition(_ asset: AVAsset) -> AVVideoComposition {
        let f = filter
        let bright = brightness
        let sat = saturation
        let con = contrast
        let hueAngle = hue
        let hi = highlights
        let sh = shadows
        let shp = sharpen
        let dns = denoise
        let rmBg = removeBg
        // Phụ đề: nếu đổi tốc độ, thời gian khung tính theo composition đã scale → quy về thời gian gốc.
        let caps = burnCaptions ? captions : []
        let speedChanged = abs(speed - 1.0) > 0.01
        let capOffset = speedChanged ? trimStart : 0.0
        let capSpeed = speedChanged ? speed : 1.0
        // Lớp chữ trên video (render 1 lần).
        let overlayImg: CIImage? = {
            let t = overlayText.trimmingCharacters(in: .whitespacesAndNewlines)
            return t.isEmpty ? nil : renderCaption(t)
        }()
        let overlayY = overlayPosY
        let zoomOn = zoomMotion
        // Fade in/out: mốc thời gian đầu/cuối trong hệ toạ độ khung xuất.
        let fadeOn = fadeInOut
        let outStart = speedChanged ? 0.0 : trimStart
        let outEnd = speedChanged ? max(0.1, (trimEnd - trimStart) / speed) : trimEnd
        let target = resolvedRenderSize()   // độ phân giải xuất (nil = giữ nguyên)
        // §3.2 — Chuyển cảnh tại điểm cắt: quy đổi thời điểm cắt sang hệ toạ độ khung xuất.
        let splitFX: [(center: Double, half: Double, type: Int)] = splits.compactMap { sp in
            guard sp.transition > 0, sp.dur > 0.01 else { return nil }
            let c = speedChanged ? (sp.time - trimStart) / speed : sp.time
            return (c, sp.dur / 2, sp.transition)
        }
        let comp = AVVideoComposition(asset: asset) { request in
            let src = request.sourceImage
            var img = src.clampedToExtent()

            // Chuyển động phóng to dần (Ken Burns): phóng quanh tâm theo tiến độ thời gian.
            if zoomOn {
                let span = max(0.1, outEnd - outStart)
                let prog = min(1.0, max(0.0, (request.compositionTime.seconds - outStart) / span))
                let z = 1.0 + 0.18 * prog
                let cx = src.extent.midX, cy = src.extent.midY
                var tr = CGAffineTransform.identity
                tr = tr.translatedBy(x: cx, y: cy)
                tr = tr.scaledBy(x: CGFloat(z), y: CGFloat(z))
                tr = tr.translatedBy(x: -cx, y: -cy)
                img = img.transformed(by: tr).cropped(to: src.extent).clampedToExtent()
            }

            // Xoá nền / tách người: Vision tách người → làm mờ phông sau lưng (chân dung).
            if rmBg {
                let req = VNGeneratePersonSegmentationRequest()
                req.qualityLevel = .balanced
                req.outputPixelFormat = kCVPixelFormatType_OneComponent8
                let handler = VNImageRequestHandler(ciImage: img, options: [:])
                if (try? handler.perform([req])) != nil,
                   let maskBuf = req.results?.first?.pixelBuffer {
                    var mask = CIImage(cvPixelBuffer: maskBuf)
                    let sx = img.extent.width / max(1, mask.extent.width)
                    let sy = img.extent.height / max(1, mask.extent.height)
                    mask = mask.transformed(by: CGAffineTransform(scaleX: sx, y: sy))
                    let bg = img.applyingGaussianBlur(sigma: 14).cropped(to: img.extent)
                    let blend = CIFilter.blendWithMask()
                    blend.inputImage = img          // người (giữ rõ)
                    blend.backgroundImage = bg       // phông (làm mờ)
                    blend.maskImage = mask
                    img = (blend.outputImage ?? img).cropped(to: src.extent).clampedToExtent()
                }
            }

            let cc = CIFilter.colorControls()
            cc.inputImage = img
            cc.brightness = Float(bright)
            cc.saturation = Float(sat)
            cc.contrast = Float(con)
            img = cc.outputImage ?? img

            // Tông màu (Hue)
            if abs(hueAngle) > 0.001 {
                let h = CIFilter.hueAdjust(); h.inputImage = img; h.angle = Float(hueAngle)
                img = h.outputImage ?? img
            }
            // Vùng sáng / Vùng tối (Highlights / Shadows)
            if abs(hi - 1.0) > 0.001 || abs(sh) > 0.001 {
                let hs = CIFilter.highlightShadowAdjust()
                hs.inputImage = img
                hs.highlightAmount = Float(hi)
                hs.shadowAmount = Float(sh)
                img = hs.outputImage ?? img
            }
            // Giảm nhiễu (Denoise) — làm trước để không khuếch đại hạt khi làm nét.
            if dns > 0.001 {
                let nr = CIFilter.noiseReduction()
                nr.inputImage = img
                nr.noiseLevel = Float(dns * 0.05)   // 0…0.05
                nr.sharpness = 0.4
                img = nr.outputImage ?? img
            }
            // Làm nét video mờ (Sharpen)
            if shp > 0.001 {
                let sp = CIFilter.sharpenLuminance()
                sp.inputImage = img
                sp.sharpness = Float(shp)
                img = sp.outputImage ?? img
            }

            switch f {
            case 1:
                let v = CIFilter.vibrance(); v.inputImage = img; v.amount = 1.0
                img = v.outputImage ?? img
            case 2:
                let m = CIFilter.photoEffectMono(); m.inputImage = img
                img = m.outputImage ?? img
            case 3:
                let t = CIFilter.temperatureAndTint(); t.inputImage = img
                t.neutral = CIVector(x: 6500, y: 0)
                t.targetNeutral = CIVector(x: 4800, y: 0)
                img = t.outputImage ?? img
            case 4:
                let t = CIFilter.temperatureAndTint(); t.inputImage = img
                t.neutral = CIVector(x: 6500, y: 0)
                t.targetNeutral = CIVector(x: 9000, y: 0)
                img = t.outputImage ?? img
            case 5:
                let s = CIFilter.sepiaTone(); s.inputImage = img; s.intensity = 0.9
                img = s.outputImage ?? img
            case 6:   // Điện ảnh — tương phản mềm + hơi lạnh (teal/orange nhẹ)
                let t = CIFilter.temperatureAndTint(); t.inputImage = img
                t.neutral = CIVector(x: 6500, y: 0); t.targetNeutral = CIVector(x: 5600, y: 8)
                img = t.outputImage ?? img
                let cc2 = CIFilter.colorControls(); cc2.inputImage = img
                cc2.contrast = 1.08; cc2.saturation = 0.92
                img = cc2.outputImage ?? img
            case 7:   // Kịch tính — tương phản cao + nét cạnh
                let cc2 = CIFilter.colorControls(); cc2.inputImage = img
                cc2.contrast = 1.22; cc2.saturation = 1.1
                img = cc2.outputImage ?? img
            case 8:   // Mơ màng — hồng nhạt + mềm sáng
                let t = CIFilter.temperatureAndTint(); t.inputImage = img
                t.neutral = CIVector(x: 6500, y: 0); t.targetNeutral = CIVector(x: 7200, y: -12)
                img = t.outputImage ?? img
                let b = CIFilter.colorControls(); b.inputImage = img; b.brightness = 0.04; b.saturation = 1.05
                img = b.outputImage ?? img
            case 9:   // Xanh ngọc — nghiêng lạnh teal
                let t = CIFilter.temperatureAndTint(); t.inputImage = img
                t.neutral = CIVector(x: 6500, y: 0); t.targetNeutral = CIVector(x: 8200, y: 20)
                img = t.outputImage ?? img
            case 10:  // Nắng vàng — ấm rực
                let t = CIFilter.temperatureAndTint(); t.inputImage = img
                t.neutral = CIVector(x: 6500, y: 0); t.targetNeutral = CIVector(x: 4300, y: -6)
                img = t.outputImage ?? img
                let v = CIFilter.vibrance(); v.inputImage = img; v.amount = 0.5
                img = v.outputImage ?? img
            case 11:  // Tương phản — đen trắng tương phản cao
                let m = CIFilter.photoEffectMono(); m.inputImage = img
                img = m.outputImage ?? img
                let cc2 = CIFilter.colorControls(); cc2.inputImage = img; cc2.contrast = 1.25
                img = cc2.outputImage ?? img
            default: break
            }

            // Phụ đề: khắc dòng đang hoạt động vào KHUNG (đặt gần đáy, giữa).
            if !caps.isEmpty {
                let t = capOffset + request.compositionTime.seconds * capSpeed
                if let seg = caps.first(where: { t >= $0.start && t <= $0.end }) {
                    let targetW = src.extent.width * 0.92
                    let capW = max(1, seg.image.extent.width)
                    let scale = targetW / capW
                    var cap = seg.image.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
                    let tx = src.extent.minX + (src.extent.width - cap.extent.width) / 2 - cap.extent.minX
                    let ty = src.extent.minY + src.extent.height * 0.06 - cap.extent.minY
                    cap = cap.transformed(by: CGAffineTransform(translationX: tx, y: ty))
                    img = cap.composited(over: img)
                }
            }

            // Lớp chữ / tiêu đề: khắc lên video ở vị trí dọc đã chọn (hiện suốt clip).
            if let ov = overlayImg {
                let targetW = src.extent.width * 0.9
                let scale = targetW / max(1, ov.extent.width)
                var o = ov.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
                let tx = src.extent.minX + (src.extent.width - o.extent.width) / 2 - o.extent.minX
                let ty = src.extent.minY + CGFloat(overlayY) * max(0, src.extent.height - o.extent.height) - o.extent.minY
                o = o.transformed(by: CGAffineTransform(translationX: tx, y: ty))
                img = o.composited(over: img)
            }

            // Chuyển cảnh mờ dần vào/ra: 0.6s đầu và 0.6s cuối làm tối dần về đen.
            if fadeOn {
                let ct = request.compositionTime.seconds
                let fromStart = ct - outStart
                let fromEnd = outEnd - ct
                let dur = 0.6
                let f = max(0.0, min(1.0, min(fromStart / dur, fromEnd / dur)))
                if f < 0.999 {
                    let m = CIFilter.colorMatrix()
                    m.inputImage = img
                    m.rVector = CIVector(x: CGFloat(f), y: 0, z: 0, w: 0)
                    m.gVector = CIVector(x: 0, y: CGFloat(f), z: 0, w: 0)
                    m.bVector = CIVector(x: 0, y: 0, z: CGFloat(f), w: 0)
                    img = (m.outputImage ?? img).clampedToExtent()
                }
            }

            // §3.2 — Chuyển cảnh tại điểm cắt: áp hiệu ứng quanh mỗi đường cắt.
            if !splitFX.isEmpty {
                let ct = request.compositionTime.seconds
                for fx in splitFX where fx.half > 0.001 {
                    let dx = (ct - fx.center) / fx.half   // -1…1 trong cửa sổ chuyển cảnh
                    if abs(dx) < 1 {
                        img = Self.applyTransition(img, type: fx.type,
                                                   edge: 1 - abs(dx), x: dx, extent: src.extent)
                    }
                }
            }

            // Độ phân giải xuất: scale khung về kích thước mục tiêu (phóng to = nét hơn).
            var outImg = img.cropped(to: src.extent)
            if let target = target {
                let fx = target.width / max(1, src.extent.width)
                let fy = target.height / max(1, src.extent.height)
                outImg = outImg
                    .transformed(by: CGAffineTransform(translationX: -src.extent.minX, y: -src.extent.minY))
                    .transformed(by: CGAffineTransform(scaleX: fx, y: fy))
                    .cropped(to: CGRect(origin: .zero, size: target))
            }
            request.finish(with: outImg, context: Self.ciCtx)
        }
        // Đổi renderSize khi có chọn độ phân giải (giữ nguyên = không đụng, không rủi ro).
        if let target = target, let mut = comp.mutableCopy() as? AVMutableVideoComposition {
            mut.renderSize = target
            return mut
        }
        return comp
    }

    /// §3.2 — Áp 1 hiệu ứng chuyển cảnh lên khung. edge∈[0,1] (1 = ngay đường cắt), x∈[-1,1].
    static func applyTransition(_ img: CIImage, type: Int, edge: Double, x: Double, extent: CGRect) -> CIImage {
        let e = CGFloat(max(0, min(1, edge)))
        let cx = extent.midX, cy = extent.midY
        func centered(_ t: CGAffineTransform) -> CIImage {
            let m = CGAffineTransform(translationX: -cx, y: -cy)
                .concatenating(t)
                .concatenating(CGAffineTransform(translationX: cx, y: cy))
            return img.transformed(by: m).clampedToExtent().cropped(to: extent)
        }
        switch type {
        case 1: // Mờ đen — tối dần rồi sáng lại ngay đường cắt
            let m = CIFilter.colorMatrix(); m.inputImage = img
            let f = 1 - e
            m.rVector = CIVector(x: f, y: 0, z: 0, w: 0)
            m.gVector = CIVector(x: 0, y: f, z: 0, w: 0)
            m.bVector = CIVector(x: 0, y: 0, z: f, w: 0)
            return (m.outputImage ?? img).clampedToExtent().cropped(to: extent)
        case 2: // Chớp trắng
            let cc = CIFilter.colorControls(); cc.inputImage = img; cc.brightness = Float(e)
            return (cc.outputImage ?? img).clampedToExtent().cropped(to: extent)
        case 3: // Hòa tan — nhòe nhẹ
            return img.clampedToExtent().applyingGaussianBlur(sigma: Double(e) * 22).cropped(to: extent)
        case 4: // Phóng to (zoom punch)
            return centered(CGAffineTransform(scaleX: 1 + e * 0.4, y: 1 + e * 0.4))
        case 5: // Trượt ngang
            return centered(CGAffineTransform(translationX: CGFloat(x) * extent.width, y: 0))
        case 6: // Xoay
            return centered(CGAffineTransform(rotationAngle: CGFloat(x) * 0.5))
        case 7: // Nhiễu số (glitch) — vỡ hạt + lệch màu
            let p = CIFilter.pixellate(); p.inputImage = img
            p.center = CIVector(x: cx, y: cy); p.scale = Float(1 + e * 22)
            var o = p.outputImage ?? img
            let h = CIFilter.hueAdjust(); h.inputImage = o; h.angle = Float(x) * 1.5
            o = h.outputImage ?? o
            return o.clampedToExtent().cropped(to: extent)
        case 8: // Nhòe mờ (mạnh)
            return img.clampedToExtent().applyingGaussianBlur(sigma: Double(e) * 34).cropped(to: extent)
        case 9: // Lật — ép ngang về giữa rồi bung ra
            let s = max(0.05, abs(cos(CGFloat(x) * .pi / 2)))
            return centered(CGAffineTransform(scaleX: s, y: 1))
        case 10: // Thu nhỏ
            return centered(CGAffineTransform(scaleX: max(0.05, 1 - e * 0.35), y: max(0.05, 1 - e * 0.35)))
        default:
            return img
        }
    }

    /// Kích thước khung xuất theo độ phân giải đã chọn (giữ đúng tỉ lệ gốc). nil = giữ nguyên.
    private func resolvedRenderSize() -> CGSize? {
        guard outRes > 0, naturalSize.width > 1, naturalSize.height > 1 else { return nil }
        let longEdge = max(naturalSize.width, naturalSize.height)
        let factor = CGFloat(outRes) / longEdge
        var w = (naturalSize.width * factor).rounded()
        var h = (naturalSize.height * factor).rounded()
        // Encoder yêu cầu kích thước chẵn.
        w -= w.truncatingRemainder(dividingBy: 2)
        h -= h.truncatingRemainder(dividingBy: 2)
        guard w >= 2, h >= 2 else { return nil }
        return CGSize(width: w, height: h)
    }

    // MARK: - Phụ đề tự động
    private func generateCaptions() async {
        guard let inputURL else { return }
        generatingCaptions = true; captionMsg = nil
        defer { generatingCaptions = false }
        let auth = await withCheckedContinuation { (c: CheckedContinuation<SFSpeechRecognizerAuthorizationStatus, Never>) in
            SFSpeechRecognizer.requestAuthorization { c.resume(returning: $0) }
        }
        guard auth == .authorized else { captionMsg = "Chưa được cấp quyền nhận diện giọng nói."; return }
        let rec = SFSpeechRecognizer(locale: Locale(identifier: "vi-VN")) ?? SFSpeechRecognizer()
        guard let rec, rec.isAvailable else {
            captionMsg = "Thiết bị chưa hỗ trợ nhận diện giọng nói tiếng Việt."; return
        }
        let req = SFSpeechURLRecognitionRequest(url: inputURL)
        req.shouldReportPartialResults = false
        if #available(iOS 16.0, *) { req.addsPunctuation = true }
        do {
            let transcription: SFTranscription = try await withCheckedThrowingContinuation { cont in
                var done = false
                rec.recognitionTask(with: req) { res, err in
                    if done { return }
                    if let err { done = true; cont.resume(throwing: err); return }
                    if let res, res.isFinal { done = true; cont.resume(returning: res.bestTranscription) }
                }
            }
            let segs = buildCaptions(from: transcription)
            captions = segs
            captionMsg = segs.isEmpty ? "Không nhận được lời thoại rõ ràng." : "Đã tạo \(segs.count) dòng phụ đề."
        } catch {
            captionMsg = "Nhận diện thất bại: \(error.localizedDescription)"
        }
    }

    private func buildCaptions(from t: SFTranscription) -> [CaptionSeg] {
        var out: [CaptionSeg] = []
        var chunk: [SFTranscriptionSegment] = []
        func flush() {
            guard let first = chunk.first, let last = chunk.last else { return }
            let text = chunk.map { $0.substring }.joined(separator: " ").trimmingCharacters(in: .whitespaces)
            guard !text.isEmpty else { chunk = []; return }
            let start = first.timestamp
            let end = max(last.timestamp + last.duration, start + 0.8)
            if let img = renderCaption(text) {
                out.append(CaptionSeg(start: start, end: end, text: text, image: img))
            }
            chunk = []
        }
        for s in t.segments {
            chunk.append(s)
            let dur = (chunk.last!.timestamp + chunk.last!.duration) - chunk.first!.timestamp
            if chunk.count >= 8 || dur >= 3.0 { flush() }
        }
        flush()
        return out
    }

    private func renderCaption(_ text: String) -> CIImage? {
        let refWidth: CGFloat = 900
        let font = UIFont.systemFont(ofSize: 44, weight: .bold)
        let para = NSMutableParagraphStyle(); para.alignment = .center
        let attrs: [NSAttributedString.Key: Any] = [
            .font: font, .foregroundColor: UIColor.white, .paragraphStyle: para,
            .strokeColor: UIColor.black, .strokeWidth: -3.0
        ]
        let maxTextWidth = refWidth - 80
        let bounding = (text as NSString).boundingRect(
            with: CGSize(width: maxTextWidth, height: 600),
            options: [.usesLineFragmentOrigin, .usesFontLeading], attributes: attrs, context: nil)
        let textH = ceil(bounding.height)
        let size = CGSize(width: refWidth, height: textH + 34)
        let renderer = UIGraphicsImageRenderer(size: size)
        let uiImg = renderer.image { _ in
            UIColor.black.withAlphaComponent(0.45).setFill()
            UIBezierPath(roundedRect: CGRect(x: 16, y: 0, width: refWidth - 32, height: size.height), cornerRadius: 14).fill()
            (text as NSString).draw(with: CGRect(x: 40, y: 17, width: maxTextWidth, height: textH),
                                    options: [.usesLineFragmentOrigin, .usesFontLeading], attributes: attrs, context: nil)
        }
        guard let cg = uiImg.cgImage else { return nil }
        return CIImage(cgImage: cg)
    }

    private func export() async {
        guard let inputURL else { return }
        exporting = true; error = nil; info = nil; outputURL = nil
        let asset = AVURLAsset(url: inputURL)
        let start = CMTime(seconds: trimStart, preferredTimescale: 600)
        let end = CMTime(seconds: trimEnd, preferredTimescale: 600)
        let range = CMTimeRange(start: start, end: end)

        // Nguồn xuất: dựng composition nếu đổi TỐC ĐỘ hoặc có NHẠC NỀN; nếu không → dùng asset gốc.
        let speedChanged = abs(speed - 1.0) > 0.01
        let needComp = speedChanged || musicURL != nil
        let exportAsset: AVAsset
        let exportRange: CMTimeRange
        var mixToUse: AVMutableAudioMix?
        if needComp {
            let comp = AVMutableComposition()
            var origAudio: AVMutableCompositionTrack?
            do {
                if let vTrack = try await asset.loadTracks(withMediaType: .video).first {
                    let cv = comp.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid)
                    try cv?.insertTimeRange(range, of: vTrack, at: .zero)
                    cv?.preferredTransform = try await vTrack.load(.preferredTransform)
                }
                if let aTrack = try await asset.loadTracks(withMediaType: .audio).first {
                    let ca = comp.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid)
                    try? ca?.insertTimeRange(range, of: aTrack, at: .zero)
                    origAudio = ca
                }
            } catch {
                self.error = "Lỗi dựng video: \(error.localizedDescription)"; exporting = false; return
            }
            // Đổi tốc độ (scale trước khi thêm nhạc để nhạc không bị nhanh/chậm theo).
            if speedChanged {
                let scaled = CMTime(seconds: max(0.1, (trimEnd - trimStart) / speed), preferredTimescale: 600)
                comp.scaleTimeRange(CMTimeRange(start: .zero, duration: comp.duration), toDuration: scaled)
            }
            let finalDur = comp.duration
            // Thêm nhạc nền (tự lặp cho vừa độ dài video).
            var musicTrack: AVMutableCompositionTrack?
            if let musicURL {
                let musicAsset = AVURLAsset(url: musicURL)
                if let mTrack = try? await musicAsset.loadTracks(withMediaType: .audio).first {
                    let cm = comp.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid)
                    let mDur = (try? await musicAsset.load(.duration)) ?? finalDur
                    if mDur.seconds > 0.1 {
                        var t = CMTime.zero
                        while t < finalDur {
                            let seg = CMTimeMinimum(mDur, finalDur - t)
                            try? cm?.insertTimeRange(CMTimeRange(start: .zero, duration: seg), of: mTrack, at: t)
                            t = t + seg
                        }
                    }
                    musicTrack = cm
                }
            }
            // Trộn âm lượng nhạc & âm gốc.
            let mix = AVMutableAudioMix()
            var params: [AVMutableAudioMixInputParameters] = []
            if let origAudio {
                let p = AVMutableAudioMixInputParameters(track: origAudio)
                p.setVolume(Float(originalVolume), at: .zero)
                params.append(p)
            }
            if let musicTrack {
                let p = AVMutableAudioMixInputParameters(track: musicTrack)
                p.setVolume(Float(musicVolume), at: .zero)
                params.append(p)
            }
            if !params.isEmpty { mix.inputParameters = params; mixToUse = mix }
            exportAsset = comp
            exportRange = CMTimeRange(start: .zero, duration: finalDur)
        } else {
            exportAsset = asset
            exportRange = range
        }

        guard let session = AVAssetExportSession(asset: exportAsset,
                                                 presetName: AVAssetExportPresetHighestQuality) else {
            error = "Không tạo được phiên xuất."; exporting = false; return
        }
        session.videoComposition = makeComposition(exportAsset)
        session.audioMix = mixToUse
        let out = FileManager.default.temporaryDirectory
            .appendingPathComponent("kenios_edit_\(Int(Date().timeIntervalSince1970)).mp4")
        try? FileManager.default.removeItem(at: out)
        session.outputURL = out
        session.outputFileType = .mp4
        session.timeRange = exportRange

        await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
            session.exportAsynchronously { cont.resume() }
        }

        if session.status == .completed {
            outputURL = out
            let attrs = try? FileManager.default.attributesOfItem(atPath: out.path)
            let size = (attrs?[.size] as? Int) ?? 0
            info = "Xuất xong! \(humanSize(size))"
        } else {
            error = "Xuất thất bại: \(session.error?.localizedDescription ?? "lỗi không rõ")"
        }
        exporting = false
    }

    private func saveToPhotos(_ url: URL) async {
        savingToPhotos = true; saveMsg = nil
        let status = await withCheckedContinuation { (c: CheckedContinuation<PHAuthorizationStatus, Never>) in
            PHPhotoLibrary.requestAuthorization(for: .addOnly) { c.resume(returning: $0) }
        }
        guard status == .authorized || status == .limited else {
            saveMsg = "Chưa được cấp quyền lưu vào Thư viện ảnh."
            savingToPhotos = false; return
        }
        do {
            try await PHPhotoLibrary.shared().performChanges {
                PHAssetCreationRequest.creationRequestForAssetFromVideo(atFileURL: url)
            }
            saveMsg = "Đã lưu video vào Thư viện máy ✓"
        } catch {
            saveMsg = "Lưu thất bại: \(error.localizedDescription)"
        }
        savingToPhotos = false
    }
}
