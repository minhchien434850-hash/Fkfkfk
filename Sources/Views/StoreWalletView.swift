import SwiftUI

// ============================ Ví cửa hàng (tách biệt app chính) ============================
struct StoreWalletView: View {
    @EnvironmentObject var store: AppStore
    @Environment(\.dismiss) var dismiss

    @State private var wallet: StoreWallet?
    @State private var amountText = ""
    @State private var topup: StoreTopupResponse?
    @State private var creating = false
    @State private var checking = false
    @State private var error: String?
    @State private var info: String?

    private let presets = [50_000, 100_000, 200_000, 500_000, 1_000_000]
    private var amount: Int? { Int(amountText.filter { $0.isNumber }) }

    var body: some View {
        NavigationStack {
            Form {
                Section("Số dư ví") {
                    HStack {
                        Image(systemName: "wallet.pass.fill").foregroundStyle(Theme.gold)
                        Text(kFormatVND(wallet?.balance ?? 0))
                            .font(.title2.bold()).foregroundStyle(Theme.accent)
                        Spacer()
                    }
                    if let pct = wallet?.bonusPercent, pct > 0 {
                        Label("Đang khuyến mãi +\(pct)% khi nạp ví!", systemImage: "gift.fill")
                            .font(.caption).foregroundStyle(.pink)
                    }
                }

                if topup == nil {
                    Section("Nạp tiền vào ví") {
                        HStack {
                            TextField("Số tiền muốn nạp", text: $amountText).keyboardType(.numberPad)
                            Text("đ").foregroundStyle(.secondary)
                        }
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack {
                                ForEach(presets, id: \.self) { v in
                                    Button(kFormatVND(v)) { amountText = "\(v)" }
                                        .font(.caption)
                                        .padding(.horizontal, 10).padding(.vertical, 6)
                                        .background(Color(.secondarySystemBackground)).clipShape(Capsule())
                                }
                            }
                        }
                        if let a = amount, let pct = wallet?.bonusPercent, pct > 0 {
                            Text("Nạp \(kFormatVND(a)) → nhận \(kFormatVND(a + a * pct / 100)) vào ví (+\(pct)%)")
                                .font(.caption).foregroundStyle(.pink)
                        }
                        Button {
                            Task { await createTopup() }
                        } label: {
                            HStack {
                                if creating { ProgressView().tint(.white) }
                                Text(creating ? "Đang tạo..." : "Tạo lệnh nạp")
                            }
                            .frame(maxWidth: .infinity).frame(height: 44)
                            .background((amount ?? 0) >= 1000 ? Theme.purple : Color.gray)
                            .foregroundStyle(.white).clipShape(RoundedRectangle(cornerRadius: 10))
                        }
                        .disabled(creating || (amount ?? 0) < 1000)
                    }
                } else if let t = topup {
                    topupBox(t)
                }

                if let info { Section { Text(info).font(.footnote).foregroundStyle(.green) } }
                if let error { Section { Text(error).font(.footnote).foregroundStyle(.red) } }

                Section("Lịch sử ví") {
                    if (wallet?.tx ?? []).isEmpty {
                        Text("Chưa có giao dịch nào.").foregroundStyle(.secondary)
                    } else {
                        ForEach(wallet!.tx) { tx in
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(tx.kind == "topup" ? "Nạp ví" : "Mua hàng").font(.subheadline)
                                    if !tx.note.isEmpty {
                                        Text(tx.note).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                                    }
                                }
                                Spacer()
                                Text((tx.amount >= 0 ? "+" : "") + kFormatVND(tx.amount))
                                    .font(.subheadline.bold())
                                    .foregroundStyle(tx.amount >= 0 ? .green : .red)
                            }
                        }
                    }
                }
            }
            .navigationTitle("Ví cửa hàng")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Đóng") { dismiss() } } }
            .task { await reload() }
            .refreshable { await reload() }
        }
    }

    @ViewBuilder private func topupBox(_ t: StoreTopupResponse) -> some View {
        Section("Quét mã QR để nạp \(kFormatVND(t.amount))") {
            if let qr = t.qrUrl, let url = URL(string: qr) {
                AsyncImage(url: url) { img in
                    img.resizable().scaledToFit().frame(maxWidth: 240).frame(maxWidth: .infinity)
                } placeholder: { ProgressView().frame(maxWidth: .infinity) }
            }
            LabeledContent("Ngân hàng", value: t.bankInfo.bank)
            LabeledContent("Số tài khoản", value: t.bankInfo.account)
            LabeledContent("Chủ tài khoản", value: t.bankInfo.name)
            LabeledContent("Nội dung CK", value: t.bankInfo.content)
            LabeledContent("Số tiền", value: kFormatVND(t.amount))
            if t.bonus > 0 {
                LabeledContent("Nhận vào ví", value: kFormatVND(t.credited) + " (+\(t.bonusPercent)%)")
            }
            Text(t.message).font(.caption).foregroundStyle(.secondary)
            Button {
                Task { await checkPaid(before: wallet?.balance ?? 0) }
            } label: {
                HStack {
                    if checking { ProgressView() }
                    Text(checking ? "Đang kiểm tra..." : "Tôi đã chuyển khoản — kiểm tra")
                }
                .frame(maxWidth: .infinity).frame(height: 44)
                .background(Color.green.opacity(0.18)).foregroundStyle(.green)
                .clipShape(RoundedRectangle(cornerRadius: 10))
            }.disabled(checking)
            Button("Huỷ lệnh nạp", role: .destructive) { topup = nil; info = nil }
        }
    }

    private func reload() async {
        wallet = try? await store.api.storeWallet()
    }
    private func createTopup() async {
        guard let a = amount else { return }
        creating = true; error = nil; info = nil
        do { topup = try await store.api.storeTopup(amount: a) }
        catch { self.error = error.localizedDescription }
        creating = false
    }
    private func checkPaid(before: Int) async {
        checking = true; error = nil
        let w = try? await store.api.storeWallet()
        if let w {
            wallet = w
            if w.balance > before {
                info = "Nạp ví thành công! Số dư: \(kFormatVND(w.balance))"
                topup = nil; amountText = ""
            } else {
                info = "Chưa nhận được tiền. Vui lòng đợi thêm rồi kiểm tra lại."
            }
        }
        checking = false
    }
}
