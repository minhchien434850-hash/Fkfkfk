import SwiftUI
import UIKit
import UniformTypeIdentifiers

// UIKit document picker — dùng thay thế SwiftUI .fileImporter vì iOS disable nút "Mở"
// khi dùng allowedContentTypes abstract (UTType.item). asCopy: true = iOS tự copy file
// vào sandbox trước khi trả URL nên không cần startAccessingSecurityScopedResource().
struct DocumentPicker: UIViewControllerRepresentable {
    var allowsMultipleSelection: Bool = true
    var onPick: ([URL]) -> Void

    private static let supportedTypes: [UTType] = [
        .data, .image, .movie, .pdf, .text,
        .spreadsheet, .presentation, .archive,
        .sourceCode, .json, .xml, .html,
        .commaSeparatedText, .plainText, .rtf
    ]

    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        let picker = UIDocumentPickerViewController(
            forOpeningContentTypes: Self.supportedTypes,
            asCopy: true
        )
        picker.allowsMultipleSelection = allowsMultipleSelection
        picker.shouldShowFileExtensions = true
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: UIDocumentPickerViewController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(onPick: onPick) }

    class Coordinator: NSObject, UIDocumentPickerDelegate {
        let onPick: ([URL]) -> Void
        init(onPick: @escaping ([URL]) -> Void) { self.onPick = onPick }

        func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
            onPick(urls)
        }
        func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {}
    }
}
