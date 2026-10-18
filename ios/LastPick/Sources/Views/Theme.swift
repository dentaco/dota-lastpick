import SwiftUI
import UIKit

enum Theme {
    static let bg = Color(hex: 0x0B0A0D)
    static let panel = Color(hex: 0x16131A)
    static let panelHi = Color(hex: 0x1E1A23)
    static let line = Color.white.opacity(0.08)
    static let text = Color(hex: 0xECE6DC)
    static let muted = Color(hex: 0x9A92A3)
    static let gold = Color(hex: 0xD9A84E)
    static let ally = Color(hex: 0x5FD38A)
    static let enemy = Color(hex: 0xE5484D)
    static let ban = Color(hex: 0x8A8494)

    static func attr(_ a: String) -> Color {
        switch a {
        case "str": Color(hex: 0xE0553F)
        case "agi": Color(hex: 0x4CC46A)
        case "int": Color(hex: 0x48A6E8)
        default: Color(hex: 0xC99BFF)
        }
    }

    static let attrName = ["str": "Strength", "agi": "Agility", "int": "Intelligence", "all": "Universal"]

    static func signed(_ v: Double, digits: Int = 1) -> String {
        let s = String(format: "%.\(digits)f", abs(v))
        return (v >= 0 ? "+" : "−") + s
    }

    static func pct(_ v: Double, digits: Int = 1) -> String { String(format: "%.\(digits)f%%", v * 100) }
}

extension Color {
    init(hex: UInt32) {
        self.init(.sRGB, red: Double((hex >> 16) & 0xFF) / 255, green: Double((hex >> 8) & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255, opacity: 1)
    }
}

// MARK: - Portraits (bundled; Valve's CDN only for heroes released after this build)

enum PortraitCache {
    private static let cache = NSCache<NSString, UIImage>()
    static func image(_ slug: String) -> UIImage? {
        if let img = cache.object(forKey: slug as NSString) { return img }
        guard let url = Bundle.main.url(forResource: slug, withExtension: "jpg", subdirectory: "Portraits"),
              let img = UIImage(contentsOfFile: url.path) else { return nil }
        cache.setObject(img, forKey: slug as NSString)
        return img
    }
}

struct Portrait: View {
    let hero: Hero
    var height: CGFloat = 36

    var body: some View {
        Group {
            if let img = PortraitCache.image(hero.slug) {
                Image(uiImage: img).resizable()
            } else {
                AsyncImage(url: URL(string: "https://cdn.cloudflare.steamstatic.com/apps/dota2/images/dota_react/heroes/\(hero.slug).png")) { img in
                    img.resizable()
                } placeholder: {
                    ZStack {
                        Theme.attr(hero.attr).opacity(0.25)
                        Text(String(hero.name.prefix(2))).font(.caption.bold()).foregroundStyle(Theme.text)
                    }
                }
            }
        }
        .aspectRatio(16 / 9, contentMode: .fill)
        .frame(width: height * 16 / 9, height: height)
        .clipShape(RoundedRectangle(cornerRadius: height * 0.16, style: .continuous))
        .accessibilityHidden(true)
    }
}

// MARK: - Building blocks

struct Panel<Content: View>: View {
    @ViewBuilder var content: Content
    var body: some View {
        VStack(alignment: .leading, spacing: 12) { content }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.panel.opacity(0.92), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(Theme.line))
    }
}

struct SectionTitle: View {
    let title: String
    var subtitle: String?
    var icon: String?
    var tint: Color = Theme.gold

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            if let icon { Image(systemName: icon).foregroundStyle(tint).font(.subheadline.weight(.semibold)) }
            Text(title).font(.headline).foregroundStyle(Theme.text)
            Spacer(minLength: 8)
            if let subtitle { Text(subtitle).font(.caption).foregroundStyle(Theme.muted).multilineTextAlignment(.trailing) }
        }
    }
}

struct ValueChip: View {
    let hero: Hero?
    let text: String
    var tint: Color

    var body: some View {
        HStack(spacing: 4) {
            if let hero { Portrait(hero: hero, height: 16) }
            Text(text).font(.caption2.weight(.semibold)).monospacedDigit()
        }
        .padding(.horizontal, 6).padding(.vertical, 3)
        .foregroundStyle(tint)
        .background(tint.opacity(0.14), in: Capsule())
    }
}

struct NoteChip: View {
    let text: String
    var body: some View {
        Text(text).font(.caption2.weight(.medium))
            .padding(.horizontal, 7).padding(.vertical, 3)
            .foregroundStyle(Theme.gold)
            .background(Theme.gold.opacity(0.14), in: Capsule())
    }
}

/// Centered diverging bar for a signed value.
struct DivergingBar: View {
    let value: Double
    let max: Double
    var body: some View {
        GeometryReader { g in
            let half = g.size.width / 2
            let w = Swift.min(abs(value) / Swift.max(max, 0.01), 1) * half
            ZStack(alignment: .leading) {
                Capsule().fill(Color.white.opacity(0.06))
                Rectangle().fill(Color.white.opacity(0.18)).frame(width: 1).offset(x: half)
                Capsule().fill(value >= 0 ? Theme.ally : Theme.enemy)
                    .frame(width: w).offset(x: value >= 0 ? half : half - w)
            }
        }
        .frame(height: 6)
    }
}

struct PositionBadges: View {
    let heroId: Int
    var body: some View {
        HStack(spacing: 3) {
            ForEach(positionsOf(heroId), id: \.self) { p in
                Text("P\(p)").font(.system(size: 9, weight: .bold)).foregroundStyle(Theme.muted)
                    .padding(.horizontal, 4).padding(.vertical, 1)
                    .overlay(RoundedRectangle(cornerRadius: 4).stroke(Theme.line))
            }
        }
        .accessibilityLabel("Positions " + positionsOf(heroId).map(String.init).joined(separator: ", "))
    }
}

/// Slow drifting embers behind the app (off with Reduce Motion).
struct EmberField: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private struct Ember { let x, speed, size, phase: Double; let color: Color }
    private let embers: [Ember] = (0..<38).map { i in
        var g = SeededGenerator(seed: UInt64(i) &* 2654435761 &+ 7)
        return Ember(x: .random(in: 0...1, using: &g), speed: .random(in: 0.012...0.035, using: &g),
                     size: .random(in: 1.2...3.2, using: &g), phase: .random(in: 0...1, using: &g),
                     color: [Theme.enemy, Theme.gold, Color(hex: 0xFF7A3D)][i % 3])
    }

    var body: some View {
        if reduceMotion {
            Color.clear
        } else {
            TimelineView(.animation(minimumInterval: 1.0 / 30)) { tl in
                Canvas { ctx, size in
                    let t = tl.date.timeIntervalSinceReferenceDate
                    for e in embers {
                        let p = (e.phase + t * e.speed).truncatingRemainder(dividingBy: 1)
                        let y = size.height * (1 - p)
                        let x = size.width * e.x + sin(t * 0.6 + e.phase * 6) * 14
                        let alpha = sin(p * .pi) * 0.55
                        ctx.fill(Path(ellipseIn: CGRect(x: x, y: y, width: e.size, height: e.size)), with: .color(e.color.opacity(alpha)))
                    }
                }
            }
            .allowsHitTesting(false)
        }
    }
}

struct AppBackground: View {
    var body: some View {
        ZStack {
            Theme.bg
            RadialGradient(colors: [Theme.enemy.opacity(0.16), .clear], center: .init(x: 0.85, y: -0.05), startRadius: 10, endRadius: 520)
            RadialGradient(colors: [Theme.ally.opacity(0.08), .clear], center: .init(x: -0.1, y: 1.05), startRadius: 10, endRadius: 480)
            EmberField().opacity(0.8)
        }
        .ignoresSafeArea()
    }
}

struct SeededGenerator: RandomNumberGenerator {
    private var state: UInt64
    init(seed: UInt64) { state = seed == 0 ? 0x9E3779B97F4A7C15 : seed }
    mutating func next() -> UInt64 {
        state ^= state << 13; state ^= state >> 7; state ^= state << 17
        return state
    }
}

enum Haptics {
    static func pick() { UIImpactFeedbackGenerator(style: .medium).impactOccurred() }
    static func light() { UISelectionFeedbackGenerator().selectionChanged() }
    static func success() { UINotificationFeedbackGenerator().notificationOccurred(.success) }
}
