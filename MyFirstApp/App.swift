import SwiftUI

// MARK: - 数据模型（反斗限免快照 monitor-appstore.apprcn.com/api/v1/snapshot）

struct Snapshot: Decodable {
    let generated_at_iso: String?
    let alerts: [FreeApp]
}

struct RegionState: Codable, Hashable {
    let region: String
    let state: String
    let free: Bool
    let price_text: String?
    let rating: Double
    let rating_count: Int

    var label: String {
        switch region {
        case "cn": return "国区"
        case "us": return "美区"
        case "de": return "德区"
        default: return region
        }
    }
}

struct FreeApp: Codable, Identifiable, Hashable {
    let id: Int
    let app_id: String
    let name: String
    let cn_name: String?
    let us_name: String?
    let genre: String?
    let artist: String?
    let platform: String?
    let region: String?
    let artwork_url: String?
    let track_url: String?
    let old_price_text: String?
    let cn_old_price: Double?
    let us_old_price: Double?
    let cn_old_price_text: String?
    let us_old_price_text: String?
    let cn_rating: Double
    let cn_rating_count: Int
    let us_rating: Double
    let us_rating_count: Int
    let created_at: Int
    let free_days: Int?
    let description_zh: String?
    let description_us: String?
    let description: String?
    let regions: [RegionState]?

    // Identifiable：直接用快照里的 id（Int）
    var displayName: String {
        if let cn = cn_name, !cn.isEmpty { return cn }
        return name
    }

    var platformLabel: String {
        switch platform {
        case "macos": return "macOS"
        case "universal": return "通用"
        default: return "iOS"
        }
    }

    /// 仍在免费：任一区服 free=true；快照没给 regions 时按仍在免费算
    var isStillFree: Bool {
        guard let regions else { return true }
        return regions.contains { $0.free }
    }

    func isFree(in region: String) -> Bool {
        if let r = regions?.first(where: { $0.region == region }) { return r.free }
        return self.region == region
    }

    var freeRegions: [RegionState] {
        (regions ?? []).filter { $0.free }
    }

    /// 两区原价拼成一行，如 ¥38 · $4.99
    var oldPriceLine: String {
        var parts: [String] = []
        if let cn = cn_old_price_text, !cn.isEmpty { parts.append(cn) }
        if let us = us_old_price_text, !us.isEmpty, us != cn_old_price_text { parts.append(us) }
        if parts.isEmpty, let p = old_price_text { parts.append(p) }
        return parts.joined(separator: " · ")
    }

    /// 评分取两区里评价数更多的那个
    var bestRating: (value: Double, count: Int)? {
        let cn = (cn_rating, cn_rating_count)
        let us = (us_rating, us_rating_count)
        let pick = cn.1 >= us.1 ? cn : us
        guard pick.0 > 0 else { return nil }
        return pick
    }

    /// 原价越高分越高（约算成人民币），用于“原价最高”排序
    var valueScore: Double {
        (us_old_price ?? 0) * 7 + (cn_old_price ?? 0)
    }

    var createdDate: Date {
        Date(timeIntervalSince1970: TimeInterval(created_at))
    }

    var detailDescription: String? {
        if let zh = description_zh, !zh.isEmpty { return zh }
        if let d = description, !d.isEmpty { return d }
        if let us = description_us, !us.isEmpty { return us }
        return nil
    }
}

// MARK: - 数据层

@MainActor
final class DealStore: ObservableObject {
    static let snapshotURL = URL(string: "https://monitor-appstore.apprcn.com/api/v1/snapshot")!

    @Published var apps: [FreeApp] = []
    @Published var isLoading = false
    @Published var lastUpdated: Date?
    @Published var errorMessage: String?

    @Published var favorites: [FreeApp] = [] {
        didSet { saveFavorites() }
    }

    private let favoritesKey = "favoriteDeals"
    private var cacheURL: URL {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("snapshot.json")
    }

    init() {
        if let data = UserDefaults.standard.data(forKey: favoritesKey),
           let saved = try? JSONDecoder().decode([FreeApp].self, from: data) {
            favorites = saved
        }
    }

    private func saveFavorites() {
        if let data = try? JSONEncoder().encode(favorites) {
            UserDefaults.standard.set(data, forKey: favoritesKey)
        }
    }

    func isFavorite(_ app: FreeApp) -> Bool {
        favorites.contains { $0.app_id == app.app_id }
    }

    func toggleFavorite(_ app: FreeApp) {
        if let i = favorites.firstIndex(where: { $0.app_id == app.app_id }) {
            favorites.remove(at: i)
        } else {
            favorites.append(app)
        }
    }

    func refresh() async {
        isLoading = true
        defer { isLoading = false }
        do {
            let (data, _) = try await URLSession.shared.data(from: Self.snapshotURL)
            let snap = try JSONDecoder().decode(Snapshot.self, from: data)
            apply(snap, data: data, offline: false)
        } catch {
            // 联网失败：读上次缓存的快照顶上
            if let data = try? Data(contentsOf: cacheURL),
               let snap = try? JSONDecoder().decode(Snapshot.self, from: data) {
                apply(snap, data: nil, offline: true)
            } else {
                errorMessage = "加载失败，请检查网络后下拉重试"
            }
        }
    }

    private func apply(_ snap: Snapshot, data: Data?, offline: Bool) {
        apps = snap.alerts.filter { $0.isStillFree }
        lastUpdated = Date()
        errorMessage = offline ? "离线缓存 · 刚才更新失败" : nil
        if let data { try? data.write(to: cacheURL) }
    }
}

// MARK: - 筛选与排序

enum RegionFilter: String, CaseIterable {
    case all, cn, us
    var label: String {
        switch self {
        case .all: return "全部"
        case .cn: return "国区"
        case .us: return "美区"
        }
    }
}

enum SortOrder: String, CaseIterable {
    case value, rating, newest
    var label: String {
        switch self {
        case .value: return "原价最高"
        case .rating: return "评分最高"
        case .newest: return "最新上架"
        }
    }
}

// MARK: - 入口

@main
struct MyFirstAppApp: App {
    @StateObject private var store = DealStore()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(store)
        }
    }
}

struct ContentView: View {
    var body: some View {
        TabView {
            DealsListView()
                .tabItem {
                    Label("今日限免", systemImage: "tag.fill")
                }
            FavoritesView()
                .tabItem {
                    Label("收藏", systemImage: "star.fill")
                }
        }
    }
}

// MARK: - 今日限免列表

struct DealsListView: View {
    @EnvironmentObject private var store: DealStore
    @AppStorage("dealRegionFilter") private var regionRaw = RegionFilter.all.rawValue
    @AppStorage("dealSortOrder") private var sortRaw = SortOrder.value.rawValue
    @State private var searchText = ""

    private var regionFilter: RegionFilter {
        RegionFilter(rawValue: regionRaw) ?? .all
    }
    private var sortOrder: SortOrder {
        SortOrder(rawValue: sortRaw) ?? .value
    }

    private var filtered: [FreeApp] {
        var list = store.apps
        switch regionFilter {
        case .cn: list = list.filter { $0.isFree(in: "cn") }
        case .us: list = list.filter { $0.isFree(in: "us") }
        case .all: break
        }
        if !searchText.isEmpty {
            list = list.filter {
                $0.displayName.localizedCaseInsensitiveContains(searchText)
                || ($0.artist ?? "").localizedCaseInsensitiveContains(searchText)
            }
        }
        switch sortOrder {
        case .value: list.sort { $0.valueScore > $1.valueScore }
        case .rating: list.sort { ($0.bestRating?.value ?? 0) > ($1.bestRating?.value ?? 0) }
        case .newest: list.sort { $0.created_at > $1.created_at }
        }
        return list
    }

    var body: some View {
        NavigationStack {
            Group {
                if store.apps.isEmpty && !store.isLoading {
                    ContentUnavailableView {
                        Label("暂无限免", systemImage: "tag.slash")
                    } description: {
                        Text(store.errorMessage ?? "下拉刷新试试")
                    }
                } else {
                    List {
                        Section {
                            ForEach(filtered) { app in
                                NavigationLink(value: app) {
                                    DealRow(app: app)
                                }
                                .swipeActions(edge: .trailing) {
                                    Button {
                                        store.toggleFavorite(app)
                                    } label: {
                                        Label(
                                            store.isFavorite(app) ? "取消收藏" : "收藏",
                                            systemImage: store.isFavorite(app) ? "star.slash" : "star"
                                        )
                                    }
                                    .tint(.orange)
                                }
                            }
                        } footer: {
                            if let updated = store.lastUpdated {
                                Text("更新于 \(updated.formatted(date: .omitted, time: .shortened)) · 共 \(store.apps.count) 款仍免费")
                            }
                        }
                    }
                    .listStyle(.insetGrouped)
                    .refreshable { await store.refresh() }
                }
            }
            .navigationTitle("今日限免")
            .searchable(text: $searchText, prompt: "搜应用或开发者")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Picker("区服", selection: Binding(
                            get: { regionFilter },
                            set: { regionRaw = $0.rawValue }
                        )) {
                            ForEach(RegionFilter.allCases, id: \.self) { f in
                                Text(f.label).tag(f)
                            }
                        }
                        Picker("排序", selection: Binding(
                            get: { sortOrder },
                            set: { sortRaw = $0.rawValue }
                        )) {
                            ForEach(SortOrder.allCases, id: \.self) { s in
                                Text(s.label).tag(s)
                            }
                        }
                    } label: {
                        Label("筛选", systemImage: "line.3.horizontal.decrease.circle")
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        Task { await store.refresh() }
                    } label: {
                        Label("刷新", systemImage: "arrow.clockwise")
                    }
                    .disabled(store.isLoading)
                }
            }
            .navigationDestination(for: FreeApp.self) { app in
                DealDetailView(app: app)
            }
            .task {
                if store.apps.isEmpty { await store.refresh() }
            }
            .alert("提示", isPresented: Binding(
                get: { store.errorMessage != nil && store.apps.isEmpty },
                set: { if !$0 { store.errorMessage = nil } }
            )) {
                Button("好", role: .cancel) {}
            } message: {
                Text(store.errorMessage ?? "")
            }
        }
    }
}

// MARK: - 列表行

struct DealRow: View {
    let app: FreeApp

    var body: some View {
        HStack(spacing: 12) {
            AsyncImage(url: URL(string: app.artwork_url ?? "")) { image in
                image.resizable().scaledToFill()
            } placeholder: {
                RoundedRectangle(cornerRadius: 14)
                    .fill(.quaternary)
                    .overlay(Image(systemName: "app.fill").foregroundStyle(.secondary))
            }
            .frame(width: 60, height: 60)
            .clipShape(RoundedRectangle(cornerRadius: 14))

            VStack(alignment: .leading, spacing: 4) {
                Text(app.displayName)
                    .font(.headline)
                    .lineLimit(1)
                Text([app.genre, app.artist].compactMap { $0 }.joined(separator: " · "))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                HStack(spacing: 6) {
                    Text(app.oldPriceLine)
                        .font(.subheadline)
                        .strikethrough()
                        .foregroundStyle(.secondary)
                    Text("免费")
                        .font(.caption)
                        .fontWeight(.semibold)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(.green)
                        .foregroundStyle(.white)
                        .clipShape(Capsule())
                    if let rating = app.bestRating {
                        Label(String(format: "%.1f", rating.value), systemImage: "star.fill")
                            .font(.caption)
                            .foregroundStyle(.orange)
                    }
                }
                HStack(spacing: 4) {
                    Text(app.platformLabel)
                        .font(.caption2)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1)
                        .background(.quaternary)
                        .clipShape(Capsule())
                    ForEach(app.freeRegions, id: \.region) { r in
                        Text(r.label)
                            .font(.caption2)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1)
                            .background(.quaternary)
                            .clipShape(Capsule())
                    }
                }
            }
        }
        .padding(.vertical, 4)
    }
}

// MARK: - 详情页

struct DealDetailView: View {
    @EnvironmentObject private var store: DealStore
    let app: FreeApp

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack(spacing: 16) {
                    AsyncImage(url: URL(string: app.artwork_url ?? "")) { image in
                        image.resizable().scaledToFill()
                    } placeholder: {
                        RoundedRectangle(cornerRadius: 24)
                            .fill(.quaternary)
                    }
                    .frame(width: 96, height: 96)
                    .clipShape(RoundedRectangle(cornerRadius: 22))

                    VStack(alignment: .leading, spacing: 6) {
                        Text(app.displayName)
                            .font(.title3)
                            .fontWeight(.bold)
                        Text(app.artist ?? "")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        Text([app.genre, app.platformLabel].compactMap { $0 }.joined(separator: " · "))
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }

                HStack(spacing: 12) {
                    if let rating = app.bestRating {
                        VStack {
                            Text(String(format: "%.1f", rating.value))
                                .font(.title2)
                                .fontWeight(.bold)
                            Text("\(rating.count) 个评分")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Divider()
                    }
                    VStack {
                        Text(app.oldPriceLine)
                            .font(.title2)
                            .fontWeight(.bold)
                            .strikethrough()
                        Text("原价")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Divider()
                    VStack {
                        Text("免费")
                            .font(.title2)
                            .fontWeight(.bold)
                            .foregroundStyle(.green)
                        Text("限时")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    if let days = app.free_days {
                        Divider()
                        VStack {
                            Text("\(days) 天")
                                .font(.title2)
                                .fontWeight(.bold)
                            Text("已免费")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .frame(maxWidth: .infinity)

                if let track = app.track_url, let url = URL(string: track) {
                    Link(destination: url) {
                        Label("在 App Store 中打开", systemImage: "arrow.up.forward.app")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.orange)
                }

                HStack {
                    Button {
                        store.toggleFavorite(app)
                    } label: {
                        Label(
                            store.isFavorite(app) ? "已收藏" : "收藏",
                            systemImage: store.isFavorite(app) ? "star.fill" : "star"
                        )
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    if let track = app.track_url, let url = URL(string: track) {
                        ShareLink(item: url) {
                            Label("分享", systemImage: "square.and.arrow.up")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                    }
                }

                if let desc = app.detailDescription {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("简介")
                            .font(.headline)
                        Text(desc)
                            .font(.body)
                            .foregroundStyle(.secondary)
                    }
                }

                Text("数据来自反斗限免 · 限免随时结束，看到喜欢的先领")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            .padding()
        }
        .navigationTitle(app.displayName)
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - 收藏页

struct FavoritesView: View {
    @EnvironmentObject private var store: DealStore

    var body: some View {
        NavigationStack {
            Group {
                if store.favorites.isEmpty {
                    ContentUnavailableView {
                        Label("还没有收藏", systemImage: "star")
                    } description: {
                        Text("在今日限免里左滑一首应用就能收藏")
                    }
                } else {
                    List {
                        ForEach(store.favorites) { app in
                            NavigationLink(value: app) {
                                DealRow(app: app)
                            }
                            .swipeActions(edge: .trailing) {
                                Button(role: .destructive) {
                                    store.toggleFavorite(app)
                                } label: {
                                    Label("取消收藏", systemImage: "star.slash")
                                }
                            }
                        }
                    }
                    .listStyle(.insetGrouped)
                }
            }
            .navigationTitle("收藏")
            .navigationDestination(for: FreeApp.self) { app in
                DealDetailView(app: app)
            }
        }
    }
}
