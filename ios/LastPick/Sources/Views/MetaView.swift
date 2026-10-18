import SwiftUI

/// Best heroes right now: win rate and pick rate per rank bracket and position, with S–D tiers.
struct MetaView: View {
    @Environment(AppModel.self) private var app
    @State private var position = 0
    @State private var bracket: Bracket = .all
    @State private var sort: Sort = .winRate
    @State private var didSeed = false

    enum Sort: String, CaseIterable, Identifiable { case winRate = "Win rate", pickRate = "Pick rate"; var id: String { rawValue } }

    var body: some View {
        let e = app.engine(bracket)
        var rows = e.meta(position: position)
        if sort == .pickRate { rows.sort { $0.pickRate > $1.pickRate } }

        return NavigationStack {
            List {
                Section {
                    Picker("Position", selection: $position) {
                        Text("Any").tag(0)
                        ForEach(1...5, id: \.self) { Text("\($0)").tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets(top: 4, leading: 0, bottom: 4, trailing: 0))
                    HStack {
                        Picker("Rank", selection: $bracket) {
                            ForEach(Bracket.allCases) { Text(app.data.bracketName($0)).tag($0) }
                        }
                        .tint(Theme.gold)
                        Spacer()
                        Picker("Sort", selection: $sort) {
                            ForEach(Sort.allCases) { Text($0.rawValue).tag($0) }
                        }
                        .tint(Theme.gold)
                    }
                    .labelsHidden()
                    .listRowBackground(Theme.panel)
                } footer: {
                    Text(position == 0 ? "All heroes" : "Heroes usually played at position \(position) (\(POS_LABEL[position]))")
                        + Text(" · \(Int(e.totalMatches).formatted()) matches")
                }

                Section {
                    ForEach(Array(rows.enumerated()), id: \.element.id) { i, r in
                        NavigationLink(value: r.hero.id) { MetaRowView(rank: i + 1, row: r) }
                            .listRowBackground(Theme.panel)
                    }
                } footer: {
                    Text("Tiers rank heroes by win rate among those in at least 0.5% of matches: S top 10%, A next 20%, B middle 40%, C next 20%, D bottom 10%. Win rate isn't everything — a hero can be strong but hard to play.")
                }
            }
            .scrollContentBackground(.hidden)
            .background(AppBackground())
            .navigationTitle("Meta")
            .navigationDestination(for: Int.self) { HeroDetailView(heroId: $0) }
        }
        .onAppear {
            // Start on the user's own rank and role from the draft screen, once.
            if !didSeed { bracket = app.state.bracket; position = app.state.position; didSeed = true }
        }
    }
}

struct MetaRowView: View {
    let rank: Int
    let row: MetaRow

    var body: some View {
        HStack(spacing: 10) {
            Text("\(rank)").font(.caption.monospacedDigit()).foregroundStyle(Theme.muted).frame(width: 24, alignment: .trailing)
            TierBadge(tier: row.tier)
            Portrait(hero: row.hero, height: 26)
            VStack(alignment: .leading, spacing: 2) {
                Text(row.hero.name).font(.subheadline.weight(.semibold)).foregroundStyle(Theme.text).lineLimit(1).minimumScaleFactor(0.75)
                PositionBadges(heroId: row.hero.id)
            }
            Spacer(minLength: 4)
            VStack(alignment: .trailing, spacing: 1) {
                Text(Theme.pct(row.winRate)).font(.subheadline.weight(.bold)).monospacedDigit()
                    .foregroundStyle(row.winRate >= 0.5 ? Theme.ally : Theme.enemy)
                Text("\(Theme.pct(row.pickRate)) picked").font(.caption2).monospacedDigit().foregroundStyle(Theme.muted)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

struct TierBadge: View {
    let tier: String
    var color: Color {
        switch tier {
        case "S": Theme.gold
        case "A": Theme.ally
        case "B": Color(hex: 0x48A6E8)
        case "C": Theme.muted
        case "D": Theme.enemy
        default: Theme.muted.opacity(0.5)
        }
    }
    var body: some View {
        Text(tier).font(.system(size: 12, weight: .heavy, design: .serif))
            .frame(width: 22, height: 22)
            .foregroundStyle(color)
            .background(color.opacity(0.15), in: RoundedRectangle(cornerRadius: 5))
            .accessibilityLabel(tier == "–" ? "Not enough games for a tier" : "Tier \(tier)")
    }
}
