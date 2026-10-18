import Foundation

// The same data.json the web app serves: hero list + pairwise vs/with game counts from recent ranked public matches.

struct Hero: Codable, Identifiable, Hashable {
    let id: Int
    let name: String
    let slug: String
    let attr: String // str | agi | int | all
    let melee: Bool
    let roles: [String]
}

enum Bracket: Int, CaseIterable, Codable, Identifiable {
    case all = -1, low = 0, mid = 1, high = 2
    var id: Int { rawValue }
}

struct GameData {
    let updated: Date
    let days: Int
    let matches: Int
    let brackets: [String]
    let heroes: [Hero] // alphabetical
    let byId: [Int: Hero]
    let vs: [Int: [Int]] // pairKey(a,b), a<b → [g,wA] × 3 brackets (wins for the lower id)
    let with: [Int: [Int]] // pairKey(a,b), a<b → [g,w] × 3 brackets (wins together)

    static func pairKey(_ a: Int, _ b: Int) -> Int { a < b ? a * 1000 + b : b * 1000 + a }

    func bracketName(_ b: Bracket) -> String {
        b == .all ? "All ranks" : (brackets.indices.contains(b.rawValue) ? brackets[b.rawValue] : "Bracket \(b.rawValue + 1)")
    }

    private struct Raw: Decodable {
        let updated: String
        let days: Int
        let matches: Int
        let brackets: [String]
        let heroes: [Hero]
        let vs: [String: [Int]]
        let with: [String: [Int]]
    }

    enum LoadError: Error { case invalid(String) }

    init(json: Data) throws {
        let raw = try JSONDecoder().decode(Raw.self, from: json)
        guard raw.heroes.count >= 100, raw.vs.count >= 1000, raw.with.count >= 1000, raw.brackets.count == 3 else {
            throw LoadError.invalid("incomplete data (\(raw.heroes.count) heroes, \(raw.vs.count) pairs)")
        }
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let plain = ISO8601DateFormatter()
        guard let date = iso.date(from: raw.updated) ?? plain.date(from: raw.updated) else {
            throw LoadError.invalid("bad date \(raw.updated)")
        }
        func pack(_ m: [String: [Int]]) throws -> [Int: [Int]] {
            var out = [Int: [Int]](minimumCapacity: m.count)
            for (k, v) in m {
                let parts = k.split(separator: "-").compactMap { Int($0) }
                guard parts.count == 2, v.count == 6, parts[0] < 1000, parts[1] < 1000 else { throw LoadError.invalid("bad pair \(k)") }
                out[Self.pairKey(parts[0], parts[1])] = v
            }
            return out
        }
        updated = date
        days = raw.days
        matches = raw.matches
        brackets = raw.brackets
        heroes = raw.heroes.sorted { $0.name < $1.name }
        byId = Dictionary(uniqueKeysWithValues: raw.heroes.map { ($0.id, $0) })
        vs = try pack(raw.vs)
        with = try pack(raw.with)
    }
}
