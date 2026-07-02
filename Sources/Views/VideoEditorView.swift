import SwiftUI
import AVFoundation
import PhotosUI
import Photos
import CoreImage
import CoreImage.CIFilterBuiltins
import UniformTypeIdentifiers
import Vision

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
    // Công cụ nâng cao: làm nét (deblur) + giảm nhiễu
    @State private var sharpen = 0.0       // 0 ... 2 (0 = không làm nét)
    @State private var denoise = 0.0       // 0 ... 1 (0 = không giảm nhiễu)
    @State private var speed = 1.0         // 0.25 ... 4 (tốc độ phát; 1 = giữ nguyên)
    @State private var removeBg = false    // Xoá nền/tách người → làm mờ phông (Vision)
    @State private var loading = false
    @State private var exporting = false
    @State private var outputURL: URL?
    @State private var info: String?
    @State private var error: String?
    @State private var savingToPhotos = false
    @State private var saveMsg: String?

    private let filterNames = ["Gốc", "Rực rỡ", "Đen trắng", "Ấm", "Lạnh", "Cổ điển"]

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
                    // Cắt video
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Cắt video").font(.subheadline.bold())
                        HStack { Text("Bắt đầu"); Spacer(); Text(timeStr(trimStart)).foregroundStyle(.secondary) }
                        Slider(value: $trimStart, in: 0...max(0.1, duration)) { _ in clampTrim() }
                        HStack { Text("Kết thúc"); Spacer(); Text(timeStr(trimEnd)).foregroundStyle(.secondary) }
                        Slider(value: $trimEnd, in: 0...max(0.1, duration)) { _ in clampTrim() }
                        Text("Độ dài sau cắt: \(timeStr(max(0, trimEnd - trimStart)))")
                            .font(.caption).foregroundStyle(.green)
                    }
                    .padding().kCard(16)

                    // Bộ lọc màu
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Bộ lọc").font(.subheadline.bold())
                        Picker("Bộ lọc", selection: $filter) {
                            ForEach(0..<filterNames.count, id: \.self) { i in
                                Text(filterNames[i]).tag(i)
                            }
                        }.pickerStyle(.segmented)

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

                    // Công cụ nâng cao: làm nét video mờ + giảm nhiễu
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Nâng cao").font(.subheadline.bold())
                        HStack { Text("Làm nét (Sharpen)"); Spacer(); Text(String(format: "%.1f", sharpen)) }
                            .font(.caption)
                        Slider(value: $sharpen, in: 0...2)
                        HStack { Text("Giảm nhiễu (Denoise)"); Spacer(); Text(String(format: "%.0f%%", denoise*100)) }
                            .font(.caption)
                        Slider(value: $denoise, in: 0...1)

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
                        Text("Kéo 'Làm nét' để video mờ nét hơn; 'Giảm nhiễu' làm mịn hạt nhiễu; 'Tốc độ' làm nhanh/chậm clip. Áp dụng khi xuất video.")
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
                } else {
                    error = "Không đọc được video."
                }
            } catch { self.error = error.localizedDescription }
            loading = false
        }
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
        return AVVideoComposition(asset: asset) { request in
            let src = request.sourceImage
            var img = src.clampedToExtent()

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
            default: break
            }

            request.finish(with: img.cropped(to: src.extent), context: Self.ciCtx)
        }
    }

    private func export() async {
        guard let inputURL else { return }
        exporting = true; error = nil; info = nil; outputURL = nil
        let asset = AVURLAsset(url: inputURL)
        let start = CMTime(seconds: trimStart, preferredTimescale: 600)
        let end = CMTime(seconds: trimEnd, preferredTimescale: 600)
        let range = CMTimeRange(start: start, end: end)

        // Nguồn xuất: nếu đổi TỐC ĐỘ → dựng composition rồi scaleTimeRange; nếu không → dùng asset gốc.
        let exportAsset: AVAsset
        let exportRange: CMTimeRange
        if abs(speed - 1.0) > 0.01 {
            let comp = AVMutableComposition()
            do {
                if let vTrack = try await asset.loadTracks(withMediaType: .video).first {
                    let cv = comp.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid)
                    try cv?.insertTimeRange(range, of: vTrack, at: .zero)
                    cv?.preferredTransform = try await vTrack.load(.preferredTransform)
                }
                if let aTrack = try await asset.loadTracks(withMediaType: .audio).first {
                    let ca = comp.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid)
                    try? ca?.insertTimeRange(range, of: aTrack, at: .zero)
                }
            } catch {
                self.error = "Lỗi dựng video: \(error.localizedDescription)"; exporting = false; return
            }
            let scaled = CMTime(seconds: max(0.1, (trimEnd - trimStart) / speed), preferredTimescale: 600)
            comp.scaleTimeRange(CMTimeRange(start: .zero, duration: comp.duration), toDuration: scaled)
            exportAsset = comp
            exportRange = CMTimeRange(start: .zero, duration: scaled)
        } else {
            exportAsset = asset
            exportRange = range
        }

        guard let session = AVAssetExportSession(asset: exportAsset,
                                                 presetName: AVAssetExportPresetHighestQuality) else {
            error = "Không tạo được phiên xuất."; exporting = false; return
        }
        session.videoComposition = makeComposition(exportAsset)
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
