import SwiftUI

// §5 — "Thông tin ứng dụng": màn công khai (tách khỏi trang quản trị) thể hiện
// rõ Ngày sản xuất và Nhà phát hành để tăng tính minh bạch, chuyên nghiệp.
struct AppInfoView: View {
    @EnvironmentObject var store: AppStore
    // Đồng bộ logo với app gốc: cùng đọc cài đặt logo admin chỉnh (hiệu ứng/font/chuyển động).
    @AppStorage("appLogoEffect") private var appLogoEffect = "rainbow"
    @AppStorage("appLogoFont") private var appLogoFont = "rounded"
    @AppStorage("appLogoAnim") private var appLogoAnim = "shimmer"

    private var appName: String {
        (Bundle.main.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String)
            ?? (Bundle.main.object(forInfoDictionaryKey: "CFBundleName") as? String)
            ?? "KENIOS"
    }
    // Phiên bản hiển thị dạng X.Y ĐẸP (…3.9 → 4.0 → 4.1…) suy từ số build — ĐỒNG BỘ với popup cập nhật.
    private var versionDisplay: String {
        let b = Int(Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "0") ?? 0
        let idx = max(0, b - 884)          // build 913 → 3.9 · build 914 → 4.0
        return "\(1 + idx / 10).\(idx % 10)"
    }
    private let publisher = "KENIOS"

    // Ngày sản xuất ≈ ngày build (lấy theo thời điểm sửa Info.plist trong gói app).
    private var productionDate: Date {
        if let url = Bundle.main.url(forResource: "Info", withExtension: "plist"),
           let attrs = try? FileManager.default.attributesOfItem(atPath: url.path),
           let d = attrs[.modificationDate] as? Date {
            return d
        }
        if let exe = Bundle.main.executableURL,
           let attrs = try? FileManager.default.attributesOfItem(atPath: exe.path),
           let d = attrs[.modificationDate] as? Date {
            return d
        }
        return Date()
    }

    private var productionDateString: String {
        let f = DateFormatter()
        f.locale = Locale(identifier: store.language == "en" ? "en_US" : "vi_VN")
        f.dateFormat = "dd/MM/yyyy"
        return f.string(from: productionDate)
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                VStack(spacing: 10) {
                    // Logo đồng bộ với app gốc: admin đổi trong Cài đặt → hiện ngay ở đây.
                    AnimatedStoreLogo(text: "KENIOS", effect: appLogoEffect,
                                      fontStyle: appLogoFont, anim: appLogoAnim, size: 40)
                    Text(store.t("Ứng dụng chính thức KENIOS", "Official KENIOS application"))
                        .font(.caption).foregroundStyle(.secondary)
                }
                .padding(.top, 16)

                VStack(spacing: 0) {
                    infoRow(store.t("Tên ứng dụng", "App name"), appName)
                    Divider()
                    infoRow(store.t("Phiên bản", "Version"), versionDisplay)
                    Divider()
                    infoRow(store.t("Ngày sản xuất", "Production date"), productionDateString)
                    Divider()
                    infoRow(store.t("Nhà phát hành", "Publisher"), publisher)
                }
                .background(Color(.secondarySystemBackground))
                .clipShape(RoundedRectangle(cornerRadius: 14))
                .padding(.horizontal)

                Text("© \(String(Calendar.current.component(.year, from: Date()))) \(publisher). "
                     + store.t("Bảo lưu mọi quyền.", "All rights reserved."))
                    .font(.caption2).foregroundStyle(.tertiary)
                    .padding(.top, 4)

                Spacer(minLength: 20)
            }
        }
        .navigationTitle(store.t("Thông tin ứng dụng", "App Information"))
        .navigationBarTitleDisplayMode(.inline)
    }

    private func infoRow(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label).foregroundStyle(.secondary)
            Spacer()
            Text(value).font(.subheadline.weight(.semibold))
                .multilineTextAlignment(.trailing)
        }
        .padding(.horizontal, 16).padding(.vertical, 13)
    }
}
