import Foundation

// Port of the web app's src/engine.ts, plus the draft reads that only the app has (enemy next-pick odds,
// ban threats, meta tiers, hero matchups). Every number is in win-rate percentage points unless noted.
//
// Last-pick score = hero's own win-rate edge + summed matchup advantage vs each enemy
//                 + 0.6 × synergy with allies + a small bonus for filling roles the team is missing.

struct Draft: Equatable {
    var allies: [Int] = []
    var enemies: [Int] = []
    var bans: [Int] = []

    /// The same draft seen from the other side.
    var flipped: Draft { Draft(allies: enemies, enemies: allies, bans: bans) }
    var taken: Set<Int> { Set(allies + enemies + bans) }
}

struct Line: Identifiable {
    let hero: Int
    var value: Double // percentage points
    let games: Int
    var id: Int { hero }
}

struct Pick: Identifiable {
    let hero: Hero
    let total: Double
    let base: Double
    let counter: Double
    let synergy: Double
    let roles: Double
    let vs: [Line]
    let with: [Line] // raw synergy per ally (before the 0.6 weight)
    let roleNotes: [String]
    var id: Int { hero.id }

    /// Average head-to-head games per enemy matchup; low numbers mean a noisy estimate.
    var lowData: Bool {
        guard !vs.isEmpty else { return false }
        return Double(vs.reduce(0) { $0 + $1.games }) / Double(vs.count) < Engine.lowDataGames
    }
}

struct Prediction: Identifiable {
    let pick: Pick // scored from the enemy team's point of view
    let chance: Double // 0…1, share among all heroes still available
    var id: Int { pick.id }
}

struct Threat: Identifiable {
    let pick: Pick // enemy point of view: how good this hero would be against your team
    let value: Double
    var id: Int { pick.id }
}

struct MetaRow: Identifiable {
    let hero: Hero
    let winRate: Double // 0…1
    let pickRate: Double // 0…1, share of matches the hero appears in
    let games: Int
    var tier: String = ""
    var id: Int { hero.id }
}

func positionsOf(_ id: Int) -> [Int] { POSITIONS[id] ?? [1, 2, 3, 4, 5] }

final class Engine {
    static let K = 150.0 // shrinkage prior: pairs with few games pull toward "no effect"
    static let synergyWeight = 0.6
    static let lowDataGames = 300.0

    let data: GameData
    let bracket: Bracket
    let totalMatches: Double
    private var baseGames: [Int: Double] = [:]
    private var baseWR: [Int: Double] = [:]

    init(data: GameData, bracket: Bracket = .all) {
        self.data = data
        self.bracket = bracket
        // Each match yields 5 vs-pairs per hero, so pair totals / 5 = hero games/wins.
        var acc: [Int: (Double, Double)] = [:]
        for (k, arr) in data.vs {
            let a = k / 1000, b = k % 1000
            let (g, w) = Engine.sum(arr, bracket)
            let A = acc[a] ?? (0, 0), B = acc[b] ?? (0, 0)
            acc[a] = (A.0 + g, A.1 + w)
            acc[b] = (B.0 + g, B.1 + (g - w))
        }
        var games = 0.0
        for h in data.heroes {
            let (g, w) = acc[h.id] ?? (0, 0)
            baseGames[h.id] = g / 5
            baseWR[h.id] = g > 0 ? w / g : 0.5
            games += g / 5
        }
        totalMatches = games / 10
    }

    private static func sum(_ arr: [Int]?, _ br: Bracket) -> (Double, Double) {
        guard let arr else { return (0, 0) }
        if br == .all { return (Double(arr[0] + arr[2] + arr[4]), Double(arr[1] + arr[3] + arr[5])) }
        return (Double(arr[br.rawValue * 2]), Double(arr[br.rawValue * 2 + 1]))
    }

    func hero(_ id: Int) -> Hero? { data.byId[id] }
    func winRate(_ id: Int) -> Double { baseWR[id] ?? 0.5 }
    func games(_ id: Int) -> Int { Int(baseGames[id] ?? 0) }
    func pickRate(_ id: Int) -> Double { totalMatches > 0 ? (baseGames[id] ?? 0) / totalMatches : 0 }

    /// Advantage of hero a vs hero b beyond what their base win rates predict (percentage points).
    func vs(_ a: Int, _ b: Int) -> Line {
        let (g, wLow) = Engine.sum(data.vs[GameData.pairKey(a, b)], bracket)
        let w = a < b ? wLow : g - wLow
        let expected = 0.5 + winRate(a) - winRate(b)
        return Line(hero: b, value: (w - g * expected) / (g + Engine.K) * 100, games: Int(g))
    }

    /// Extra win rate when a and b are on the same team, beyond their base win rates (percentage points).
    func with(_ a: Int, _ b: Int) -> Line {
        let (g, w) = Engine.sum(data.with[GameData.pairKey(a, b)], bracket)
        let expected = winRate(a) + winRate(b) - 0.5
        return Line(hero: b, value: (w - g * expected) / (g + Engine.K) * 100, games: Int(g))
    }

    func score(_ id: Int, _ draft: Draft) -> Pick {
        let hero = data.byId[id]!
        let vs = draft.enemies.map { self.vs(id, $0) }
        let wi = draft.allies.map { self.with(id, $0) }
        let (bonus, notes) = Engine.roleFit(hero, draft.allies.compactMap { data.byId[$0] })
        let base = (winRate(id) - 0.5) * 100
        let counter = vs.reduce(0) { $0 + $1.value }
        let synergy = wi.reduce(0) { $0 + $1.value } * Engine.synergyWeight
        return Pick(hero: hero, total: base + counter + synergy + bonus, base: base, counter: counter,
                    synergy: synergy, roles: bonus, vs: vs, with: wi, roleNotes: notes)
    }

    func rank(_ draft: Draft, position: Int = 0, exclude: Set<Int> = [], only: Set<Int>? = nil) -> [Pick] {
        let taken = draft.taken
        return data.heroes
            .filter { !taken.contains($0.id) && !exclude.contains($0.id) && (only?.contains($0.id) ?? true) }
            .filter { position == 0 || positionsOf($0.id).contains(position) }
            .map { score($0.id, draft) }
            .sorted { $0.total > $1.total }
    }

    // MARK: - Enemy reads

    /// Who the enemy is likely to pick next: popularity in this bracket (log pick rate) plus how strong the hero
    /// is for their draft against yours, softmaxed over every hero still available. `chance` is a share of that whole field,
    /// so the returned top `limit` intentionally sums to less than 1 (the UI says so).
    func predictEnemy(_ draft: Draft, exclude: Set<Int> = [], limit: Int = 6) -> [Prediction] {
        let theirs = draft.flipped
        let taken = draft.taken.union(exclude)
        let scored = data.heroes.filter { !taken.contains($0.id) }.map { h -> (Pick, Double) in
            let p = score(h.id, theirs)
            return (p, log(max(pickRate(h.id), 0.002)) + 0.45 * p.total)
        }
        guard let top = scored.map(\.1).max() else { return [] }
        let z = scored.reduce(0) { $0 + exp($1.1 - top) }
        return scored.sorted { $0.1 > $1.1 }.prefix(limit).map { Prediction(pick: $0.0, chance: exp($0.1 - top) / z) }
    }

    /// Heroes most worth banning: how hard each would counter the heroes already on your team (its own win-rate edge
    /// plus its matchups vs your heroes — not its fit with their team), nudged toward heroes people actually play.
    func banThreats(_ draft: Draft, exclude: Set<Int> = [], limit: Int = 5) -> [Threat] {
        let theirs = draft.flipped
        let taken = draft.taken.union(exclude)
        let mean = 10.0 / Double(max(data.heroes.count, 1))
        return data.heroes.filter { !taken.contains($0.id) }.map { h -> Threat in
            let p = score(h.id, theirs)
            let popularity = min(max(log(max(pickRate(h.id), 0.002) / mean), -2), 2)
            return Threat(pick: p, value: p.base + p.counter + 0.8 * popularity)
        }
        .sorted { $0.value > $1.value }
        .prefix(limit).map { $0 }
    }

    // MARK: - Meta & matchups

    /// Heroes by win rate for a position, with tiers by rank among heroes that see real play (≥0.5% of matches).
    func meta(position: Int = 0) -> [MetaRow] {
        var rows = data.heroes
            .filter { position == 0 || positionsOf($0.id).contains(position) }
            .map { MetaRow(hero: $0, winRate: winRate($0.id), pickRate: pickRate($0.id), games: games($0.id)) }
            .sorted { $0.winRate > $1.winRate }
        let played = rows.filter { $0.pickRate >= 0.005 }.count
        var i = 0
        for r in rows.indices {
            guard rows[r].pickRate >= 0.005 else { rows[r].tier = "–"; continue }
            let pct = Double(i) / Double(max(played, 1))
            rows[r].tier = pct < 0.1 ? "S" : pct < 0.3 ? "A" : pct < 0.7 ? "B" : pct < 0.9 ? "C" : "D"
            i += 1
        }
        return rows
    }

    /// Heroes that beat `id` (their advantage over it), best first.
    func counters(of id: Int, limit: Int = 8) -> [Line] {
        data.heroes.filter { $0.id != id }
            .map { other -> Line in let l = vs(other.id, id); return Line(hero: other.id, value: l.value, games: l.games) }
            .sorted { $0.value > $1.value }.prefix(limit).map { $0 }
    }

    /// Heroes `id` beats, best first.
    func goodAgainst(_ id: Int, limit: Int = 8) -> [Line] {
        data.heroes.filter { $0.id != id }.map { vs(id, $0.id) }.sorted { $0.value > $1.value }.prefix(limit).map { $0 }
    }

    /// Best teammates for `id`, best first.
    func bestWith(_ id: Int, limit: Int = 8) -> [Line] {
        data.heroes.filter { $0.id != id }.map { with(id, $0.id) }.sorted { $0.value > $1.value }.prefix(limit).map { $0 }
    }

    // MARK: - Roles

    private static let needs: [(role: String, label: String, bonus: Double, heroPos: (([Int]) -> Bool)?)] = [
        ("Disabler", "adds the lockdown your team lacks", 0.5, nil),
        ("Initiator", "gives your team an initiator", 0.5, nil),
        ("Durable", "adds a frontliner", 0.4, nil),
        ("Carry", "gives your team a late-game carry", 0.6, { $0[0] <= 2 }),
        ("Support", "your team has no support yet", 0.5, { $0[0] >= 4 }),
    ]

    /// Small bonus when the candidate fills a role none of the allies cover (only once 3+ allies are known).
    static func roleFit(_ hero: Hero, _ allies: [Hero]) -> (Double, [String]) {
        guard allies.count >= 3 else { return (0, []) }
        let have = Set(allies.flatMap(\.roles))
        var bonus = 0.0
        var notes: [String] = []
        for n in needs where !have.contains(n.role) && hero.roles.contains(n.role) {
            if let f = n.heroPos, !f(positionsOf(hero.id)) { continue }
            bonus += n.bonus
            notes.append(n.label)
        }
        return (min(bonus, 1.5), notes)
    }
}

// MARK: - Search

private func norm(_ s: String) -> String { s.lowercased().filter { $0.isLetter || $0.isNumber } }

/// Match quality for a query (higher is better, 0 = no match). Handles aliases, prefixes, word starts and initials.
func matchScore(_ h: Hero, _ raw: String) -> Int {
    let q = norm(raw)
    if q.isEmpty { return 1 }
    let name = norm(h.name)
    let words = h.name.lowercased().split(whereSeparator: { $0 == " " || $0 == "'" || $0 == "-" }).map(String.init)
    let initials = String(words.compactMap(\.first))
    if ALIASES[q] == h.id { return 100 }
    if name == q { return 95 }
    if name.hasPrefix(q) { return 80 }
    if initials == q { return 75 }
    if words.contains(where: { norm($0).hasPrefix(q) }) { return 60 }
    if norm(h.slug).contains(q) { return 40 }
    if name.contains(q) { return 30 }
    return 0
}

/// Heroes matching a query (best match first; alphabetical when the query is empty), optionally one attribute only.
func searchHeroes(_ heroes: [Hero], _ query: String, attr: String? = nil) -> [Hero] {
    let q = query.trimmingCharacters(in: .whitespaces)
    let pool = heroes.filter { attr == nil || $0.attr == attr }
    if q.isEmpty { return pool }
    let scored: [(hero: Hero, score: Int)] = pool.map { ($0, matchScore($0, q)) }.filter { $0.1 > 0 }
    return scored.sorted { a, b in a.score != b.score ? a.score > b.score : a.hero.name < b.hero.name }.map(\.hero)
}
