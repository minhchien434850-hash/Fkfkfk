import SwiftUI
import UIKit
import UniformTypeIdentifiers

// UIKit document picker — thay thế SwiftUI .fileImporter vì iOS hay ẩn file (đen)
// và không hiện nút "Mở" khi dùng UTType abstract.
//
// Cách dùng:
//   DocumentPicker(contentTypes: [.pdf], allowsMultipleSelection: true) { urls in ... }
//   DocumentPicker(contentTypes: [.audio, .mp3, .mpeg4Audio]) { urls in ... }
//   DocumentPicker() { urls in ... }  // mặc định: mọi loại file
//
// - asCopy = false → iOS trả URL gốc (security-scoped), picker tự gọi
//   startAccessingSecurityScopedResource trước khi trả về.
// - allowsMultipleSelection = true → iOS hiện ô tích (✓) và nút "Mở" (Open).

struct DocumentPicker: UIViewControllerRepresentable {
    var contentTypes: [UTType]
    var allowsMultipleSelection: Bool
    var asCopy: Bool
    var onPick: ([URL]) -> Void

    init(
        contentTypes: [UTType] = DocumentPicker.defaultTypes,
        allowsMultipleSelection: Bool = true,
        asCopy: Bool = false,
        onPick: @escaping ([URL]) -> Void
    ) {
        self.contentTypes = contentTypes
        self.allowsMultipleSelection = allowsMultipleSelection
        self.asCopy = asCopy
        self.onPick = onPick
    }

    static let defaultTypes: [UTType] = [
        .data, .image, .movie, .pdf, .text,
        .spreadsheet, .presentation, .archive,
        .sourceCode, .json, .xml, .html,
        .commaSeparatedText, .plainText, .rtf
    ]

    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        let picker = UIDocumentPickerViewController(
            forOpeningContentTypes: contentTypes,
            asCopy: asCopy
        )
        picker.allowsMultipleSelection = allowsMultipleSelection
        picker.shouldShowFileExtensions = true
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: UIDocumentPickerViewController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(asCopy: asCopy, onPick: onPick)
    }

    class Coordinator: NSObject, UIDocumentPickerDelegate {
        let asCopy: Bool
        let onPick: ([URL]) -> Void

        init(asCopy: Bool, onPick: @escaping ([URL]) -> Void) {
            self.asCopy = asCopy
            self.onPick = onPick
        }

        func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
            if asCopy {
                onPick(urls)
                return
            }

            // Không phải asCopy → URL là security-scoped. Xin quyền truy cập (best-effort).
            // QUAN TRỌNG: vẫn trả về MỌI URL kể cả khi startAccessingSecurityScopedResource()
            // trả về false — nhiều file (iCloud, file lớn, file vừa tải về) trả false nhưng vẫn
            // đọc/copy được. Trước đây lọc bỏ các URL này → bấm "Mở" như KHÔNG có gì xảy ra.
            for url in urls {
                _ = url.startAccessingSecurityScopedResource()
            }
            onPick(urls)
            // Lưu ý: caller phải gọi stopAccessingSecurityScopedResource sau khi dùng xong,
            // hoặc copy file ra thư mục tạm rồi stop ngay (xem copyToTemp trong FileToolsView).
        }

        func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {}
    }
}
