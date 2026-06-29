import SwiftUI

struct GameLauncherView: View {
    @EnvironmentObject var store: AppStore
    private let launcher = GameLauncher.shared
    @State private var memInfo = GameLauncher.MemoryInfo(used: 0, total: 0)
    @State private var thermalText = ("Bình thường", "checkmark.seal.fill")
    @State private var cleaning = false
    @State private var cleanDone = false
    @State private var timer = Timer.publish(every: 2, on: .main, in: .common).autoconnect()
    @State private var selectedCategory: NativeGame.GameCategory?

    private var filteredGames: [NativeGame] {
        guard let cat = selectedCategory else { return launcher.catalog }
        return launcher.catalog.filter { $0.category == cat }
    }

    private let cols = [
        GridItem(.flexible(), spacing: 14),
        GridItem(.flexible(), spacing: 14),
        GridItem(.flexible(), spacing: 14)
    ]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    headerSection
                    systemStatusCard
                    optimizeButton
                    categoryFilter
                    gameGrid
                }
                .padding()
            }
            .background(Theme.bgNavy.ignoresSafeArea())
            .navigationTitle(store.t("Game Launcher", "Game Launcher"))
            .navigationBarTitleDisplayMode(.inline)
            .onAppear { refreshStatus() }
            .onReceive(timer) { _ in refreshStatus() }
        }
    }

    // MARK: - Header

    private var headerSection: some View {
        KHeroHeader(
            icon: "gamecontroller.fill",
            title: store.t("Game Launcher", "Game Launcher"),
            subtitle: store.t("Tối ưu hiệu năng · Khởi chạy game nhanh", "Optimize performance · Launch games fast")
        )
    }

    // MARK: - System Status Card

    private var systemStatusCard: some View {
        VStack(spacing: 14) {
            HStack {
                Image(systemName: "cpu")
                    .font(.headline)
                    .foregroundStyle(Theme.gold)
                Text(store.t("Trạng thái hệ thống", "System Status"))
                    .font(.subheadline.bold())
                    .foregroundStyle(.white)
                Spacer()
            }

            HStack(spacing: 16) {
                // RAM
                statusPill(
                    icon: "memorychip",
                    label: "RAM",
                    value: "\(memInfo.freeMB) MB " + store.t("trống", "free"),
                    color: memInfo.usagePercent < 60 ? .green : memInfo.usagePercent < 80 ? .orange : .red
                )

                // Nhiệt độ
                statusPill(
                    icon: thermalText.1,
                    label: store.t("Nhiệt", "Thermal"),
                    value: store.t(thermalText.0, thermalText.0),
                    color: thermalColor
                )
            }

            // RAM bar
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text(store.t("Bộ nhớ App:", "App memory:"))
                        .font(.caption2).foregroundStyle(.white.opacity(0.6))
                    Spacer()
                    Text("\(memInfo.usedMB) / \(memInfo.totalMB) MB")
                        .font(.caption2.monospacedDigit()).foregroundStyle(.white.opacity(0.8))
                }
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 4)
                            .fill(Color.white.opacity(0.1))
                        RoundedRectangle(cornerRadius: 4)
                            .fill(ramBarColor)
                            .frame(width: geo.size.width * min(memInfo.usagePercent / 100, 1.0))
                    }
                }
                .frame(height: 8)
            }
        }
        .padding()
        .background(Color.white.opacity(0.06))
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    // MARK: - Optimize Button

    private var optimizeButton: some View {
        Button {
            runCleanup()
        } label: {
            HStack(spacing: 12) {
                if cleaning {
                    ProgressView().tint(.white)
                } else {
                    Image(systemName: cleanDone ? "checkmark.circle.fill" : "bolt.fill")
                        .font(.title3)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(cleaning
                         ? store.t("Đang tối ưu...", "Optimizing...")
                         : cleanDone
                           ? store.t("Đã tối ưu xong!", "Optimization complete!")
                           : store.t("Tối ưu hiệu năng", "Optimize Performance"))
                        .font(.headline.bold())
                    if !cleaning && !cleanDone {
                        Text(store.t("Dọn RAM · Xoá cache · Giải phóng tài nguyên",
                                     "Clean RAM · Clear cache · Free resources"))
                            .font(.caption2)
                            .opacity(0.8)
                    }
                }
                Spacer()
            }
            .frame(maxWidth: .infinity)
            .padding()
            .background(
                cleanDone
                    ? LinearGradient(colors: [.green, .green.opacity(0.7)], startPoint: .leading, endPoint: .trailing)
                    : LinearGradient(colors: [Color(red: 1, green: 0.4, blue: 0), Color(red: 1, green: 0.6, blue: 0.1)], startPoint: .leading, endPoint: .trailing)
            )
            .foregroundStyle(.white)
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .shadow(color: (cleanDone ? Color.green : Color.orange).opacity(0.4), radius: 10, y: 4)
        }
        .disabled(cleaning)
    }

    // MARK: - Category Filter

    private var categoryFilter: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                filterChip(label: store.t("Tất cả", "All"), selected: selectedCategory == nil) {
                    selectedCategory = nil
                }
                ForEach(NativeGame.GameCategory.allCases, id: \.self) { cat in
                    let count = launcher.catalog.filter { $0.category == cat }.count
                    if count > 0 {
                        filterChip(label: cat.rawValue, selected: selectedCategory == cat) {
                            selectedCategory = cat
                        }
                    }
                }
            }
        }
    }

    private func filterChip(label: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label)
                .font(.caption.bold())
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(selected ? Theme.accent : Color.white.opacity(0.08))
                .foregroundStyle(selected ? .white : .white.opacity(0.7))
                .clipShape(Capsule())
        }
    }

    // MARK: - Game Grid

    private var gameGrid: some View {
        LazyVGrid(columns: cols, spacing: 14) {
            ForEach(filteredGames) { game in
                gameCard(game)
            }
        }
    }

    private func gameCard(_ game: NativeGame) -> some View {
        let installed = launcher.isInstalled(game)

        return VStack(spacing: 10) {
            // Icon
            ZStack {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: categoryColors(game.category),
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 62, height: 62)
                    .shadow(color: categoryColors(game.category).first!.opacity(0.4), radius: 8, y: 4)

                Image(systemName: game.icon)
                    .font(.system(size: 26, weight: .semibold))
                    .foregroundStyle(.white)
            }

            // Tên game
            Text(game.name)
                .font(.caption2.bold())
                .foregroundStyle(.white)
                .lineLimit(2)
                .multilineTextAlignment(.center)
                .frame(height: 30)

            // Badge thể loại
            Text(game.category.rawValue)
                .font(.system(size: 8, weight: .semibold))
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Color.white.opacity(0.1))
                .foregroundStyle(.white.opacity(0.6))
                .clipShape(Capsule())

            // Nút hành động
            Button {
                if installed {
                    launcher.optimizeAndLaunch(game)
                } else {
                    launcher.openAppStore(game)
                }
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: installed ? "bolt.fill" : "arrow.down.circle")
                        .font(.system(size: 10, weight: .bold))
                    Text(installed
                         ? store.t("Tối ưu & Chơi", "Optimize & Play")
                         : store.t("Tải Game", "Download"))
                        .font(.system(size: 10, weight: .bold))
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
                .background(installed
                    ? LinearGradient(colors: [.green, .green.opacity(0.7)], startPoint: .leading, endPoint: .trailing)
                    : LinearGradient(colors: [Theme.accent, Theme.accent.opacity(0.7)], startPoint: .leading, endPoint: .trailing)
                )
                .foregroundStyle(.white)
                .clipShape(RoundedRectangle(cornerRadius: 10))
            }
        }
        .padding(10)
        .background(Color.white.opacity(installed ? 0.08 : 0.04))
        .clipShape(RoundedRectangle(cornerRadius: 18))
        .overlay(
            RoundedRectangle(cornerRadius: 18)
                .stroke(installed ? Color.green.opacity(0.3) : Color.white.opacity(0.06), lineWidth: 1)
        )
    }

    // MARK: - Helpers

    private func refreshStatus() {
        memInfo = launcher.memoryInfo()
        thermalText = launcher.thermalStateText()
    }

    private func runCleanup() {
        cleaning = true
        cleanDone = false
        launcher.cleanupBeforeLaunch()
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
            cleaning = false
            cleanDone = true
            refreshStatus()
            DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                cleanDone = false
            }
        }
    }

    private var thermalColor: Color {
        switch ProcessInfo.processInfo.thermalState {
        case .nominal:  return .green
        case .fair:     return .yellow
        case .serious:  return .orange
        case .critical: return .red
        @unknown default: return .gray
        }
    }

    private var ramBarColor: LinearGradient {
        let pct = memInfo.usagePercent
        if pct < 60 {
            return LinearGradient(colors: [.green, .green.opacity(0.7)], startPoint: .leading, endPoint: .trailing)
        } else if pct < 80 {
            return LinearGradient(colors: [.orange, .yellow], startPoint: .leading, endPoint: .trailing)
        } else {
            return LinearGradient(colors: [.red, .orange], startPoint: .leading, endPoint: .trailing)
        }
    }

    private func statusPill(icon: String, label: String, value: String, color: Color) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.caption)
                .foregroundStyle(color)
            VStack(alignment: .leading, spacing: 2) {
                Text(label)
                    .font(.system(size: 9))
                    .foregroundStyle(.white.opacity(0.5))
                Text(value)
                    .font(.caption2.bold())
                    .foregroundStyle(.white)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(color.opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    private func categoryColors(_ cat: NativeGame.GameCategory) -> [Color] {
        switch cat {
        case .moba:    return [Color(red: 0.9, green: 0.2, blue: 0.3), Color(red: 0.7, green: 0.1, blue: 0.2)]
        case .battle:  return [Color(red: 1.0, green: 0.5, blue: 0.0), Color(red: 0.9, green: 0.3, blue: 0.0)]
        case .fps:     return [Color(red: 0.2, green: 0.5, blue: 0.9), Color(red: 0.1, green: 0.3, blue: 0.7)]
        case .racing:  return [Color(red: 0.0, green: 0.8, blue: 0.5), Color(red: 0.0, green: 0.6, blue: 0.4)]
        case .sport:   return [Color(red: 0.3, green: 0.7, blue: 0.2), Color(red: 0.2, green: 0.5, blue: 0.1)]
        case .other:   return [Color(red: 0.6, green: 0.3, blue: 0.9), Color(red: 0.4, green: 0.2, blue: 0.7)]
        }
    }
}
