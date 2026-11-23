import Foundation
import AuthenticationServices
import CryptoKit
import Security
import UIKit
import Observation

/// Sign in with Google (read-only YouTube access), the same way the Android app does it:
/// import your subscriptions, playlists and liked videos, and stay signed in.
/// The refresh token lives in the iPhone Keychain, so you stay signed in until you sign out.
@Observable
final class GoogleAccount: NSObject {
    static let shared = GoogleAccount()

    struct Profile: Codable, Equatable {
        var name: String
        var handle: String?
        var avatar: String?
    }

    var profile: Profile?
    var busy = false
    var status: String?

    var signedIn: Bool { profile != nil }
    var configured: Bool { !Config.googleClientID.isEmpty }

    @ObservationIgnored private var accessToken: String?
    @ObservationIgnored private var tokenExpiry = Date.distantPast
    @ObservationIgnored private var session: ASWebAuthenticationSession?

    private static let scope = "https://www.googleapis.com/auth/youtube.readonly"
    private static let api = "https://www.googleapis.com/youtube/v3/"

    private var redirectScheme: String {
        // Google's iOS clients use the reversed client ID as the redirect scheme.
        Config.googleClientID.split(separator: ".").reversed().joined(separator: ".")
    }
    private var redirectURI: String { "\(redirectScheme):/oauth2redirect" }

    override init() {
        super.init()
        if let data = UserDefaults.standard.data(forKey: "google_profile"),
           let p = try? JSONDecoder().decode(Profile.self, from: data), Keychain.read() != nil {
            profile = p
        }
    }

    // MARK: Sign in / out

    @MainActor
    func signIn() async {
        guard configured else {
            status = "Google sign-in isn't set up in this build yet."
            return
        }
        busy = true
        status = nil
        defer { busy = false }
        do {
            let verifier = Self.randomString(64)
            let challenge = Data(SHA256.hash(data: Data(verifier.utf8))).base64URL
            var c = URLComponents(string: "https://accounts.google.com/o/oauth2/v2/auth")!
            c.queryItems = [
                .init(name: "client_id", value: Config.googleClientID),
                .init(name: "redirect_uri", value: redirectURI),
                .init(name: "response_type", value: "code"),
                .init(name: "scope", value: Self.scope),
                .init(name: "code_challenge", value: challenge),
                .init(name: "code_challenge_method", value: "S256"),
                .init(name: "access_type", value: "offline"),
                .init(name: "prompt", value: "select_account")
            ]
            let callback = try await authenticate(c.url!)
            guard let code = URLComponents(url: callback, resolvingAgainstBaseURL: false)?
                .queryItems?.first(where: { $0.name == "code" })?.value else {
                status = "Sign-in was cancelled."
                return
            }
            let json = try await tokenRequest([
                "code": code,
                "client_id": Config.googleClientID,
                "redirect_uri": redirectURI,
                "grant_type": "authorization_code",
                "code_verifier": verifier
            ])
            guard let access = json["access_token"] as? String else { throw AccountError.message("Google didn't return a token") }
            accessToken = access
            tokenExpiry = Date().addingTimeInterval((json["expires_in"] as? Double ?? 3600) - 120)
            if let refresh = json["refresh_token"] as? String { Keychain.save(refresh) }
            try await loadProfile()
            await importAll()
        } catch let e as ASWebAuthenticationSessionError where e.code == .canceledLogin {
            status = "Sign-in was cancelled."
        } catch {
            status = "Sign-in failed: \(error.localizedDescription)"
        }
    }

    @MainActor
    func signOut() {
        if let t = accessToken ?? Keychain.read(),
           let url = URL(string: "https://oauth2.googleapis.com/revoke?token=\(t)") {
            var req = URLRequest(url: url)
            req.httpMethod = "POST"
            URLSession.shared.dataTask(with: req).resume()
        }
        Keychain.delete()
        accessToken = nil
        profile = nil
        status = nil
        UserDefaults.standard.removeObject(forKey: "google_profile")
    }

    /// Called at launch: keeps the profile fresh and, once a day, picks up new subscriptions.
    @MainActor
    func refreshOnLaunch() async {
        guard signedIn else { return }
        try? await loadProfile()
        let s = AppSettings.shared
        guard s.d.syncOnLaunch else { return }
        if let last = s.d.lastSync, Date().timeIntervalSince(last) < 20 * 3600 { return }
        await importAll(quiet: true)
    }

    // MARK: Import

    @MainActor
    func importAll(quiet: Bool = false) async {
        guard signedIn else { return }
        busy = true
        defer { busy = false }
        do {
            status = "Importing subscriptions…"
            let subs = try await all("subscriptions", ["part": "snippet", "mine": "true", "order": "alphabetical"], pages: 20)
            let channels: [Channel] = subs.compactMap { item in
                guard let sn = item["snippet"] as? [String: Any],
                      let id = YTParse.dig(sn, "resourceId", "channelId") as? String else { return nil }
                let name = (sn["title"] as? String ?? "").replacingOccurrences(of: " - Topic", with: "")
                return Channel(id: id, name: name, avatar: Self.bestThumb(sn["thumbnails"]))
            }
            let newSubs = Library.shared.mergeSubscriptions(channels)

            status = "Importing playlists…"
            let lists = try await all("playlists", ["part": "snippet,contentDetails", "mine": "true"], pages: 4)
            var playlistCount = 0
            var videoCount = 0
            for pl in lists {
                guard let pid = pl["id"] as? String, let sn = pl["snippet"] as? [String: Any] else { continue }
                let title = sn["title"] as? String ?? "Playlist"
                status = "Importing playlist “\(title)”…"
                let items = try await all("playlistItems", ["part": "snippet,contentDetails", "playlistId": pid], pages: 6)
                let videos = items.compactMap(Self.video(fromPlaylistItem:))
                Library.shared.upsertPlaylist(name: title, sourceID: pid, videos: videos)
                playlistCount += 1
                videoCount += videos.count
            }

            status = "Importing liked videos…"
            let liked = try await all("videos", ["part": "snippet,contentDetails", "myRating": "like"], pages: 4)
            let newLiked = Library.shared.mergeLiked(liked.compactMap(Self.video(fromVideo:)))

            AppSettings.shared.set(\.lastSync, Date())
            let summary = "Imported \(channels.count) subscriptions (\(newSubs) new), \(playlistCount) playlists (\(videoCount) videos) and \(newLiked) liked videos."
            status = quiet ? nil : summary
            if quiet && newSubs > 0 { PlayerModel.shared.showToast("\(newSubs) new subscriptions from YouTube") }
        } catch {
            status = "Import stopped: \(error.localizedDescription)"
        }
    }

    @MainActor
    private func loadProfile() async throws {
        let json = try await get("channels", ["part": "snippet", "mine": "true"])
        let sn = ((json["items"] as? [[String: Any]])?.first?["snippet"] as? [String: Any]) ?? [:]
        let p = Profile(name: sn["title"] as? String ?? "You",
                        handle: sn["customUrl"] as? String,
                        avatar: Self.bestThumb(sn["thumbnails"]))
        profile = p
        if let data = try? JSONEncoder().encode(p) { UserDefaults.standard.set(data, forKey: "google_profile") }
    }

    // MARK: API plumbing

    private func freshToken() async throws -> String {
        if let t = accessToken, Date() < tokenExpiry { return t }
        guard let refresh = Keychain.read() else { throw AccountError.message("Please sign in again") }
        let json = try await tokenRequest([
            "client_id": Config.googleClientID,
            "refresh_token": refresh,
            "grant_type": "refresh_token"
        ])
        guard let t = json["access_token"] as? String else { throw AccountError.message("Please sign in again") }
        accessToken = t
        tokenExpiry = Date().addingTimeInterval((json["expires_in"] as? Double ?? 3600) - 120)
        return t
    }

    private func tokenRequest(_ form: [String: String]) async throws -> [String: Any] {
        var req = URLRequest(url: URL(string: "https://oauth2.googleapis.com/token")!)
        req.httpMethod = "POST"
        req.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        req.httpBody = form.map { "\($0.key)=\($0.value.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? "")" }
            .joined(separator: "&").data(using: .utf8)
        let (data, _) = try await URLSession.shared.data(for: req)
        let json = (try JSONSerialization.jsonObject(with: data) as? [String: Any]) ?? [:]
        if let err = json["error_description"] as? String ?? json["error"] as? String { throw AccountError.message(err) }
        return json
    }

    private func get(_ path: String, _ params: [String: String]) async throws -> [String: Any] {
        let token = try await freshToken()
        var c = URLComponents(string: Self.api + path)!
        c.queryItems = params.map { URLQueryItem(name: $0.key, value: $0.value) }
        var req = URLRequest(url: c.url!)
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        let (data, _) = try await URLSession.shared.data(for: req)
        let json = (try JSONSerialization.jsonObject(with: data) as? [String: Any]) ?? [:]
        if let err = json["error"] as? [String: Any] {
            throw AccountError.message("YouTube said: \(err["message"] as? String ?? "error")")
        }
        return json
    }

    private func all(_ path: String, _ params: [String: String], pages: Int) async throws -> [[String: Any]] {
        var out: [[String: Any]] = []
        var pageToken: String?
        for _ in 0..<pages {
            var p = params
            p["maxResults"] = "50"
            if let pageToken { p["pageToken"] = pageToken }
            let json = try await get(path, p)
            out += (json["items"] as? [[String: Any]]) ?? []
            guard let next = json["nextPageToken"] as? String, !next.isEmpty else { break }
            pageToken = next
        }
        return out
    }

    @MainActor
    private func authenticate(_ url: URL) async throws -> URL {
        try await withCheckedThrowingContinuation { cont in
            let s = ASWebAuthenticationSession(url: url, callbackURLScheme: redirectScheme) { callback, error in
                if let callback { cont.resume(returning: callback) } else { cont.resume(throwing: error ?? AccountError.message("Sign-in was cancelled.")) }
            }
            s.presentationContextProvider = self
            s.prefersEphemeralWebBrowserSession = false
            session = s
            if !s.start() { cont.resume(throwing: AccountError.message("Couldn't open the sign-in page.")) }
        }
    }

    // MARK: Parsing

    static func bestThumb(_ any: Any?) -> String? {
        guard let t = any as? [String: Any] else { return nil }
        for k in ["high", "medium", "default"] {
            if let u = (t[k] as? [String: Any])?["url"] as? String { return u }
        }
        return nil
    }

    static func isoDuration(_ s: String?) -> String? {
        guard let s, let re = try? NSRegularExpression(pattern: "P(?:(\\d+)D)?T?(?:(\\d+)H)?(?:(\\d+)M)?(?:(\\d+)S)?"),
              let m = re.firstMatch(in: s, range: NSRange(s.startIndex..., in: s)) else { return nil }
        func n(_ i: Int) -> Int {
            guard let r = Range(m.range(at: i), in: s) else { return 0 }
            return Int(s[r]) ?? 0
        }
        let total = n(1) * 86400 + n(2) * 3600 + n(3) * 60 + n(4)
        return total > 0 ? formatTime(Double(total)) : nil
    }

    static func video(fromPlaylistItem item: [String: Any]) -> Video? {
        guard let sn = item["snippet"] as? [String: Any],
              let id = YTParse.dig(sn, "resourceId", "videoId") as? String,
              let title = sn["title"] as? String, title != "Private video", title != "Deleted video" else { return nil }
        return Video(id: id, title: title,
                     channel: (sn["videoOwnerChannelTitle"] as? String ?? "").replacingOccurrences(of: " - Topic", with: ""),
                     channelId: sn["videoOwnerChannelId"] as? String)
    }

    static func video(fromVideo item: [String: Any]) -> Video? {
        guard let id = item["id"] as? String, let sn = item["snippet"] as? [String: Any] else { return nil }
        return Video(id: id, title: sn["title"] as? String ?? "",
                     channel: (sn["channelTitle"] as? String ?? "").replacingOccurrences(of: " - Topic", with: ""),
                     channelId: sn["channelId"] as? String,
                     duration: isoDuration(YTParse.dig(item, "contentDetails", "duration") as? String))
    }

    static func randomString(_ n: Int) -> String {
        let chars = Array("ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~")
        return String((0..<n).map { _ in chars.randomElement()! })
    }
}

extension GoogleAccount: ASWebAuthenticationPresentationContextProviding {
    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        let scene = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first
        return scene?.windows.first { $0.isKeyWindow } ?? ASPresentationAnchor()
    }
}

enum AccountError: LocalizedError {
    case message(String)
    var errorDescription: String? {
        switch self { case .message(let m): return m }
    }
}

private extension Data {
    var base64URL: String {
        base64EncodedString().replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "")
    }
}

/// Tiny Keychain wrapper for the Google refresh token.
enum Keychain {
    private static let service = "com.ajayk909.premium.google"

    static func save(_ value: String) {
        delete()
        let q: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
                                kSecAttrService as String: service,
                                kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock,
                                kSecValueData as String: Data(value.utf8)]
        SecItemAdd(q as CFDictionary, nil)
    }

    static func read() -> String? {
        let q: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
                                kSecAttrService as String: service,
                                kSecReturnData as String: true,
                                kSecMatchLimit as String: kSecMatchLimitOne]
        var out: AnyObject?
        guard SecItemCopyMatching(q as CFDictionary, &out) == errSecSuccess, let d = out as? Data else { return nil }
        return String(data: d, encoding: .utf8)
    }

    static func delete() {
        SecItemDelete([kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service] as CFDictionary)
    }
}
