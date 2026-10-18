import SwiftUI

/// One last-pick suggestion: why it's good (best matchups), the draft score, and on tap the full breakdown.
struct PickCard: View {
    @Environment(AppModel.self) private var app
    let pick: Pick
    let rank: Int?
    let expanded: Bool
    let showActions: Bool
    let toggle: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Button(action: toggle) { summary }.buttonStyle(.plain)
            if expanded {
                breakdown
                if showActions { actions }
            }
        }
    }

    private var summary: some View {
        HStack(alignment: .center, spacing: 10) {
            if let rank {
                Text("\(rank)").font(.system(.subheadline, design: .serif).weight(.heavy))
                    .foregroundStyle(rank <= 3 ? Theme.gold : Theme.muted).frame(width: 18)
            }
            Portrait(hero: pick.hero, height: 38)
            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 6) {
                    Text(pick.hero.name).font(.subheadline.weight(.semibold)).foregroundStyle(Theme.text).lineLimit(1)
                    if app.pool.contains(pick.hero.id) {
                        Image(systemName: "star.fill").font(.system(size: 9)).foregroundStyle(Theme.gold).accessibilityLabel("In your pool")
                    }
                    PositionBadges(heroId: pick.hero.id)
                    if pick.lowData {
                        Text("low data").font(.system(size: 9, weight: .semibold)).foregroundStyle(Theme.gold)
                            .padding(.horizontal, 4).padding(.vertical, 1).background(Theme.gold.opacity(0.14), in: Capsule())
                    }
                }
                reasons
            }
            Spacer(minLength: 4)
            VStack(alignment: .trailing, spacing: 0) {
                Text(Theme.signed(pick.total)).font(.headline).monospacedDigit()
                    .foregroundStyle(pick.total >= 0 ? Theme.ally : Theme.enemy)
                Text("score").font(.caption2).foregroundStyle(Theme.muted)
            }
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityHint(expanded ? "Hides the breakdown" : "Shows why")
    }

    @ViewBuilder private var reasons: some View {
        let sorted = pick.vs.sorted { $0.value > $1.value }
        let good = sorted.filter { $0.value >= 0.8 }.prefix(3)
        let bad = sorted.filter { $0.value <= -0.8 }.reversed().prefix(2)
        if good.isEmpty && bad.isEmpty && pick.synergy < 0.8 && pick.roleNotes.isEmpty {
            Text(pick.vs.isEmpty ? "Win rate \(Theme.pct(app.engine().winRate(pick.hero.id)))" : "No standout matchups — pick on comfort.")
                .font(.caption2).foregroundStyle(Theme.muted)
        } else {
            FlowLayout(spacing: 4) {
                ForEach(Array(good)) { l in ValueChip(hero: app.hero(l.hero), text: Theme.signed(l.value), tint: Theme.ally) }
                ForEach(Array(bad)) { l in ValueChip(hero: app.hero(l.hero), text: Theme.signed(l.value), tint: Theme.enemy) }
                if pick.synergy >= 0.8 { NoteChip(text: "synergy \(Theme.signed(pick.synergy))") }
                ForEach(pick.roleNotes, id: \.self) { NoteChip(text: $0) }
            }
        }
    }

    private var breakdown: some View {
        let e = app.engine()
        let maxV = max(4, (pick.vs.map { abs($0.value) } + pick.with.map { abs($0.value * Engine.synergyWeight) } + [abs(pick.base)]).max() ?? 4)
        return VStack(spacing: 7) {
            row("Hero win rate (\(Theme.pct(e.winRate(pick.hero.id))))", nil, pick.base, maxV)
            ForEach(pick.vs) { l in row("vs \(app.hero(l.hero)?.name ?? "?")", "\(l.games.formatted()) games", l.value, maxV) }
            ForEach(pick.with) { l in row("with \(app.hero(l.hero)?.name ?? "?")", "×0.6 · \(l.games.formatted()) games", l.value * Engine.synergyWeight, maxV) }
            if pick.roles > 0 { row("Fills a missing role", nil, pick.roles, maxV) }
        }
        .padding(10)
        .background(Color.black.opacity(0.25), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private func row(_ label: String, _ sub: String?, _ v: Double, _ maxV: Double) -> some View {
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 0) {
                Text(label).font(.caption).foregroundStyle(Theme.text).lineLimit(1)
                if let sub { Text(sub).font(.system(size: 9)).foregroundStyle(Theme.muted) }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            DivergingBar(value: v, max: maxV).frame(width: 80)
            Text(Theme.signed(v)).font(.caption.weight(.semibold)).monospacedDigit().frame(width: 40, alignment: .trailing)
                .foregroundStyle(v >= 0 ? Theme.ally : Theme.enemy)
        }
        .accessibilityElement(children: .combine)
    }

    private var actions: some View {
        let id = pick.hero.id
        let inPool = app.pool.contains(id)
        return HStack(spacing: 8) {
            Button {
                app.state.you = id
                Haptics.success()
            } label: { Label("Lock in", systemImage: "lock.fill") }
                .buttonStyle(.borderedProminent).tint(Theme.gold).foregroundStyle(Theme.bg)
            Button {
                if inPool { app.pool.remove(id) } else { app.pool.insert(id) }
                Haptics.light()
            } label: { Label(inPool ? "In pool" : "Pool", systemImage: inPool ? "star.fill" : "star") }
                .buttonStyle(.bordered).tint(Theme.gold)
            Button {
                app.hidden.insert(id)
                Haptics.light()
            } label: { Label("Hide", systemImage: "eye.slash") }
                .buttonStyle(.bordered).tint(Theme.muted)
            Spacer(minLength: 0)
            NavigationLink(value: id) { Image(systemName: "info.circle").font(.title3) }
                .tint(Theme.gold).accessibilityLabel("\(pick.hero.name) matchups")
        }
        .font(.caption.weight(.semibold))
        .controlSize(.small)
        .labelStyle(.titleAndIcon)
    }
}
