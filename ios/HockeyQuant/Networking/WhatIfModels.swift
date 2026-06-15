import Foundation

/// Per-team levers sent to the what-if endpoint.
struct WhatIfTeamOverride: Encodable {
    var goalie: String?        // "starter" | "backup"
    var fatigueMult: Double?
    var injuryMult: Double?
    var stMult: Double?
}

struct WhatIfRequest: Encodable {
    let away: String
    let home: String
    var awayOverrides: WhatIfTeamOverride?
    var homeOverrides: WhatIfTeamOverride?
}

/// The resolved factor values used for a team (the client inits its sliders from these).
struct WhatIfFactors: Decodable, Hashable {
    let goalie: String?
    let backupGoalie: String?
    let goalieGsax: Double
    let backupGoalieGsax: Double?
    let fatigueMult: Double
    let injuryMult: Double
    let stMult: Double
}

struct WhatIfApplied: Decodable { let away: WhatIfFactors; let home: WhatIfFactors }

/// Expected goals for a matchup in both home orientations (Monte-Carlo input).
struct SimOrientation: Decodable, Hashable { let aXg: Double; let bXg: Double }
struct SimInputs: Decodable {
    let a: String          // away team
    let b: String          // home team
    let aHome: SimOrientation
    let bHome: SimOrientation
}

struct WhatIfResult: Decodable {
    let awayTeam: String
    let homeTeam: String
    let awayXg: Double
    let homeXg: Double
    let total: Double
    let margin: Double
    let mlAwayProb: Double
    let mlHomeProb: Double
    let puckLine: Double
    let puckLineHomeCoverProb: Double
    let overUnder: Double
    let overProb: Double
    let underProb: Double
    let applied: WhatIfApplied
}
