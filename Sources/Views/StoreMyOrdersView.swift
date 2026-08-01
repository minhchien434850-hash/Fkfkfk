import SwiftUI
import AVKit
import WebKit

// ============================ Đơn của tôi (khách) ============================
struct StoreMyOrdersView: View {
    @EnvironmentObject var store: AppStore
    @Environment(\.dismiss) var dismiss
    @State private var orders: [StoreOrder] = []
    @State private var loading = false
    @State private var timelineOrder: StoreOrder? = nil

    var body: some View {
        NavigationStack {
            List {
                if loading && orders.isEmpty {
                    HStack { Spacer(); ProgressView(); Spacer() }
                } else if orders.isEmpty {
                    Text(store.t("Bạn chưa mua sản phẩm nào.", "You haven't bought any products.")).foregroundStyle(.secondary)
                } else {
                    ForEach(orders) { o in orderRow(o) }
                }
            }
            .navigationTitle(store.t("Đơn của tôi", "My orders"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button(store.t("Đóng", "Close")) { dismiss() } } }
            .task { await reload() }
            .refreshable { await reload() }
            .sheet(item: $timelineOrder) { o in StoreOrderTimelineView(order: o) }
        }
    }

    @ViewBuilder private func orderRow(_ o: StoreOrder) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(o.productName).font(.subheadline.bold())
                Spacer()
                Text(o.status == "completed" ? "Hoàn tất" : "Chờ thanh toán")
                    .font(.caption2)
                    .foregroundStyle(o.status == "completed" ? .green : .orange)
            }
            Text(kFormatVND(o.amount)).font(.caption).foregroundStyle(Theme.accent)
            if let msg = o.delivery, !msg.isEmpty {
                HStack(alignment: .top) {
                    Text(msg).font(.caption).textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Button { UIPasteboard.general.string = msg } label: { Image(systemName: "doc.on.doc") }
                        .buttonStyle(.borderless)
                }
                .padding(8).background(Color(.secondarySystemBackground))
                .clipShape(RoundedRectangle(cornerRadius: 8))
            } else if let key = o.key, !key.isEmpty {
                HStack {
                    Text(key).font(.caption.monospaced()).textSelection(.enabled).lineLimit(2)
                    Spacer()
                    Button { UIPasteboard.general.string = key } label: { Image(systemName: "doc.on.doc") }
                        .buttonStyle(.borderless)
                }
                .padding(8).background(Color(.secondarySystemBackground))
                .clipShape(RoundedRectangle(cornerRadius: 8))
            }
            if o.status == "completed" {
                if let url = o.downloadUrl, !url.isEmpty, let u = URL(string: url) {
                    Link(destination: u) {
                        Label(store.t("Tải game", "Download game"), systemImage: "arrow.down.circle.fill").font(.caption.bold())
                    }
                } else if let fid = o.downloadFileId {
                    StoreFileDownloadButton(fileId: fid)
                }
            }
            Button { timelineOrder = o } label: {
                Label(store.t("Xem tiến trình đơn", "View order timeline"), systemImage: "list.bullet.clipboard")
                    .font(.caption2)
            }
            .buttonStyle(.borderless)
        }
        .padding(.vertical, 4)
    }

    private func reload() async {
        loading = true
        orders = (try? await store.api.storeMyOrders()) ?? []
        loading = false
    }
}

// ============================ Tiến trình đơn hàng (§3.2) ============================
struct StoreOrderTimelineView: View {
    let order: StoreOrder
    @EnvironmentObject var store: AppStore
    @Environment(\.dismiss) var dismiss

    private struct Step: Identifiable {
        let id = UUID()
        let title: String
        let detail: String
        let icon: String
        let done: Bool
        let time: Int?
    }

    private var isCancelled: Bool {
        order.status == "cancelled" || order.status == "refunded" || order.status == "failed"
    }
    private var isCompleted: Bool { order.status == "completed" }

    private var steps: [Step] {
        var arr: [Step] = []
        arr.append(Step(title: store.t("Đã đặt đơn", "Order placed"),
                        detail: order.productName,
                        icon: "cart.fill.badge.plus", done: true, time: order.createdAt))
        arr.append(Step(title: store.t("Thanh toán", "Payment"),
                        detail: kFormatVND(order.amount),
                        icon: "creditcard.fill",
                        done: isCompleted, time: isCompleted ? order.createdAt : nil))
        if isCancelled {
            arr.append(Step(title: store.t("Đã huỷ / hoàn tiền", "Cancelled / refunded"),
                            detail: store.t("Đơn không hoàn tất.", "Order did not complete."),
                            icon: "xmark.octagon.fill", done: true, time: nil))
            return arr
        }
        let delivered = isCompleted && ((order.key?.isEmpty == false) || (order.delivery?.isEmpty == false)
                                        || order.downloadUrl?.isEmpty == false || order.downloadFileId != nil)
        arr.append(Step(title: store.t("Giao hàng / Giao key", "Delivery"),
                        detail: delivered ? store.t("Đã giao nội dung sản phẩm.", "Product content delivered.")
                                          : store.t("Đang chuẩn bị giao.", "Preparing delivery."),
                        icon: "shippingbox.fill", done: delivered, time: nil))
        arr.append(Step(title: store.t("Hoàn tất", "Completed"),
                        detail: isCompleted ? store.t("Đơn đã hoàn tất.", "Order completed.")
                                            : store.t("Chờ hoàn tất.", "Awaiting completion."),
                        icon: "checkmark.seal.fill", done: isCompleted, time: nil))
        if let exp = order.expiresAt, exp > 0 {
            arr.append(Step(title: store.t("Hạn sử dụng", "Expires"),
                            detail: store.t("Hết hạn vào", "Expires on"),
                            icon: "clock.badge.exclamationmark", done: false, time: exp))
        }
        return arr
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    // Tiêu đề đơn
                    VStack(alignment: .leading, spacing: 4) {
                        Text(order.productName).font(.headline)
                        if let ref = order.ref, !ref.isEmpty {
                            Text(store.t("Mã đơn: ", "Ref: ") + ref).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    .padding(.bottom, 16)

                    ForEach(Array(steps.enumerated()), id: \.element.id) { idx, s in
                        HStack(alignment: .top, spacing: 12) {
                            VStack(spacing: 0) {
                                ZStack {
                                    Circle().fill(s.done ? Theme.accent : Color(.systemGray4))
                                        .frame(width: 34, height: 34)
                                    Image(systemName: s.icon).font(.caption).foregroundStyle(.white)
                                }
                                if idx < steps.count - 1 {
                                    Rectangle()
                                        .fill(s.done ? Theme.accent.opacity(0.6) : Color(.systemGray4))
                                        .frame(width: 3, height: 40)
                                }
                            }
                            VStack(alignment: .leading, spacing: 3) {
                                Text(s.title).font(.subheadline.bold())
                                    .foregroundStyle(s.done ? .primary : .secondary)
                                Text(s.detail).font(.caption).foregroundStyle(.secondary)
                                if let t = s.time, t > 0 {
                                    Text(fmtTime(t)).font(.caption2).foregroundStyle(.tertiary)
                                }
                            }
                            Spacer()
                        }
                    }
                }
                .padding()
            }
            .navigationTitle(store.t("Tiến trình đơn", "Order timeline"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button(store.t("Đóng", "Close")) { dismiss() } } }
        }
    }

    private func fmtTime(_ ts: Int) -> String {
        let f = DateFormatter()
        f.dateFormat = "HH:mm dd/MM/yyyy"
        return f.string(from: Date(timeIntervalSince1970: TimeInterval(ts)))
    }
}

