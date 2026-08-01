import SwiftUI
import Photos
import AVFoundation

// ============================================================================
//  Xin quyền truy cập trước khi THÊM ảnh / video / file lên (tải lên).
//  Dùng chung cho mọi nơi trong app. Nếu bị từ chối → mở Cài đặt để cấp quyền.
// ============================================================================
enum MediaPermission {

    /// Xin quyền truy cập Thư viện Ảnh/Video. Trả về true nếu được phép (đầy đủ hoặc giới hạn).
    static func ensurePhotos() async -> Bool {
        let status = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        switch status {
        case .authorized, .limited:
            return true
        case .notDetermined:
            return await withCheckedContinuation { (cont: CheckedContinuation<Bool, Never>) in
                PHPhotoLibrary.requestAuthorization(for: .readWrite) { s in
                    cont.resume(returning: s == .authorized || s == .limited)
                }
            }
        default:
            return false
        }
    }

    /// Xin quyền Micro (thu âm) — dùng khi cần ghi âm.
    static func ensureMicrophone() async -> Bool {
        await withCheckedContinuation { (cont: CheckedContinuation<Bool, Never>) in
            AVAudioSession.sharedInstance().requestRecordPermission { granted in
                cont.resume(returning: granted)
            }
        }
    }

    /// Mở phần Cài đặt của app để người dùng cấp quyền thủ công.
    @MainActor static func openSettings() {
        if let url = URL(string: UIApplication.openSettingsURLString) {
            UIApplication.shared.open(url)
        }
    }
}

// Tiện ích gắn cảnh báo "cần cấp quyền" + nút mở Cài đặt cho 1 view bất kỳ.
struct MediaPermissionAlert: ViewModifier {
    @Binding var isPresented: Bool
    func body(content: Content) -> some View {
        content.alert("Cần cấp quyền", isPresented: $isPresented) {
            Button("Mở Cài đặt") { MediaPermission.openSettings() }
            Button("Để sau", role: .cancel) {}
        } message: {
            Text("Hãy cấp quyền truy cập Ảnh/Video trong Cài đặt để thêm và tải lên ảnh, video hoặc file.")
        }
    }
}

extension View {
    /// Hiện cảnh báo cấp quyền (kèm nút mở Cài đặt) khi `isPresented` = true.
    func mediaPermissionAlert(_ isPresented: Binding<Bool>) -> some View {
        modifier(MediaPermissionAlert(isPresented: isPresented))
    }
}
