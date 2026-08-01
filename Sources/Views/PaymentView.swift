import SwiftUI

struct PaymentView: View {
    @EnvironmentObject var store: AppStore
    @Environment(\.dismiss) var dismiss

    @State private var packages: [PaymentPackage] = []
    @State private var history: [PaymentRecord] = []
    @State private var created: PaymentCreateResponse?
    @State private var error: String?
    @State private var loading = false
    @State private var checking = false
    @State private var cancelling: Int?
    @State private var info: String?

    var body: some View {
        NavigationStack {
            Form {
                Section(store.t("Tài khoản hiện tại", "Current account")) {
                    HStack {
                        Text(store.isPro ? store.t("Gói PRO", "PRO plan") : store.t("Gói Free", "Free plan"))
                        Spacer()
                        if store.isPro {
                            Label(store.t("Đã kích hoạt PRO", "PRO activated"), systemImage: "crown.fill")
                                .font(.caption).foregroundStyle(Theme.gold)
                        } else {
                            Text(store.t("Chưa nâng cấp", "Not upgraded")).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }

                Section(store.t("Nâng cấp tài khoản", "Upgrade account")) {
                    ForEach(packages) { p in
                        Button {
                            Task { await create(p) }
                        } label: {
                            HStack {
                                VStack(alignment: .leading) {
                                    Text(p.label).foregroundStyle(.primary)
                                    if let d = p.days, d > 0 {
                                        Text(store.t("Thời hạn \(d) ngày · mở khoá toàn bộ PRO",
                                                     "\(d) days · unlock all PRO"))
                                            .font(.caption).foregroundStyle(.secondary)
                                    } else {
                                        Text(store.t("Mở khoá toàn bộ tính năng PRO", "Unlock all PRO features")).font(.caption).foregroundStyle(.secondary)
                                    }
                                }
                                Spacer()
                                if loading { ProgressView() }
                                else { Image(systemName: "chevron.right").foregroundStyle(.secondary) }
                            }
                        }
                        .disabled(loading)
                    }
                    if store.isPro {
                        if let exp = store.planExpiryText {
                            Text(store.t("Bạn đang là PRO, hết hạn \(exp). Mua thêm để gia hạn.",
                                         "You're PRO until \(exp). Buy more to extend."))
                                .font(.caption).foregroundStyle(.secondary)
                        } else {
                            Text(store.t("Tài khoản của bạn đã là PRO.", "Your account is already PRO."))
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }

                if let created {
                    Section(store.t("Quét mã QR để chuyển khoản", "Scan QR to transfer")) {
                        if let qr = created.qrUrl, let url = URL(string: qr) {
                            AsyncImage(url: url) { phase in
                                switch phase {
                                case .success(let img):
                                    img.resizable().scaledToFit()
                                        .frame(maxWidth: 260).frame(maxWidth: .infinity)
                                        .padding(8).background(Color.white)
                                        .clipShape(RoundedRectangle(cornerRadius: 14))
                                case .failure:
                                    Text(store.t("Không tải được mã QR. Dùng số tài khoản bên dưới.",
                                                 "Could not load QR. Use the account number below."))
                                        .font(.footnote).foregroundStyle(.secondary)
                                default:
                                    ProgressView().frame(maxWidth: .infinity)
                                }
                            }
                        }
                        LabeledContent(store.t("Ngân hàng", "Bank"), value: created.bankInfo.bank)
                        LabeledContent(store.t("Số tài khoản", "Account number"), value: created.bankInfo.account)
                        LabeledContent(store.t("Chủ tài khoản", "Account holder"), value: created.bankInfo.name)
                        LabeledContent(store.t("Nội dung CK", "Transfer note"), value: created.bankInfo.content)
                        LabeledContent(store.t("Số tiền", "Amount"), value: kFormatVND(created.amount))
                        Text(created.message).font(.footnote).foregroundStyle(.secondary)
                        Button {
                            Task { await checkPaid() }
                        } label: {
                            HStack {
                                if checking { ProgressView() }
                                Text(checking ? store.t("Đang kiểm tra...", "Checking...") : store.t("Tôi đã chuyển khoản — kiểm tra", "I've transferred — check"))
                            }
                            .frame(maxWidth: .infinity).frame(height: 46)
                            .background(Color.green.opacity(0.18)).foregroundStyle(.green)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                        }.disabled(checking)
                        if let info { Text(info).font(.footnote).foregroundStyle(.green) }
                        Text(store.t("Hệ thống tự xác nhận trong ~20 giây sau khi nhận tiền. Nếu chưa lên PRO, đợi chút rồi bấm kiểm tra lại.",
                                     "The system auto-confirms ~20s after receiving payment. If not PRO yet, wait a bit and check again."))
                            .font(.caption2).foregroundStyle(.secondary)
                    }
                }

                Section(store.t("Lịch sử giao dịch", "Transaction history")) {
                    if history.isEmpty {
                        Text(store.t("Chưa có giao dịch nào.", "No transactions yet.")).foregroundStyle(.secondary)
                    } else {
                        ForEach(history) { h in
                            HStack {
                                VStack(alignment: .leading) {
                                    Text(h.credits > 0
                                         ? "\(h.amount) đ → \(h.credits) credits"
                                         : "\(h.amount) đ → " + store.t("Nâng cấp PRO", "PRO upgrade"))
                                    Text(h.ref ?? "").font(.caption2).foregroundStyle(.secondary)
                                }
                                Spacer()
                                if h.status == "pending" {
                                    HStack(spacing: 8) {
                                        statusBadge(h.status)
                                        if cancelling == h.id {
                                            ProgressView().scaleEffect(0.8)
                                        } else {
                                            Button(store.t("Huỷ đơn", "Cancel"), role: .destructive) {
                                                Task { await cancelOrder(h) }
                                            }
                                            .font(.caption2.bold())
                                            .buttonStyle(.borderless)
                                        }
                                    }
                                } else {
                                    statusBadge(h.status)
                                }
                            }
                        }
                    }
                }

                if let error { Text(error).foregroundStyle(.red).font(.footnote) }
            }
            .navigationTitle(store.t("Nâng cấp PRO", "Upgrade to PRO"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button(store.t("Đóng", "Close")) { dismiss() } } }
            .task { await load() }
            .refreshable { await load() }
        }
    }

    private func statusBadge(_ status: String) -> some View {
        let (text, color): (String, Color)
        switch status {
        case "completed": (text, color) = (store.t("Đã cộng", "Credited"), .green)
        case "pending":   (text, color) = (store.t("Chờ xác nhận", "Pending"), .orange)
        case "cancelled", "canceled": (text, color) = (store.t("Đã huỷ", "Cancelled"), .secondary)
        default:          (text, color) = (status, .secondary)
        }
        return Text(text).font(.caption2)
            .padding(.horizontal, 8).padding(.vertical, 3)
            .background(color.opacity(0.18)).foregroundStyle(color)
            .clipShape(Capsule())
    }

    private func load() async {
        error = nil
        do {
            packages = try await store.api.paymentPackages()
            history = try await store.api.paymentHistory()
        } catch { self.error = error.localizedDescription }
    }

    private func create(_ p: PaymentPackage) async {
        loading = true; error = nil; info = nil
        do {
            created = try await store.api.createPayment(package: p.id, amount: p.amount)
            history = try await store.api.paymentHistory()
        } catch { self.error = error.localizedDescription }
        loading = false
    }

    private func checkPaid() async {
        checking = true; error = nil
        await store.refreshMe()
        await store.refreshCredits()
        history = (try? await store.api.paymentHistory()) ?? history
        if store.isPro {
            info = store.t("Thanh toán thành công! Tài khoản đã lên PRO.", "Payment successful! Account upgraded to PRO.")
            created = nil
        } else {
            info = store.t("Chưa nhận được thanh toán. Vui lòng đợi thêm rồi kiểm tra lại.",
                           "Payment not received yet. Please wait and check again.")
        }
        checking = false
    }

    private func cancelOrder(_ h: PaymentRecord) async {
        cancelling = h.id; error = nil
        do {
            _ = try await store.api.cancelPayment(id: h.id)
            history = try await store.api.paymentHistory()
            if created != nil { created = nil }
        } catch { self.error = error.localizedDescription }
        cancelling = nil
    }
}
