import SwiftUI

/// Look up any hero: who counters it, who it beats, who it plays best with.
struct HeroesView: View {
    @Environment(AppModel.self) private var app
    @State private var query = ""
    @State private var attr: String?

    var body: some View {
        let heroes = searchHeroes(app.data.heroes, query, attr: attr)

        NavigationStack {
            ScrollView {
                HStack(spacing: 6) {
                    ForEach(["str", "agi", "int", "all"], id: \.self) { a in
                        let on = attr == a
                        Button { attr = on ? nil : a } label: {
                            Text(Theme.attrName[a]!).font(.caption.weight(.semibold))
                                .padding(.horizontal, 10).padding(.vertical, 5)
                                .foregroundStyle(on ? Theme.bg : Theme.attr(a))
                                .background(on ? Theme.attr(a) : Theme.attr(a).opacity(0.12), in: Capsule())
                        }
                        .buttonStyle(.plain)
                        .accessibilityAddTraits(on ? .isSelected : [])
                    }
                    Spacer()
                }
                .padding(.horizontal, 16)
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 100), spacing: 10)], spacing: 12) {
                    ForEach(heroes) { h in
                        NavigationLink(value: h.id) {
                            VStack(spacing: 5) {
                                GeometryReader { g in Portrait(hero: h, height: g.size.width * 9 / 16) }
                                    .aspectRatio(16 / 9, contentMode: .fit)
                                    .overlay(alignment: .topTrailing) {
                                        if app.pool.contains(h.id) {
                                            Image(systemName: "star.fill").font(.system(size: 10)).foregroundStyle(Theme.gold)
                                                .padding(4).background(.black.opacity(0.5), in: Circle()).padding(3)
                                        }
                                    }
                                Text(h.name).font(.caption.weight(.medium)).foregroundStyle(Theme.text).lineLimit(1).minimumScaleFactor(0.8)
                            }
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(h.name)
                    }
                }
                .padding(16)
                if heroes.isEmpty {
                    Text("No hero matches “\(query)”").foregroundStyle(Theme.muted)
                }
            }
            .background(AppBackground())
            .navigationTitle("Heroes")
            .searchable(text: $query, prompt: "Search heroes (pa, sf, am…)")
            .autocorrectionDisabled()
            .textInputAutocapitalization(.never)
            .navigationDestination(for: Int.self) { HeroDetailView(heroId: $0) }
        }
    }
}

struct HeroDetailView: View {
    @Environment(AppModel.self) private var app
    let heroId: Int
    @State private var bracket: Bracket?

    var body: some View {
        if let h = app.hero(heroId) {
            let br = bracket ?? app.state.bracket
            let e = app.engine(br)
            ScrollView {
                VStack(spacing: 14) {
                    header(h, e)
                    Picker("Rank", selection: Binding(get: { br }, set: { bracket = $0 })) {
                        ForEach(Bracket.allCases) { Text(app.data.bracketName($0)).tag($0) }
                    }
                    .pickerStyle(.menu).tint(Theme.gold)
                    .frame(maxWidth: .infinity, alignment: .trailing)
                    lines("Countered by", "heroes that win vs \(h.name)", icon: "shield.lefthalf.filled.slash", tint: Theme.enemy,
                          e.counters(of: heroId), positiveTint: Theme.enemy)
                    lines("Good against", "\(h.name) wins vs these", icon: "bolt.fill", tint: Theme.ally,
                          e.goodAgainst(heroId), positiveTint: Theme.ally)
                    lines("Best teammates", "extra win rate together", icon: "person.2.fill", tint: Theme.gold,
                          e.bestWith(heroId), positiveTint: Theme.gold)
                    Text("Advantage = win rate in that matchup beyond what both heroes' overall win rates predict, shrunk toward zero when there are few games.")
                        .font(.caption2).foregroundStyle(Theme.muted)
                }
                .padding(16)
            }
            .background(AppBackground())
            .navigationTitle(h.name)
            .navigationBarTitleDisplayMode(.inline)
        } else {
            ContentUnavailableView("Hero not found", systemImage: "questionmark")
        }
    }

    private func header(_ h: Hero, _ e: Engine) -> some View {
        let inPool = app.pool.contains(h.id)
        return Panel {
            HStack(spacing: 12) {
                Portrait(hero: h, height: 64)
                VStack(alignment: .leading, spacing: 4) {
                    Text(h.name).font(.system(.title3, design: .serif).weight(.heavy)).foregroundStyle(Theme.text)
                    Text("\(Theme.attrName[h.attr] ?? "") · \(h.melee ? "Melee" : "Ranged")")
                        .font(.caption).foregroundStyle(Theme.attr(h.attr))
                    PositionBadges(heroId: h.id)
                }
            }
            HStack {
                stat("Win rate", Theme.pct(e.winRate(h.id)), e.winRate(h.id) >= 0.5 ? Theme.ally : Theme.enemy)
                stat("Pick rate", Theme.pct(e.pickRate(h.id)), Theme.text)
                stat("Games", e.games(h.id).formatted(.number.notation(.compactName)), Theme.text)
            }
            if !h.roles.isEmpty {
                Text(h.roles.joined(separator: " · ")).font(.caption.weight(.medium)).foregroundStyle(Theme.gold)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Button {
                if inPool { app.pool.remove(h.id) } else { app.pool.insert(h.id) }
                Haptics.light()
            } label: {
                Label(inPool ? "In my hero pool" : "Add to my hero pool", systemImage: inPool ? "star.fill" : "star")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered).tint(Theme.gold)
        }
    }

    private func stat(_ label: String, _ value: String, _ color: Color) -> some View {
        VStack(spacing: 2) {
            Text(value).font(.headline).monospacedDigit().foregroundStyle(color)
            Text(label).font(.caption2).foregroundStyle(Theme.muted)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
    }

    private func lines(_ title: String, _ sub: String, icon: String, tint: Color, _ ls: [Line], positiveTint: Color) -> some View {
        Panel {
            SectionTitle(title: title, subtitle: sub, icon: icon, tint: tint)
            ForEach(ls) { l in
                if let other = app.hero(l.hero) {
                    NavigationLink(value: other.id) {
                        HStack(spacing: 10) {
                            Portrait(hero: other, height: 28)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(other.name).font(.subheadline.weight(.medium)).foregroundStyle(Theme.text)
                                Text("\(l.games.formatted()) games").font(.caption2).foregroundStyle(Theme.muted)
                            }
                            Spacer()
                            Text(Theme.signed(l.value)).font(.subheadline.weight(.bold)).monospacedDigit()
                                .foregroundStyle(l.value >= 0 ? positiveTint : Theme.muted)
                            Image(systemName: "chevron.right").font(.caption2.weight(.bold)).foregroundStyle(Theme.muted.opacity(0.6))
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityElement(children: .combine)
                }
            }
        }
    }
}
