import SwiftUI
import Photos
import UIKit

// ======================== Trình thiết kế Lớp phủ (Overlay) cho Live ========================
// Chọn MẪU sẵn → sửa tên kênh / dòng chữ → xuất ảnh PNG (nền trong suốt) hoặc tạo link
// để dán vào OBS / Larix làm khung overlay khi phát Live đa nền tảng.

struct OverlayTemplateInfo: Identifiable {
    let id: String
    let name: String
}

struct OverlayDesignerView: View {
    @EnvironmentObject var store: AppStore

    @State private var templateId = "livenow"
    @State private var channelName = "KÊNH CỦA BẠN"
    @State private var subtitle = "Đang phát trực tiếp"
    @State private var portrait = true
    @State private var working = false
    @State private var message: String?
    @State private var resultLink: String?

    private let templates: [OverlayTemplateInfo] = [
        .init(id: "livenow", name: "LIVE NOW"),
        .init(id: "neon",    name: "Neon"),
        .init(id: "gaming",  name: "Gaming"),
        .init(id: "minimal", name: "Tối giản"),
        .init(id: "none",    name: "Không khung"),
    ]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text(store.t("Thiết kế Lớp phủ (Overlay)", "Overlay Designer"))
                    .font(.title3.bold())
                Text(store.t("Chọn mẫu → sửa chữ → xuất ảnh PNG / tạo link để dán vào OBS/Larix làm khung Live.",
                             "Pick a template → edit text → export PNG / link to use in OBS/Larix."))
                    .font(.caption).foregroundStyle(.secondary)

                // Xem trước
                ZStack {
                    // Nền ô caro để thấy phần trong suốt
                    CheckerboardBackground()
                    OverlayCanvas(templateId: templateId, name: channelName, subtitle: subtitle)
                }
                .aspectRatio(portrait ? 9.0/16.0 : 16.0/9.0, contentMode: .fit)
                .frame(maxWidth: .infinity)
                .frame(maxHeight: 360)
                .clipShape(RoundedRectangle(cornerRadius: 14))
                .overlay(RoundedRectangle(cornerRadius: 14).stroke(.white.opacity(0.1)))

                // Hướng khung
                Picker("", selection: $portrait) {
                    Text(store.t("Dọc 9:16", "Portrait 9:16")).tag(true)
                    Text(store.t("Ngang 16:9", "Landscape 16:9")).tag(false)
                }
                .pickerStyle(.segmented)

                // Chọn MẪU
                Text(store.t("Chọn mẫu", "Choose a template")).font(.headline)
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 12) {
                        ForEach(templates) { t in
                            Button { templateId = t.id } label: {
                                VStack(spacing: 6) {
                                    ZStack {
                                        Color.black
                                        OverlayCanvas(templateId: t.id, name: channelName, subtitle: subtitle)
                                    }
                                    .aspectRatio(9.0/16.0, contentMode: .fit)
                                    .frame(width: 80, height: 142)
                                    .clipShape(RoundedRectangle(cornerRadius: 8))
                                    .overlay(RoundedRectangle(cornerRadius: 8)
                                        .stroke(templateId == t.id ? Color.red : .white.opacity(0.15),
                                                lineWidth: templateId == t.id ? 3 : 1))
                                    Text(t.name).font(.caption2)
                                        .foregroundStyle(templateId == t.id ? .red : .secondary)
                                }
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.vertical, 2)
                }

                // Sửa chữ
                if templateId != "none" {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(store.t("Tên kênh", "Channel name")).font(.caption).foregroundStyle(.secondary)
                        TextField("KÊNH CỦA BẠN", text: $channelName)
                            .padding(10).background(Color(.secondarySystemBackground))
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                        Text(store.t("Dòng phụ", "Subtitle")).font(.caption).foregroundStyle(.secondary)
                        TextField(store.t("Đang phát trực tiếp", "Live now"), text: $subtitle)
                            .padding(10).background(Color(.secondarySystemBackground))
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                    }
                }

                // Nút xuất
                Button { Task { await saveToPhotos() } } label: {
                    HStack {
                        if working { ProgressView().tint(.white) }
                        Image(systemName: "square.and.arrow.down.fill")
                        Text(store.t("Lưu ảnh PNG vào máy", "Save PNG to Photos"))
                    }
                    .font(.subheadline.bold()).foregroundStyle(.white)
                    .frame(maxWidth: .infinity).frame(height: 48)
                    .background(working ? Color.gray : Theme.accent)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                }.disabled(working)

                Button { Task { await makeLink() } } label: {
                    HStack {
                        Image(systemName: "link")
                        Text(store.t("Tạo link ảnh (dùng cho OBS)", "Create image link (for OBS)"))
                    }
                    .font(.subheadline.bold())
                    .frame(maxWidth: .infinity).frame(height: 48)
                    .overlay(RoundedRectangle(cornerRadius: 12).stroke(Theme.accent, lineWidth: 1.5))
                    .foregroundStyle(Theme.accent)
                }.disabled(working)

                if let resultLink {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(store.t("Link ảnh overlay:", "Overlay image link:")).font(.caption.bold())
                        Text(resultLink).font(.system(.caption2, design: .monospaced))
                            .foregroundStyle(Theme.accent).textSelection(.enabled).lineLimit(2)
                        Button { UIPasteboard.general.string = resultLink } label: {
                            Label(store.t("Copy link", "Copy link"), systemImage: "doc.on.doc").font(.caption)
                        }.buttonStyle(.bordered)
                    }
                    .padding(10).background(Color(.secondarySystemBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                }
                if let message {
                    Text(message).font(.caption).foregroundStyle(message.contains("✓") ? .green : .red)
                }

                Text(store.t("💡 Trong OBS/Larix: thêm nguồn ‘Hình ảnh’ → chọn ảnh PNG (hoặc dán link) → đặt lên trên video. Vì PNG nền trong suốt nên chỉ hiện khung, không che video.",
                             "💡 In OBS/Larix: add an ‘Image’ source → pick the PNG (or paste link) → place above your video. The transparent PNG shows only the frame."))
                    .font(.caption2).foregroundStyle(.secondary)
            }
            .padding()
        }
    }

    // Render canvas → PNG nền trong suốt
    @MainActor private func renderPNG() -> Data? {
        let W: CGFloat = portrait ? 1080 : 1920
        let H: CGFloat = portrait ? 1920 : 1080
        let content = OverlayCanvas(templateId: templateId, name: channelName, subtitle: subtitle)
            .frame(width: W, height: H)
        let renderer = ImageRenderer(content: content)
        renderer.scale = 1
        renderer.isOpaque = false
        return renderer.uiImage?.pngData()
    }

    private func saveToPhotos() async {
        working = true; message = nil
        defer { working = false }
        guard let data = await renderPNG() else { message = "Không tạo được ảnh."; return }
        let status = await withCheckedContinuation { (c: CheckedContinuation<PHAuthorizationStatus, Never>) in
            PHPhotoLibrary.requestAuthorization(for: .addOnly) { c.resume(returning: $0) }
        }
        guard status == .authorized || status == .limited else {
            message = "Cần cấp quyền lưu ảnh trong Cài đặt."; return
        }
        do {
            try await PHPhotoLibrary.shared().performChanges {
                PHAssetCreationRequest.forAsset().addResource(with: .photo, data: data, options: nil)
            }
            message = "Đã lưu ảnh overlay vào Thư viện máy ✓"
        } catch { message = "Lưu thất bại: \(error.localizedDescription)" }
    }

    private func makeLink() async {
        working = true; message = nil; resultLink = nil
        defer { working = false }
        guard let data = await renderPNG() else { message = "Không tạo được ảnh."; return }
        do {
            let url = try await store.api.mediaUpload(
                dataBase64: data.base64EncodedString(), mime: "image/png",
                name: "overlay_\(Int(Date().timeIntervalSince1970)).png")
            resultLink = url
            message = "Đã tạo link ✓"
        } catch { message = "Tạo link thất bại: \(error.localizedDescription)" }
    }
}

// Nền caro để thấy vùng trong suốt khi xem trước
struct CheckerboardBackground: View {
    var body: some View {
        GeometryReader { geo in
            let s: CGFloat = 14
            let cols = Int(geo.size.width / s) + 1
            let rows = Int(geo.size.height / s) + 1
            Canvas { ctx, _ in
                for r in 0..<rows {
                    for c in 0..<cols where (r + c) % 2 == 0 {
                        ctx.fill(Path(CGRect(x: CGFloat(c)*s, y: CGFloat(r)*s, width: s, height: s)),
                                 with: .color(.gray.opacity(0.18)))
                    }
                }
            }
            .background(Color(.systemGray5))
        }
    }
}

// ======================== Các MẪU overlay (vẽ bằng SwiftUI, scale theo khung) ========================
struct OverlayCanvas: View {
    let templateId: String
    let name: String
    let subtitle: String

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height
            ZStack {
                switch templateId {
                case "livenow": liveNow(w, h)
                case "neon":    neon(w, h)
                case "gaming":  gaming(w, h)
                case "minimal": minimal(w, h)
                default:        Color.clear
                }
            }
            .frame(width: w, height: h)
        }
    }

    // ---- LIVE NOW (khung công nghệ xanh cyan) ----
    @ViewBuilder private func liveNow(_ w: CGFloat, _ h: CGFloat) -> some View {
        let cyan = Color(red: 0.0, green: 0.78, blue: 0.92)
        ZStack {
            RoundedRectangle(cornerRadius: w*0.04)
                .stroke(cyan, lineWidth: w*0.012)
                .padding(w*0.03)
            VStack {
                HStack {
                    Text("LIVE NOW")
                        .font(.system(size: w*0.055, weight: .heavy)).foregroundStyle(.white)
                        .padding(.horizontal, w*0.04).padding(.vertical, w*0.015)
                        .background(cyan)
                        .clipShape(Capsule())
                    Spacer()
                }
                .padding(w*0.05)
                Spacer()
                Text(subtitle)
                    .font(.system(size: w*0.045, weight: .bold)).foregroundStyle(.white)
                    .frame(maxWidth: .infinity).padding(.vertical, w*0.025)
                    .background(cyan.opacity(0.9))
            }
            VStack { Spacer()
                Text(name).font(.system(size: w*0.05, weight: .black))
                    .foregroundStyle(.white).shadow(radius: 3)
                    .padding(.bottom, h*0.10)
            }
        }
    }

    // ---- Neon (viền hồng/tím phát sáng) ----
    @ViewBuilder private func neon(_ w: CGFloat, _ h: CGFloat) -> some View {
        let grad = LinearGradient(colors: [Color(red:1,green:0.2,blue:0.7), Color(red:0.5,green:0.3,blue:1)],
                                  startPoint: .topLeading, endPoint: .bottomTrailing)
        ZStack {
            RoundedRectangle(cornerRadius: w*0.06)
                .stroke(grad, lineWidth: w*0.02)
                .shadow(color: .pink.opacity(0.8), radius: w*0.03)
                .padding(w*0.03)
            VStack {
                HStack(spacing: w*0.02) {
                    Circle().fill(.red).frame(width: w*0.03, height: w*0.03)
                    Text("LIVE").font(.system(size: w*0.045, weight: .black)).foregroundStyle(.white)
                    Spacer()
                    Text(name).font(.system(size: w*0.05, weight: .heavy)).foregroundStyle(.white)
                }
                .padding(.horizontal, w*0.06).padding(.top, h*0.04)
                Spacer()
                Text(subtitle).font(.system(size: w*0.04, weight: .semibold))
                    .foregroundStyle(.white).padding(.bottom, h*0.05)
            }
        }
    }

    // ---- Gaming (góc chữ L + thanh dưới) ----
    @ViewBuilder private func gaming(_ w: CGFloat, _ h: CGFloat) -> some View {
        let g = Color(red: 0.6, green: 1.0, blue: 0.2)
        ZStack {
            ForEach(0..<4, id: \.self) { i in
                cornerBracket(w: w).foregroundStyle(g)
                    .rotationEffect(.degrees(Double(i) * 90))
                    .frame(width: w, height: h)
            }
            VStack {
                Spacer()
                HStack(spacing: w*0.02) {
                    Image(systemName: "gamecontroller.fill").font(.system(size: w*0.05)).foregroundStyle(g)
                    Text(name).font(.system(size: w*0.05, weight: .black)).foregroundStyle(.white)
                    Spacer()
                    Text(subtitle).font(.system(size: w*0.035)).foregroundStyle(.white.opacity(0.85))
                }
                .padding(w*0.04)
                .background(LinearGradient(colors: [.clear, .black.opacity(0.75)], startPoint: .top, endPoint: .bottom))
            }
        }
    }

    private func cornerBracket(w: CGFloat) -> some View {
        VStack {
            HStack {
                Path { p in
                    p.move(to: CGPoint(x: 0, y: w*0.14)); p.addLine(to: .zero); p.addLine(to: CGPoint(x: w*0.14, y: 0))
                }.stroke(lineWidth: w*0.012)
                .frame(width: w*0.14, height: w*0.14)
                Spacer()
            }
            Spacer()
        }
        .padding(w*0.05)
    }

    // ---- Tối giản (thanh chữ dưới + chấm LIVE) ----
    @ViewBuilder private func minimal(_ w: CGFloat, _ h: CGFloat) -> some View {
        VStack {
            Spacer()
            HStack(spacing: w*0.025) {
                Circle().fill(.red).frame(width: w*0.035, height: w*0.035)
                Text(name).font(.system(size: w*0.05, weight: .bold)).foregroundStyle(.white)
                Spacer()
                Text(subtitle).font(.system(size: w*0.035)).foregroundStyle(.white.opacity(0.85))
            }
            .padding(.horizontal, w*0.05).padding(.vertical, w*0.03)
            .background(.black.opacity(0.55))
            .clipShape(Capsule())
            .padding(w*0.05)
            .padding(.bottom, h*0.04)
        }
    }
}
