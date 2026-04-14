import Foundation

// MARK: - Models

struct LiveMatch: Identifiable {
    let id: String           // match_id
    let matchId: String
    let sportId: String
    let roomId: String
    let title: String
    let homeName: String
    let awayName: String
    let homeLogo: String
    let awayLogo: String
    let homeScore: Int
    let awayScore: Int
    let competition: String
    let stage: String
    let viewers: Int
    let screenshot: String
    let isLive: Bool
}

struct MatchInfo {
    let homeName: String
    let awayName: String
    let homeScore: Int
    let awayScore: Int
    let competition: String
    let stage: String
}

struct StreamOption: Identifiable, Hashable {
    let id: String
    let name: String
    let url: String
    let loginRequired: Bool
    let sort: Int
}

struct RoomResult {
    let roomId: String
    let matchInfo: MatchInfo?
    let streams: [StreamOption]
}

// MARK: - Service

class StreamService: @unchecked Sendable {
    static let shared = StreamService()

    private let apiBase = "https://apc.j8w1d1r1p4g4q6t.cc"
    private let siteOrigin = "https://fqzb141.com"

    private lazy var session: URLSession = {
        let config = URLSessionConfiguration.default
        config.httpAdditionalHeaders = ["Referer": siteOrigin]
        return URLSession(configuration: config, delegate: TLSDelegate(), delegateQueue: nil)
    }()

    // MARK: - Home page data

    /// Fetch recommended live matches (currently broadcasting)
    func fetchLiveMatches() async throws -> [LiveMatch] {
        let url = URL(string: "\(apiBase)/v1/recommend/match")!
        let data = try await fetchJson(url: url)

        guard let dataObj = data["data"] as? [String: Any],
              let list = dataObj["list"] as? [[String: Any]] else { return [] }

        return list.compactMap { m in
            guard let matchId = m["match_id"] else { return nil }
            let title = m["room_title"] as? String ?? ""
            // Parse "comp home-away" or "comp home VS away" from title
            let parts = parseTitle(title)

            return LiveMatch(
                id: "\(matchId)",
                matchId: "\(matchId)",
                sportId: "\(m["sport_id"] ?? 1)",
                roomId: "\(m["chatroom_id"] ?? "888888888")",
                title: title,
                homeName: parts.home,
                awayName: parts.away,
                homeLogo: "",
                awayLogo: "",
                homeScore: 0,
                awayScore: 0,
                competition: parts.comp,
                stage: "",
                viewers: m["heat_number"] as? Int ?? 0,
                screenshot: (m["match_screenshot_url"] as? String) ?? (m["screenshot_url"] as? String) ?? "",
                isLive: (m["status"] as? Int ?? 0) == 2
            )
        }
    }

    /// Fetch scheduled matches (upcoming and live)
    func fetchSchedule() async throws -> [LiveMatch] {
        let url = URL(string: "\(apiBase)/v1/web/plate/schedule")!
        let data = try await fetchJson(url: url)

        guard let dataObj = data["data"] as? [String: Any],
              let list = dataObj["match_list"] as? [[String: Any]] else { return [] }

        return list.compactMap { m in
            guard let matchId = m["match_id"] else { return nil }
            let status = m["match_status"] as? Int ?? 0

            return LiveMatch(
                id: "\(matchId)",
                matchId: "\(matchId)",
                sportId: "\(m["sport_id"] ?? 1)",
                roomId: "\(m["chatroom_id"] ?? "888888888")",
                title: "\(m["alias_name"] ?? "") \(m["home_name"] ?? "") vs \(m["away_name"] ?? "")",
                homeName: m["home_name"] as? String ?? "",
                awayName: m["away_name"] as? String ?? "",
                homeLogo: m["home_logo"] as? String ?? "",
                awayLogo: m["away_logo"] as? String ?? "",
                homeScore: m["home_score"] as? Int ?? 0,
                awayScore: m["away_score"] as? Int ?? 0,
                competition: m["alias_name"] as? String ?? "",
                stage: "",
                viewers: 0,
                screenshot: "",
                isLive: status == 2 || (m["live_status"] as? Int ?? 0) == 1
            )
        }
    }

    // MARK: - Room / Stream data

    func findRooms(matchId: String, sportId: String = "1") async throws -> [String] {
        let url = URL(string: "\(apiBase)/v14/channel/list")!
        let data = try await fetchJson(url: url)

        guard let channels = data["data"] as? [[String: Any]] else { return [] }
        var roomIds: [String] = []
        for channel in channels {
            guard let rooms = channel["list"] as? [[String: Any]] else { continue }
            for room in rooms {
                if let mid = room["match_id"], "\(mid)" == matchId {
                    if let rid = room["room_id"] { roomIds.append("\(rid)") }
                }
            }
        }
        return roomIds
    }

    func getRoomData(roomId: String, matchId: String, sportId: String = "1") async throws -> RoomResult {
        let url = URL(string: "\(apiBase)/v1/room?room_id=\(roomId)&sport_id=\(sportId)&match_id=\(matchId)")!
        let data = try await fetchJson(url: url)

        guard let roomData = data["data"] as? [String: Any] else {
            throw StreamError.noData
        }

        var matchInfo: MatchInfo? = nil
        if let mi = roomData["match_info"] as? [String: Any] {
            matchInfo = MatchInfo(
                homeName: mi["home_name"] as? String ?? "Home",
                awayName: mi["away_name"] as? String ?? "Away",
                homeScore: mi["home_score"] as? Int ?? 0,
                awayScore: mi["away_score"] as? Int ?? 0,
                competition: mi["alias_name"] as? String ?? "",
                stage: mi["stages_name"] as? String ?? ""
            )
        }

        var streams: [StreamOption] = []
        if let flows = roomData["play_flow"] as? [[String: Any]] {
            for flow in flows {
                guard let codeId = flow["code_id"] as? String,
                      let name = flow["name"] as? String,
                      var playUrl = flow["play_url"] as? String else { continue }

                if playUrl.contains(".flv") {
                    playUrl = playUrl.replacingOccurrences(of: ".flv", with: ".m3u8")
                }

                streams.append(StreamOption(
                    id: codeId, name: name, url: playUrl,
                    loginRequired: (flow["login_status"] as? Int ?? 0) == 1,
                    sort: flow["sort"] as? Int ?? 0
                ))
            }
        }

        if streams.isEmpty, let pullUrl = roomData["pull_url"] as? String, !pullUrl.isEmpty {
            streams.append(StreamOption(
                id: "default", name: "Default", url: pullUrl,
                loginRequired: false, sort: 0
            ))
        }

        streams.sort { $0.sort > $1.sort }

        return RoomResult(roomId: "\(roomData["room_id"] ?? roomId)", matchInfo: matchInfo, streams: streams)
    }

    // MARK: - Helpers

    private func fetchJson(url: URL) async throws -> [String: Any] {
        var request = URLRequest(url: url)
        request.setValue(siteOrigin, forHTTPHeaderField: "Referer")
        let (data, _) = try await session.data(for: request)
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw StreamError.badResponse
        }
        return json
    }

    /// Parse room titles like "欧冠 马竞VS巴萨" or "女南美国联 玻利维亚女足-乌拉圭女足"
    private func parseTitle(_ title: String) -> (comp: String, home: String, away: String) {
        let separators = [" VS ", " vs ", "-", "VS"]
        let parts = title.split(separator: " ", maxSplits: 1).map(String.init)
        let comp = parts.count > 1 ? parts[0] : ""
        let teams = parts.count > 1 ? parts[1] : title

        for sep in separators {
            let teamParts = teams.components(separatedBy: sep)
            if teamParts.count == 2 {
                return (comp, teamParts[0].trimmingCharacters(in: .whitespaces),
                        teamParts[1].trimmingCharacters(in: .whitespaces))
            }
        }
        return (comp, teams, "")
    }
}

enum StreamError: LocalizedError {
    case noData, badResponse, noRooms

    var errorDescription: String? {
        switch self {
        case .noData: return "No data returned from API"
        case .badResponse: return "Invalid response from API"
        case .noRooms: return "No active rooms found for this match"
        }
    }
}

final class TLSDelegate: NSObject, URLSessionDelegate, @unchecked Sendable {
    func urlSession(
        _ session: URLSession,
        didReceive challenge: URLAuthenticationChallenge,
        completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void
    ) {
        if challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust,
           let trust = challenge.protectionSpace.serverTrust {
            completionHandler(.useCredential, URLCredential(trust: trust))
        } else {
            completionHandler(.performDefaultHandling, nil)
        }
    }
}
