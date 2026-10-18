import XCTest
@testable import LastPick

// Mirrors the web app's src/engine.test.ts against the same bundled data.json, plus the app-only reads.
final class EngineTests: XCTestCase {
    static let data: GameData = {
        let url = Bundle(for: EngineTests.self).bundleURL.deletingLastPathComponent().appendingPathComponent("LastPick.app/data.json")
        let fallback = Bundle.main.url(forResource: "data", withExtension: "json")
        return try! GameData(json: Data(contentsOf: FileManager.default.fileExists(atPath: url.path) ? url : fallback!))
    }()
    let m = Engine(data: EngineTests.data)
    func id(_ name: String) -> Int { EngineTests.data.heroes.first { $0.name == name }!.id }

    func testBaseWinRatesAreSane() {
        for h in EngineTests.data.heroes {
            XCTAssertGreaterThan(m.winRate(h.id), 0.35, h.name)
            XCTAssertLessThan(m.winRate(h.id), 0.65, h.name)
        }
    }

    func testVsIsAntisymmetric() {
        let a = id("Anti-Mage"), b = id("Storm Spirit")
        XCTAssertEqual(m.vs(a, b).games, m.vs(b, a).games)
        XCTAssertEqual(m.vs(a, b).value, -m.vs(b, a).value, accuracy: 1e-6)
    }

    func testNeverSuggestsTakenHeroesAndRespectsPosition() {
        let d = Draft(allies: [id("Axe"), id("Lion")], enemies: [id("Pudge"), id("Sniper")], bans: [id("Invoker")])
        let ids = m.rank(d, position: 2).map(\.hero.id)
        for x in d.allies + d.enemies + d.bans { XCTAssertFalse(ids.contains(x)) }
        XCTAssertFalse(ids.contains(id("Crystal Maiden")))
    }

    func testKnownHardCountersRankHigh() {
        let d = Draft(enemies: [id("Medusa"), id("Storm Spirit"), id("Outworld Devourer")])
        XCTAssertTrue(m.rank(d).prefix(25).map(\.hero.name).contains("Anti-Mage"))
    }

    func testScoreAddsUp() {
        let d = Draft(allies: [id("Axe"), id("Lion"), id("Lina")], enemies: [id("Pudge"), id("Sniper")])
        let p = m.score(id("Juggernaut"), d)
        XCTAssertEqual(p.total, p.base + p.counter + p.synergy + p.roles, accuracy: 1e-9)
        XCTAssertEqual(p.counter, p.vs.reduce(0) { $0 + $1.value }, accuracy: 1e-9)
    }

    func testPredictionsAreAProbabilityShareOverAvailableHeroes() {
        let d = Draft(allies: [id("Axe")], enemies: [id("Pudge"), id("Sniper")], bans: [id("Invoker")])
        let all = m.predictEnemy(d, limit: 500)
        XCTAssertEqual(all.reduce(0) { $0 + $1.chance }, 1, accuracy: 1e-6)
        XCTAssertEqual(all.count, EngineTests.data.heroes.count - 4)
        XCTAssertTrue(all.allSatisfy { !d.taken.contains($0.pick.hero.id) })
        XCTAssertEqual(all.map(\.chance), all.map(\.chance).sorted(by: >))
        // scored from the enemy's side: their allies are our enemies
        XCTAssertEqual(all[0].pick.vs.map(\.hero), d.allies)
    }

    func testBanThreatsScoreAgainstYourTeam() {
        let d = Draft(allies: [id("Medusa"), id("Storm Spirit")], enemies: [], bans: [])
        let t = m.banThreats(d, limit: 10)
        XCTAssertEqual(t.count, 10)
        XCTAssertTrue(t.allSatisfy { $0.pick.vs.map(\.hero) == d.allies })
    }

    func testMetaTiersAndPickRates() {
        let rows = m.meta()
        XCTAssertEqual(rows.count, EngineTests.data.heroes.count)
        XCTAssertEqual(rows.reduce(0) { $0 + $1.pickRate }, 10, accuracy: 0.01) // 10 heroes per match
        XCTAssertEqual(rows.first?.tier, "S")
        XCTAssertTrue(rows.filter { $0.pickRate >= 0.005 }.allSatisfy { ["S", "A", "B", "C", "D"].contains($0.tier) })
        XCTAssertTrue(m.meta(position: 5).allSatisfy { positionsOf($0.hero.id).contains(5) })
    }

    func testMatchupListsPointAtTheRightHeroes() {
        let pa = id("Phantom Assassin")
        let c = m.counters(of: pa)
        XCTAssertEqual(c.count, 8)
        XCTAssertFalse(c.contains { $0.hero == pa })
        XCTAssertEqual(c[0].value, m.vs(c[0].hero, pa).value, accuracy: 1e-9)
        XCTAssertEqual(m.goodAgainst(pa)[0].value, m.vs(pa, m.goodAgainst(pa)[0].hero).value, accuracy: 1e-9)
    }

    func testSearch() {
        let h = { (n: String) in EngineTests.data.heroes.first { $0.name == n }! }
        XCTAssertEqual(matchScore(h("Phantom Assassin"), "pa"), 100)
        XCTAssertEqual(matchScore(h("Shadow Fiend"), "SF"), 100)
        XCTAssertGreaterThan(matchScore(h("Crystal Maiden"), "crys"), 0)
        XCTAssertEqual(matchScore(h("Axe"), "zzz"), 0)
    }

    func testDraftStateNextEmpty() {
        var s = DraftState()
        XCTAssertEqual(s.nextEmpty(after: nil), Slot(team: .enemy, index: 0))
        for i in 0..<5 { s.enemy[i] = i + 1 }
        XCTAssertEqual(s.nextEmpty(after: Slot(team: .enemy, index: 4)), Slot(team: .ally, index: 0))
        for i in 0..<4 { s.ally[i] = i + 10 }
        XCTAssertNil(s.nextEmpty(after: Slot(team: .ally, index: 3)))
        XCTAssertEqual(s.nextEmpty(after: Slot(team: .ban, index: 0)), Slot(team: .ban, index: 0))
    }

    func testRejectsBrokenData() {
        XCTAssertThrowsError(try GameData(json: Data("{}".utf8)))
        XCTAssertThrowsError(try GameData(json: Data(#"{"updated":"x","days":3,"matches":1,"brackets":[],"heroes":[],"vs":{},"with":{}}"#.utf8)))
    }
}
