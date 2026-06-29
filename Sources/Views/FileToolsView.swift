import SwiftUI
import PDFKit
import VisionKit
import AVFoundation
import PhotosUI
import PencilKit
import UniformTypeIdentifiers

// ============================ Công cụ tệp (PDF · Âm thanh · Hình ảnh) ============================
// Tất cả dùng framework gốc Apple (PDFKit / VisionKit / AVFoundation) nên chạy ổn định.

func ftTmp(_ name: String) -> URL { FileManager.default.temporaryDirectory.appendingPathComponent(name) }
func ftStamp() -> Int { Int(Date().timeIntervalSince1970) }

enum FileTool: String, Identifiable {
    case scan, imagesToPDF, mergePDF, pagesPDF, passwordPDF, compressPDF
    case pdfToText, textToPDF, pdfMeta, signPDF
    case trimAudio, cropImage
    var id: String { rawValue }

    var title: String {
        switch self {
        case .scan:        return "Quét tài liệu"
        case .imagesToPDF: return "Ảnh → PDF"
        case .mergePDF:    return "Hợp nhất PDF"
        case .pagesPDF:    return "Quản lý trang"
        case .passwordPDF: return "Đặt mật khẩu"
        case .compressPDF: return "Giảm dung lượng"
        case .pdfToText:   return "PDF → Văn bản"
        case .textToPDF:   return "Văn bản → PDF"
        case .pdfMeta:     return "Sửa thông tin PDF"
        case .signPDF:     return "Ký tên / Vẽ lên PDF"
        case .trimAudio:   return "Cắt âm thanh"
        case .cropImage:   return "Cắt ảnh"
        }
    }
    var icon: String {
        switch self {
        case .scan:        return "doc.viewfinder"
        case .imagesToPDF: return "photo.stack"
        case .mergePDF:    return "doc.on.doc.fill"
        case .pagesPDF:    return "square.grid.2x2.fill"
        case .passwordPDF: return "lock.fill"
        case .compressPDF: return "arrow.down.right.and.arrow.up.left"
        case .pdfToText:   return "doc.text.magnifyingglass"
        case .textToPDF:   return "text.badge.plus"
        case .pdfMeta:     return "info.circle.fill"
        case .signPDF:     return "signature"
        case .trimAudio:   return "waveform"
        case .cropImage:   return "crop"
        }
    }
    var color: Color {
        switch self {
        case .scan:        return Color(red: 0.0, green: 0.6, blue: 0.95)
        case .imagesToPDF: return Color(red: 0.95, green: 0.45, blue: 0.2)
        case .mergePDF:    return Color(red: 0.92, green: 0.3, blue: 0.35)
        case .pagesPDF:    return Color(red: 0.0, green: 0.7, blue: 0.55)
        case .passwordPDF: return Color(red: 0.2, green: 0.55, blue: 0.95)
        case .compressPDF: return Color(red: 0.9, green: 0.35, blue: 0.45)
        case .pdfToText:   return Color(red: 0.35, green: 0.5, blue: 0.95)
        case .textToPDF:   return Color(red: 0.45, green: 0.6, blue: 0.2)
        case .pdfMeta:     return Color(red: 0.5, green: 0.5, blue: 0.6)
        case .signPDF:     return Color(red: 0.85, green: 0.3, blue: 0.6)
        case .trimAudio:   return Color(red: 0.0, green: 0.7, blue: 0.7)
        case .cropImage:   return Color(red: 0.55, green: 0.4, blue: 0.95)
        }
    }
}

struct FileToolsView: View {
    @State private var active: FileTool?
    private let cols = [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    group("Trình sửa PDF", [.imagesToPDF, .mergePDF, .pagesPDF, .passwordPDF, .compressPDF, .pdfToText, .textToPDF, .pdfMeta, .signPDF])
                    group("Trình sửa âm thanh", [.trimAudio])
                    group("Hình ảnh", [.scan, .cropImage])
                }
                .padding()
            }
            .navigationTitle("Công cụ tệp")
            .navigationBarTitleDisplayMode(.inline)
            .sheet(item: $active) { tool in toolView(tool) }
        }
    }

    @ViewBuilder private func group(_ title: String, _ tools: [FileTool]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title).font(.title3.bold())
            LazyVGrid(columns: cols, spacing: 12) {
                ForEach(tools) { t in
                    Button { active = t } label: { card(t) }.buttonStyle(.plain)
                }
            }
        }
    }

    private func card(_ t: FileTool) -> some View {
        HStack(spacing: 12) {
            Image(systemName: t.icon)
                .font(.system(size: 20, weight: .semibold)).foregroundStyle(.white)
                .frame(width: 44, height: 44)
                .background(t.color)
                .clipShape(RoundedRectangle(cornerRadius: 11))
            Text(t.title).font(.subheadline.bold()).foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(12)
        .frame(maxWidth: .infinity, minHeight: 70, alignment: .leading)
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }

    @ViewBuilder private func toolView(_ t: FileTool) -> some View {
        switch t {
        case .scan:        ScanToPDFTool()
        case .imagesToPDF: ImagesToPDFTool()
        case .mergePDF:    MergePDFTool()
        case .pagesPDF:    PagesPDFTool()
        case .passwordPDF: PasswordPDFTool()
        case .compressPDF: CompressPDFTool()
        case .pdfToText:   PDFToTextTool()
        case .textToPDF:   TextToPDFTool()
        case .pdfMeta:     PDFMetaTool()
        case .signPDF:     SignPDFTool()
        case .trimAudio:   TrimAudioTool()
        case .cropImage:   CropImageTool()
        }
    }
}

// ============================ Khung & tiện ích dùng chung ============================
struct ToolScaffold<Content: View>: View {
    let title: String
    @ViewBuilder var content: () -> Content
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) { content() }
                    .padding()
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Đóng") { dismiss() } } }
        }
    }
}

struct ToolResultCard: View {
    let url: URL
    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: "checkmark.seal.fill").font(.system(size: 44)).foregroundStyle(.green)
            Text("Hoàn tất!").font(.headline)
            Text(url.lastPathComponent).font(.caption).foregroundStyle(.secondary).lineLimit(1)
            ShareLink(item: url) {
                Label("Lưu / Chia sẻ", systemImage: "square.and.arrow.up")
                    .font(.subheadline.bold()).foregroundStyle(.white)
                    .frame(maxWidth: .infinity).frame(height: 48)
                    .background(Color.accentColor).clipShape(RoundedRectangle(cornerRadius: 12))
            }
        }
        .frame(maxWidth: .infinity).padding()
        .background(Color.green.opacity(0.08)).clipShape(RoundedRectangle(cornerRadius: 14))
    }
}

private func bigButton(_ title: String, _ icon: String, disabled: Bool = false, busy: Bool = false, _ action: @escaping () -> Void) -> some View {
    Button(action: action) {
        HStack {
            if busy { ProgressView().tint(.white) }
            Image(systemName: icon)
            Text(title)
        }
        .font(.subheadline.bold()).foregroundStyle(.white)
        .frame(maxWidth: .infinity).frame(height: 50)
        .background(disabled || busy ? Color.gray : Color.accentColor)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
    .disabled(disabled || busy)
}

// Copy file người dùng chọn về thư mục tạm (tránh lỗi quyền security-scoped khi xử lý)
private func copyToTemp(_ url: URL) -> URL? {
    let ok = url.startAccessingSecurityScopedResource()
    defer { if ok { url.stopAccessingSecurityScopedResource() } }
    let dest = ftTmp("in_\(ftStamp())_\(url.lastPathComponent)")
    try? FileManager.default.removeItem(at: dest)
    do { try FileManager.default.copyItem(at: url, to: dest); return dest }
    catch { return nil }
}

// Tạo PDF từ danh sách ảnh (mỗi ảnh 1 trang, kích thước theo ảnh)
private func makePDF(from images: [UIImage], name: String) -> URL? {
    guard !images.isEmpty else { return nil }
    let data = NSMutableData()
    UIGraphicsBeginPDFContextToData(data, .zero, nil)
    for img in images {
        let rect = CGRect(origin: .zero, size: img.size)
        UIGraphicsBeginPDFPageWithInfo(rect, nil)
        img.draw(in: rect)
    }
    UIGraphicsEndPDFContext()
    let url = ftTmp(name)
    return data.write(to: url, atomically: true) ? url : nil
}

// ============================ 1) Ảnh → PDF ============================
struct ImagesToPDFTool: View {
    @State private var picker: [PhotosPickerItem] = []
    @State private var images: [UIImage] = []
    @State private var result: URL?
    @State private var busy = false

    var body: some View {
        ToolScaffold(title: "Ảnh → PDF") {
            Text("Chọn nhiều ảnh để gộp thành 1 file PDF.").font(.caption).foregroundStyle(.secondary)
            PhotosPicker(selection: $picker, maxSelectionCount: 30, matching: .images) {
                Label("Chọn ảnh", systemImage: "photo.on.rectangle").frame(maxWidth: .infinity).frame(height: 48)
                    .background(Color(.secondarySystemBackground)).clipShape(RoundedRectangle(cornerRadius: 12))
            }
            if !images.isEmpty {
                Text("Đã chọn \(images.count) ảnh").font(.subheadline)
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack { ForEach(Array(images.enumerated()), id: \.offset) { _, im in
                        Image(uiImage: im).resizable().scaledToFill().frame(width: 70, height: 90).clipShape(RoundedRectangle(cornerRadius: 8))
                    } }
                }
                bigButton("Tạo PDF", "doc.fill", busy: busy) { create() }
            }
            if let result { ToolResultCard(url: result) }
        }
        .onChange(of: picker) { items in Task { await load(items) } }
    }
    private func load(_ items: [PhotosPickerItem]) async {
        var arr: [UIImage] = []
        for it in items { if let d = try? await it.loadTransferable(type: Data.self), let img = UIImage(data: d) { arr.append(img) } }
        images = arr; result = nil
    }
    private func create() {
        busy = true
        DispatchQueue.global(qos: .userInitiated).async {
            let url = makePDF(from: images, name: "anh_\(ftStamp()).pdf")
            DispatchQueue.main.async { result = url; busy = false }
        }
    }
}

// ============================ 2) Hợp nhất PDF ============================
struct MergePDFTool: View {
    @State private var inputs: [URL] = []
    @State private var showImporter = false
    @State private var result: URL?
    @State private var busy = false
    @State private var error: String?

    var body: some View {
        ToolScaffold(title: "Hợp nhất PDF") {
            Text("Chọn nhiều file PDF để nối thành 1 file.").font(.caption).foregroundStyle(.secondary)
            bigButton("Chọn các file PDF", "folder.fill") { showImporter = true }
            if !inputs.isEmpty {
                ForEach(Array(inputs.enumerated()), id: \.offset) { _, u in
                    Label(u.lastPathComponent, systemImage: "doc.fill").font(.caption).lineLimit(1)
                }
                bigButton("Hợp nhất (\(inputs.count) file)", "doc.on.doc.fill", busy: busy) { merge() }
            }
            if let error { Text(error).font(.caption).foregroundStyle(.red) }
            if let result { ToolResultCard(url: result) }
        }
        .sheet(isPresented: $showImporter) {
            DocumentPicker(contentTypes: [.pdf], allowsMultipleSelection: true) { urls in
                inputs = urls.compactMap { copyToTemp($0) }; result = nil
                showImporter = false
            }
        }
    }
    private func merge() {
        busy = true; error = nil
        DispatchQueue.global(qos: .userInitiated).async {
            let merged = PDFDocument()
            for u in inputs {
                guard let doc = PDFDocument(url: u) else { continue }
                for i in 0..<doc.pageCount { if let p = doc.page(at: i) { merged.insert(p, at: merged.pageCount) } }
            }
            var out: URL? = nil
            if merged.pageCount > 0 {
                let url = ftTmp("hopnhat_\(ftStamp()).pdf")
                if merged.write(to: url) { out = url }
            }
            DispatchQueue.main.async {
                busy = false
                if let out { result = out } else { error = "Không hợp nhất được (file PDF lỗi hoặc có mật khẩu)." }
            }
        }
    }
}

// ============================ 3) Quản lý trang (xoá trang) ============================
struct PagesPDFTool: View {
    @State private var input: URL?
    @State private var doc: PDFDocument?
    @State private var thumbs: [UIImage] = []
    @State private var removed: Set<Int> = []
    @State private var showImporter = false
    @State private var result: URL?
    @State private var busy = false
    private let cols = [GridItem(.adaptive(minimum: 90), spacing: 8)]

    var body: some View {
        ToolScaffold(title: "Quản lý trang PDF") {
            Text("Chọn PDF → chạm vào trang muốn XOÁ (sẽ mờ + dấu ✗), rồi lưu.").font(.caption).foregroundStyle(.secondary)
            bigButton("Chọn file PDF", "folder.fill") { showImporter = true }
            if !thumbs.isEmpty {
                LazyVGrid(columns: cols, spacing: 8) {
                    ForEach(Array(thumbs.enumerated()), id: \.offset) { i, im in
                        ZStack(alignment: .topTrailing) {
                            Image(uiImage: im).resizable().scaledToFit()
                                .frame(height: 120).background(Color.white)
                                .clipShape(RoundedRectangle(cornerRadius: 6))
                                .opacity(removed.contains(i) ? 0.3 : 1)
                                .overlay(alignment: .bottom) { Text("\(i+1)").font(.caption2).padding(2).background(.black.opacity(0.6)).foregroundStyle(.white).clipShape(Capsule()).padding(2) }
                            if removed.contains(i) {
                                Image(systemName: "xmark.circle.fill").foregroundStyle(.red).background(Circle().fill(.white)).padding(3)
                            }
                        }
                        .onTapGesture { if removed.contains(i) { removed.remove(i) } else { removed.insert(i) } }
                    }
                }
                let keep = thumbs.count - removed.count
                bigButton("Lưu (\(keep) trang)", "square.and.arrow.down.fill", disabled: keep == 0, busy: busy) { save() }
            }
            if let result { ToolResultCard(url: result) }
        }
        .sheet(isPresented: $showImporter) {
            DocumentPicker(contentTypes: [.pdf], allowsMultipleSelection: false) { urls in
                if let u = urls.first, let local = copyToTemp(u) {
                    input = local; loadThumbs(local)
                }
                showImporter = false
            }
        }
    }
    private func loadThumbs(_ url: URL) {
        result = nil; removed = []; thumbs = []
        guard let d = PDFDocument(url: url) else { return }
        doc = d
        DispatchQueue.global(qos: .userInitiated).async {
            var arr: [UIImage] = []
            for i in 0..<d.pageCount {
                if let p = d.page(at: i) { arr.append(p.thumbnail(of: CGSize(width: 180, height: 240), for: .mediaBox)) }
            }
            DispatchQueue.main.async { thumbs = arr }
        }
    }
    private func save() {
        guard let d = doc else { return }
        busy = true
        DispatchQueue.global(qos: .userInitiated).async {
            let out = PDFDocument()
            for i in 0..<d.pageCount where !removed.contains(i) {
                if let p = d.page(at: i) { out.insert(p, at: out.pageCount) }
            }
            var url: URL? = nil
            if out.pageCount > 0 { let u = ftTmp("trang_\(ftStamp()).pdf"); if out.write(to: u) { url = u } }
            DispatchQueue.main.async { result = url; busy = false }
        }
    }
}

// ============================ 4) Đặt mật khẩu PDF ============================
struct PasswordPDFTool: View {
    @State private var input: URL?
    @State private var password = ""
    @State private var showImporter = false
    @State private var result: URL?
    @State private var busy = false
    @State private var error: String?

    var body: some View {
        ToolScaffold(title: "Đặt mật khẩu PDF") {
            Text("Chọn PDF và đặt mật khẩu mở file.").font(.caption).foregroundStyle(.secondary)
            bigButton(input == nil ? "Chọn file PDF" : "Đã chọn — đổi file", "folder.fill") { showImporter = true }
            if input != nil {
                SecureField("Nhập mật khẩu (≥1 ký tự)", text: $password)
                    .padding(12).background(Color(.secondarySystemBackground)).clipShape(RoundedRectangle(cornerRadius: 10))
                bigButton("Đặt mật khẩu", "lock.fill", disabled: password.isEmpty, busy: busy) { apply() }
            }
            if let error { Text(error).font(.caption).foregroundStyle(.red) }
            if let result { ToolResultCard(url: result) }
        }
        .sheet(isPresented: $showImporter) {
            DocumentPicker(contentTypes: [.pdf], allowsMultipleSelection: false) { urls in
                if let u = urls.first { input = copyToTemp(u); result = nil }
                showImporter = false
            }
        }
    }
    private func apply() {
        guard let u = input, let doc = PDFDocument(url: u) else { error = "Không đọc được PDF."; return }
        busy = true; error = nil
        DispatchQueue.global(qos: .userInitiated).async {
            let out = ftTmp("matkhau_\(ftStamp()).pdf")
            let ok = doc.write(to: out, withOptions: [
                .userPasswordOption: password,
                .ownerPasswordOption: password
            ])
            DispatchQueue.main.async {
                busy = false
                if ok { result = out } else { error = "Đặt mật khẩu thất bại." }
            }
        }
    }
}

// ============================ 5) Giảm dung lượng PDF ============================
struct CompressPDFTool: View {
    @State private var input: URL?
    @State private var quality = 0.4
    @State private var showImporter = false
    @State private var result: URL?
    @State private var busy = false
    @State private var origSize = 0
    @State private var newSize = 0

    var body: some View {
        ToolScaffold(title: "Giảm dung lượng PDF") {
            Text("Nén PDF bằng cách giảm chất lượng ảnh trong trang.").font(.caption).foregroundStyle(.secondary)
            bigButton(input == nil ? "Chọn file PDF" : "Đã chọn — đổi file", "folder.fill") { showImporter = true }
            if input != nil {
                VStack(alignment: .leading) {
                    Text("Mức nén: \(Int(quality * 100))% chất lượng").font(.caption)
                    Slider(value: $quality, in: 0.1...0.8)
                    Text("Càng kéo trái càng nhẹ (chất lượng thấp hơn).").font(.caption2).foregroundStyle(.secondary)
                }
                if origSize > 0 { Text("Gốc: \(ftSize(origSize))").font(.caption).foregroundStyle(.secondary) }
                bigButton("Nén PDF", "arrow.down.right.and.arrow.up.left", busy: busy) { compress() }
            }
            if let result {
                if newSize > 0 { Text("Sau nén: \(ftSize(newSize))").font(.caption).foregroundStyle(.green) }
                ToolResultCard(url: result)
            }
        }
        .sheet(isPresented: $showImporter) {
            DocumentPicker(contentTypes: [.pdf], allowsMultipleSelection: false) { urls in
                if let u = urls.first {
                    input = copyToTemp(u); result = nil; newSize = 0
                    origSize = (try? FileManager.default.attributesOfItem(atPath: input?.path ?? ""))?[.size] as? Int ?? 0
                }
                showImporter = false
            }
        }
    }
    private func compress() {
        guard let u = input, let doc = PDFDocument(url: u) else { return }
        busy = true
        let q = quality
        DispatchQueue.global(qos: .userInitiated).async {
            let data = NSMutableData()
            UIGraphicsBeginPDFContextToData(data, .zero, nil)
            for i in 0..<doc.pageCount {
                guard let page = doc.page(at: i) else { continue }
                let bounds = page.bounds(for: .mediaBox)
                let img = page.thumbnail(of: bounds.size, for: .mediaBox)
                let rect = CGRect(origin: .zero, size: bounds.size)
                UIGraphicsBeginPDFPageWithInfo(rect, nil)
                if let jpeg = img.jpegData(compressionQuality: q), let small = UIImage(data: jpeg) {
                    small.draw(in: rect)
                } else {
                    img.draw(in: rect)
                }
            }
            UIGraphicsEndPDFContext()
            let out = ftTmp("nen_\(ftStamp()).pdf")
            let ok = data.write(to: out, atomically: true)
            DispatchQueue.main.async {
                busy = false
                if ok { result = out; newSize = data.length }
            }
        }
    }
}

func ftSize(_ bytes: Int) -> String {
    let f = ByteCountFormatter(); f.countStyle = .file; return f.string(fromByteCount: Int64(bytes))
}

// ============================ 6) Cắt âm thanh ============================
struct TrimAudioTool: View {
    @State private var input: URL?
    @State private var duration: Double = 0
    @State private var start: Double = 0
    @State private var end: Double = 0
    @State private var showImporter = false
    @State private var result: URL?
    @State private var busy = false
    @State private var error: String?

    var body: some View {
        ToolScaffold(title: "Cắt âm thanh") {
            Text("Chọn file âm thanh và chọn đoạn muốn giữ.").font(.caption).foregroundStyle(.secondary)
            bigButton(input == nil ? "Chọn file âm thanh" : "Đã chọn — đổi file", "folder.fill") { showImporter = true }
            if input != nil, duration > 0 {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Bắt đầu: \(ftTime(start))").font(.caption)
                    Slider(value: $start, in: 0...duration) { _ in if start > end { end = start } }
                    Text("Kết thúc: \(ftTime(end))").font(.caption)
                    Slider(value: $end, in: 0...duration) { _ in if end < start { start = end } }
                    Text("Độ dài đoạn giữ: \(ftTime(max(0, end - start)))").font(.caption2).foregroundStyle(.secondary)
                }
                bigButton("Cắt & xuất (.m4a)", "scissors", disabled: end <= start, busy: busy) { trim() }
            }
            if let error { Text(error).font(.caption).foregroundStyle(.red) }
            if let result { ToolResultCard(url: result) }
        }
        .sheet(isPresented: $showImporter) {
            DocumentPicker(contentTypes: [.audio, .mp3, .mpeg4Audio], allowsMultipleSelection: false) { urls in
                if let u = urls.first, let local = copyToTemp(u) {
                    input = local; result = nil
                    Task {
                        let asset = AVURLAsset(url: local)
                        if let d = try? await asset.load(.duration) {
                            let secs = CMTimeGetSeconds(d)
                            await MainActor.run { duration = secs; start = 0; end = secs }
                        }
                    }
                }
                showImporter = false
            }
        }
    }
    private func trim() {
        guard let u = input else { return }
        busy = true; error = nil
        let asset = AVURLAsset(url: u)
        guard let export = AVAssetExportSession(asset: asset, presetName: AVAssetExportPresetAppleM4A) else {
            busy = false; error = "Không tạo được phiên xuất."; return
        }
        let out = ftTmp("amthanh_\(ftStamp()).m4a")
        try? FileManager.default.removeItem(at: out)
        export.outputURL = out
        export.outputFileType = .m4a
        export.timeRange = CMTimeRange(start: CMTime(seconds: start, preferredTimescale: 600),
                                       end: CMTime(seconds: end, preferredTimescale: 600))
        export.exportAsynchronously {
            DispatchQueue.main.async {
                busy = false
                if export.status == .completed { result = out }
                else { error = export.error?.localizedDescription ?? "Xuất thất bại." }
            }
        }
    }
}

func ftTime(_ s: Double) -> String {
    let t = Int(s); return String(format: "%02d:%02d", t / 60, t % 60)
}

// ============================ 7) Quét tài liệu → PDF ============================
struct ScanToPDFTool: View {
    @State private var showScanner = false
    @State private var result: URL?
    @State private var busy = false

    var body: some View {
        ToolScaffold(title: "Quét tài liệu") {
            Text("Dùng camera quét tài liệu (tự bắt cạnh giấy) rồi lưu thành PDF.").font(.caption).foregroundStyle(.secondary)
            if VNDocumentCameraViewController.isSupported {
                bigButton("Mở camera quét", "doc.viewfinder", busy: busy) { showScanner = true }
            } else {
                Text("Thiết bị không hỗ trợ quét tài liệu.").font(.caption).foregroundStyle(.red)
            }
            if let result { ToolResultCard(url: result) }
        }
        .fullScreenCover(isPresented: $showScanner) {
            DocScanner { images in
                showScanner = false
                guard !images.isEmpty else { return }
                busy = true
                DispatchQueue.global(qos: .userInitiated).async {
                    let url = makePDF(from: images, name: "quet_\(ftStamp()).pdf")
                    DispatchQueue.main.async { result = url; busy = false }
                }
            }
            .ignoresSafeArea()
        }
    }
}

struct DocScanner: UIViewControllerRepresentable {
    var onResult: ([UIImage]) -> Void
    func makeUIViewController(context: Context) -> VNDocumentCameraViewController {
        let vc = VNDocumentCameraViewController()
        vc.delegate = context.coordinator
        return vc
    }
    func updateUIViewController(_ uiViewController: VNDocumentCameraViewController, context: Context) {}
    func makeCoordinator() -> Coordinator { Coordinator(onResult: onResult) }

    final class Coordinator: NSObject, VNDocumentCameraViewControllerDelegate {
        let onResult: ([UIImage]) -> Void
        init(onResult: @escaping ([UIImage]) -> Void) { self.onResult = onResult }
        func documentCameraViewController(_ controller: VNDocumentCameraViewController, didFinishWith scan: VNDocumentCameraScan) {
            var imgs: [UIImage] = []
            for i in 0..<scan.pageCount { imgs.append(scan.imageOfPage(at: i)) }
            onResult(imgs)
        }
        func documentCameraViewControllerDidCancel(_ controller: VNDocumentCameraViewController) { onResult([]) }
        func documentCameraViewController(_ controller: VNDocumentCameraViewController, didFailWithError error: Error) { onResult([]) }
    }
}

// ============================ 8) Cắt ảnh (crop) ============================
struct CropImageTool: View {
    @State private var picker: PhotosPickerItem?
    @State private var image: UIImage?
    @State private var result: URL?
    @State private var cropRect: CGRect = .zero      // theo toạ độ khung hiển thị
    @State private var imageRect: CGRect = .zero     // vùng ảnh thật trong khung
    @State private var imageVersion = 0
    @State private var busy = false

    var body: some View {
        ToolScaffold(title: "Cắt ảnh") {
            Text("Chọn ảnh, kéo 4 góc khung để chọn vùng cắt.").font(.caption).foregroundStyle(.secondary)
            PhotosPicker(selection: $picker, matching: .images) {
                Label("Chọn ảnh", systemImage: "photo").frame(maxWidth: .infinity).frame(height: 48)
                    .background(Color(.secondarySystemBackground)).clipShape(RoundedRectangle(cornerRadius: 12))
            }
            if let image {
                GeometryReader { geo in
                    let fitted = fitRect(imageSize: image.size, in: geo.size)
                    ZStack {
                        Image(uiImage: image).resizable().scaledToFit()
                        CropOverlay(cropRect: $cropRect, bounds: fitted)
                    }
                    .onAppear {
                        imageRect = fitted
                        cropRect = fitted.insetBy(dx: fitted.width*0.1, dy: fitted.height*0.1)
                    }
                }
                .frame(height: 360)
                .id(imageVersion)
                bigButton("Cắt ảnh", "crop", busy: busy) { crop() }
            }
            if let result { ToolResultCard(url: result) }
        }
        .onChange(of: picker) { item in
            Task {
                if let item, let d = try? await item.loadTransferable(type: Data.self), let img = UIImage(data: d) {
                    await MainActor.run { image = img; cropRect = .zero; result = nil; imageVersion += 1 }
                }
            }
        }
    }
    private func crop() {
        guard let image, imageRect.width > 0 else { return }
        busy = true
        // Quy đổi cropRect (khung) → pixel ảnh thật
        let scaleX = image.size.width / imageRect.width
        let scaleY = image.size.height / imageRect.height
        let x = (cropRect.minX - imageRect.minX) * scaleX
        let y = (cropRect.minY - imageRect.minY) * scaleY
        let w = cropRect.width * scaleX
        let h = cropRect.height * scaleY
        let pxRect = CGRect(x: x, y: y, width: w, height: h).integral
        DispatchQueue.global(qos: .userInitiated).async {
            var out: URL? = nil
            if let cg = image.cgImage?.cropping(to: pxRect) {
                let cropped = UIImage(cgImage: cg, scale: image.scale, orientation: image.imageOrientation)
                if let data = cropped.jpegData(compressionQuality: 0.95) {
                    let url = ftTmp("catanh_\(ftStamp()).jpg")
                    if (try? data.write(to: url)) != nil { out = url }
                }
            }
            DispatchQueue.main.async { result = out; busy = false }
        }
    }
}

// Tính vùng ảnh (scaledToFit) nằm trong khung
private func fitRect(imageSize: CGSize, in container: CGSize) -> CGRect {
    guard imageSize.width > 0, imageSize.height > 0 else { return .zero }
    let scale = min(container.width / imageSize.width, container.height / imageSize.height)
    let w = imageSize.width * scale, h = imageSize.height * scale
    return CGRect(x: (container.width - w) / 2, y: (container.height - h) / 2, width: w, height: h)
}

// Khung cắt với 4 góc kéo được
struct CropOverlay: View {
    @Binding var cropRect: CGRect
    let bounds: CGRect

    var body: some View {
        ZStack {
            Rectangle().stroke(Color.yellow, lineWidth: 2)
                .frame(width: cropRect.width, height: cropRect.height)
                .position(x: cropRect.midX, y: cropRect.midY)
            ForEach(0..<4, id: \.self) { i in
                handle(i)
            }
        }
    }
    @ViewBuilder private func handle(_ corner: Int) -> some View {
        let p = cornerPoint(corner)
        Circle().fill(Color.yellow).frame(width: 22, height: 22)
            .position(x: p.x, y: p.y)
            .gesture(DragGesture().onChanged { v in update(corner, v.location) })
    }
    private func cornerPoint(_ c: Int) -> CGPoint {
        switch c {
        case 0: return CGPoint(x: cropRect.minX, y: cropRect.minY)
        case 1: return CGPoint(x: cropRect.maxX, y: cropRect.minY)
        case 2: return CGPoint(x: cropRect.minX, y: cropRect.maxY)
        default: return CGPoint(x: cropRect.maxX, y: cropRect.maxY)
        }
    }
    private func update(_ corner: Int, _ loc: CGPoint) {
        let x = min(max(loc.x, bounds.minX), bounds.maxX)
        let y = min(max(loc.y, bounds.minY), bounds.maxY)
        var r = cropRect
        switch corner {
        case 0: r = CGRect(x: x, y: y, width: r.maxX - x, height: r.maxY - y)
        case 1: r = CGRect(x: r.minX, y: y, width: x - r.minX, height: r.maxY - y)
        case 2: r = CGRect(x: x, y: r.minY, width: r.maxX - x, height: y - r.minY)
        default: r = CGRect(x: r.minX, y: r.minY, width: x - r.minX, height: y - r.minY)
        }
        if r.width > 30 && r.height > 30 { cropRect = r }
    }
}

// ============================ 9) PDF → Văn bản ============================
struct PDFToTextTool: View {
    @State private var showImporter = false
    @State private var text = ""
    @State private var result: URL?

    var body: some View {
        ToolScaffold(title: "PDF → Văn bản") {
            Text("Trích toàn bộ chữ trong PDF ra văn bản.").font(.caption).foregroundStyle(.secondary)
            bigButton("Chọn file PDF", "folder.fill") { showImporter = true }
            if !text.isEmpty {
                TextEditor(text: .constant(text)).frame(height: 240)
                    .padding(6).background(Color(.secondarySystemBackground)).clipShape(RoundedRectangle(cornerRadius: 10))
                Button { UIPasteboard.general.string = text } label: {
                    Label("Copy văn bản", systemImage: "doc.on.doc")
                }.buttonStyle(.bordered)
                if let result { ToolResultCard(url: result) }
            }
        }
        .fileImporter(isPresented: $showImporter, allowedContentTypes: [.pdf], allowsMultipleSelection: false) { res in
            if case .success(let urls) = res, let u = urls.first, let local = copyToTemp(u), let doc = PDFDocument(url: local) {
                let t = doc.string ?? ""
                text = t.isEmpty ? "(PDF không có chữ trích được — có thể là bản scan ảnh)" : t
                if !t.isEmpty {
                    let out = ftTmp("vanban_\(ftStamp()).txt")
                    result = (try? t.write(to: out, atomically: true, encoding: .utf8)) != nil ? out : nil
                } else { result = nil }
            }
        }
    }
}

// ============================ 10) Văn bản → PDF ============================
struct TextToPDFTool: View {
    @State private var text = ""
    @State private var result: URL?
    @State private var busy = false

    var body: some View {
        ToolScaffold(title: "Văn bản → PDF") {
            Text("Nhập / dán văn bản rồi tạo file PDF.").font(.caption).foregroundStyle(.secondary)
            TextEditor(text: $text).frame(height: 260)
                .padding(6).background(Color(.secondarySystemBackground)).clipShape(RoundedRectangle(cornerRadius: 10))
            bigButton("Tạo PDF", "doc.fill", disabled: text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, busy: busy) { create() }
            if let result { ToolResultCard(url: result) }
        }
    }
    private func create() {
        busy = true
        let content = text
        DispatchQueue.global(qos: .userInitiated).async {
            let url = textToPDFFile(content)
            DispatchQueue.main.async { result = url; busy = false }
        }
    }
}

// Tạo PDF nhiều trang từ văn bản (Core Text — tự xuống trang)
private func textToPDFFile(_ text: String) -> URL? {
    let pageW: CGFloat = 595, pageH: CGFloat = 842   // A4 @72dpi
    let margin: CGFloat = 40
    let attrs: [NSAttributedString.Key: Any] = [
        .font: UIFont.systemFont(ofSize: 14),
        .foregroundColor: UIColor.black
    ]
    let full = NSAttributedString(string: text, attributes: attrs)
    let framesetter = CTFramesetterCreateWithAttributedString(full)
    let data = NSMutableData()
    UIGraphicsBeginPDFContextToData(data, CGRect(x: 0, y: 0, width: pageW, height: pageH), nil)
    var location = 0
    var safety = 0
    while location < full.length && safety < 2000 {
        safety += 1
        UIGraphicsBeginPDFPage()
        guard let ctx = UIGraphicsGetCurrentContext() else { break }
        ctx.translateBy(x: 0, y: pageH)
        ctx.scaleBy(x: 1, y: -1)
        let path = CGPath(rect: CGRect(x: margin, y: margin, width: pageW - margin*2, height: pageH - margin*2), transform: nil)
        let frame = CTFramesetterCreateFrame(framesetter, CFRange(location: location, length: 0), path, nil)
        CTFrameDraw(frame, ctx)
        let visible = CTFrameGetVisibleStringRange(frame)
        if visible.length <= 0 { break }
        location += visible.length
    }
    UIGraphicsEndPDFContext()
    let url = ftTmp("vanban_\(ftStamp()).pdf")
    return data.write(to: url, atomically: true) ? url : nil
}

// ============================ 11) Sửa thông tin PDF (metadata) ============================
struct PDFMetaTool: View {
    @State private var input: URL?
    @State private var showImporter = false
    @State private var title = ""
    @State private var author = ""
    @State private var subject = ""
    @State private var result: URL?
    @State private var busy = false

    var body: some View {
        ToolScaffold(title: "Sửa thông tin PDF") {
            Text("Sửa Tiêu đề / Tác giả / Chủ đề của file PDF.").font(.caption).foregroundStyle(.secondary)
            bigButton(input == nil ? "Chọn file PDF" : "Đã chọn — đổi file", "folder.fill") { showImporter = true }
            if input != nil {
                metaField("Tiêu đề", $title)
                metaField("Tác giả", $author)
                metaField("Chủ đề", $subject)
                bigButton("Lưu thông tin", "square.and.arrow.down.fill", busy: busy) { save() }
            }
            if let result { ToolResultCard(url: result) }
        }
        .fileImporter(isPresented: $showImporter, allowedContentTypes: [.pdf], allowsMultipleSelection: false) { res in
            if case .success(let urls) = res, let u = urls.first, let local = copyToTemp(u) {
                input = local; result = nil
                if let doc = PDFDocument(url: local) {
                    let a = doc.documentAttributes ?? [:]
                    title = a[PDFDocumentAttribute.titleAttribute] as? String ?? ""
                    author = a[PDFDocumentAttribute.authorAttribute] as? String ?? ""
                    subject = a[PDFDocumentAttribute.subjectAttribute] as? String ?? ""
                }
            }
        }
    }
    private func metaField(_ label: String, _ binding: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label).font(.caption).foregroundStyle(.secondary)
            TextField(label, text: binding)
                .padding(10).background(Color(.secondarySystemBackground)).clipShape(RoundedRectangle(cornerRadius: 10))
        }
    }
    private func save() {
        guard let u = input, let doc = PDFDocument(url: u) else { return }
        busy = true
        DispatchQueue.global(qos: .userInitiated).async {
            var a = doc.documentAttributes ?? [:]
            a[PDFDocumentAttribute.titleAttribute] = title
            a[PDFDocumentAttribute.authorAttribute] = author
            a[PDFDocumentAttribute.subjectAttribute] = subject
            doc.documentAttributes = a
            let out = ftTmp("thongtin_\(ftStamp()).pdf")
            let ok = doc.write(to: out)
            DispatchQueue.main.async { result = ok ? out : nil; busy = false }
        }
    }
}

// ============================ 12) Ký tên / Vẽ lên PDF ============================
struct SignPDFTool: View {
    @State private var doc: PDFDocument?
    @State private var pageImages: [UIImage] = []
    @State private var pageIndex = 0
    @State private var canvas = PKCanvasView()
    @State private var showImporter = false
    @State private var result: URL?
    @State private var busy = false

    var body: some View {
        ToolScaffold(title: "Ký tên / Vẽ lên PDF") {
            Text("Chọn PDF → chọn trang → vẽ chữ ký/ghi chú lên trang → lưu.").font(.caption).foregroundStyle(.secondary)
            bigButton("Chọn file PDF", "folder.fill") { showImporter = true }
            if !pageImages.isEmpty {
                if pageImages.count > 1 {
                    Stepper("Trang \(pageIndex + 1)/\(pageImages.count)", value: $pageIndex, in: 0...(pageImages.count - 1))
                        .onChange(of: pageIndex) { _ in canvas.drawing = PKDrawing() }
                }
                GeometryReader { geo in
                    let img = pageImages[pageIndex]
                    let r = fitRect(imageSize: img.size, in: geo.size)
                    ZStack {
                        Image(uiImage: img).resizable().scaledToFit()
                        DrawCanvas(canvas: $canvas)
                            .frame(width: r.width, height: r.height)
                            .position(x: r.midX, y: r.midY)
                    }
                }
                .frame(height: 380)
                .background(Color(.systemGray5))
                .clipShape(RoundedRectangle(cornerRadius: 10))
                Button { canvas.drawing = PKDrawing() } label: { Label("Xoá nét vẽ", systemImage: "trash") }.buttonStyle(.bordered)
                bigButton("Lưu PDF đã ký", "checkmark.circle.fill", busy: busy) { save() }
            }
            if let result { ToolResultCard(url: result) }
        }
        .fileImporter(isPresented: $showImporter, allowedContentTypes: [.pdf], allowsMultipleSelection: false) { res in
            if case .success(let urls) = res, let u = urls.first, let local = copyToTemp(u), let d = PDFDocument(url: local) {
                doc = d; result = nil; pageIndex = 0; canvas.drawing = PKDrawing()
                DispatchQueue.global(qos: .userInitiated).async {
                    var arr: [UIImage] = []
                    for i in 0..<d.pageCount {
                        if let p = d.page(at: i) { arr.append(p.thumbnail(of: p.bounds(for: .mediaBox).size, for: .mediaBox)) }
                    }
                    DispatchQueue.main.async { pageImages = arr }
                }
            }
        }
    }
    private func save() {
        guard let doc else { return }
        busy = true
        let idx = pageIndex
        let drawing = canvas.drawing
        let canvasBounds = canvas.bounds
        DispatchQueue.global(qos: .userInitiated).async {
            let out = PDFDocument()
            for i in 0..<doc.pageCount {
                if i == idx, let page = doc.page(at: i) {
                    let size = page.bounds(for: .mediaBox).size
                    let pageImg = page.thumbnail(of: size, for: .mediaBox)
                    let drawImg = drawing.image(from: canvasBounds == .zero ? CGRect(origin: .zero, size: size) : canvasBounds,
                                                scale: UIScreen.main.scale)
                    let renderer = UIGraphicsImageRenderer(size: size)
                    let composed = renderer.image { _ in
                        pageImg.draw(in: CGRect(origin: .zero, size: size))
                        drawImg.draw(in: CGRect(origin: .zero, size: size))
                    }
                    if let pg = PDFPage(image: composed) { out.insert(pg, at: out.pageCount) }
                } else if let p = doc.page(at: i) {
                    out.insert(p, at: out.pageCount)
                }
            }
            var url: URL? = nil
            if out.pageCount > 0 { let u = ftTmp("kyten_\(ftStamp()).pdf"); if out.write(to: u) { url = u } }
            DispatchQueue.main.async { result = url; busy = false }
        }
    }
}

// Canvas vẽ tay (PencilKit) nền trong suốt
struct DrawCanvas: UIViewRepresentable {
    @Binding var canvas: PKCanvasView
    func makeUIView(context: Context) -> PKCanvasView {
        canvas.drawingPolicy = .anyInput
        canvas.backgroundColor = .clear
        canvas.isOpaque = false
        canvas.tool = PKInkingTool(.pen, color: .black, width: 4)
        return canvas
    }
    func updateUIView(_ uiView: PKCanvasView, context: Context) {}
}
