import SwiftUI
import UniformTypeIdentifiers
import PhotosUI


// ---- Đơn hàng đã bán (admin) ----
struct StoreAdminOrdersView: View {
    @EnvironmentObject var store: AppStore
    @State private var orders: [StoreAdminOrder] = []

    var body: some View {
        List {
            if orders.isEmpty {
                Text(store.t("Chưa có đơn nào.", "No orders yet.")).foregroundStyle(.secondary)
            } else {
                ForEach(orders) { o in
                    VStack(alignment: .leading, spacing: 2) {
                        HStack {
                            Text(o.productName).font(.subheadline.bold())
                            Spacer()
                            Text(o.status == "completed" ? store.t("đã thanh toán", "paid") : store.t("chờ", "pending"))
                                .font(.caption2)
                                .foregroundStyle(o.status == "completed" ? .green : .orange)
                        }
                        Text("\(kFormatVND(o.amount)) · @\(o.username)")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
        }
        .navigationTitle(store.t("Đơn hàng", "Orders"))
        .navigationBarTitleDisplayMode(.inline)
        .task { orders = (try? await store.api.adminStoreOrders()) ?? [] }
        .refreshable { orders = (try? await store.api.adminStoreOrders()) ?? [] }
    }
}

// ---- Khuyến mãi nạp ví (%) — admin ----
struct StoreTopupBonusEditor: View {
    @EnvironmentObject var store: AppStore
    @State private var percentText = ""
    @State private var message: String?
    @State private var isError = false
    private var percent: Int? { Int(percentText.filter { $0.isNumber }) }

    var body: some View {
        Form {
            Section(store.t("Phần trăm thưởng khi khách nạp ví", "Bonus percent on customer top-up")) {
                HStack {
                    TextField(store.t("Ví dụ: 20", "e.g. 20"), text: $percentText).keyboardType(.numberPad)
                    Text("%").foregroundStyle(.secondary)
                }
                if let p = percent, p > 0 {
                    Text(store.t("Khách nạp 100.000đ sẽ nhận", "A 100,000đ top-up gives") + " \(kFormatVND(100_000 + 100_000 * p / 100)) " + store.t("vào ví.", "in the wallet."))
                        .font(.caption).foregroundStyle(.pink)
                }
                Text(store.t("Đặt 0 để tắt khuyến mãi. Áp dụng cho VÍ cửa hàng (tách biệt với nâng cấp PRO của app chính).",
                             "Set 0 to disable. Applies to the store WALLET (separate from the main app's PRO upgrade)."))
                    .font(.caption2).foregroundStyle(.secondary)
            }
            Section { Button(store.t("Lưu", "Save")) { Task { await save() } }.disabled(percent == nil) }
            if let message { Text(message).font(.footnote).foregroundStyle(isError ? .red : .green) }
        }
        .navigationTitle(store.t("Khuyến mãi", "Promotions"))
        .navigationBarTitleDisplayMode(.inline)
        .task {
            if let r = try? await store.api.adminGetTopupBonus() { percentText = "\(r.percent)" }
        }
    }
    private func save() async {
        guard let p = percent else { return }
        message = nil
        do { let r = try await store.api.adminSetTopupBonus(percent: p); isError = false; message = r.message }
        catch { isError = true; message = error.localizedDescription }
    }
}

// ---- Kho hàng (tồn kho) — admin ----
struct StoreInventoryView: View {
    @EnvironmentObject var store: AppStore
    @State private var inv: StoreInventory?

    var body: some View {
        List {
            if let inv {
                Section {
                    HStack {
                        invStat(store.t("Còn lại", "Available"), "\(inv.totalAvailable)", .green)
                        invStat(store.t("Đã bán", "Sold"), "\(inv.totalSold)", .blue)
                        invStat(store.t("Hết hàng", "Out of stock"), "\(inv.outOfStock)", inv.outOfStock > 0 ? .red : .secondary)
                    }
                    .listRowBackground(Color.clear)
                }
                Section(store.t("Sản phẩm", "Products") + " (\(inv.products.count)) — " + store.t("ưu tiên hết/sắp hết", "out/low stock first")) {
                    if inv.products.isEmpty {
                        Text(store.t("Chưa có sản phẩm nào.", "No products yet.")).foregroundStyle(.secondary)
                    }
                    ForEach(inv.products) { p in
                        HStack(spacing: 10) {
                            Image(systemName: (p.kind ?? "app") == "acc" ? "gamecontroller.fill" : "key.fill")
                                .foregroundStyle((p.kind ?? "app") == "acc" ? .purple : Theme.accent)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(p.name).font(.subheadline.bold()).lineLimit(1)
                                Text("\(p.categoryName) › \(p.folderName)")
                                    .font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                            }
                            Spacer()
                            VStack(alignment: .trailing, spacing: 2) {
                                Text(p.available == 0 ? store.t("HẾT", "OUT") : store.t("Còn", "Left") + " \(p.available)")
                                    .font(.caption.bold())
                                    .foregroundStyle(p.available == 0 ? .red : (p.available <= 5 ? .orange : .green))
                                Text(store.t("đã bán", "sold") + " \(p.sold)").font(.caption2).foregroundStyle(.secondary)
                            }
                        }
                        .padding(.vertical, 2)
                    }
                }
            } else {
                HStack { Spacer(); ProgressView(); Spacer() }
            }
        }
        .navigationTitle(store.t("Kho hàng", "Inventory"))
        .navigationBarTitleDisplayMode(.inline)
        .task { inv = try? await store.api.adminStoreInventory() }
        .refreshable { inv = try? await store.api.adminStoreInventory() }
    }

    private func invStat(_ label: String, _ value: String, _ color: Color) -> some View {
        VStack(spacing: 4) {
            Text(value).font(.title3.bold().monospacedDigit()).foregroundStyle(color)
            Text(label).font(.caption2).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

// ======================== Nạp/Trừ ví khách hàng thủ công ========================
struct AdminWalletAdjustView: View {
    @EnvironmentObject var store: AppStore
    var prefillUser: String = ""              // mở sẵn với 1 khách (từ danh sách người dùng)
    @State private var userIdentifier = ""    // username hoặc publicId
    @State private var amountText = ""
    @State private var note = ""
    @State private var isDeduct = false       // false = nạp, true = trừ
    @State private var processing = false
    @State private var message: String?
    @State private var isError = false
    @State private var history: [WalletAdjustRecord] = []

    private var amount: Int? { Int(amountText.filter { $0.isNumber }) }
    private let presets = [10_000, 50_000, 100_000, 200_000, 500_000]

    var body: some View {
        Form {
            Section {
                KHeroHeader(icon: "dollarsign.arrow.circlepath",
                            title: store.t("Điều chỉnh ví", "Adjust wallet"),
                            subtitle: store.t("Nạp hoặc trừ tiền ví khách hàng thủ công",
                                              "Manually add or deduct customer wallet funds"))
                    .listRowInsets(EdgeInsets()).listRowBackground(Color.clear)
            }

            Section(store.t("Khách hàng", "Customer")) {
                TextField(store.t("Username hoặc ID khách hàng", "Customer username or ID"), text: $userIdentifier)
                    .textInputAutocapitalization(.never).autocorrectionDisabled()
            }
            .onAppear { if userIdentifier.isEmpty && !prefillUser.isEmpty { userIdentifier = prefillUser } }

            Section(store.t("Loại thao tác", "Operation type")) {
                Picker("", selection: $isDeduct) {
                    Text(store.t("Nạp tiền (+)", "Add (+)")).tag(false)
                    Text(store.t("Trừ tiền (-)", "Deduct (-)")).tag(true)
                }.pickerStyle(.segmented)
            }

            Section(isDeduct ? store.t("Số tiền trừ", "Deduct amount") : store.t("Số tiền nạp", "Add amount")) {
                HStack {
                    TextField(store.t("Nhập số tiền (VND)", "Enter amount (VND)"), text: $amountText).keyboardType(.numberPad)
                    Text("đ").foregroundStyle(.secondary)
                }
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(presets, id: \.self) { v in
                            Button(kFormatVND(v)) { amountText = "\(v)" }
                                .font(.caption)
                                .padding(.horizontal, 10).padding(.vertical, 5)
                                .background(Color(.secondarySystemBackground)).clipShape(Capsule())
                        }
                    }
                }
            }

            Section(store.t("Ghi chú", "Note")) {
                TextField(store.t("Lý do (tuỳ chọn)", "Reason (optional)"), text: $note, axis: .vertical).lineLimit(1...3)
            }

            Section {
                Button {
                    Task { await adjust() }
                } label: {
                    HStack {
                        if processing { ProgressView().tint(.white) }
                        Text(processing ? store.t("Đang xử lý...", "Processing...") : (isDeduct ? store.t("Trừ ví", "Deduct wallet") : store.t("Nạp ví", "Add to wallet")))
                    }
                    .frame(maxWidth: .infinity).frame(height: 44)
                    .background(userIdentifier.isEmpty || (amount ?? 0) < 1 ? Color.gray :
                                (isDeduct ? Color.red : Color.green))
                    .foregroundStyle(.white).clipShape(RoundedRectangle(cornerRadius: 10))
                }
                .buttonStyle(.plain)
                .disabled(userIdentifier.isEmpty || (amount ?? 0) < 1 || processing)
            }

            if let message {
                Section {
                    Text(message).foregroundStyle(isError ? .red : .green).font(.footnote)
                }
            }

            if !history.isEmpty {
                Section(store.t("Lịch sử thao tác (phiên này)", "Operation history (this session)")) {
                    ForEach(history) { r in
                        HStack {
                            Image(systemName: r.delta >= 0 ? "plus.circle.fill" : "minus.circle.fill")
                                .foregroundStyle(r.delta >= 0 ? .green : .red)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(r.user).font(.caption.bold())
                                Text(r.note).font(.caption2).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Text((r.delta >= 0 ? "+" : "") + kFormatVND(r.delta))
                                .font(.caption.bold())
                                .foregroundStyle(r.delta >= 0 ? .green : .red)
                        }
                    }
                }
            }
        }
        .navigationTitle(store.t("Điều chỉnh ví", "Adjust wallet"))
        .navigationBarTitleDisplayMode(.inline)
    }

    private func adjust() async {
        guard let amt = amount, amt > 0, !userIdentifier.isEmpty else { return }
        processing = true; message = nil; isError = false
        let delta = isDeduct ? -amt : amt
        do {
            let resp = try await store.api.adminAdjustStoreWallet(
                userIdentifier: userIdentifier.trimmingCharacters(in: .whitespacesAndNewlines),
                delta: delta,
                note: note.isEmpty ? (isDeduct ? "Admin trừ ví thủ công" : "Admin nạp ví thủ công") : note)
            message = resp.message
            let record = WalletAdjustRecord(user: userIdentifier, delta: delta,
                                            note: note.isEmpty ? resp.message : note)
            history.insert(record, at: 0)
            // Gửi thông báo local cho admin
            store.postLocalNotification(
                title: isDeduct ? "Đã trừ ví" : "Đã nạp ví",
                body: "\(isDeduct ? "-" : "+")\(kFormatVND(amt)) cho \(userIdentifier)")
            amountText = ""; note = ""; userIdentifier = ""
        } catch {
            isError = true; message = error.localizedDescription
        }
        processing = false
    }
}

struct WalletAdjustRecord: Identifiable {
    let id = UUID()
    let user: String
    let delta: Int
    let note: String
}

// ======================== Thống kê & Phân tích (Admin) ========================
struct AdminAnalyticsView: View {
    @EnvironmentObject var store: AppStore
    @State private var stats: AdminStats?
    @State private var orders: [StoreAdminOrder] = []
    @State private var loading = false

    private var topProducts: [(name: String, count: Int, revenue: Int)] {
        var map: [String: (Int, Int)] = [:]
        for o in orders where o.status == "completed" {
            let cur = map[o.productName] ?? (0, 0)
            map[o.productName] = (cur.0 + 1, cur.1 + o.amount)
        }
        return map.map { (name: $0.key, count: $0.value.0, revenue: $0.value.1) }
            .sorted { $0.revenue > $1.revenue }
            .prefix(5).map { $0 }
    }

    private var storeRevenue: Int {
        orders.filter { $0.status == "completed" }.reduce(0) { $0 + $1.amount }
    }
    private var completedOrderCount: Int {
        orders.filter { $0.status == "completed" }.count
    }

    var body: some View {
        List {
            if loading && stats == nil {
                HStack { Spacer(); ProgressView(store.t("Đang tải...", "Loading...")); Spacer() }
            } else if let s = stats {
                Section(store.t("Doanh thu cửa hàng", "Store revenue")) {
                    HStack(spacing: 10) {
                        analyticsCard(store.t("Tổng cộng", "Total"), kFormatVND(storeRevenue), .green)
                        analyticsCard(store.t("Đơn hoàn tất", "Completed orders"), "\(completedOrderCount)", .blue)
                    }
                    .listRowBackground(Color.clear).listRowInsets(EdgeInsets())
                }
                Section(store.t("Người dùng", "Users")) {
                    HStack(spacing: 10) {
                        analyticsCard(store.t("Tổng users", "Total users"), "\(s.totalUsers)", .purple)
                        analyticsCard(store.t("7 ngày mới", "New (7 days)"), "+\(s.newUsers7d)", .orange)
                    }
                    .listRowBackground(Color.clear).listRowInsets(EdgeInsets())
                }
                Section(store.t("AI & Hội thoại", "AI & Conversations")) {
                    HStack(spacing: 10) {
                        analyticsCard(store.t("Hội thoại", "Conversations"), "\(s.totalConversations)", .teal)
                        analyticsCard(store.t("Tin nhắn", "Messages"), "\(s.totalMessages)", Theme.accent)
                    }
                    .listRowBackground(Color.clear).listRowInsets(EdgeInsets())
                    HStack(spacing: 10) {
                        analyticsCard(store.t("Doanh thu AI", "AI revenue"), kFormatVND(s.revenueTotal), .green)
                        analyticsCard(store.t("30 ngày", "30 days"), kFormatVND(s.revenue30d), .mint)
                    }
                    .listRowBackground(Color.clear).listRowInsets(EdgeInsets())
                }
                if !topProducts.isEmpty {
                    Section(store.t("Top sản phẩm bán chạy", "Top selling products")) {
                        let maxRev = topProducts.first.map { $0.revenue } ?? 1
                        ForEach(topProducts.indices, id: \.self) { i in
                            let item = topProducts[i]
                            VStack(alignment: .leading, spacing: 6) {
                                HStack {
                                    Text(item.name).font(.subheadline.bold()).lineLimit(1)
                                    Spacer()
                                    Text(kFormatVND(item.revenue))
                                        .font(.caption.bold()).foregroundStyle(Theme.accent)
                                }
                                HStack(spacing: 6) {
                                    GeometryReader { geo in
                                        ZStack(alignment: .leading) {
                                            RoundedRectangle(cornerRadius: 3)
                                                .fill(Color(.tertiarySystemBackground))
                                                .frame(height: 6)
                                            RoundedRectangle(cornerRadius: 3)
                                                .fill(Theme.accent)
                                                .frame(width: geo.size.width * CGFloat(item.revenue) / CGFloat(maxRev),
                                                       height: 6)
                                        }
                                    }
                                    .frame(height: 6)
                                    Text("\(item.count) " + store.t("đơn", "orders")).font(.caption2).foregroundStyle(.secondary)
                                }
                            }
                            .padding(.vertical, 2)
                        }
                    }
                }
                if !s.topProviders.isEmpty {
                    Section(store.t("AI provider phổ biến", "Popular AI providers")) {
                        let maxCount = s.topProviders.first?.count ?? 1
                        ForEach(s.topProviders, id: \.provider) { p in
                            VStack(alignment: .leading, spacing: 6) {
                                HStack {
                                    Text(p.provider).font(.subheadline)
                                    Spacer()
                                    Text("\(p.count) " + store.t("lượt", "uses")).font(.caption2).foregroundStyle(.secondary)
                                }
                                GeometryReader { geo in
                                    ZStack(alignment: .leading) {
                                        RoundedRectangle(cornerRadius: 3)
                                            .fill(Color(.tertiarySystemBackground))
                                            .frame(height: 6)
                                        RoundedRectangle(cornerRadius: 3)
                                            .fill(Theme.purple)
                                            .frame(width: geo.size.width * CGFloat(p.count) / CGFloat(maxCount),
                                                   height: 6)
                                    }
                                }
                                .frame(height: 6)
                            }
                            .padding(.vertical, 2)
                        }
                    }
                }
            } else if !loading {
                Text(store.t("Không tải được thống kê.", "Could not load statistics.")).foregroundStyle(.secondary)
            }
        }
        .navigationTitle(store.t("Thống kê & Phân tích", "Statistics & Analytics"))
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
        .refreshable { await load() }
    }

    private func analyticsCard(_ label: String, _ value: String, _ color: Color) -> some View {
        VStack(spacing: 6) {
            Text(value).font(.headline.monospacedDigit()).foregroundStyle(color).lineLimit(1).minimumScaleFactor(0.7)
            Text(label).font(.caption2).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private func load() async {
        loading = true
        async let s = store.api.adminStats()
        async let o = store.api.adminStoreOrders()
        stats = try? await s
        orders = (try? await o) ?? []
        loading = false
    }
}

// ======================== Quản lý mã khuyến mãi (Admin) ========================
struct AdminPromoCodesView: View {
    @EnvironmentObject var store: AppStore
    @State private var codes: [PromoCode] = []
    @State private var loading = false
    @State private var showAdd = false
    @State private var message: String?

    // Form tạo mới
    @State private var newCode = ""
    @State private var discountType = "percent"
    @State private var discountValue = ""
    @State private var minAmount = ""
    @State private var maxUses = ""

    var body: some View {
        List {
            if loading {
                Section { ProgressView() }
            }
            Section {
                ForEach(Array(codes.enumerated()), id: \.offset) { _, promo in
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text(promo.code).font(.headline.monospaced())
                            Spacer()
                            Text(promo.discountType == "percent"
                                 ? "-\(promo.discountValue)%"
                                 : "-\(kFormatVND(promo.discountValue))")
                                .font(.caption.bold()).foregroundStyle(.green)
                                .padding(.horizontal, 8).padding(.vertical, 3)
                                .background(Color.green.opacity(0.15))
                                .clipShape(Capsule())
                        }
                        HStack(spacing: 12) {
                            Label("\(promo.usedCount)\(promo.maxUses > 0 ? "/\(promo.maxUses)" : "") " + store.t("lượt", "uses"),
                                  systemImage: "person.2")
                            if promo.minAmount > 0 {
                                Label(store.t("Tối thiểu", "Min") + " \(kFormatVND(promo.minAmount))", systemImage: "cart")
                            }
                            if promo.expiresAt > 0 {
                                Label(Date(timeIntervalSince1970: TimeInterval(promo.expiresAt))
                                        .formatted(.dateTime.day().month().year()),
                                      systemImage: "calendar")
                            }
                        }
                        .font(.caption2).foregroundStyle(.secondary)
                    }
                    .swipeActions(edge: .trailing) {
                        Button(role: .destructive) { Task { await deleteCode(promo.id) } } label: {
                            Label(store.t("Xoá", "Delete"), systemImage: "trash")
                        }
                    }
                }
            } header: {
                HStack {
                    Text(store.t("Danh sách mã", "Code list") + " (\(codes.count))")
                    Spacer()
                    Button { showAdd = true } label: { Image(systemName: "plus") }
                }
            }

            if let message {
                Section { Text(message).font(.footnote).foregroundStyle(.secondary) }
            }
        }
        .navigationTitle(store.t("Mã khuyến mãi", "Promo codes"))
        .navigationBarTitleDisplayMode(.inline)
        .task { await reload() }
        .sheet(isPresented: $showAdd) { addSheet }
    }

    private var addSheet: some View {
        NavigationStack {
            Form {
                Section(store.t("Mã giảm giá", "Discount code")) {
                    TextField(store.t("Tên mã (VD: SALE50)", "Code name (e.g. SALE50)"), text: $newCode)
                        .textInputAutocapitalization(.characters)
                        .autocorrectionDisabled()
                    Picker(store.t("Loại giảm", "Discount type"), selection: $discountType) {
                        Text(store.t("Phần trăm (%)", "Percent (%)")).tag("percent")
                        Text(store.t("Số tiền cố định (đ)", "Fixed amount (đ)")).tag("fixed")
                    }
                    TextField(discountType == "percent" ? store.t("Giảm bao nhiêu % (VD: 20)", "Discount % (e.g. 20)") : store.t("Giảm bao nhiêu đ (VD: 10000)", "Discount đ (e.g. 10000)"),
                              text: $discountValue)
                        .keyboardType(.numberPad)
                }
                Section(store.t("Điều kiện", "Conditions")) {
                    TextField(store.t("Đơn tối thiểu (VD: 50000, để trống = không giới hạn)", "Min order (e.g. 50000, empty = no limit)"), text: $minAmount)
                        .keyboardType(.numberPad)
                    TextField(store.t("Số lần dùng tối đa (để trống = không giới hạn)", "Max uses (empty = unlimited)"), text: $maxUses)
                        .keyboardType(.numberPad)
                }
            }
            .navigationTitle(store.t("Tạo mã mới", "Create new code"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { Button(store.t("Huỷ", "Cancel")) { showAdd = false } }
                ToolbarItem(placement: .topBarTrailing) {
                    Button(store.t("Tạo", "Create")) { Task { await createCode() } }
                        .bold()
                        .disabled(newCode.trimmingCharacters(in: .whitespaces).isEmpty || discountValue.isEmpty)
                }
            }
        }
    }

    private func reload() async {
        loading = true
        codes = (try? await store.api.adminListPromoCodes()) ?? []
        loading = false
    }

    private func createCode() async {
        let code = newCode.trimmingCharacters(in: .whitespaces).uppercased()
        guard !code.isEmpty, let value = Int(discountValue), value > 0 else { return }
        let min = Int(minAmount) ?? 0
        let max = Int(maxUses) ?? 0
        do {
            _ = try await store.api.adminCreatePromoCode(
                code: code, discountType: discountType, discountValue: value,
                minAmount: min, maxUses: max, expiresAt: 0)
            showAdd = false
            newCode = ""; discountValue = ""; minAmount = ""; maxUses = ""
            await reload()
        } catch {
            message = error.localizedDescription
        }
    }

    private func deleteCode(_ id: Int) async {
        _ = try? await store.api.adminDeletePromoCode(id)
        await reload()
    }
}

// ======================== Gửi Push Notification (Admin) ========================
struct AdminPushNotificationView: View {
    @EnvironmentObject var store: AppStore
    @State private var notifTitle = ""
    @State private var notifBody = ""
    @State private var sending = false
    @State private var result: String?
    @State private var isError = false
    @State private var deviceStats: PushDeviceStats?

    var body: some View {
        Form {
            if let stats = deviceStats {
                Section(store.t("Thiết bị đã đăng ký", "Registered devices")) {
                    Label("\(stats.totalDevices) " + store.t("thiết bị", "devices"), systemImage: "iphone")
                    Label("\(stats.totalUsers) " + store.t("người dùng", "users"), systemImage: "person.2")
                }
            }

            Section(store.t("Nội dung thông báo", "Notification content")) {
                TextField(store.t("Tiêu đề", "Title"), text: $notifTitle)
                TextField(store.t("Nội dung", "Body"), text: $notifBody, axis: .vertical)
                    .lineLimit(3...6)
            }

            Section {
                Button {
                    Task { await sendNotif() }
                } label: {
                    HStack {
                        if sending { ProgressView().padding(.trailing, 4) }
                        Text(sending ? store.t("Đang gửi...", "Sending...") : store.t("Gửi cho tất cả người dùng", "Send to all users"))
                            .font(.headline)
                    }
                    .frame(maxWidth: .infinity)
                }
                .disabled(sending || notifTitle.isEmpty || notifBody.isEmpty)
            }

            if let result {
                Section {
                    Text(result).foregroundStyle(isError ? .red : .green).font(.footnote)
                }
            }

            Section(store.t("Hướng dẫn cấu hình APNs", "APNs setup guide")) {
                Text("""
                Để gửi push notification thật, cần cấu hình các biến môi trường trên server:
                • APNS_KEY_ID — Key ID từ Apple Developer
                • APNS_TEAM_ID — Team ID của tài khoản
                • APNS_BUNDLE_ID — Bundle ID của app
                • APNS_KEY_PATH — Đường dẫn file .p8
                """)
                .font(.caption).foregroundStyle(.secondary)
            }
        }
        .navigationTitle(store.t("Gửi thông báo", "Send notification"))
        .navigationBarTitleDisplayMode(.inline)
        .task { deviceStats = try? await store.api.adminPushDeviceStats() }
    }

    private func sendNotif() async {
        sending = true; result = nil; isError = false
        do {
            let r = try await store.api.adminSendPushNotification(title: notifTitle, body: notifBody)
            result = r.message; isError = false
        } catch {
            result = error.localizedDescription; isError = true
        }
        sending = false
    }
}
