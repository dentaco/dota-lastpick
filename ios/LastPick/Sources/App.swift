import SwiftUI

@main
struct LastPickApp: App {
    @State private var app = AppModel()
    @Environment(\.scenePhase) private var phase

    init() {
        let tab = UITabBarAppearance()
        tab.configureWithDefaultBackground()
        tab.backgroundColor = UIColor(Theme.bg).withAlphaComponent(0.85)
        UITabBar.appearance().standardAppearance = tab
        UITabBar.appearance().scrollEdgeAppearance = tab
        let nav = UINavigationBarAppearance()
        nav.configureWithTransparentBackground()
        nav.titleTextAttributes = [.foregroundColor: UIColor(Theme.text)]
        nav.largeTitleTextAttributes = [.foregroundColor: UIColor(Theme.text)]
        UINavigationBar.appearance().standardAppearance = nav
        UINavigationBar.appearance().scrollEdgeAppearance = nav
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(app)
                .preferredColorScheme(.dark)
                .tint(Theme.gold)
                .task { await app.refreshIfStale() }
                .onChange(of: phase) { _, p in
                    if p == .active { Task { await app.refreshIfStale() } }
                }
        }
    }
}

struct RootView: View {
    @State private var tab = ProcessInfo.processInfo.environment["LASTPICK_TAB"].flatMap(Int.init) ?? 0

    var body: some View {
        TabView(selection: $tab) {
            DraftView().tabItem { Label("Draft", systemImage: "square.grid.3x2.fill") }.tag(0)
            MetaView().tabItem { Label("Meta", systemImage: "chart.bar.fill") }.tag(1)
            HeroesView().tabItem { Label("Heroes", systemImage: "person.3.fill") }.tag(2)
            MoreView().tabItem { Label("More", systemImage: "ellipsis.circle.fill") }.tag(3)
        }
    }
}
