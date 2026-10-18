import SwiftUI

struct PickerRequest: Identifiable {
    let id = UUID()
    let slot: Slot
}

struct DraftView: View {
    @Environment(AppModel.self) private var app
    @State private var picker: PickerRequest?
    @State private var expanded: Set<Int> = []
    @State private var showBans = false
    @State private var showAvoid = false
    @State private var confirmReset = false

    var body: some View {
        let engine = app.engine()
        let s = app.state
        let draft = s.draft
        let filter = app.suggestionFilter
        let ranked = engine.rank(draft, position: s.position, exclude: filter.exclude, only: filter.only)

        NavigationStack {
            ScrollViewReader { proxy in
            ScrollView {
                VStack(spacing: 14) {
                    header
                    board(s)
                    controls(s)
                    if let you = s.you, app.hero(you) != nil { yourPick(engine.score(you, draft)) }
                    bestPicks(ranked, draft: draft, engine: engine).id("best")
                    if draft.enemies.count < 5 {
                        predictions(engine.predictEnemy(s.teamDraft), draft: s.teamDraft).id("predictions")
                        bans(engine.banThreats(s.teamDraft), draft: s.teamDraft).id("bans")
                    }
                    avoid(Array(ranked.suffix(5).reversed()))
                    DataFooter()
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 28)
            }
            #if DEBUG
            .onAppear { debugHooks(ranked, proxy) }
            #endif
            .scrollDismissesKeyboard(.interactively)
            .safeAreaInset(edge: .top, spacing: 0) { Color.clear.frame(height: 0).background(Theme.bg.opacity(0.94)) }
            .background(AppBackground())
            .toolbar(.hidden, for: .navigationBar)
            }
            .navigationDestination(for: Int.self) { HeroDetailView(heroId: $0) }
        }
        .sheet(item: $picker) { req in
            HeroPickerSheet(start: req.slot, query: debugQuery)
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
        }
        .confirmationDialog("Clear the whole draft?", isPresented: $confirmReset, titleVisibility: .visible) {
            Button("Clear draft", role: .destructive) { app.resetDraft(); expanded = []; Haptics.light() }
        }
    }

    #if DEBUG
    private var debugQuery: String { ProcessInfo.processInfo.environment["LASTPICK_DEMO_QUERY"] ?? "" }
    /// Simulator screenshots: LASTPICK_DEMO_EXPAND=1, LASTPICK_DEMO_SCROLL=<section id>, LASTPICK_DEMO_QUERY=<text> opens the picker.
    private func debugHooks(_ ranked: [Pick], _ proxy: ScrollViewProxy) {
        let env = ProcessInfo.processInfo.environment
        if env["LASTPICK_DEMO_EXPAND"] != nil, let top = ranked.first { expanded.insert(top.id) }
        if let id = env["LASTPICK_DEMO_SCROLL"] {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { proxy.scrollTo(id, anchor: .top) }
        }
        if env["LASTPICK_DEMO_QUERY"] != nil, let slot = app.state.nextEmpty(after: Slot(team: .ally, index: 0)) {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { picker = PickerRequest(slot: slot) }
        }
    }
    #else
    private var debugQuery: String { "" }
    #endif

    // MARK: Header

    private var header: some View {
        HStack(spacing: 10) {
            Image("Mark").resizable().frame(width: 34, height: 34).accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 1) {
                Text("Last Pick").font(.system(.title2, design: .serif).weight(.heavy)).foregroundStyle(Theme.text)
                Text("Counter their draft. Pick the hero that wins.").font(.caption).foregroundStyle(Theme.muted)
            }
            Spacer()
            if !app.state.isEmpty {
                ShareLink(item: shareURL, message: Text("My Dota 2 draft — best last picks")) {
                    Image(systemName: "square.and.arrow.up").font(.body.weight(.semibold))
                }
                .accessibilityLabel("Share draft")
                Button { confirmReset = true } label: {
                    Image(systemName: "arrow.counterclockwise").font(.body.weight(.semibold))
                }
                .accessibilityLabel("Clear draft")
            }
        }
        .foregroundStyle(Theme.gold)
        .padding(.top, 8)
    }

    private var shareURL: URL {
        let s = app.state
        let ids = { (a: [Int?]) in a.compactMap { $0 }.map(String.init).joined(separator: ".") }
        var parts: [String] = []
        if !ids(s.ally).isEmpty { parts.append("a=" + ids(s.ally)) }
        if !ids(s.enemy).isEmpty { parts.append("e=" + ids(s.enemy)) }
        if !ids(Array(s.ban.prefix(10))).isEmpty { parts.append("b=" + ids(Array(s.ban.prefix(10)))) }
        if let y = s.you { parts.append("y=\(y)") }
        if s.position > 0 { parts.append("p=\(s.position)") }
        if s.bracket != .all { parts.append("r=\(s.bracket.rawValue)") }
        return URL(string: "https://dota-last-pick.vercel.app/" + (parts.isEmpty ? "" : "#" + parts.joined(separator: "&")))!
    }

    // MARK: Board

    private func board(_ s: DraftState) -> some View {
        Panel {
            teamRow("Your team", tint: Theme.ally, team: .ally, s: s, you: true)
            HStack {
                Rectangle().fill(Theme.line).frame(height: 1)
                Text("VS").font(.system(.caption, design: .serif).weight(.heavy)).foregroundStyle(Theme.muted)
                Rectangle().fill(Theme.line).frame(height: 1)
            }
            teamRow("Enemy team", tint: Theme.enemy, team: .enemy, s: s, you: false)
            DisclosureGroup(isExpanded: $showBans) {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 7), spacing: 6) {
                    ForEach(0..<DraftState.size[.ban]!, id: \.self) { i in
                        SlotView(heroId: s.ban[i], tint: Theme.ban, label: "Ban slot \(i + 1)", strike: true) {
                            picker = PickerRequest(slot: Slot(team: .ban, index: i))
                        }
                    }
                }
                .padding(.top, 8)
            } label: {
                let n = s.ban.compactMap { $0 }.count
                Text(n > 0 ? "Bans (\(n))" : "Bans").font(.subheadline.weight(.semibold)).foregroundStyle(Theme.muted)
            }
            .tint(Theme.muted)
        }
    }

    private func teamRow(_ title: String, tint: Color, team: Team, s: DraftState, you: Bool) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Circle().fill(tint).frame(width: 7, height: 7)
                Text(title.uppercased()).font(.caption.weight(.bold)).tracking(1.2).foregroundStyle(tint)
                Spacer()
                let n = s.list(team).compactMap { $0 }.count
                Text("\(n)/\(DraftState.size[team]!)").font(.caption2).foregroundStyle(Theme.muted).monospacedDigit()
            }
            HStack(spacing: 6) {
                ForEach(0..<DraftState.size[team]!, id: \.self) { i in
                    SlotView(heroId: s.list(team)[i], tint: tint, label: "\(title) slot \(i + 1)") {
                        picker = PickerRequest(slot: Slot(team: team, index: i))
                    }
                }
                if you {
                    YouSlot(heroId: s.you) { app.state.you = nil; Haptics.light() }
                }
            }
        }
    }

    // MARK: Controls

    private func controls(_ s: DraftState) -> some View {
        @Bindable var app = app
        return Panel {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("I'm playing").font(.subheadline.weight(.semibold)).foregroundStyle(Theme.text)
                    Spacer()
                    Text(s.position == 0 ? "Any position" : "Position \(s.position) · \(POS_LABEL[s.position])")
                        .font(.caption).foregroundStyle(Theme.muted)
                }
                Picker("Position", selection: $app.state.position) {
                    Text("Any").tag(0)
                    ForEach(1...5, id: \.self) { Text("\($0)").tag($0) }
                }
                .pickerStyle(.segmented)
            }
            HStack {
                Text("Rank").font(.subheadline.weight(.semibold)).foregroundStyle(Theme.text)
                Spacer()
                Picker("Rank", selection: $app.state.bracket) {
                    ForEach(Bracket.allCases) { Text(app.data.bracketName($0)).tag($0) }
                }
                .tint(Theme.gold)
            }
            if !app.pool.isEmpty {
                Toggle(isOn: $app.onlyPool) {
                    VStack(alignment: .leading, spacing: 1) {
                        Text("Only my hero pool").font(.subheadline.weight(.semibold)).foregroundStyle(Theme.text)
                        Text("\(app.pool.count) heroes").font(.caption).foregroundStyle(Theme.muted)
                    }
                }
                .tint(Theme.gold)
            }
        }
    }

    // MARK: Results

    private func yourPick(_ p: Pick) -> some View {
        Panel {
            SectionTitle(title: "Your pick", subtitle: "locked in", icon: "lock.fill")
            PickCard(pick: p, rank: nil, expanded: true, showActions: false, toggle: {})
            Button("Change pick") { app.state.you = nil; Haptics.light() }
                .font(.subheadline.weight(.semibold)).tint(Theme.gold)
        }
    }

    private func bestPicks(_ ranked: [Pick], draft: Draft, engine: Engine) -> some View {
        Panel {
            SectionTitle(
                title: draft.enemies.isEmpty ? "Strongest picks right now" : "Best last picks",
                subtitle: draft.enemies.isEmpty ? "add enemy heroes to counter-pick"
                    : "vs \(draft.enemies.count) enem\(draft.enemies.count == 1 ? "y" : "ies")"
                    + (draft.allies.isEmpty ? "" : " · with \(draft.allies.count) all\(draft.allies.count == 1 ? "y" : "ies")"),
                icon: "crown.fill")
            if ranked.isEmpty {
                Text("No heroes left for this filter.").font(.subheadline).foregroundStyle(Theme.muted)
            }
            ForEach(Array(ranked.prefix(10).enumerated()), id: \.element.id) { i, p in
                PickCard(pick: p, rank: i + 1, expanded: expanded.contains(p.id), showActions: true) {
                    withAnimation(.snappy) { if expanded.contains(p.id) { expanded.remove(p.id) } else { expanded.insert(p.id) } }
                }
                if i < min(ranked.count, 10) - 1 { Divider().overlay(Theme.line) }
            }
            if !app.hidden.isEmpty {
                HStack {
                    Text("\(app.hidden.count) hero\(app.hidden.count == 1 ? "" : "es") hidden from suggestions")
                    Spacer()
                    Button("Show all") { app.hidden = []; Haptics.light() }.tint(Theme.gold)
                }
                .font(.caption).foregroundStyle(Theme.muted)
            }
        }
    }

    private func predictions(_ preds: [Prediction], draft: Draft) -> some View {
        Panel {
            SectionTitle(title: "They might pick next",
                         subtitle: draft.allies.isEmpty && draft.enemies.isEmpty ? "most likely in this bracket" : "popularity + fit vs your team",
                         icon: "eye.fill", tint: Theme.enemy)
            ForEach(preds) { pr in
                NavigationLink(value: pr.pick.hero.id) {
                    ThreatRow(pick: pr.pick, trailing: Theme.pct(pr.chance, digits: 0), trailingCaption: "chance",
                              barValue: pr.chance, barMax: preds.first?.chance ?? 1)
                }
                .buttonStyle(.plain)
            }
            Text("% = chance this is their next pick, out of every hero still available, so the list doesn't add up to 100%. Estimated from how often each hero is picked in this bracket and how well it fits their draft against yours.")
                .font(.caption2).foregroundStyle(Theme.muted)
        }
    }

    private func bans(_ threats: [Threat], draft: Draft) -> some View {
        Panel {
            SectionTitle(title: "Ban suggestions",
                         subtitle: draft.allies.isEmpty ? "strongest heroes in this bracket" : "would hurt your draft most",
                         icon: "nosign", tint: Theme.ban)
            ForEach(threats) { t in
                NavigationLink(value: t.pick.hero.id) {
                    ThreatRow(pick: t.pick, trailing: Theme.signed(t.value), trailingCaption: "threat",
                              barValue: nil, barMax: 1)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func avoid(_ worst: [Pick]) -> some View {
        Panel {
            DisclosureGroup(isExpanded: $showAvoid) {
                VStack(spacing: 10) {
                    ForEach(worst) { p in
                        PickCard(pick: p, rank: nil, expanded: false, showActions: false, toggle: {})
                    }
                }
                .padding(.top, 10)
            } label: {
                Label("Worst picks into this draft", systemImage: "hand.thumbsdown.fill")
                    .font(.subheadline.weight(.semibold)).foregroundStyle(Theme.muted)
            }
            .tint(Theme.muted)
        }
    }
}

// MARK: - Slots

struct SlotView: View {
    @Environment(AppModel.self) private var app
    let heroId: Int?
    let tint: Color
    let label: String
    var strike = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack {
                RoundedRectangle(cornerRadius: 7, style: .continuous).fill(Color.white.opacity(0.04))
                if let id = heroId, let h = app.hero(id) {
                    GeometryReader { g in Portrait(hero: h, height: g.size.height) }
                        .grayscale(strike ? 0.9 : 0)
                        .overlay {
                            if strike { Rectangle().fill(Theme.enemy).frame(height: 2).rotationEffect(.degrees(-20)) }
                        }
                } else {
                    Image(systemName: "plus").font(.caption.weight(.bold)).foregroundStyle(tint.opacity(0.7))
                }
            }
            .aspectRatio(16 / 9, contentMode: .fit)
            .overlay(RoundedRectangle(cornerRadius: 7, style: .continuous)
                .strokeBorder(heroId == nil ? tint.opacity(0.35) : tint.opacity(0.8), style: StrokeStyle(lineWidth: 1, dash: heroId == nil ? [3, 3] : [])))
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(heroId.flatMap { app.hero($0)?.name }.map { "\(label): \($0). Double-tap to change." } ?? "\(label), empty. Double-tap to add a hero.")
    }
}

struct YouSlot: View {
    @Environment(AppModel.self) private var app
    let heroId: Int?
    let clear: () -> Void

    var body: some View {
        Button(action: clear) {
            ZStack {
                RoundedRectangle(cornerRadius: 7, style: .continuous).fill(Theme.gold.opacity(0.08))
                if let id = heroId, let h = app.hero(id) {
                    GeometryReader { g in Portrait(hero: h, height: g.size.height) }
                } else {
                    Text("YOU").font(.system(size: 10, weight: .heavy)).foregroundStyle(Theme.gold)
                }
            }
            .aspectRatio(16 / 9, contentMode: .fit)
            .overlay(RoundedRectangle(cornerRadius: 7, style: .continuous).strokeBorder(Theme.gold.opacity(heroId == nil ? 0.5 : 1), lineWidth: 1.5))
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.plain)
        .disabled(heroId == nil)
        .accessibilityLabel(heroId.flatMap { app.hero($0)?.name }.map { "Your pick: \($0). Double-tap to clear." } ?? "Your pick, empty. Lock one in from the results.")
    }
}

// MARK: - Rows

struct ThreatRow: View {
    @Environment(AppModel.self) private var app
    let pick: Pick // enemy point of view
    let trailing: String
    let trailingCaption: String
    let barValue: Double?
    let barMax: Double

    var body: some View {
        HStack(spacing: 10) {
            Portrait(hero: pick.hero, height: 34)
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(pick.hero.name).font(.subheadline.weight(.semibold)).foregroundStyle(Theme.text).lineLimit(1)
                    PositionBadges(heroId: pick.hero.id)
                }
                let beats = pick.vs.filter { $0.value >= 0.8 }.sorted { $0.value > $1.value }.prefix(3)
                if !beats.isEmpty {
                    FlowLayout(spacing: 4) {
                        ForEach(Array(beats)) { l in
                            ValueChip(hero: app.hero(l.hero), text: "beats \(Theme.signed(l.value))", tint: Theme.enemy)
                        }
                    }
                } else if let bar = barValue {
                    GeometryReader { g in
                        Capsule().fill(Theme.enemy.opacity(0.7)).frame(width: max(4, g.size.width * bar / max(barMax, 0.001)))
                    }
                    .frame(height: 4)
                } else {
                    Text("Win rate \(Theme.pct(app.engine().winRate(pick.hero.id)))").font(.caption2).foregroundStyle(Theme.muted)
                }
            }
            Spacer(minLength: 6)
            VStack(alignment: .trailing, spacing: 0) {
                Text(trailing).font(.subheadline.weight(.bold)).monospacedDigit().foregroundStyle(Theme.text)
                Text(trailingCaption).font(.caption2).foregroundStyle(Theme.muted)
            }
            Image(systemName: "chevron.right").font(.caption2.weight(.bold)).foregroundStyle(Theme.muted.opacity(0.6))
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }
}

struct DataFooter: View {
    @Environment(AppModel.self) private var app
    var body: some View {
        let d = app.data
        Text("Based on \(d.matches.formatted()) ranked public matches from the \(d.days) days up to \(d.updated.formatted(date: .abbreviated, time: .omitted)), via OpenDota. Matchups are additive estimates, not a guarantee. Dota 2 is a trademark of Valve Corporation; this app is not affiliated with Valve.")
            .font(.caption2).foregroundStyle(Theme.muted)
            .multilineTextAlignment(.center)
            .padding(.top, 4)
    }
}

/// Wrapping row layout for chips.
struct FlowLayout: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxW = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, rowH: CGFloat = 0, widest: CGFloat = 0
        for v in subviews {
            let s = v.sizeThatFits(.unspecified)
            if x > 0 && x + s.width > maxW { y += rowH + spacing; x = 0; rowH = 0 }
            x += s.width + spacing
            rowH = max(rowH, s.height)
            widest = max(widest, x - spacing)
        }
        return CGSize(width: min(widest, maxW), height: y + rowH)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, rowH: CGFloat = 0
        for v in subviews {
            let s = v.sizeThatFits(.unspecified)
            if x > bounds.minX && x + s.width > bounds.maxX { y += rowH + spacing; x = bounds.minX; rowH = 0 }
            v.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(s))
            x += s.width + spacing
            rowH = max(rowH, s.height)
        }
    }
}
