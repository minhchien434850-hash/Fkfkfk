import SwiftUI

// ======================== Trò chơi — khu game riêng (chơi trong app) ========================
struct GameItem: Identifiable, Codable, Hashable {
    var id = UUID()
    var name: String
    var url: String
    var icon: String = "gamecontroller.fill"
}

struct GameZoneView: View {
    @EnvironmentObject var store: AppStore
    @AppStorage("kenios_games") private var gamesRaw = "[]"
    @State private var playURL: String?
    @State private var showAdd = false
    @State private var newName = ""
    @State private var newURL = ""

    // Game/cổng game có sẵn (HTML5, chơi ngay trên web trong app)
    private let builtin: [GameItem] = [
        GameItem(name: "CrazyGames", url: "https://www.crazygames.com", icon: "gamecontroller.fill"),
        GameItem(name: "Poki",       url: "https://poki.com",            icon: "flame.fill"),
        GameItem(name: "Y8",         url: "https://www.y8.com",          icon: "star.fill"),
        GameItem(name: "Friv",       url: "https://www.friv.com",        icon: "face.smiling.fill"),
        GameItem(name: "Miniclip",   url: "https://www.miniclip.com",    icon: "circle.grid.3x3.fill"),
        GameItem(name: "2048",       url: "https://play2048.co",         icon: "square.grid.2x2.fill"),
        GameItem(name: "Tetris",     url: "https://tetris.com/play-tetris", icon: "square.stack.3d.up.fill"),
        GameItem(name: "Cờ vua",     url: "https://www.chess.com/play",  icon: "crown.fill"),
        GameItem(name: "Slither.io", url: "https://slither.io",          icon: "scribble.variable"),
        GameItem(name: "Agar.io",    url: "https://agar.io",             icon: "circle.fill"),
        GameItem(name: "Skribbl",    url: "https://skribbl.io",          icon: "pencil.and.outline"),
        GameItem(name: "GamePix",    url: "https://www.gamepix.com",     icon: "dpad.fill"),
    ]

    private let cols = [GridItem(.adaptive(minimum: 100), spacing: 14)]

    private var customGames: [GameItem] {
        (try? JSONDecoder().decode([GameItem].self, from: Data(gamesRaw.utf8))) ?? []
    }
    private func saveCustom(_ list: [GameItem]) {
        if let d = try? JSONEncoder().encode(list) { gamesRaw = String(data: d, encoding: .utf8) ?? "[]" }
    }
    private func addCustom() {
        var url = newURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !url.isEmpty else { return }
        if !url.lowercased().hasPrefix("http") { url = "https://" + url }
        let name = newName.trimmingCharacters(in: .whitespaces).isEmpty ? url : newName
        var list = customGames
        list.append(GameItem(name: name, url: url))
        saveCustom(list)
        newName = ""; newURL = ""
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    KHeroHeader(icon: "gamecontroller.fill",
                                title: store.t("Trò chơi", "Games"),
                                subtitle: store.t("Chơi game ngay trong app · thêm game/app yêu thích",
                                                  "Play games in-app · add your favorite games/apps"))

                    // Game của bạn
                    if !customGames.isEmpty {
                        Text(store.t("Game / app của bạn", "Your games / apps")).font(.headline)
                        LazyVGrid(columns: cols, spacing: 14) {
                            ForEach(customGames) { g in
                                gameCard(g, custom: true)
                            }
                        }
                    }

                    Text(store.t("Kho game", "Game library")).font(.headline)
                    LazyVGrid(columns: cols, spacing: 14) {
                        ForEach(builtin) { g in
                            gameCard(g, custom: false)
                        }
                        // Nút thêm game
                        Button { newName = ""; newURL = ""; showAdd = true } label: {
                            VStack(spacing: 8) {
                                Image(systemName: "plus")
                                    .font(.system(size: 26, weight: .bold))
                                    .foregroundStyle(Theme.accent)
                                    .frame(width: 56, height: 56)
                                    .background(Theme.accent.opacity(0.14))
                                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                                Text(store.t("Thêm", "Add")).font(.caption).foregroundStyle(.secondary)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                            .kCard(16)
                        }.buttonStyle(.plain)
                    }
                }
                .padding()
            }
            .navigationTitle(store.t("Trò chơi", "Games"))
            .navigationBarTitleDisplayMode(.inline)
            .fullScreenCover(item: Binding(
                get: { playURL.map { IdentifiedURL(url: $0) } },
                set: { playURL = $0?.url })) { item in
                GamePlayerView(url: item.url)
            }
            .alert(store.t("Thêm game / app (web)", "Add game / app (web)"), isPresented: $showAdd) {
                TextField(store.t("Tên (vd: Game của tôi)", "Name (e.g. My game)"), text: $newName)
                TextField(store.t("Link (vd: crazygames.com)", "Link (e.g. crazygames.com)"), text: $newURL)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                Button(store.t("Thêm", "Add")) { addCustom() }
                Button(store.t("Huỷ", "Cancel"), role: .cancel) { }
            } message: {
                Text(store.t("Dán link game/website để thêm vào kho và chơi ngay trong app.",
                             "Paste a game/website link to add it and play right in the app."))
            }
        }
    }

    private func gameCard(_ g: GameItem, custom: Bool) -> some View {
        Button { playURL = g.url } label: {
            VStack(spacing: 8) {
                Image(systemName: g.icon)
                    .font(.system(size: 26, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 56, height: 56)
                    .background(Theme.heroGradient)
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                Text(g.name).font(.caption).foregroundStyle(.primary)
                    .lineLimit(1).minimumScaleFactor(0.7)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .kCard(16)
        }
        .buttonStyle(.plain)
        .contextMenu {
            if custom {
                Button(role: .destructive) {
                    saveCustom(customGames.filter { $0.id != g.id })
                } label: { Label(store.t("Xoá", "Delete"), systemImage: "trash") }
            }
        }
    }
}

// Bọc String thành Identifiable cho fullScreenCover
private struct IdentifiedURL: Identifiable {
    let url: String
    var id: String { url }
}

// Trình chơi game toàn màn hình (dùng lại BrowserWebView)
struct GamePlayerView: View {
    @EnvironmentObject var store: AppStore
    let url: String
    @Environment(\.dismiss) private var dismiss
    @StateObject private var model = BrowserModel()

    var body: some View {
        NavigationStack {
            BrowserWebView(model: model)
                .ignoresSafeArea(edges: .bottom)
                .onAppear { model.open(url) }
                .navigationTitle(model.pageTitle.isEmpty ? store.t("Đang chơi", "Playing") : model.pageTitle)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) {
                        Button(store.t("Đóng", "Close")) { dismiss() }
                    }
                    ToolbarItem(placement: .topBarTrailing) {
                        HStack {
                            Button { model.back() } label: { Image(systemName: "chevron.left") }
                                .disabled(!model.canGoBack)
                            Button { model.reload() } label: { Image(systemName: "arrow.clockwise") }
                        }
                    }
                }
        }
    }
}
