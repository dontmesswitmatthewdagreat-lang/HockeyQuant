import Foundation

/// Typed client for the HockeyQuant FastAPI backend.
/// Mirrors the endpoints used by the web client (`frontend/src/api.js`).
/// Prediction math stays server-side — the app is purely a client.
struct APIClient: Sendable {

    enum Environment: Sendable {
        case production
        case local

        var baseURL: URL {
            switch self {
            case .production: return URL(string: "https://hockeyquant.onrender.com")!
            case .local: return URL(string: "http://localhost:8000")!
            }
        }
    }

    enum APIError: LocalizedError {
        case badStatus(Int)
        case noGames
        case decoding(String)
        case transport(String)
        case message(String)

        var errorDescription: String? {
            switch self {
            case .badStatus(let code): return "Server returned \(code)."
            case .noGames: return "No games scheduled for this date."
            case .decoding(let detail): return "Couldn't read the response. \(detail)"
            case .transport(let detail): return detail
            case .message(let detail): return detail
            }
        }
    }

    let environment: Environment
    private let session: URLSession

    init(environment: Environment = .production) {
        self.environment = environment
        let config = URLSessionConfiguration.default
        // Render free tier can cold-start (30–60s); give requests room.
        config.timeoutIntervalForRequest = 90
        config.waitsForConnectivity = true
        self.session = URLSession(configuration: config)
    }

    private static let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.keyDecodingStrategy = .convertFromSnakeCase
        return d
    }()

    private static let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.keyEncodingStrategy = .convertToSnakeCase
        return e
    }()

    // MARK: - Predictions

    /// `GET /api/predictions/{date}` — full game predictions for a date.
    func predictions(for date: Date) async throws -> PredictionsResponse {
        try await predictions(dateString: Self.apiDateString(date))
    }

    func predictions(dateString: String) async throws -> PredictionsResponse {
        let url = environment.baseURL
            .appendingPathComponent("api")
            .appendingPathComponent("predictions")
            .appendingPathComponent(dateString)
        return try await get(url, as: PredictionsResponse.self, treat404As: APIError.noGames)
    }

    /// `GET /api/games/{date}/scores` — live/final scores for a date.
    func scores(forDate dateString: String) async throws -> [GameScore] {
        let url = environment.baseURL
            .appendingPathComponent("api")
            .appendingPathComponent("games")
            .appendingPathComponent(dateString)
            .appendingPathComponent("scores")
        return try await get(url, as: ScoresResponse.self).games
    }

    // MARK: - Teams

    /// `GET /api/teams` — all teams with standings.
    func teams() async throws -> [TeamListItem] {
        let url = environment.baseURL
            .appendingPathComponent("api")
            .appendingPathComponent("teams")
        return try await get(url, as: [TeamListItem].self)
    }

    /// `GET /api/teams/{abbrev}` — detailed team stats.
    func teamDetail(_ abbrev: String) async throws -> TeamDetailResponse {
        let url = environment.baseURL
            .appendingPathComponent("api")
            .appendingPathComponent("teams")
            .appendingPathComponent(abbrev)
        return try await get(url, as: TeamDetailResponse.self)
    }

    // MARK: - Accuracy

    /// `GET /api/accuracy/stats` — overall accuracy stats + recent results.
    func accuracyStats() async throws -> AccuracyResponse {
        let url = environment.baseURL
            .appendingPathComponent("api")
            .appendingPathComponent("accuracy")
            .appendingPathComponent("stats")
        return try await get(url, as: AccuracyResponse.self)
    }

    /// `GET /api/accuracy/trend` — rolling + cumulative accuracy for charting.
    func trend(window: Int = 30) async throws -> TrendResponse {
        var components = URLComponents(
            url: environment.baseURL
                .appendingPathComponent("api")
                .appendingPathComponent("accuracy")
                .appendingPathComponent("trend"),
            resolvingAgainstBaseURL: false
        )!
        components.queryItems = [
            URLQueryItem(name: "window", value: String(window)),
            URLQueryItem(name: "prediction_type", value: "moneyline"),
        ]
        return try await get(components.url!, as: TrendResponse.self)
    }

    /// `GET /api/accuracy/parlay-stats` — historical parlay hit rate.
    func parlayStats() async throws -> ParlayStats {
        let url = environment.baseURL
            .appendingPathComponent("api")
            .appendingPathComponent("accuracy")
            .appendingPathComponent("parlay-stats")
        return try await get(url, as: ParlayStats.self)
    }

    // MARK: - Custom models

    /// `GET /api/models` (auth) — the user's models.
    func models(token: String) async throws -> [UserModel] {
        let url = apiURL("models")
        let data = try await perform("GET", url, token: token, body: Optional<Int>.none)
        return try Self.decode(ModelsListResponse.self, from: data).models
    }

    /// `POST /api/models` (auth) — create a model.
    func createModel(_ request: CreateModelRequest, token: String) async throws -> UserModel {
        let data = try await perform("POST", apiURL("models"), token: token, body: request)
        return try Self.decode(UserModel.self, from: data)
    }

    /// `PUT /api/models/{id}` (auth) — update a model.
    func updateModel(id: String, _ request: CreateModelRequest, token: String) async throws -> UserModel {
        let url = apiURL("models").appendingPathComponent(id)
        let data = try await perform("PUT", url, token: token, body: request)
        return try Self.decode(UserModel.self, from: data)
    }

    /// `DELETE /api/models/{id}` (auth).
    func deleteModel(id: String, token: String) async throws {
        let url = apiURL("models").appendingPathComponent(id)
        _ = try await perform("DELETE", url, token: token, body: Optional<Int>.none)
    }

    /// `GET /api/models/{id}/predictions/{date}` (auth) — the model's picks for a date.
    func modelPredictions(modelId: String, dateString: String, token: String) async throws -> ModelPredictionsResponse {
        let url = apiURL("models")
            .appendingPathComponent(modelId)
            .appendingPathComponent("predictions")
            .appendingPathComponent(dateString)
        let data = try await perform("GET", url, token: token, body: Optional<Int>.none)
        return try Self.decode(ModelPredictionsResponse.self, from: data)
    }

    /// `GET /api/models/leaderboard` — public model leaderboard.
    func modelsLeaderboard() async throws -> [ModelLeaderboardEntry] {
        let url = apiURL("models").appendingPathComponent("leaderboard")
        let data = try await perform("GET", url, token: nil, body: Optional<Int>.none)
        return try Self.decode([ModelLeaderboardEntry].self, from: data)
    }

    private func apiURL(_ path: String) -> URL {
        environment.baseURL.appendingPathComponent("api").appendingPathComponent(path)
    }

    private static func decode<T: Decodable>(_ type: T.Type, from data: Data) throws -> T {
        do { return try decoder.decode(T.self, from: data) }
        catch {
            Log.error("Decoding \(T.self) failed", error)
            throw APIError.decoding(String(describing: error))
        }
    }

    /// Core request with optional bearer auth + JSON body.
    private func perform<Body: Encodable>(
        _ method: String, _ url: URL, token: String?, body: Body?
    ) async throws -> Data {
        Log.request(method, url)
        var request = URLRequest(url: url)
        request.httpMethod = method
        if let token { request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }
        if let body {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try? Self.encoder.encode(body)
        }

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            Log.error("Transport failure", error)
            throw APIError.transport(error.localizedDescription)
        }

        let status = (response as? HTTPURLResponse)?.statusCode ?? -1
        Log.response(status, url, bytes: data.count)
        guard (200..<300).contains(status) else {
            // Surface the backend's error detail when present.
            if let detail = try? Self.decoder.decode(ErrorDetail.self, from: data) {
                throw APIError.message(detail.detail)
            }
            throw APIError.badStatus(status)
        }
        return data
    }

    private struct ErrorDetail: Decodable { let detail: String }

    // MARK: - AI summary

    /// `POST /api/summary` — AI "Why [team]?" explanation for a prediction.
    func summary(for game: GamePrediction) async throws -> String {
        let url = environment.baseURL
            .appendingPathComponent("api")
            .appendingPathComponent("summary")
        return try await post(url, body: SummaryRequest(game: game), as: SummaryResponse.self).summary
    }

    /// Pre-warm the backend to mitigate Render cold starts. Fire-and-forget.
    func warmUp() async {
        let url = environment.baseURL.appendingPathComponent("health")
        Log.request("GET", url)
        _ = try? await session.data(from: url)
    }

    // MARK: - Core request

    private func get<T: Decodable>(
        _ url: URL,
        as type: T.Type,
        treat404As notFoundError: APIError? = nil
    ) async throws -> T {
        Log.request("GET", url)
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(from: url)
        } catch {
            Log.error("Transport failure", error)
            throw APIError.transport(error.localizedDescription)
        }

        let status = (response as? HTTPURLResponse)?.statusCode ?? -1
        Log.response(status, url, bytes: data.count)

        if status == 404, let notFoundError { throw notFoundError }
        guard (200..<300).contains(status) else { throw APIError.badStatus(status) }

        do {
            return try Self.decoder.decode(T.self, from: data)
        } catch {
            Log.error("Decoding \(T.self) failed", error)
            throw APIError.decoding(String(describing: error))
        }
    }

    private func post<Body: Encodable, T: Decodable>(
        _ url: URL,
        body: Body,
        as type: T.Type
    ) async throws -> T {
        Log.request("POST", url)
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        do {
            request.httpBody = try Self.encoder.encode(body)
        } catch {
            throw APIError.decoding("Failed to encode request body.")
        }

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            Log.error("Transport failure", error)
            throw APIError.transport(error.localizedDescription)
        }

        let status = (response as? HTTPURLResponse)?.statusCode ?? -1
        Log.response(status, url, bytes: data.count)
        guard (200..<300).contains(status) else { throw APIError.badStatus(status) }

        do {
            return try Self.decoder.decode(T.self, from: data)
        } catch {
            Log.error("Decoding \(T.self) failed", error)
            throw APIError.decoding(String(describing: error))
        }
    }

    // MARK: - Helpers

    private static let apiDateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .gregorian)
        f.locale = Locale(identifier: "en_US_POSIX")
        // NHL API uses ET dates; the backend keys cache by ET date string.
        f.timeZone = TimeZone(identifier: "America/New_York")
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    static func apiDateString(_ date: Date) -> String {
        apiDateFormatter.string(from: date)
    }
}

// MARK: - Fantasy League

extension APIClient {

    private func fantasyURL(_ path: String) -> URL {
        apiURL("fantasy").appendingPathComponent(path)
    }

    /// `POST /api/what-if` — re-run the goal model with overridden inputs.
    func whatIf(_ request: WhatIfRequest) async throws -> WhatIfResult {
        let data = try await perform("POST", apiURL("what-if"), token: nil, body: request)
        return try Self.decode(WhatIfResult.self, from: data)
    }

    /// `GET /api/accuracy/ml-model` — train a model (logistic|boosted) on the features.
    func mlModel(features: [String], model: String = "logistic") async throws -> MLModelResponse {
        var comps = URLComponents(url: apiURL("accuracy").appendingPathComponent("ml-model"), resolvingAgainstBaseURL: false)!
        var items = [URLQueryItem(name: "model", value: model)]
        if !features.isEmpty { items.append(URLQueryItem(name: "features", value: features.joined(separator: ","))) }
        comps.queryItems = items
        let data = try await perform("GET", comps.url!, token: nil, body: Optional<Int>.none)
        return try Self.decode(MLModelResponse.self, from: data)
    }

    /// `POST /api/accuracy/ml-model/save` — train + save an ML model to the leaderboard.
    func createMLModel(name: String, features: [String], model: String, token: String) async throws -> MLSaveResponse {
        struct Req: Encodable { let name: String; let features: [String]; let model: String }
        let url = apiURL("accuracy").appendingPathComponent("ml-model").appendingPathComponent("save")
        let data = try await perform("POST", url, token: token, body: Req(name: name, features: features, model: model))
        return try Self.decode(MLSaveResponse.self, from: data)
    }

    /// `GET /api/accuracy/backtest-data` — graded picks enriched with factor edges.
    func backtestData() async throws -> BacktestData {
        let url = apiURL("accuracy").appendingPathComponent("backtest-data")
        let data = try await perform("GET", url, token: nil, body: Optional<Int>.none)
        return try Self.decode(BacktestData.self, from: data)
    }

    /// `GET /api/accuracy/calibration` — reliability of the model's win probabilities.
    func calibration() async throws -> CalibrationResponse {
        let url = apiURL("accuracy").appendingPathComponent("calibration")
        let data = try await perform("GET", url, token: nil, body: Optional<Int>.none)
        return try Self.decode(CalibrationResponse.self, from: data)
    }

    /// `GET /api/season-sim` — season/playoff odds (mock=true forces a demo season).
    func seasonSim(mock: Bool) async throws -> SeasonProjection {
        var comps = URLComponents(url: apiURL("season-sim"), resolvingAgainstBaseURL: false)!
        comps.queryItems = [URLQueryItem(name: "mock", value: mock ? "true" : "false")]
        let data = try await perform("GET", comps.url!, token: nil, body: Optional<Int>.none)
        return try Self.decode(SeasonProjection.self, from: data)
    }

    /// `GET /api/sim-inputs` — matchup expected goals for both home orientations.
    func simInputs(away: String, home: String) async throws -> SimInputs {
        var comps = URLComponents(url: apiURL("sim-inputs"), resolvingAgainstBaseURL: false)!
        comps.queryItems = [URLQueryItem(name: "away", value: away), URLQueryItem(name: "home", value: home)]
        let data = try await perform("GET", comps.url!, token: nil, body: Optional<Int>.none)
        return try Self.decode(SimInputs.self, from: data)
    }

    /// `GET /api/shot-map` — shots for a game (by date + team abbrevs).
    func shotMap(date: String, away: String, home: String) async throws -> GameShotMap {
        var comps = URLComponents(url: apiURL("shot-map"), resolvingAgainstBaseURL: false)!
        comps.queryItems = [
            URLQueryItem(name: "date", value: date),
            URLQueryItem(name: "away", value: away),
            URLQueryItem(name: "home", value: home),
        ]
        let data = try await perform("GET", comps.url!, token: nil, body: Optional<Int>.none)
        return try Self.decode(GameShotMap.self, from: data)
    }

    /// `GET /api/team-shot-map` — a team's shots over its recent games.
    func teamShotMap(team: String, games: Int = 15) async throws -> TeamShotMap {
        var comps = URLComponents(url: apiURL("team-shot-map"), resolvingAgainstBaseURL: false)!
        comps.queryItems = [URLQueryItem(name: "team", value: team), URLQueryItem(name: "games", value: "\(games)")]
        let data = try await perform("GET", comps.url!, token: nil, body: Optional<Int>.none)
        return try Self.decode(TeamShotMap.self, from: data)
    }

    // MARK: - Pick'em friend leagues

    private func pickemURL(_ path: String) -> URL {
        apiURL("pickem").appendingPathComponent(path)
    }

    private struct CreatePickemBody: Encodable { let name: String }
    private struct JoinPickemBody: Encodable { let inviteCode: String }

    func pickemLeagues(token: String) async throws -> [PickemLeague] {
        let data = try await perform("GET", pickemURL("leagues"), token: token, body: Optional<Int>.none)
        return try Self.decode(PickemLeaguesResponse.self, from: data).leagues
    }

    func createPickemLeague(name: String, token: String) async throws -> PickemLeague {
        let data = try await perform("POST", pickemURL("leagues"), token: token, body: CreatePickemBody(name: name))
        return try Self.decode(PickemLeague.self, from: data)
    }

    func joinPickemLeague(code: String, token: String) async throws -> PickemLeague {
        let url = pickemURL("leagues").appendingPathComponent("join")
        let data = try await perform("POST", url, token: token, body: JoinPickemBody(inviteCode: code))
        return try Self.decode(PickemLeague.self, from: data)
    }

    func pickemLeague(id: String, token: String) async throws -> PickemLeagueDetail {
        let url = pickemURL("leagues").appendingPathComponent(id)
        let data = try await perform("GET", url, token: token, body: Optional<Int>.none)
        return try Self.decode(PickemLeagueDetail.self, from: data)
    }

    /// `GET /api/fantasy/players` — the draftable player pool (optionally filtered).
    func fantasyPlayers(slotType: String? = nil, query: String? = nil) async throws -> [FantasyPlayer] {
        var comps = URLComponents(
            url: fantasyURL("players"), resolvingAgainstBaseURL: false
        )!
        var items: [URLQueryItem] = []
        if let slotType { items.append(.init(name: "slot_type", value: slotType)) }
        if let query, !query.isEmpty { items.append(.init(name: "q", value: query)) }
        if !items.isEmpty { comps.queryItems = items }
        let data = try await perform("GET", comps.url!, token: nil, body: Optional<Int>.none)
        return try Self.decode(FantasyPlayersResponse.self, from: data).players
    }

    /// `GET /api/fantasy/leagues` — the user's leagues.
    func myLeagues(token: String) async throws -> [FantasyLeagueSummary] {
        let data = try await perform("GET", fantasyURL("leagues"), token: token, body: Optional<Int>.none)
        return try Self.decode(MyLeaguesResponse.self, from: data).leagues
    }

    /// `POST /api/fantasy/leagues` — create a league.
    func createLeague(name: String, teamName: String, leagueType: String, mode: String, cpuCount: Int, maxMembers: Int, draftPace: String, token: String) async throws -> FantasyLeagueSummary {
        let body = CreateLeagueBody(name: name, teamName: teamName, leagueType: leagueType, mode: mode, cpuCount: cpuCount, maxMembers: maxMembers, draftPace: draftPace)
        let data = try await perform("POST", fantasyURL("leagues"), token: token, body: body)
        return try Self.decode(FantasyLeagueSummary.self, from: data)
    }

    /// `POST /api/fantasy/leagues/join` — join by invite code.
    func joinLeague(inviteCode: String, teamName: String, token: String) async throws -> FantasyLeagueSummary {
        let body = JoinLeagueBody(inviteCode: inviteCode, teamName: teamName)
        let url = fantasyURL("leagues").appendingPathComponent("join")
        let data = try await perform("POST", url, token: token, body: body)
        return try Self.decode(FantasyLeagueSummary.self, from: data)
    }

    /// `GET /api/fantasy/leagues/{id}` — lobby detail (members + draft status).
    func leagueDetail(_ id: String, token: String) async throws -> LeagueDetail {
        let url = fantasyURL("leagues").appendingPathComponent(id)
        let data = try await perform("GET", url, token: token, body: Optional<Int>.none)
        return try Self.decode(LeagueDetail.self, from: data)
    }

    /// `POST /api/fantasy/leagues/{id}/start-draft` (commissioner).
    func startDraft(_ id: String, token: String) async throws -> DraftResponse {
        let url = fantasyURL("leagues").appendingPathComponent(id).appendingPathComponent("start-draft")
        let data = try await perform("POST", url, token: token, body: Optional<Int>.none)
        return try Self.decode(DraftResponse.self, from: data)
    }

    /// `POST /api/fantasy/leagues/{id}/start-offseason` (commissioner) — reset into the
    /// off-season build phase (random starter rosters + Cap Space carryover).
    func startOffseason(_ id: String, token: String) async throws -> FantasyLeagueSummary {
        let url = fantasyURL("leagues").appendingPathComponent(id).appendingPathComponent("start-offseason")
        let data = try await perform("POST", url, token: token, body: Optional<Int>.none)
        return try Self.decode(FantasyLeagueSummary.self, from: data)
    }

    /// `POST /api/fantasy/leagues/{id}/lottery/run` (commissioner) — run the weighted
    /// draft lottery; returns the odds + suspense reveal sequence.
    func runLottery(_ id: String, token: String) async throws -> LotteryResult {
        let url = fantasyURL("leagues").appendingPathComponent(id).appendingPathComponent("lottery").appendingPathComponent("run")
        let data = try await perform("POST", url, token: token, body: Optional<Int>.none)
        return try Self.decode(LotteryResult.self, from: data)
    }

    /// `GET /api/fantasy/leagues/{id}/draft` — live draft state + board.
    func draftState(_ id: String, token: String) async throws -> DraftResponse {
        let url = fantasyURL("leagues").appendingPathComponent(id).appendingPathComponent("draft")
        let data = try await perform("GET", url, token: token, body: Optional<Int>.none)
        return try Self.decode(DraftResponse.self, from: data)
    }

    /// `POST /api/fantasy/leagues/{id}/draft/pick` — make the on-the-clock pick.
    func makePick(_ id: String, playerId: String, token: String) async throws -> DraftResponse {
        let url = fantasyURL("leagues").appendingPathComponent(id).appendingPathComponent("draft").appendingPathComponent("pick")
        let data = try await perform("POST", url, token: token, body: PickBody(playerId: playerId))
        return try Self.decode(DraftResponse.self, from: data)
    }

    /// `POST /api/fantasy/leagues/{id}/draft/autopick` — auto-pick for the clock.
    /// `expectedPick` makes expiry-driven auto-picks idempotent across clients.
    func autopick(_ id: String, expectedPick: Int? = nil, token: String) async throws -> DraftResponse {
        var comps = URLComponents(
            url: fantasyURL("leagues").appendingPathComponent(id).appendingPathComponent("draft").appendingPathComponent("autopick"),
            resolvingAgainstBaseURL: false
        )!
        if let expectedPick { comps.queryItems = [URLQueryItem(name: "expected_pick", value: String(expectedPick))] }
        let data = try await perform("POST", comps.url!, token: token, body: Optional<Int>.none)
        return try Self.decode(DraftResponse.self, from: data)
    }

    /// `GET /api/fantasy/leagues/{id}/season` — standings, roster, schedule.
    func season(_ id: String, token: String) async throws -> FantasySeasonResponse {
        let url = fantasyURL("leagues").appendingPathComponent(id).appendingPathComponent("season")
        let data = try await perform("GET", url, token: token, body: Optional<Int>.none)
        return try Self.decode(FantasySeasonResponse.self, from: data)
    }

    /// `POST /api/fantasy/leagues/{id}/simulate-week/{week}` — offseason test scoring.
    func simulateWeek(_ id: String, week: Int, token: String) async throws {
        let url = fantasyURL("leagues").appendingPathComponent(id)
            .appendingPathComponent("simulate-week").appendingPathComponent(String(week))
        _ = try await perform("POST", url, token: token, body: Optional<Int>.none)
    }

    // MARK: Playoffs

    func startPlayoffs(_ id: String, token: String) async throws {
        let url = fantasyURL("leagues").appendingPathComponent(id).appendingPathComponent("start-playoffs")
        _ = try await perform("POST", url, token: token, body: Optional<Int>.none)
    }

    func advancePlayoffs(_ id: String, token: String) async throws {
        let url = fantasyURL("leagues").appendingPathComponent(id).appendingPathComponent("advance-playoffs")
        _ = try await perform("POST", url, token: token, body: Optional<Int>.none)
    }

    // MARK: Trades

    func leagueRosters(_ id: String, token: String) async throws -> [DraftMember] {
        let url = fantasyURL("leagues").appendingPathComponent(id).appendingPathComponent("rosters")
        let data = try await perform("GET", url, token: token, body: Optional<Int>.none)
        struct R: Codable { let rosters: [DraftMember] }
        return try Self.decode(R.self, from: data).rosters
    }

    func trades(_ id: String, token: String) async throws -> [TradeItem] {
        let url = fantasyURL("leagues").appendingPathComponent(id).appendingPathComponent("trades")
        let data = try await perform("GET", url, token: token, body: Optional<Int>.none)
        return try Self.decode(TradesResponse.self, from: data).trades
    }

    func proposeTrade(_ id: String, toMemberId: String, myPlayerId: String, theirPlayerId: String, token: String) async throws {
        let url = fantasyURL("leagues").appendingPathComponent(id).appendingPathComponent("trades")
        _ = try await perform("POST", url, token: token, body: ProposeTradeBody(toMemberId: toMemberId, myPlayerId: myPlayerId, theirPlayerId: theirPlayerId))
    }

    /// `POST /api/fantasy/leagues/{id}/offseason/trade` — propose an off-season trade
    /// (player + optional Cap Space for a same-position player); CPU accepts if fair.
    func offseasonTrade(_ id: String, toMemberId: String, myPlayerId: String, theirPlayerId: String, myCap: Int, token: String) async throws -> TradeResult {
        let url = fantasyURL("leagues").appendingPathComponent(id).appendingPathComponent("offseason").appendingPathComponent("trade")
        let data = try await perform("POST", url, token: token, body: OffseasonTradeBody(toMemberId: toMemberId, myPlayerId: myPlayerId, theirPlayerId: theirPlayerId, myCap: myCap))
        return try Self.decode(TradeResult.self, from: data)
    }

    func respondTrade(_ id: String, tradeId: String, accept: Bool, token: String) async throws {
        let url = fantasyURL("leagues").appendingPathComponent(id).appendingPathComponent("trades").appendingPathComponent(tradeId).appendingPathComponent("respond")
        _ = try await perform("POST", url, token: token, body: RespondTradeBody(accept: accept))
    }

    // MARK: Global league

    func globalLeague(token: String) async throws -> GlobalResponse {
        let data = try await perform("GET", fantasyURL("global"), token: token, body: Optional<Int>.none)
        return try Self.decode(GlobalResponse.self, from: data)
    }

    func globalJoin(teamName: String, token: String) async throws -> FantasyLeagueSummary {
        let url = fantasyURL("global").appendingPathComponent("join")
        let data = try await perform("POST", url, token: token, body: JoinLeagueBody(inviteCode: "GLOBAL", teamName: teamName))
        return try Self.decode(FantasyLeagueSummary.self, from: data)
    }

    func globalSetSlot(slot: String, playerId: String, token: String) async throws {
        let url = fantasyURL("global").appendingPathComponent("roster")
        _ = try await perform("POST", url, token: token, body: SetSlotBody(slot: slot, playerId: playerId))
    }

    func globalLeaderboard(token: String) async throws -> [GlobalLeaderboardRow] {
        let url = fantasyURL("global").appendingPathComponent("leaderboard")
        let data = try await perform("GET", url, token: token, body: Optional<Int>.none)
        return try Self.decode(GlobalLeaderboardResponse.self, from: data).leaderboard
    }

    func cupMatchup(token: String) async throws -> CupMatchupResponse {
        let url = fantasyURL("cup").appendingPathComponent("my-matchup")
        let data = try await perform("GET", url, token: token, body: Optional<Int>.none)
        return try Self.decode(CupMatchupResponse.self, from: data)
    }

    /// `GET /api/news/latest` — the league morning digest + the team's recent digests.
    func newsLatest(team: String?) async throws -> [NewsDigest] {
        var comps = URLComponents(
            url: apiURL("news").appendingPathComponent("latest"), resolvingAgainstBaseURL: false
        )!
        if let team, !team.isEmpty { comps.queryItems = [URLQueryItem(name: "team", value: team)] }
        let data = try await perform("GET", comps.url!, token: nil, body: Optional<Int>.none)
        return try Self.decode(NewsLatestResponse.self, from: data).digests
    }

    /// `GET /api/news/search` — AI answer from live news + matches from past digests.
    func newsSearch(query: String) async throws -> NewsSearchResponse {
        var comps = URLComponents(url: apiURL("news").appendingPathComponent("search"), resolvingAgainstBaseURL: false)!
        comps.queryItems = [URLQueryItem(name: "q", value: query)]
        let data = try await perform("GET", comps.url!, token: nil, body: Optional<Int>.none)
        return try Self.decode(NewsSearchResponse.self, from: data)
    }

    /// `GET /api/prospects` — team pool (by abbrev) or the league notable board.
    func prospects(team: String?) async throws -> [Prospect] {
        var comps = URLComponents(url: apiURL("prospects"), resolvingAgainstBaseURL: false)!
        if let team, !team.isEmpty { comps.queryItems = [URLQueryItem(name: "team", value: team)] }
        let data = try await perform("GET", comps.url!, token: nil, body: Optional<Int>.none)
        return try Self.decode(ProspectsResponse.self, from: data).prospects
    }

    /// `GET /api/prospects/mock-draft` — the latest weekly first-round mock draft.
    func mockDraft() async throws -> MockDraft? {
        let url = apiURL("prospects").appendingPathComponent("mock-draft")
        let data = try await perform("GET", url, token: nil, body: Optional<Int>.none)
        return try Self.decode(MockDraftResponse.self, from: data).mockDraft
    }

    /// `POST /api/me/device-token` — register this device's APNs token.
    func registerDeviceToken(_ token: String, authToken: String) async throws {
        let url = apiURL("me").appendingPathComponent("device-token")
        _ = try await perform("POST", url, token: authToken, body: DeviceTokenBody(token: token, platform: "ios"))
    }
}
