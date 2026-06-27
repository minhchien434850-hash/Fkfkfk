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
    @State private var info: String?

    var body: some View {
        NavigationStack {
            Form {
                Section("Tài khoản hiện tại") {
                    HStack {
                        Text(store.isPro ? "Gói PRO" : "Gói Free")
                        Spacer()
                        if store.isPro {
                            Label("Đã kích hoạt PRO", systemImage: "crown.fill")
                                .font(.caption).foregroundStyle(Theme.gold)
                        } else {
                            Text("Chưa nâng cấp").font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }

                Section("Nâng cấp tài khoản") {
                    ForEach(packages) { p in
                        Button {
                            Task { await create(p) }
                        } label: {
                            HStack {
                                VStack(alignment: .leading) {
                                    Text(p.label).foregroundStyle(.primary)
                                    if p.credits > 0 {
                                        Text("\(p.credits) credits").font(.caption).foregroundStyle(.secondary)
                                    } else {
                                        Text("Mở khoá toàn bộ tính năng PRO").font(.caption).foregroundStyle(.secondary)
                                    }
                                }
                                Spacer()
                                if loading { ProgressView() }
                                else { Image(systemName: "chevron.right").foregroundStyle(.secondary) }
                            }
                        }
                        .disabled(loading || store.isPro)
                    }
                    if store.isPro {
                        Text("Tài khoản của bạn đã là PRO.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }

                if let created {
                    Section("Quét mã QR để chuyển khoản") {
                        if let qr = created.qrUrl, let url = URL(string: qr) {
                            AsyncImage(url: url) { phase in
                                switch phase {
                                case .success(let img):
                                    img.resizable().scaledToFit()
                                        .frame(maxWidth: 260).frame(maxWidth: .infinity)
                                        .padding(8).background(Color.white)
                                        .clipShape(RoundedRectangle(cornerRadius: 14))
                                case .failure:
                                    Text("Không tải được mã QR. Dùng số tài khoản bên dưới.")
                                        .font(.footnote).foregroundStyle(.secondary)
                                default:
                                    ProgressView().frame(maxWidth: .infinity)
                                }
                            }
                        }
                        LabeledContent("Ngân hàng", value: created.bankInfo.bank)
                        LabeledContent("Số tài khoản", value: created.bankInfo.account)
                        LabeledContent("Chủ tài khoản", value: created.bankInfo.name)
                        LabeledContent("Nội dung CK", value: created.bankInfo.content)
                        LabeledContent("Số tiền", value: kFormatVND(created.amount))
                        Text(created.message).font(.footnote).foregroundStyle(.secondary)
                        Button {
                            Task { await checkPaid() }
                        } label: {
                            HStack {
                                if checking { ProgressView() }
                                Text(checking ? "Đang kiểm tra..." : "Tôi đã chuyển khoản — kiểm tra")
                            }
                            .frame(maxWidth: .infinity).frame(height: 46)
                            .background(Color.green.opacity(0.18)).foregroundStyle(.green)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                        }.disabled(checking)
                        if let info { Text(info).font(.footnote).foregroundStyle(.green) }
                        Text("Hệ thống tự xác nhận trong ~20 giây sau khi nhận tiền. Nếu chưa lên PRO, đợi chút rồi bấm kiểm tra lại.")
                            .font(.caption2).foregroundStyle(.secondary)
                    }
                }

                Section("Lịch sử giao dịch") {
                    if history.isEmpty {
                        Text("Chưa có giao dịch nào.").foregroundStyle(.secondary)
                    } else {
                        ForEach(history) { h in
                            HStack {
                                VStack(alignment: .leading) {
                                    Text(h.credits > 0
                                         ? "\(h.amount) đ → \(h.credits) credits"
                                         : "\(h.amount) đ → Nâng cấp PRO")
                                    Text(h.ref ?? "").font(.caption2).foregroundStyle(.secondary)
                                }
                                Spacer()
                                statusBadge(h.status)
                            }
                        }
                    }
                }

                if let error { Text(error).foregroundStyle(.red).font(.footnote) }
            }
            .navigationTitle("Nâng cấp PRO")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Đóng") { dismiss() } } }
            .task { await load() }
            .refreshable { await load() }
        }
    }

    private func statusBadge(_ status: String) -> some View {
        let (text, color): (String, Color) = status == "completed"
            ? ("Đã cộng", .green) : (status == "pending" ? ("Chờ xác nhận", .orange) : (status, .secondary))
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
            info = "Thanh toán thành công! Tài khoản đã lên PRO."
            created = nil
        } else {
            info = "Chưa nhận được thanh toán. Vui lòng đợi thêm rồi kiểm tra lại."
        }
        checking = false
    }
}
