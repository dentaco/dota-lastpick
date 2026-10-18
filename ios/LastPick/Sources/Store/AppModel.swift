import Foundation
import Observation

enum Team: String, Codable { case ally, enemy, ban }

struct Slot: Hashable, Codable {
    let team: Team
    let index: Int
}

/// Everything the user has entered. Saved on every change so the draft survives app switches.
struct DraftState: Codable, Equatable {
    static let size: [Team: Int] = [.ally: 4, .enemy: 5, .ban: 14]

    var ally: [Int?] = Array(repeating: nil, count: 4)
    var enemy: [Int?] = Array(repeating: nil, count: 5)
    var ban: [Int?] = Array(repeating: nil, count: 14)
    var you: Int?
    var position = 0
    var bracket: Bracket = .all

    subscript(slot: Slot) -> Int? {
        get { list(slot.team)[slot.index] }
        set {
            switch slot.team {
            case .ally: ally[slot.index] = newValue
            case .enemy: enemy[slot.index] = newValue
            case .ban: ban[slot.index] = newValue
            }
        }
    }

    func list(_ t: Team) -> [Int?] { t == .ally ? ally : t == .enemy ? enemy : ban }

    /// Allies don't include your own locked pick: the last-pick list scores candidates for that slot.
    var draft: Draft { Draft(allies: ally.compactMap { $0 }, enemies: enemy.compactMap { $0 }, bans: ban.compactMap { $0 }) }
    /// Your full team (with your locked pick) — what the enemy is drafting against.
    var teamDraft: Draft {
        var d = draft
        if let you { d.allies.append(you) }
        return d
    }
    var taken: Set<Int> { draft.taken.union(you.map { [$0] } ?? []) }
    var isEmpty: Bool { taken.isEmpty }

    /// Next empty slot, continuing from `after` (enemy first, then your team; bans stay in the ban row).
    func nextEmpty(after: Slot?) -> Slot? {
        let cur = after ?? Slot(team: .enemy, index: 0)
        let order: [Team] = cur.team == .ban ? [.ban] : cur.team == .ally ? [.ally, .enemy] : [.enemy, .ally]
        for t in order {
            let n = DraftState.size[t]!
            let start = t == cur.team ? cur.index : 0
            for k in 0..<n {
                let i = (start + k) % n
                if list(t)[i] == nil { return Slot(team: t, index: i) }
            }
        }
        return nil
    }
}

@MainActor
@Observable
final class AppModel {
    static let remoteURL = URL(string: "https://dota-last-pick.vercel.app/data.json")!
    static let refreshEvery: TimeInterval = 6 * 3600

    enum RefreshState: Equatable { case idle, checking, updated, upToDate, failed(String) }

    private(set) var data: GameData
    private(set) var refreshState: RefreshState = .idle
    private(set) var lastChecked: Date?

    var state: DraftState { didSet { if state != oldValue { save() } } }
    var pool: Set<Int> { didSet { defaults.set(Array(pool), forKey: Keys.pool) } }
    var hidden: Set<Int> { didSet { defaults.set(Array(hidden), forKey: Keys.hidden) } }
    var onlyPool: Bool { didSet { defaults.set(onlyPool, forKey: Keys.onlyPool) } }

    private var engines: [Bracket: Engine] = [:]
    private let defaults = UserDefaults.standard
    private enum Keys {
        static let draft = "draft.v1", pool = "pool.v1", hidden = "hidden.v1", onlyPool = "onlyPool.v1", checked = "dataChecked.v1"
    }

    init() {
        data = AppModel.loadBestLocal()
        let d = UserDefaults.standard
        if let raw = d.data(forKey: Keys.draft), let s = try? JSONDecoder().decode(DraftState.self, from: raw) {
            state = s
        } else {
            state = DraftState()
        }
        pool = Set(d.array(forKey: Keys.pool) as? [Int] ?? [])
        hidden = Set(d.array(forKey: Keys.hidden) as? [Int] ?? [])
        onlyPool = d.bool(forKey: Keys.onlyPool)
        lastChecked = d.object(forKey: Keys.checked) as? Date
        #if DEBUG
        seedDemoDraftIfAsked()
        #endif
        dropUnknownHeroes()
    }

    func engine(_ b: Bracket? = nil) -> Engine {
        let b = b ?? state.bracket
        if let e = engines[b] { return e }
        let e = Engine(data: data, bracket: b)
        engines[b] = e
        return e
    }

    func hero(_ id: Int) -> Hero? { data.byId[id] }

    /// Heroes the user doesn't want suggested (hidden, or outside their pool when "only my pool" is on).
    var suggestionFilter: (exclude: Set<Int>, only: Set<Int>?) {
        (hidden, onlyPool && !pool.isEmpty ? pool : nil)
    }

    func resetDraft() {
        let pos = state.position, br = state.bracket
        state = DraftState()
        state.position = pos
        state.bracket = br
    }

    private func save() {
        if let raw = try? JSONEncoder().encode(state) { defaults.set(raw, forKey: Keys.draft) }
    }

    /// A refresh can drop or renumber nothing in practice, but never keep an id the data doesn't know.
    private func dropUnknownHeroes() {
        var s = state
        for t in [Team.ally, .enemy, .ban] {
            for i in 0..<DraftState.size[t]! {
                let slot = Slot(team: t, index: i)
                if let id = s[slot], data.byId[id] == nil { s[slot] = nil }
            }
        }
        if let y = s.you, data.byId[y] == nil { s.you = nil }
        if s != state { state = s }
        pool = pool.filter { data.byId[$0] != nil }
        hidden = hidden.filter { data.byId[$0] != nil }
    }

    #if DEBUG
    /// Simulator screenshots / review video: LASTPICK_DEMO=full (both teams) or =mid (a draft in progress).
    private func seedDemoDraftIfAsked() {
        guard let mode = ProcessInfo.processInfo.environment["LASTPICK_DEMO"] else { return }
        let named = { (n: String) in self.data.heroes.first { $0.name == n }?.id }
        var s = DraftState()
        let allies = ["Axe", "Crystal Maiden", "Shadow Fiend", "Earthshaker"]
        let enemies = mode == "mid" ? ["Phantom Assassin", "Lion"] : ["Phantom Assassin", "Lion", "Storm Spirit", "Mars", "Witch Doctor"]
        for (i, n) in allies.prefix(mode == "mid" ? 2 : 4).enumerated() { s.ally[i] = named(n) }
        for (i, n) in enemies.enumerated() { s.enemy[i] = named(n) }
        s.ban[0] = named("Invoker")
        s.ban[1] = named("Pudge")
        state = s
    }
    #endif

    // MARK: - Data

    private static var cacheURL: URL {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("data.json")
    }

    /// Newest of the bundled snapshot and the last downloaded one. The bundled file always works offline.
    private static func loadBestLocal() -> GameData {
        let bundled = Bundle.main.url(forResource: "data", withExtension: "json")
            .flatMap { try? Data(contentsOf: $0) }.flatMap { try? GameData(json: $0) }
        let cached = (try? Data(contentsOf: cacheURL)).flatMap { try? GameData(json: $0) }
        switch (bundled, cached) {
        case let (b?, c?): return c.updated > b.updated ? c : b
        case let (b?, nil): return b
        case let (nil, c?): return c
        default: fatalError("data.json missing from the app bundle")
        }
    }

    func refreshIfStale() async {
        if let lastChecked, Date().timeIntervalSince(lastChecked) < AppModel.refreshEvery { return }
        await refresh()
    }

    func refresh() async {
        guard refreshState != .checking else { return }
        refreshState = .checking
        do {
            var req = URLRequest(url: AppModel.remoteURL, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 20)
            req.setValue("application/json", forHTTPHeaderField: "Accept")
            let (body, resp) = try await URLSession.shared.data(for: req)
            guard (resp as? HTTPURLResponse)?.statusCode == 200 else { throw URLError(.badServerResponse) }
            let fresh = try await Task.detached(priority: .utility) { try GameData(json: body) }.value
            lastChecked = Date()
            defaults.set(lastChecked, forKey: Keys.checked)
            if fresh.updated > data.updated {
                try body.write(to: AppModel.cacheURL, options: .atomic)
                data = fresh
                engines = [:]
                dropUnknownHeroes()
                refreshState = .updated
            } else {
                refreshState = .upToDate
            }
        } catch {
            refreshState = .failed((error as? URLError) != nil ? "You're offline — using saved data." : "Couldn't read new data — using saved data.")
        }
    }
}
