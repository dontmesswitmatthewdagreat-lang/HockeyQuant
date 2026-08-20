import Foundation
import Observation

/// Slots a club's roster into a real lineup, then lets you drop a drafted
/// prospect into it and see who he pushes down.
///
/// Lines are built by `fantasy_players.cost`, which across this app is the
/// standing proxy for how good a player is (it's derived from production). That
/// keeps one definition of "better" between the draft board, franchise card
/// rarity and this screen, instead of inventing a third.
///
/// Handedness is respected: LHD players fill the left side of a pair and RHD
/// the right, because a defence pair that ignores it isn't a pair a coach would
/// ever dress.
@MainActor
@Observable
final class LineupBuilder {

    /// One position in the lineup. `id` doubles as the display label.
    struct Slot: Identifiable, Hashable {
        let id: String              // "L1-LW", "D2-RD", "G1"
        let group: Group
        let rosterPos: String       // LW | C | RW | LHD | RHD | G
        let unit: Int               // line or pair number, 1-based

        enum Group: String { case forward, defense, goalie }

        var label: String {
            switch rosterPos {
            case "LHD": "LD"
            case "RHD": "RD"
            default: rosterPos
            }
        }
    }

    /// A player in the lineup — either on the roster or one you just drafted.
    struct Skater: Identifiable, Hashable {
        let id: String
        let name: String
        let rosterPos: String
        let cost: Int
        let headshot: String?
        let isDraftPick: Bool

        var headshotURL: URL? {
            guard let headshot, !headshot.isEmpty,
                  !headshot.contains("/latest/"), !headshot.contains("default")
            else { return nil }
            return URL(string: headshot)
        }

        var initials: String {
            name.split(separator: " ").compactMap { $0.first.map(String.init) }.prefix(2).joined()
        }
    }

    static let slots: [Slot] = {
        var all: [Slot] = []
        for line in 1...4 {
            for pos in ["LW", "C", "RW"] {
                all.append(Slot(id: "L\(line)-\(pos)", group: .forward, rosterPos: pos, unit: line))
            }
        }
        for pair in 1...3 {
            for pos in ["LHD", "RHD"] {
                all.append(Slot(id: "D\(pair)-\(pos)", group: .defense, rosterPos: pos, unit: pair))
            }
        }
        all.append(Slot(id: "G1", group: .goalie, rosterPos: "G", unit: 1))
        all.append(Slot(id: "G2", group: .goalie, rosterPos: "G", unit: 2))
        return all
    }()

    private(set) var assignments: [String: Skater] = [:]      // slot id → player
    private(set) var scratched: [Skater] = []                 // roster, no slot
    private(set) var picks: [Skater] = []                     // your draft picks
    private let roster: [Skater]

    init(roster: [FantasyPlayer], draftPicks: [DraftBoardEntry]) {
        self.roster = roster.map {
            Skater(id: $0.id, name: $0.fullName, rosterPos: $0.rosterPos,
                   cost: $0.cost ?? 0, headshot: $0.headshot, isDraftPick: false)
        }
        self.picks = draftPicks.map { entry in
            Skater(id: "pick-\(entry.id)", name: entry.name,
                   rosterPos: Self.rosterPos(for: entry),
                   // A prospect has no cap value yet; the point of the screen is
                   // where you *think* he fits, so he starts unpriced and only
                   // moves if you put him somewhere.
                   cost: 0, headshot: entry.prospect.info?.headshot, isDraftPick: true)
        }
        autoFill()
    }

    /// A prospect's position, mapped onto a lineup slot. Draft boards list plain
    /// "D" with no handedness, so a defenceman defaults to the left side.
    private static func rosterPos(for entry: DraftBoardEntry) -> String {
        switch (entry.position ?? entry.group).uppercased() {
        case "G": "G"
        case "D", "LHD": "LHD"
        case "RHD": "RHD"
        case "C": "C"
        case "RW", "R": "RW"
        default: "LW"
        }
    }

    // MARK: - Building

    /// Best available into the highest open slot, position by position.
    func autoFill() {
        assignments.removeAll()
        var pool = roster.sorted { $0.cost > $1.cost }
        for slot in Self.slots {
            guard let index = pool.firstIndex(where: { $0.rosterPos == slot.rosterPos }) else { continue }
            assignments[slot.id] = pool.remove(at: index)
        }
        // A club can be short a natural RHD (or dress an extra winger); rather
        // than leave a hole, fill from the same group so the lineup is complete.
        for slot in Self.slots where assignments[slot.id] == nil {
            guard let index = pool.firstIndex(where: { Self.group(of: $0.rosterPos) == slot.group })
            else { continue }
            assignments[slot.id] = pool.remove(at: index)
        }
        scratched = pool
    }

    private static func group(of rosterPos: String) -> Slot.Group {
        switch rosterPos {
        case "G": .goalie
        case "LHD", "RHD": .defense
        default: .forward
        }
    }

    /// Slots this player is eligible for: his own position first, then anything
    /// in the same group, so a left shot can still be tried on the right side.
    func eligibleSlots(for skater: Skater) -> [Slot] {
        let group = Self.group(of: skater.rosterPos)
        return Self.slots.filter { $0.group == group }
    }

    /// Put a player in a slot. Whoever was there is scratched, and if the
    /// incoming player came from another slot that slot opens up.
    func assign(_ skater: Skater, to slot: Slot) {
        if let previous = assignments.first(where: { $0.value.id == skater.id })?.key {
            assignments[previous] = nil
        }
        if let displaced = assignments[slot.id], displaced.id != skater.id {
            if displaced.isDraftPick {
                if !picks.contains(displaced) { picks.append(displaced) }
            } else {
                scratched.insert(displaced, at: 0)
            }
        }
        scratched.removeAll { $0.id == skater.id }
        assignments[slot.id] = skater
    }

    /// Draft picks not currently dressed.
    var benchedPicks: [Skater] {
        picks.filter { pick in !assignments.values.contains { $0.id == pick.id } }
    }

    func slot(of skater: Skater) -> Slot? {
        guard let id = assignments.first(where: { $0.value.id == skater.id })?.key else { return nil }
        return Self.slots.first { $0.id == id }
    }

    // MARK: - Reading the lineup

    func players(inUnit unit: Int, group: Slot.Group) -> [(slot: Slot, skater: Skater?)] {
        Self.slots.filter { $0.group == group && $0.unit == unit }
            .map { ($0, assignments[$0.id]) }
    }

    /// A line's combined cap value — the quick read on whether a unit is a
    /// scoring line or a checking one.
    func unitValue(_ unit: Int, group: Slot.Group) -> Int {
        players(inUnit: unit, group: group).compactMap { $0.skater?.cost }.reduce(0, +)
    }

    /// Where a drafted player sits relative to the players he displaced —
    /// "2nd line" is the honest answer to "how does he fit".
    func verdict(for pick: Skater) -> String? {
        guard let slot = slot(of: pick) else { return nil }
        switch slot.group {
        case .forward: return "\(ordinal(slot.unit)) line \(slot.label)"
        case .defense: return "\(ordinal(slot.unit)) pair \(slot.label)"
        case .goalie: return slot.unit == 1 ? "Starter" : "Backup"
        }
    }

    private func ordinal(_ n: Int) -> String {
        switch n {
        case 1: "1st"
        case 2: "2nd"
        case 3: "3rd"
        default: "\(n)th"
        }
    }
}
