import SwiftUI

/// Fast draft entry: type or tap a hero, it drops into the target slot and the picker moves to the next empty one.
struct HeroPickerSheet: View {
    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss
    @State private var target: Slot?
    @State private var query = ""
    @State private var attr: String?
    @FocusState private var focused: Bool

    init(start: Slot, query: String = "") {
        _target = State(initialValue: start)
        _query = State(initialValue: query)
    }

    var body: some View {
        let s = app.state
        let taken = s.taken
        let results = filtered()

        NavigationStack {
            VStack(spacing: 10) {
                miniBoard(s)
                searchBar(best: results.first(where: { !taken.contains($0.id) }))
                attrFilter
                ScrollView {
                    if results.isEmpty {
                        Text("No hero matches “\(query)”").font(.subheadline).foregroundStyle(Theme.muted).padding(.top, 30)
                    }
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 78), spacing: 8)], spacing: 10) {
                        ForEach(results) { h in
                            let isTaken = taken.contains(h.id)
                            Button { choose(h.id) } label: {
                                VStack(spacing: 4) {
                                    GeometryReader { g in Portrait(hero: h, height: g.size.width * 9 / 16) }
                                        .aspectRatio(16 / 9, contentMode: .fit)
                                        .overlay(alignment: .bottom) {
                                            Rectangle().fill(Theme.attr(h.attr)).frame(height: 2)
                                        }
                                        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                                    Text(h.name).font(.system(size: 10, weight: .medium)).foregroundStyle(Theme.text)
                                        .lineLimit(1).minimumScaleFactor(0.8)
                                }
                                .opacity(isTaken ? 0.25 : 1)
                            }
                            .buttonStyle(.plain)
                            .disabled(isTaken || target == nil)
                            .accessibilityLabel(h.name + (isTaken ? ", already in the draft" : ""))
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 20)
                }
                .scrollDismissesKeyboard(.immediately)
            }
            .padding(.top, 6)
            .background(Theme.bg.ignoresSafeArea())
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() }.tint(Theme.gold) }
                if let t = target, app.state[t] != nil {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Remove", role: .destructive) {
                            app.state[t] = nil
                            Haptics.light()
                        }
                        .tint(Theme.enemy)
                    }
                }
            }
        }
        .onAppear { focused = true }
    }

    private var title: String {
        guard let t = target else { return "Draft complete" }
        let n = t.index + 1
        switch t.team {
        case .ally: return "Your team · slot \(n)"
        case .enemy: return "Enemy · slot \(n)"
        case .ban: return "Ban · slot \(n)"
        }
    }

    private func filtered() -> [Hero] {
        searchHeroes(app.data.heroes, query, attr: attr)
    }

    private func choose(_ id: Int) {
        guard let t = target, !app.state.taken.contains(id) else { return }
        app.state[t] = id
        Haptics.pick()
        query = ""
        target = app.state.nextEmpty(after: t)
        if target == nil { dismiss() }
    }

    private func searchBar(best: Hero?) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass").foregroundStyle(Theme.muted)
            TextField("Type a hero… (pa, sf, am)", text: $query)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .submitLabel(.done)
                .focused($focused)
                .onSubmit {
                    if let best { choose(best.id) }
                    focused = true
                }
                .foregroundStyle(Theme.text)
            if !query.isEmpty {
                Button { query = "" } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(Theme.muted) }
                    .accessibilityLabel("Clear search")
            }
        }
        .padding(10)
        .background(Theme.panelHi, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .padding(.horizontal, 16)
    }

    private var attrFilter: some View {
        HStack(spacing: 6) {
            ForEach(["str", "agi", "int", "all"], id: \.self) { a in
                let on = attr == a
                Button {
                    attr = on ? nil : a
                    Haptics.light()
                } label: {
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
    }

    /// Both teams (or the ban row) in miniature; tap a slot to retarget.
    private func miniBoard(_ s: DraftState) -> some View {
        let teams: [Team] = target?.team == .ban ? [.ban] : [.ally, .enemy]
        return VStack(spacing: 6) {
            ForEach(teams, id: \.self) { team in
                let tint = team == .ally ? Theme.ally : team == .enemy ? Theme.enemy : Theme.ban
                HStack(spacing: 4) {
                    ForEach(0..<DraftState.size[team]!, id: \.self) { i in
                        let slot = Slot(team: team, index: i)
                        let on = target == slot
                        Button {
                            target = slot
                            Haptics.light()
                        } label: {
                            ZStack {
                                RoundedRectangle(cornerRadius: 5).fill(Color.white.opacity(0.04))
                                if let id = s[slot], let h = app.hero(id) {
                                    GeometryReader { g in Portrait(hero: h, height: g.size.height) }
                                }
                            }
                            .aspectRatio(16 / 9, contentMode: .fit)
                            .overlay(RoundedRectangle(cornerRadius: 5).strokeBorder(on ? Theme.gold : tint.opacity(0.4), lineWidth: on ? 2 : 1))
                            .frame(maxWidth: team == .ban ? 40 : 60)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("\(team.rawValue) slot \(i + 1)\(on ? ", selected" : "")")
                    }
                }
            }
        }
        .padding(.horizontal, 16)
    }
}
