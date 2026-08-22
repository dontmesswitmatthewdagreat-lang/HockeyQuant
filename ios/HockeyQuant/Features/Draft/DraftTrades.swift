import Foundation

/// Trading draft picks with the AI GMs.
///
/// Everything here runs off one idea: a pick is worth what the slot is worth,
/// and slot value falls off a cliff at the top of the round. The No. 1 pick is
/// worth roughly four times the No. 10 and thirty times the last pick, which is
/// why moving up costs so much more than people expect — a flat "one spot = one
/// unit" curve would let anyone buy the top of the draft with spare change.
enum DraftTrades {

    /// A tradeable asset: either a slot in this round, or a future pick.
    enum Asset: Identifiable, Hashable {
        case pick(overall: Int)
        case future(round: Int, year: Int)

        var id: String {
            switch self {
            case .pick(let overall): "pick-\(overall)"
            case .future(let round, let year): "future-\(year)-\(round)"
            }
        }

        var label: String {
            switch self {
            case .pick(let overall): "#\(overall) overall"
            case .future(let round, let year): "\(String(year)) \(ordinal(round)) round"
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

    /// Slot value, normalized so the first pick is 1000.
    ///
    /// A shifted power law, which is the shape real pick-value charts take:
    /// steep through the top ten, then a long shallow tail. Roughly #5 ≈ 595,
    /// #16 ≈ 311, #32 ≈ 196, #64 ≈ 121.
    ///
    /// An exponential was tried first and is wrong in a way that matters: it
    /// collapses past the first round, pricing a second-rounder at ~2% of a
    /// first. That makes every future pick worthless as currency and quietly
    /// kills trading up, since nothing but this year's picks can pay for it.
    static func value(ofPick overall: Int) -> Double {
        guard overall > 0 else { return 0 }
        return 1000 * pow((Double(overall) + 3) / 4, -0.75)
    }

    /// A future pick is this year's equivalent slot, discounted for the wait and
    /// for not knowing where it will land. Mid-round is the honest guess.
    static func value(ofFutureRound round: Int) -> Double {
        let assumedSlot = (round - 1) * 32 + 16
        return value(ofPick: assumedSlot) * 0.80
    }

    static func value(of asset: Asset) -> Double {
        switch asset {
        case .pick(let overall): value(ofPick: overall)
        case .future(let round, _): value(ofFutureRound: round)
        }
    }

    static func value(of assets: [Asset]) -> Double {
        assets.reduce(0) { $0 + value(of: $1) }
    }

    /// What the AI thinks of an offer.
    struct Verdict {
        let accepted: Bool
        let message: String
        /// Received minus given, from the AI's side.
        let surplus: Double
    }

    /// The premium an AI GM wants before giving up the better pick. Moving up
    /// costs extra precisely because the team moving down has to be paid for
    /// the certainty it's giving away.
    static let acceptanceMargin = 1.06

    static func evaluate(giving userAssets: [Asset], getting aiAssets: [Asset]) -> Verdict {
        // From the AI's perspective: it receives what the user gives.
        let received = value(of: userAssets)
        let surrendered = value(of: aiAssets)
        guard !userAssets.isEmpty, !aiAssets.isEmpty else {
            return Verdict(accepted: false, message: "Put something on both sides.", surplus: 0)
        }
        let surplus = received - surrendered
        if received >= surrendered * acceptanceMargin {
            return Verdict(accepted: true, message: "Deal. That works for us.", surplus: surplus)
        }
        let shortfall = surrendered * acceptanceMargin - received
        let ratio = shortfall / max(surrendered, 1)
        let message: String
        if ratio < 0.12 {
            message = "Close. Add a little and we'll do it."
        } else if ratio < 0.4 {
            message = "Not enough — we'd be paying to move down."
        } else {
            message = "Nowhere near it. That pick isn't going anywhere cheap."
        }
        return Verdict(accepted: false, message: message, surplus: surplus)
    }
}
