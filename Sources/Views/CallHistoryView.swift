import SwiftUI

// ============================ Lịch sử cuộc gọi (gọi đi / đến / nhỡ) ============================
struct CallHistoryView: View {
    @EnvironmentObject var store: AppStore
    @EnvironmentObject var calls: CallCoordinator
    @AppStorage("lastSeenCallId") private var lastSeenCallId = 0
    @State private var items: [CallHistoryItem] = []
    @State private var loading = true

    var body: some View {
        List {
            if loading {
                HStack { Spacer(); ProgressView(); Spacer() }
            } else if items.isEmpty {
                Text(store.t("Chưa có cuộc gọi nào.", "No calls yet."))
                    .foregroundStyle(.secondary).font(.footnote)
            } else {
                ForEach(items) { c in
                    HStack(spacing: 12) {
                        Image(systemName: dirIcon(c))
                            .font(.title3)
                            .foregroundStyle(c.missed ? .red : (c.incoming ? .green : Theme.accent))
                            .frame(width: 26)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(c.peer).font(.subheadline.bold())
                                .foregroundStyle(c.missed ? .red : .primary)
                            HStack(spacing: 5) {
                                Image(systemName: c.video ? "video.fill" : "phone.fill")
                                    .font(.system(size: 10)).foregroundStyle(.secondary)
                                Text(subtitle(c)).font(.caption2).foregroundStyle(.secondary)
                            }
                        }
                        Spacer()
                        Text(timeAgo(c.startedAt)).font(.caption2).foregroundStyle(.secondary)
                        Button {
                            calls.placeCall(to: FriendItem(id: c.peerId, username: c.peer), video: c.video)
                        } label: {
                            Image(systemName: c.video ? "video" : "phone")
                                .foregroundStyle(Theme.accent)
                        }
                        .buttonStyle(.borderless)
                    }
                    .padding(.vertical, 2)
                }
            }
        }
        .navigationTitle(store.t("Lịch sử cuộc gọi", "Call history"))
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
        .refreshable { await load() }
    }

    private func load() async {
        loading = true; defer { loading = false }
        items = (try? await store.api.callHistory()) ?? []
        // Đánh dấu đã xem cuộc gọi nhỡ → xoá chấm đỏ ở màn Bạn bè.
        if let maxId = items.map(\.id).max(), maxId > lastSeenCallId { lastSeenCallId = maxId }
    }

    private func dirIcon(_ c: CallHistoryItem) -> String {
        if c.missed { return "phone.arrow.down.left" }        // nhỡ
        return c.incoming ? "phone.arrow.down.left" : "phone.arrow.up.right"
    }
    private func subtitle(_ c: CallHistoryItem) -> String {
        if c.missed { return store.t("Cuộc gọi nhỡ", "Missed call") }
        if c.status == "declined" { return store.t("Đã từ chối", "Declined") }
        if c.status == "answered" {
            let m = c.duration / 60, s = c.duration % 60
            return store.t("Thời lượng ", "Duration ") + String(format: "%d:%02d", m, s)
        }
        return c.incoming ? store.t("Gọi đến", "Incoming") : store.t("Gọi đi", "Outgoing")
    }
    private func timeAgo(_ ts: Int) -> String {
        let s = max(0, Int(Date().timeIntervalSince1970) - ts)
        if s < 60 { return store.t("vừa xong", "now") }
        if s < 3600 { return "\(s/60) " + store.t("phút", "min") }
        if s < 86400 { return "\(s/3600) " + store.t("giờ", "h") }
        return "\(s/86400) " + store.t("ngày", "d")
    }
}
