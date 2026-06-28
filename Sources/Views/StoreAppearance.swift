import SwiftUI
import AVKit
import WebKit

// Nút mở bảng tuỳ chỉnh giao diện + ngôn ngữ (dùng chung — áp cho toàn app)
struct AppearanceMenu: View {
    @EnvironmentObject var store: AppStore
    @State private var show = false
    var body: some View {
        Button { show = true } label: {
            Image(systemName: "paintbrush.pointed.fill")
        }
        .sheet(isPresented: $show) { AppearanceSheet().environmentObject(store) }
    }
}

// Bảng tuỳ chỉnh đẹp: chọn Giao diện (thẻ) + Ngôn ngữ (lưới có cờ)
struct AppearanceSheet: View {
    @EnvironmentObject var store: AppStore
    @Environment(\.dismiss) private var dismiss

    private let langCols = [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    // ----- Giao diện -----
                    VStack(alignment: .leading, spacing: 10) {
                        Label(store.t("Giao diện", "Theme"), systemImage: "circle.lefthalf.filled")
                            .font(.headline)
                        HStack(spacing: 12) {
                            themeCard("light",  store.t("Sáng", "Light"),  "sun.max.fill",     [.orange, .yellow])
                            themeCard("dark",   store.t("Tối", "Dark"),    "moon.stars.fill",  [.indigo, .purple])
                            themeCard("system", store.t("Tự động", "Auto"), "circle.lefthalf.filled", [.blue, .cyan])
                        }
                    }

                    // ----- Ngôn ngữ -----
                    VStack(alignment: .leading, spacing: 10) {
                        Label(store.t("Ngôn ngữ", "Language"), systemImage: "globe")
                            .font(.headline)
                        LazyVGrid(columns: langCols, spacing: 10) {
                            ForEach(kAppLanguages, id: \.0) { code, name in
                                langCard(code, name)
                            }
                        }
                    }
                }
                .padding()
            }
            .navigationTitle(store.t("Tuỳ chỉnh giao diện", "Appearance"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(store.t("Xong", "Done")) { dismiss() }.bold()
                }
            }
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
        }
    }

    private func themeCard(_ mode: String, _ title: String, _ icon: String, _ colors: [Color]) -> some View {
        let on = store.themeMode == mode
        return Button {
            withAnimation(.easeInOut(duration: 0.15)) { store.setThemeMode(mode) }
        } label: {
            VStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 22, weight: .bold)).foregroundStyle(.white)
                    .frame(width: 52, height: 52)
                    .background(LinearGradient(colors: colors, startPoint: .topLeading, endPoint: .bottomTrailing))
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                Text(title).font(.subheadline.bold()).foregroundStyle(.primary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(Color(.secondarySystemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(on ? store.accentColor : Color.clear, lineWidth: 2)
            )
            .overlay(alignment: .topTrailing) {
                if on {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(store.accentColor).padding(6)
                }
            }
        }
        .buttonStyle(.plain)
    }

    private func langCard(_ code: String, _ name: String) -> some View {
        let on = store.language == code
        return Button {
            store.setLanguage(code)
        } label: {
            HStack(spacing: 6) {
                Text(name).font(.subheadline).foregroundStyle(.primary).lineLimit(1)
                Spacer(minLength: 2)
                if on { Image(systemName: "checkmark.circle.fill").foregroundStyle(store.accentColor) }
            }
            .padding(.horizontal, 12).padding(.vertical, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(on ? store.accentColor.opacity(0.14) : Color(.secondarySystemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(on ? store.accentColor.opacity(0.6) : Color.clear, lineWidth: 1.5)
            )
        }
        .buttonStyle(.plain)
    }
}

