import SwiftUI

struct MoreView: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        NavigationStack {
            List {
                Section("Data") {
                    LabeledContent("Matches", value: app.data.matches.formatted())
                    LabeledContent("Covers", value: "\(app.data.days) days to \(app.data.updated.formatted(date: .abbreviated, time: .shortened))")
                    if let c = app.lastChecked {
                        LabeledContent("Last checked", value: c.formatted(.relative(presentation: .named)))
                    }
                    Button {
                        Task { await app.refresh() }
                    } label: {
                        HStack {
                            Text("Check for new data")
                            Spacer()
                            switch app.refreshState {
                            case .checking: ProgressView()
                            case .updated: Text("Updated").foregroundStyle(Theme.ally)
                            case .upToDate: Text("Up to date").foregroundStyle(Theme.muted)
                            case .failed(let m): Text(m).font(.caption).foregroundStyle(Theme.enemy).multilineTextAlignment(.trailing)
                            case .idle: EmptyView()
                            }
                        }
                    }
                    .disabled(app.refreshState == .checking)
                }
                .listRowBackground(Theme.panel)

                Section {
                    NavigationLink { PoolView() } label: {
                        LabeledContent("My hero pool", value: app.pool.isEmpty ? "Not set" : "\(app.pool.count) heroes")
                    }
                    NavigationLink { HiddenView() } label: {
                        LabeledContent("Hidden heroes", value: app.hidden.isEmpty ? "None" : "\(app.hidden.count)")
                    }
                } header: { Text("Your heroes") } footer: {
                    Text("Turn on “Only my hero pool” on the Draft tab to get suggestions from heroes you actually play.")
                }
                .listRowBackground(Theme.panel)

                Section("About") {
                    NavigationLink("How the scores work") { HowItWorksView() }
                    Link("Privacy Policy", destination: URL(string: "https://dota-last-pick.vercel.app/privacy")!)
                    Link("Support & feedback", destination: URL(string: "https://dota-last-pick.vercel.app/support")!)
                    Link("Last Pick on the web", destination: URL(string: "https://dota-last-pick.vercel.app")!)
                    LabeledContent("Version", value: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0")
                }
                .listRowBackground(Theme.panel)
                .tint(Theme.gold)

                Section {
                    Text("Match data from OpenDota (opendota.com). Dota 2 and hero images are trademarks and property of Valve Corporation. Last Pick is an independent fan-made tool and is not affiliated with or endorsed by Valve.")
                        .font(.caption).foregroundStyle(Theme.muted)
                }
                .listRowBackground(Color.clear)
            }
            .scrollContentBackground(.hidden)
            .background(AppBackground())
            .navigationTitle("More")
        }
    }
}

struct PoolView: View {
    @Environment(AppModel.self) private var app
    @State private var query = ""

    var body: some View {
        let heroes = searchHeroes(app.data.heroes, query)
        List {
            Section {
                ForEach(heroes) { h in
                    let on = app.pool.contains(h.id)
                    Button {
                        if on { app.pool.remove(h.id) } else { app.pool.insert(h.id) }
                        Haptics.light()
                    } label: {
                        HStack(spacing: 10) {
                            Portrait(hero: h, height: 26)
                            Text(h.name).foregroundStyle(Theme.text)
                            Spacer()
                            Image(systemName: on ? "star.fill" : "star").foregroundStyle(on ? Theme.gold : Theme.muted)
                        }
                    }
                    .accessibilityAddTraits(on ? .isSelected : [])
                }
            } footer: {
                Text("Star the heroes you're comfortable on. Leave it empty to get suggestions from every hero.")
            }
            .listRowBackground(Theme.panel)
        }
        .scrollContentBackground(.hidden)
        .background(AppBackground())
        .navigationTitle("My hero pool")
        .searchable(text: $query, prompt: "Search heroes")
        .autocorrectionDisabled()
        .textInputAutocapitalization(.never)
        .toolbar {
            if !app.pool.isEmpty { Button("Clear") { app.pool = []; app.onlyPool = false }.tint(Theme.enemy) }
        }
    }
}

struct HiddenView: View {
    @Environment(AppModel.self) private var app
    var body: some View {
        List {
            Section {
                if app.hidden.isEmpty {
                    Text("Nothing hidden. Tap a suggestion, then Hide, to keep a hero out of your results.").foregroundStyle(Theme.muted)
                }
                ForEach(app.data.heroes.filter { app.hidden.contains($0.id) }) { h in
                    HStack(spacing: 10) {
                        Portrait(hero: h, height: 26)
                        Text(h.name).foregroundStyle(Theme.text)
                        Spacer()
                        Button("Show") { app.hidden.remove(h.id) }.tint(Theme.gold)
                    }
                }
            }
            .listRowBackground(Theme.panel)
        }
        .scrollContentBackground(.hidden)
        .background(AppBackground())
        .navigationTitle("Hidden heroes")
    }
}

struct HowItWorksView: View {
    @Environment(AppModel.self) private var app
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                block("Where the numbers come from",
                      "Every day the app downloads fresh statistics built from about \(app.data.matches.formatted()) ranked public matches from the last \(app.data.days) days (All Pick, Captains Mode and similar modes — no Turbo), split into three rank brackets. The data comes from OpenDota's public match database. A snapshot ships inside the app, so everything works offline.")
                block("Best last pick",
                      "Each candidate gets a draft score in win-rate points:\n• its overall win-rate edge in your bracket\n• + its matchup advantage against each enemy hero — how much better it does against that hero than both heroes' win rates predict\n• + 0.6 × its synergy with each ally\n• + a small bonus (max 1.5) if it fills a role your team lacks, once three allies are in.\nPairs with few games are pulled toward zero, so a lucky 10-game streak can't top the list.")
                block("They might pick next",
                      "For the enemy's next pick, every available hero is scored from their side — how well it fits their heroes against yours — and combined with how often that hero is picked in your bracket. The percentages are each hero's share of the chance across all heroes still available.")
                block("Ban suggestions",
                      "Heroes that would counter the heroes already on your team hardest: their own win-rate edge plus their matchups against your picks, nudged toward heroes people actually play in your bracket. Before anyone has picked, that's simply the strongest popular heroes. They only show while the enemy still has picks left.")
                block("Meta tiers",
                      "Heroes ranked by win rate in the chosen bracket and position. Heroes in under 0.5% of matches don't get a tier. Tiers are by rank: S top 10%, A next 20%, B middle 40%, C next 20%, D bottom 10%.")
                block("What it can't know",
                      "Matchups are added up as if they were independent, and the stats don't know your skill on a hero, lanes, or item builds. Use it as a strong second opinion, not a guarantee.")
            }
            .padding(16)
        }
        .background(AppBackground())
        .navigationTitle("How it works")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func block(_ title: String, _ body: String) -> some View {
        Panel {
            Text(title).font(.headline).foregroundStyle(Theme.gold)
            Text(body).font(.subheadline).foregroundStyle(Theme.text).fixedSize(horizontal: false, vertical: true)
        }
    }
}
