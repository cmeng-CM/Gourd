/*
 * Atoll (DynamicIsland)
 * Copyright (C) 2024-2026 Atoll Contributors
 *
 * Originally from boring.notch project
 * Modified and adapted for Atoll (DynamicIsland)
 * See NOTICE for details.
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program. If not, see <https://www.gnu.org/licenses/>.
 */

import AppKit
import Combine
import Defaults
import Foundation
import SwiftUI
import os

// MARK: - Lyric Data Structures
struct LyricLine: Identifiable, Codable, Equatable {
    let id = UUID()
    let timestamp: TimeInterval
    let text: String

    init(timestamp: TimeInterval, text: String) {
        self.timestamp = timestamp
        self.text = text
    }

    // Compares content only; `id` is regenerated per instance, so identical
    // lyrics parsed twice would otherwise never compare equal
    static func == (lhs: LyricLine, rhs: LyricLine) -> Bool {
        lhs.timestamp == rhs.timestamp && lhs.text == rhs.text
    }
}

private struct LyricsLookupKey: Hashable {
    let title: String
    let artist: String
    let album: String

    var isValid: Bool {
        !title.isEmpty && !artist.isEmpty
    }
}

let defaultImage: NSImage = .init(
    systemSymbolName: "heart.fill",
    accessibilityDescription: "Album Art"
)!

private struct ITunesExplicitnessSearchResponse: Decodable {
    let results: [ITunesExplicitnessTrack]
}

private struct ITunesExplicitnessTrack: Decodable {
    let trackName: String?
    let artistName: String?
    let collectionName: String?
    let trackExplicitness: String?
}

private actor MusicExplicitnessResolver {
    struct LookupKey: Hashable, Sendable {
        let title: String
        let artist: String
        let album: String

        init(title: String, artist: String, album: String) {
            self.title = MusicExplicitnessResolver.normalize(title)
            self.artist = MusicExplicitnessResolver.normalize(artist)
            self.album = MusicExplicitnessResolver.normalize(album)
        }

        var canResolve: Bool {
            !title.isEmpty && !artist.isEmpty
        }
    }

    static let shared = MusicExplicitnessResolver()

    private let session = URLSession(configuration: .ephemeral)
    private static let cacheLimit = 300
    private var cache: [LookupKey: Bool] = [:]
    private var cacheOrder: [LookupKey] = []
    private var inFlightTasks: [LookupKey: Task<Bool, Never>] = [:]

    private func store(_ value: Bool, for key: LookupKey) {
        if cache[key] == nil {
            cacheOrder.append(key)
            while cacheOrder.count > Self.cacheLimit {
                let evicted = cacheOrder.removeFirst()
                cache.removeValue(forKey: evicted)
            }
        }
        cache[key] = value
    }

    func resolve(title: String, artist: String, album: String) async -> Bool {
        let key = LookupKey(title: title, artist: artist, album: album)
        guard key.canResolve else { return false }

        if let cached = cache[key] {
            return cached
        }

        if let inFlightTask = inFlightTasks[key] {
            return await inFlightTask.value
        }

        let task = Task<Bool, Never> { [session] in
            await Self.fetchExplicitness(for: key, using: session)
        }

        inFlightTasks[key] = task
        let result = await task.value
        store(result, for: key)
        inFlightTasks[key] = nil
        return result
    }

    private static func fetchExplicitness(for key: LookupKey, using session: URLSession) async -> Bool {
        let query = "\(key.title) \(key.artist)"
        guard let encoded = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let url = URL(
                string: "https://itunes.apple.com/search?term=\(encoded)&media=music&entity=song&limit=15")
        else {
            return false
        }

        do {
            let (data, _) = try await session.data(from: url)
            let response = try JSONDecoder().decode(ITunesExplicitnessSearchResponse.self, from: data)

            let bestMatch = response.results
                .map { track in (track, matchScore(for: track, key: key)) }
                .max { lhs, rhs in lhs.1 < rhs.1 }

            guard let bestMatch,
                  bestMatch.1 >= 8
            else {
                return false
            }

            return bestMatch.0.trackExplicitness?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                == "explicit"
        } catch {
            return false
        }
    }

    private static func matchScore(for track: ITunesExplicitnessTrack, key: LookupKey) -> Int {
        let trackTitle = canonicalTitle(track.trackName ?? "")
        guard !trackTitle.isEmpty else { return Int.min }

        let keyTitle = canonicalTitle(key.title)
        let trackArtist = normalize(track.artistName ?? "")
        let trackAlbum = normalize(track.collectionName ?? "")

        var score = 0

        if trackTitle == keyTitle {
            score += 6
        } else if trackTitle.contains(keyTitle) || keyTitle.contains(trackTitle) {
            score += 4
        } else {
            return Int.min
        }

        if !key.artist.isEmpty {
            if trackArtist == key.artist {
                score += 4
            } else if trackArtist.contains(key.artist) || key.artist.contains(trackArtist) {
                score += 2
            }
        }

        if !key.album.isEmpty {
            if trackAlbum == key.album {
                score += 2
            } else if !trackAlbum.isEmpty && (trackAlbum.contains(key.album) || key.album.contains(trackAlbum)) {
                score += 1
            }
        }

        return score
    }

    private static func canonicalTitle(_ value: String) -> String {
        var title = value.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
        title = title.replacingOccurrences(
            of: #"\([^)]*\)|\[[^\]]*\]"#,
            with: " ",
            options: .regularExpression
        )
        title = title.replacingOccurrences(
            of: #"\s-\s(?:\d{4}\s)?(?:remaster(?:ed)?|live|edit|mix|version|mono|stereo).*$"#,
            with: " ",
            options: .regularExpression
        )
        return normalize(title)
    }

    private static func normalize(_ value: String) -> String {
        let folded = value.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
        let stripped = folded.replacingOccurrences(
            of: #"[^a-z0-9]+"#,
            with: " ",
            options: .regularExpression
        )
        return stripped
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

private actor SpotifyExplicitnessResolver {
    struct LookupKey: Hashable, Sendable {
        let trackID: String

        init?(contentIdentifier: String?, contentURL: String?) {
            guard let trackID = SpotifyExplicitnessResolver.extractTrackID(from: contentIdentifier)
                ?? SpotifyExplicitnessResolver.extractTrackID(from: contentURL)
            else {
                return nil
            }

            self.trackID = trackID
        }
    }

    static let shared = SpotifyExplicitnessResolver()

    private let session: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpAdditionalHeaders = [
            "User-Agent": "Mozilla/5.0",
            "Accept-Language": "en-US,en;q=0.9"
        ]
        return URLSession(configuration: configuration)
    }()

    private static let cacheLimit = 300
    private var cache: [LookupKey: Bool] = [:]
    private var cacheOrder: [LookupKey] = []
    private var inFlightTasks: [LookupKey: Task<Bool?, Never>] = [:]

    private func store(_ value: Bool, for key: LookupKey) {
        if cache[key] == nil {
            cacheOrder.append(key)
            while cacheOrder.count > Self.cacheLimit {
                let evicted = cacheOrder.removeFirst()
                cache.removeValue(forKey: evicted)
            }
        }
        cache[key] = value
    }

    func resolve(key: LookupKey) async -> Bool? {
        if let cached = cache[key] {
            return cached
        }

        if let inFlightTask = inFlightTasks[key] {
            return await inFlightTask.value
        }

        let task = Task<Bool?, Never> { [session] in
            await Self.fetchExplicitness(for: key, using: session)
        }

        inFlightTasks[key] = task
        let result = await task.value
        if let result {
            store(result, for: key)
        }
        inFlightTasks[key] = nil
        return result
    }

    private static func fetchExplicitness(for key: LookupKey, using session: URLSession) async -> Bool? {
        guard let url = URL(string: "https://open.spotify.com/embed/track/\(key.trackID)") else {
            return nil
        }

        do {
            let (data, response) = try await session.data(from: url)
            guard let httpResponse = response as? HTTPURLResponse,
                  (200...299).contains(httpResponse.statusCode),
                  let html = String(data: data, encoding: .utf8)
            else {
                return nil
            }

            if let isExplicit = parseIsExplicitDirectly(from: html) {
                return isExplicit
            }

            if let nextDataJSON = extractNextDataJSON(from: html),
               let isExplicit = parseIsExplicit(from: nextDataJSON) {
                return isExplicit
            }

            return nil
        } catch {
            return nil
        }
    }

    private static func extractNextDataJSON(from html: String) -> String? {
        let pattern = #"<script[^>]*id="__NEXT_DATA__"[^>]*>(.*?)</script>"#
        guard let regex = try? NSRegularExpression(
            pattern: pattern,
            options: [.dotMatchesLineSeparators, .caseInsensitive]
        ) else {
            return nil
        }

        let range = NSRange(html.startIndex..<html.endIndex, in: html)
        guard let match = regex.firstMatch(in: html, options: [], range: range),
              match.numberOfRanges > 1,
              let jsonRange = Range(match.range(at: 1), in: html)
        else {
            return nil
        }

        return String(html[jsonRange])
    }

    private static func parseIsExplicitDirectly(from html: String) -> Bool? {
        if let value = captureFirstMatch(
            in: html,
            pattern: #""isExplicit"\s*:\s*(true|false)"#
        ) {
            return value == "true"
        }

        if let label = captureFirstMatch(
            in: html,
            pattern: #""label"\s*:\s*"([A-Z_]+)""#
        ) {
            switch label {
            case "EXPLICIT":
                return true
            case "NON_EXPLICIT":
                return false
            default:
                break
            }
        }

        return nil
    }

    private static func captureFirstMatch(in source: String, pattern: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
            return nil
        }

        let range = NSRange(source.startIndex..<source.endIndex, in: source)
        guard let match = regex.firstMatch(in: source, options: [], range: range),
              match.numberOfRanges > 1,
              let valueRange = Range(match.range(at: 1), in: source)
        else {
            return nil
        }

        return String(source[valueRange]).lowercased()
    }

    private static func parseIsExplicit(from nextDataJSON: String) -> Bool? {
        guard let data = nextDataJSON.data(using: .utf8),
              let rootObject = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let props = rootObject["props"] as? [String: Any],
              let pageProps = props["pageProps"] as? [String: Any],
              let state = pageProps["state"] as? [String: Any],
              let dataObject = state["data"] as? [String: Any],
              let entity = dataObject["entity"] as? [String: Any]
        else {
            return nil
        }

        if let isExplicit = entity["isExplicit"] as? Bool {
            return isExplicit
        }

        if let contentRating = entity["contentRating"] as? [String: Any],
           let label = contentRating["label"] as? String {
            return label.trimmingCharacters(in: .whitespacesAndNewlines).uppercased() == "EXPLICIT"
        }

        return nil
    }

    private static func extractTrackID(from rawValue: String?) -> String? {
        guard let rawValue else { return nil }

        let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        if trimmed.hasPrefix("spotify:track:") {
            return validatedTrackID(String(trimmed.split(separator: ":").last ?? ""))
        }

        if let url = URL(string: trimmed) {
            let pathComponents = url.pathComponents.filter { $0 != "/" && !$0.isEmpty }
            if let trackIndex = pathComponents.firstIndex(of: "track"),
               trackIndex + 1 < pathComponents.count {
                return validatedTrackID(pathComponents[trackIndex + 1])
            }
        }

        return validatedTrackID(trimmed)
    }

    private static func validatedTrackID<S: StringProtocol>(_ candidate: S) -> String? {
        let value = String(candidate).trimmingCharacters(in: .whitespacesAndNewlines)
        guard value.range(of: #"^[A-Za-z0-9]{22}$"#, options: .regularExpression) != nil else {
            return nil
        }

        return value
    }
}

class MusicManager: ObservableObject {
    enum SkipDirection: Equatable {
        case backward
        case forward
    }

    struct SkipGesturePulse: Equatable {
        let token: Int
        let direction: SkipDirection
        let behavior: MusicSkipBehavior
    }

    static let skipGestureSeekInterval: TimeInterval = 10

    // MARK: - Properties
    static let shared = MusicManager()
    private var cancellables = Set<AnyCancellable>()
    private var controllerCancellables = Set<AnyCancellable>()
    private var debounceIdleTask: Task<Void, Never>?
    @MainActor private var pendingOptimisticPlayState: Bool?

    // Helper to check if macOS has removed support for NowPlayingController
    public private(set) var isNowPlayingDeprecated: Bool = false
    private let mediaChecker = MediaChecker()

    // Active controller
    private var activeController: (any MediaControllerProtocol)?

    // Pear Desktop auto-detection
    private static let pearDesktopBundleID = YouTubeMusicConfiguration.default.bundleIdentifier
    private var isPearDesktopAutoSwitched: Bool = false

    // Published properties for UI
    @Published var songTitle: String = "I'm Handsome"
    @Published var artistName: String = "Me"
    @Published var albumArt: NSImage = defaultImage
    @Published var isPlaying = false
    @Published var album: String = "Self Love"
    @Published var isPlayerIdle: Bool = true
    @Published var isCurrentTrackExplicit: Bool = false

    /// Whether there is an active music session with real metadata.
    /// Returns `false` only when the metadata is still placeholder/fallback defaults
    /// (i.e. nothing has been played since app launch, or the controller returned
    /// unknown/not-playing placeholders). Paused music with real metadata is still
    /// considered an active session.
    private static let placeholderTitles: Set<String> = [
        "i'm handsome", "unknown", "not playing"
    ]
    private static let placeholderArtists: Set<String> = [
        "me", "unknown"
    ]

    var hasActiveSession: Bool {
        if isPlaying { return true }
        let trimmedTitle = songTitle.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let trimmedArtist = artistName.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let hasRealTitle = !trimmedTitle.isEmpty && !Self.placeholderTitles.contains(trimmedTitle)
        let hasRealArtist = !trimmedArtist.isEmpty && !Self.placeholderArtists.contains(trimmedArtist)
        return hasRealTitle || hasRealArtist
    }

    @Published var animations: DynamicIslandAnimations = .init()
    @Published var avgColor: NSColor = .white
    @Published var secondaryColor: NSColor = .gray
    @Published var bundleIdentifier: String? = nil

    var isAppleMusicActive: Bool { bundleIdentifier == "com.apple.Music" }
    var isSpotifyActive: Bool { bundleIdentifier == SpotifyController.bundleIdentifier }
    @Published var songDuration: TimeInterval = 0
    @Published var elapsedTime: TimeInterval = 0
    @Published var timestampDate: Date = .init()
    @Published var playbackRate: Double = 1
    @Published var isShuffled: Bool = false
    @Published var repeatMode: RepeatMode = .off
    @Published var isLiveStream: Bool = false
    @ObservedObject var coordinator = DynamicIslandViewCoordinator.shared
    @Published var usingAppIconForArtwork: Bool = false
    @Published private(set) var skipGesturePulse: SkipGesturePulse?

    // MARK: - Lyrics Properties
    @Published var currentLyrics: String = ""
    @Published var syncedLyrics: [LyricLine] = []
    @Published var showLyrics: Bool = false
    @Published var currentLyricIndex: Int = -1

    // Task used to periodically sync displayed lyric with playback position
    private var lyricSyncTask: Task<Void, Never>?
    private var lyricsFetchTask: Task<Void, Never>?
    /// 瞬时故障（缓存不写、只延迟重试）之后的**一次**自动重试任务（docs/50 D-05）。
    private var lyricsTransportRetryTask: Task<Void, Never>?
    private var lyricsFetchKey: LyricsLookupKey?

    /// 取词侧的日志（`print` 在 GUI 里查不到东西——`log show --subsystem com.cmeng.gourd.music`）。
    /// **必须写全 `os.Logger`**：本模块有一个同名的 `Logger` 结构（`utils/Logger.swift`），
    /// 裸写 `Logger(...)` 会解析到它（构造参数对不上，直接编译不过）。
    private let lyricsLog = os.Logger(subsystem: "com.cmeng.gourd.music", category: "lyrics")

    /// **取词失败**（网络 / 超时 / 429 / 5xx）——与「词库确实没有这条」严格分开：
    /// 前者**不写缓存**、不报「No lyrics found」，换回这首歌或再点一次歌词键时会重新去问。
    struct LyricsFetchFailure: Error {
        let reason: String
        let attempts: Int
    }
    // Identity of the fetch that is allowed to write lyrics state. A cancelled
    // task can still reach its completion handler, and the key alone does not
    // tell it apart from a newer fetch for the same track.
    private var lyricsFetchID: UUID?
    private var activeLyricsKey: LyricsLookupKey?
    private var lyricsCache: [LyricsLookupKey: [LyricLine]] = [:]
    // Bounded, insertion-order eviction so the cache cannot grow unboundedly.
    private static let lyricsCacheLimit = 80
    private var lyricsCacheOrder: [LyricsLookupKey] = []
    private var explicitLookupTask: Task<Void, Never>?
    private var explicitLookupKey: String?

    // MARK: - Spotify Liked Songs
    /// nil = unknown (not Spotify, not connected, or lookup pending) — the like button renders disabled.
    @Published private(set) var isCurrentTrackLiked: Bool? = nil
    private var likedLookupTrackID: String?
    private var likedLookupTask: Task<Void, Never>?
    private var likeToggleTask: Task<Void, Never>?

    /// Inserts lyrics with insertion-order eviction to keep the cache bounded.
    private func storeLyricsInCache(_ lyrics: [LyricLine], for key: LyricsLookupKey) {
        if lyricsCache[key] == nil {
            lyricsCacheOrder.append(key)
            while lyricsCacheOrder.count > Self.lyricsCacheLimit {
                let evicted = lyricsCacheOrder.removeFirst()
                lyricsCache.removeValue(forKey: evicted)
            }
        }
        lyricsCache[key] = lyrics
    }

    private(set) var artworkData: Data? = nil

    @Published var videoArtworkURL: URL? = nil

    private var liveStreamUnknownDurationCount: Int = 0
    private var liveStreamEdgeObservationCount: Int = 0
    private var liveStreamCompletionObservationCount: Int = 0
    private var liveStreamCompletionReleaseCount: Int = 0

    // Store last values at the time artwork was changed
    private var lastArtworkTitle: String = "I'm Handsome"
    private var lastArtworkArtist: String = "Me"
    private var lastArtworkAlbum: String = "Self Love"
    private var lastArtworkBundleIdentifier: String? = nil
    private var lastArtworkContentIdentifier: String? = nil
    private var lastArtworkContentURL: String? = nil

    @Published var flipAngle: Double = 0
    @Published var lastFlipDirection: SkipDirection = .forward
    private let flipAnimationDuration: TimeInterval = 0.45
    private var flipCooldownActive: Bool = false

    @Published var isTransitioning: Bool = false
    private var transitionWorkItem: DispatchWorkItem?
    private var skipGestureToken: Int = 0

    // MARK: - Initialization
    init() {
        // Listen for changes to the default controller preference
        NotificationCenter.default.publisher(for: Notification.Name.mediaControllerChanged)
            .sink { [weak self] _ in
                self?.isPearDesktopAutoSwitched = false
                self?.setActiveControllerBasedOnPreference()
            }
            .store(in: &cancellables)

        Defaults.publisher(.enableLyrics)
            .receive(on: RunLoop.main)
            .sink { [weak self] change in
                self?.handleLyricsPreferenceChange(isEnabled: change.newValue)
            }
            .store(in: &cancellables)

        // Observe Pear Desktop launch/terminate for auto-detection
        setupPearDesktopAutoDetection()

        // Initialize deprecation check asynchronously
        Task { @MainActor in
            do {
                self.isNowPlayingDeprecated = try await self.mediaChecker.checkDeprecationStatus()
                print("Deprecation check completed: \(self.isNowPlayingDeprecated)")
            } catch {
                print("Failed to check deprecation status: \(error). Defaulting to false.")
                self.isNowPlayingDeprecated = false
            }
            
            // Check if Pear Desktop is already running at startup
            let pearDesktopRunning = NSWorkspace.shared.runningApplications.contains {
                $0.bundleIdentifier == Self.pearDesktopBundleID
            }
            
            if pearDesktopRunning {
                print("[MusicManager] Pear Desktop detected at startup, auto-switching to YouTubeMusicController")
                self.isPearDesktopAutoSwitched = true
                if let controller = self.createController(for: .youtubeMusic) {
                    self.setActiveController(controller)
                }
            } else {
                // Initialize the active controller after deprecation check
                self.setActiveControllerBasedOnPreference()
            }
        }
    }

    // MARK: - Pear Desktop Auto-Detection
    private func setupPearDesktopAutoDetection() {
        NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.didLaunchApplicationNotification)
            .sink { [weak self] notification in
                guard let self = self,
                      let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
                      app.bundleIdentifier == Self.pearDesktopBundleID else { return }

                print("[MusicManager] Pear Desktop launched, auto-switching to YouTubeMusicController")
                self.isPearDesktopAutoSwitched = true
                if let controller = self.createController(for: .youtubeMusic) {
                    self.setActiveController(controller)
                }
            }
            .store(in: &cancellables)

        NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.didTerminateApplicationNotification)
            .sink { [weak self] notification in
                guard let self = self,
                      let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
                      app.bundleIdentifier == Self.pearDesktopBundleID else { return }

                print("[MusicManager] Pear Desktop terminated, reverting to preferred controller")
                if self.isPearDesktopAutoSwitched {
                    self.isPearDesktopAutoSwitched = false
                    self.setActiveControllerBasedOnPreference()
                }
            }
            .store(in: &cancellables)
    }

    deinit {
        destroy()
    }
    
    public func destroy() {
        debounceIdleTask?.cancel()
        lyricsFetchTask?.cancel()
        lyricSyncTask?.cancel()
        explicitLookupTask?.cancel()
        cancellables.removeAll()
        controllerCancellables.removeAll()
        transitionWorkItem?.cancel()

        // Release active controller
        activeController = nil
    }

    // MARK: - Setup Methods
    private func createController(for type: MediaControllerType) -> (any MediaControllerProtocol)? {
        // Cleanup previous controller
        if activeController != nil {
            controllerCancellables.removeAll()
            activeController = nil
        }

        let newController: (any MediaControllerProtocol)?

        switch type {
        case .nowPlaying:
            // Only create NowPlayingController if not deprecated on this macOS version
            if !self.isNowPlayingDeprecated {
                newController = NowPlayingController()
            } else {
                return nil
            }
        case .appleMusic:
            newController = AppleMusicController()
        case .spotify:
            newController = SpotifyController()
        case .youtubeMusic:
            newController = YouTubeMusicController()
        case .amazonMusic:
            newController = AmazonMusicController()
        case .cider:
            newController = CiderController()
        }

        // Set up state observation for the new controller
        if let controller = newController {
            controller.playbackStatePublisher
                .receive(on: DispatchQueue.main)
                .sink { [weak self] state in
                    guard let self = self,
                          self.activeController === controller else { return }
                    self.updateFromPlaybackState(state)
                }
                .store(in: &controllerCancellables)
        }

        return newController
    }

    private func setActiveControllerBasedOnPreference() {
        let preferredType = Defaults[.mediaController]
        print("Preferred Media Controller: \(preferredType)")

        // If NowPlaying is deprecated but that's the preference, use Apple Music instead
        let controllerType = (self.isNowPlayingDeprecated && preferredType == .nowPlaying)
            ? .appleMusic
            : preferredType

        if let controller = createController(for: controllerType) {
            setActiveController(controller)
        } else if controllerType != .appleMusic, let fallbackController = createController(for: .appleMusic) {
            // Fallback to Apple Music if preferred controller couldn't be created
            setActiveController(fallbackController)
        }
    }

    private func setActiveController(_ controller: any MediaControllerProtocol) {
        // Set new active controller
        activeController = controller

        // Get current state from active controller
        forceUpdate()
    }

    @MainActor
    private func applyPlayState(_ state: Bool, animation: Animation?) {
        if let animation {
            var transaction = Transaction()
            transaction.animation = animation
            withTransaction(transaction) {
                self.isPlaying = state
            }
        } else {
            self.isPlaying = state
        }

        self.updateIdleState(state: state)
    }

    // MARK: - Update Methods
    @MainActor
    private func updateFromPlaybackState(_ state: PlaybackState) {
        // Check for playback state changes (playing/paused)
        let eventIsPlaying = state.isPlaying
        let expectedState = pendingOptimisticPlayState
        pendingOptimisticPlayState = nil

        if eventIsPlaying != self.isPlaying {
            let animation: Animation? = (expectedState == eventIsPlaying) ? .smooth(duration: 0.18) : .smooth
            applyPlayState(eventIsPlaying, animation: animation)

            if eventIsPlaying && !state.title.isEmpty && !state.artist.isEmpty {
                self.updateSneakPeek()
            }
        } else {
            self.updateIdleState(state: eventIsPlaying)
        }

        // Check for changes in track metadata using last artwork change values
        let titleChanged = state.title != self.lastArtworkTitle
        let artistChanged = state.artist != self.lastArtworkArtist
        let albumChanged = state.album != self.lastArtworkAlbum
        let bundleChanged = state.bundleIdentifier != self.lastArtworkBundleIdentifier
        let contentIdentifierChanged = state.contentIdentifier != self.lastArtworkContentIdentifier
        let contentURLChanged = state.contentURL != self.lastArtworkContentURL

        // Check for artwork changes
        let artworkChanged = state.artwork != nil && state.artwork != self.artworkData

        let hasContentChange =
            titleChanged
            || artistChanged
            || albumChanged
            || artworkChanged
            || bundleChanged
            || contentIdentifierChanged
            || contentURLChanged
        let liveArtworkChanged = state.liveArtworkURL != self.videoArtworkURL

        if liveArtworkChanged {
            self.videoArtworkURL = state.liveArtworkURL
        }

        if state.title != self.songTitle {
            self.songTitle = state.title
        }

        if state.artist != self.artistName {
            self.artistName = state.artist
        }

        if state.album != self.album {
            self.album = state.album
        }

        // Handle artwork and visual transitions for changed content
        let shouldAutoPeekOnTrackChange = Defaults[.showSneakPeekOnTrackChange]

        if hasContentChange {
            self.triggerFlipAnimation()

            if artworkChanged, let artwork = state.artwork {
                self.updateArtwork(artwork)
            } else if state.artwork == nil {
                // Try to use app icon if no artwork but track changed
                if let appIconImage = AppIconAsNSImage(for: state.bundleIdentifier) {
                    self.usingAppIconForArtwork = true
                    self.updateAlbumArt(newAlbumArt: appIconImage)
                }
            }
            self.artworkData = state.artwork

            // Update last artwork change values
            self.lastArtworkTitle = state.title
            self.lastArtworkArtist = state.artist
            self.lastArtworkAlbum = state.album
            self.lastArtworkBundleIdentifier = state.bundleIdentifier
            self.lastArtworkContentIdentifier = state.contentIdentifier
            self.lastArtworkContentURL = state.contentURL

            self.prepareLyricsForCurrentTrack()
            if let liveArtworkURL = state.liveArtworkURL {
                self.videoArtworkURL = liveArtworkURL
            } else {
                self.fetchVideoArtwork()
            }

            self.refreshExplicitFlag(for: state)


            // Only update sneak peek if there's actual content and something changed
            if shouldAutoPeekOnTrackChange && !state.title.isEmpty && !state.artist.isEmpty && state.isPlaying {
                self.updateSneakPeek()
            }
        } else if state.isExplicit != nil {
            self.refreshExplicitFlag(for: state)
        }

        let timeChanged = state.currentTime != self.elapsedTime
        let durationChanged = state.duration != self.songDuration
        let playbackRateChanged = state.playbackRate != self.playbackRate
        let shuffleChanged = state.isShuffled != self.isShuffled
        let repeatModeChanged = state.repeatMode != self.repeatMode

        if timeChanged {
            self.elapsedTime = state.currentTime
            // Update current lyric based on elapsed time
            self.updateCurrentLyric(for: state.currentTime)
        }

        if durationChanged {
            self.songDuration = state.duration
        }

        if playbackRateChanged {
            self.playbackRate = state.playbackRate
        }
        
        if shuffleChanged {
            self.isShuffled = state.isShuffled
        }

        if state.bundleIdentifier != self.bundleIdentifier {
            self.bundleIdentifier = state.bundleIdentifier
        }

        if repeatModeChanged {
            self.repeatMode = state.repeatMode
        }
        
        updateLiveStreamState(with: state)
        self.refreshLikedFlag(for: state)
        self.timestampDate = state.lastUpdated

        // Manage lyric sync task based on playback/lyrics availability
        if Defaults[.enableLyrics] && !self.syncedLyrics.isEmpty {
            // Ensure syncing runs while lyrics are enabled
            startLyricSync()
        } else {
            stopLyricSync()
        }
    }

    @MainActor
    private func refreshLikedFlag(for state: PlaybackState) {
        guard state.bundleIdentifier == SpotifyController.bundleIdentifier,
              SpotifyLibraryManager.shared.isAuthenticated,
              let lookupKey = SpotifyExplicitnessResolver.LookupKey(
                  contentIdentifier: state.contentIdentifier,
                  contentURL: state.contentURL
              )
        else {
            likedLookupTask?.cancel()
            likedLookupTask = nil
            likedLookupTrackID = nil
            if isCurrentTrackLiked != nil {
                isCurrentTrackLiked = nil
            }
            return
        }

        guard likedLookupTrackID != lookupKey.trackID else { return }

        likedLookupTask?.cancel()
        likeToggleTask?.cancel()
        likedLookupTrackID = lookupKey.trackID
        isCurrentTrackLiked = nil

        let trackID = lookupKey.trackID
        likedLookupTask = Task { [weak self] in
            let saved = await SpotifyLibraryManager.shared.isTrackSaved(trackID: trackID)
            guard !Task.isCancelled else { return }
            await MainActor.run {
                guard let self, self.likedLookupTrackID == trackID else { return }
                self.isCurrentTrackLiked = saved
            }
        }
    }

    @MainActor
    func toggleLike() {
        guard let trackID = likedLookupTrackID,
              let currentValue = isCurrentTrackLiked else { return }

        let targetValue = !currentValue
        isCurrentTrackLiked = targetValue

        likeToggleTask?.cancel()
        likeToggleTask = Task { [weak self] in
            let success = await SpotifyLibraryManager.shared.setTrackSaved(targetValue, trackID: trackID)
            guard !Task.isCancelled, !success else { return }
            await MainActor.run {
                guard let self, self.likedLookupTrackID == trackID else { return }
                self.isCurrentTrackLiked = currentValue
            }
        }
    }

    @MainActor
    private func refreshExplicitFlag(for state: PlaybackState) {
        if let explicitValue = state.isExplicit {
            explicitLookupTask?.cancel()
            explicitLookupTask = nil
            explicitLookupKey = nil

            if isCurrentTrackExplicit != explicitValue {
                isCurrentTrackExplicit = explicitValue
            }
            return
        }

        if state.bundleIdentifier == SpotifyController.bundleIdentifier,
           let spotifyLookupKey = SpotifyExplicitnessResolver.LookupKey(
               contentIdentifier: state.contentIdentifier,
               contentURL: state.contentURL
           ) {
            let lookupIdentifier = "spotify|\(spotifyLookupKey.trackID)"
            let fallbackTitle = state.title
            let fallbackArtist = state.artist
            let fallbackAlbum = state.album
            guard explicitLookupKey != lookupIdentifier else { return }

            explicitLookupTask?.cancel()
            explicitLookupKey = lookupIdentifier

            if isCurrentTrackExplicit {
                isCurrentTrackExplicit = false
            }

            explicitLookupTask = Task { [weak self] in
                let isExplicit = await SpotifyExplicitnessResolver.shared.resolve(key: spotifyLookupKey)

                guard !Task.isCancelled else { return }

                await MainActor.run {
                    guard let self,
                          self.explicitLookupKey == lookupIdentifier
                    else {
                        return
                    }

                    self.explicitLookupTask = nil

                    if let isExplicit {
                        self.isCurrentTrackExplicit = isExplicit
                    } else {
                        self.explicitLookupKey = nil
                        self.refreshGenericExplicitFlag(
                            title: fallbackTitle,
                            artist: fallbackArtist,
                            album: fallbackAlbum
                        )
                    }
                }
            }
            return
        }

        refreshGenericExplicitFlag(title: state.title, artist: state.artist, album: state.album)
    }

    @MainActor
    private func refreshGenericExplicitFlag(title: String, artist: String, album: String) {
        let lookupKey = MusicExplicitnessResolver.LookupKey(
            title: title,
            artist: artist,
            album: album
        )
        let lookupIdentifier = "generic|\(lookupKey.title)|\(lookupKey.artist)|\(lookupKey.album)"

        guard lookupKey.canResolve,
              !Self.placeholderTitles.contains(lookupKey.title),
              !Self.placeholderArtists.contains(lookupKey.artist)
        else {
            explicitLookupTask?.cancel()
            explicitLookupTask = nil
            explicitLookupKey = nil
            if isCurrentTrackExplicit {
                isCurrentTrackExplicit = false
            }
            return
        }

        guard explicitLookupKey != lookupIdentifier else { return }

        explicitLookupTask?.cancel()
        explicitLookupKey = lookupIdentifier

        if isCurrentTrackExplicit {
            isCurrentTrackExplicit = false
        }

        explicitLookupTask = Task { [weak self] in
            let isExplicit = await MusicExplicitnessResolver.shared.resolve(
                title: title,
                artist: artist,
                album: album
            )

            guard !Task.isCancelled else { return }

            await MainActor.run {
                guard let self,
                      self.explicitLookupKey == lookupIdentifier
                else {
                    return
                }

                self.isCurrentTrackExplicit = isExplicit
                self.explicitLookupTask = nil
            }
        }
    }

    private func triggerFlipAnimation() {
        // Debounce: rapid metadata updates (title, artwork, bundle arriving
        // separately for one track change) should only produce a single flip.
        guard !flipCooldownActive else { return }
        flipCooldownActive = true

        // Direction: positive rotation = next (page turn forward),
        //            negative rotation = previous (page turn backward).
        let delta: Double = lastFlipDirection == .forward ? 180 : -180
        withAnimation(.easeInOut(duration: flipAnimationDuration)) {
            flipAngle += delta
        }

        // Reset cooldown after the animation completes so the next
        // genuine track change can flip again.
        DispatchQueue.main.asyncAfter(deadline: .now() + flipAnimationDuration + 0.15) { [weak self] in
            self?.flipCooldownActive = false
        }
    }

    private func updateLiveStreamState(with state: PlaybackState) {
        let duration = state.duration
        let current = max(state.currentTime, elapsedTime)
        let hasKnownDuration = duration.isFinite && duration > 0
        let isPlaying = state.isPlaying

        if hasKnownDuration {
            liveStreamUnknownDurationCount = 0

            let remaining = duration - current
            let clampedDuration = max(duration, 0)
            let clampedCurrent = clampedDuration > 0
                ? max(0, min(current, clampedDuration))
                : max(0, current)
            let progress = clampedDuration > 0 ? clampedCurrent / clampedDuration : 0
            let sliderAppearsComplete = isPlaying && clampedDuration > 0 && progress >= 0.999
            let nearDurationEdge = isPlaying && remaining.isFinite && remaining <= 1.0 && clampedCurrent >= 10

            if sliderAppearsComplete {
                liveStreamCompletionObservationCount = min(liveStreamCompletionObservationCount + 1, 8)
                liveStreamCompletionReleaseCount = 0
            } else {
                liveStreamCompletionReleaseCount = min(liveStreamCompletionReleaseCount + 1, 8)
                if liveStreamCompletionObservationCount > 0 {
                    liveStreamCompletionObservationCount = max(liveStreamCompletionObservationCount - 1, 0)
                }
            }

            if nearDurationEdge || sliderAppearsComplete {
                liveStreamEdgeObservationCount = min(liveStreamEdgeObservationCount + 1, 12)
            } else if liveStreamEdgeObservationCount > 0 {
                liveStreamEdgeObservationCount = max(liveStreamEdgeObservationCount - 1, 0)
            }

            if !isLiveStream {
                if liveStreamCompletionObservationCount >= 3 || liveStreamEdgeObservationCount >= 5 {
                    isLiveStream = true
                }
            } else {
                let shouldClearForKnownDuration =
                    (duration > 10 && remaining > 5)
                    || (liveStreamCompletionObservationCount == 0
                        && liveStreamEdgeObservationCount == 0
                        && liveStreamCompletionReleaseCount >= 4)

                if shouldClearForKnownDuration {
                    isLiveStream = false
                }
            }
        } else if isPlaying {
            liveStreamEdgeObservationCount = max(liveStreamEdgeObservationCount - 1, 0)
            liveStreamCompletionObservationCount = max(liveStreamCompletionObservationCount - 1, 0)
            liveStreamCompletionReleaseCount = 0

            liveStreamUnknownDurationCount = min(liveStreamUnknownDurationCount + 1, 8)
            if liveStreamUnknownDurationCount >= 3 && !isLiveStream {
                isLiveStream = true
            }
        } else {
            liveStreamUnknownDurationCount = 0
            liveStreamEdgeObservationCount = 0
            liveStreamCompletionObservationCount = 0
            liveStreamCompletionReleaseCount = 0
        }
    }

    private func updateArtwork(_ artworkData: Data) {
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }

            if let artworkImage = NSImage(data: artworkData) {
                DispatchQueue.main.async { [weak self] in
                    self?.usingAppIconForArtwork = false
                    self?.updateAlbumArt(newAlbumArt: artworkImage)
                }
            }
        }
    }

    private func updateIdleState(state: Bool) {
        if state {
            isPlayerIdle = false
            debounceIdleTask?.cancel()
        } else {
            debounceIdleTask?.cancel()
            debounceIdleTask = Task { [weak self] in
                guard let self = self else { return }
                try? await Task.sleep(for: .seconds(Defaults[.waitInterval]))
                withAnimation {
                    self.isPlayerIdle = !self.isPlaying
                }
            }
        }
    }

    private var workItem: DispatchWorkItem?

    func updateAlbumArt(newAlbumArt: NSImage) {
        workItem?.cancel()
        workItem = DispatchWorkItem { [weak self] in
            withAnimation(.smooth) {
                self?.albumArt = newAlbumArt
                if Defaults[.coloredSpectrogram] {
                    self?.calculateAverageColor()
                }
            }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4, execute: workItem!)
    }

    // MARK: - Playback Position Estimation
    public func estimatedPlaybackPosition(at date: Date = Date()) -> TimeInterval {
        guard isPlaying else { return min(elapsedTime, songDuration) }

        let timeDifference = date.timeIntervalSince(timestampDate)
        let estimated = elapsedTime + (timeDifference * playbackRate)
        return min(max(0, estimated), songDuration)
    }

    func calculateAverageColor() {
        albumArt.prominentOpposingColors { [weak self] primary, secondary in
            DispatchQueue.main.async {
                withAnimation(.smooth) {
                    self?.avgColor = primary
                    self?.secondaryColor = secondary
                }
            }
        }
    }

    private func updateSneakPeek() {
        let standardControlsEnabled = Defaults[.showStandardMediaControls]
        let minimalisticEnabled = Defaults[.enableMinimalisticUI]

        guard standardControlsEnabled || minimalisticEnabled else { return }

        if isPlaying && Defaults[.enableSneakPeek] {
            if Defaults[.sneakPeekStyles] == .standard {
                coordinator.toggleSneakPeek(status: true, type: .music)
            } else {
                coordinator.toggleExpandingView(status: true, type: .music)
            }
        }
    }

    // MARK: - Public Methods for controlling playback
    func playPause() {
        Task {
            await activeController?.togglePlay()
        }
    }

    func play() {
        Task {
            await activeController?.play()
        }
    }

    func pause() {
        Task {
            await activeController?.pause()
        }
    }

    func toggleShuffle() {
        Task {
            await activeController?.toggleShuffle()
        }
    }

    func toggleRepeat() {
        Task {
            await activeController?.toggleRepeat()
        }
    }
    
    func togglePlay() {
        guard let controller = activeController else { return }
        let targetState = !isPlaying

        Task {
            await MainActor.run {
                pendingOptimisticPlayState = targetState
                applyPlayState(targetState, animation: .smooth(duration: 0.18))
            }

            if targetState {
                await controller.play()
            } else {
                await controller.pause()
            }
        }
    }

    func nextTrack() {
        Task {
            await activeController?.nextTrack()
        }
    }

    func previousTrack() {
        Task {
            await activeController?.previousTrack()
        }
    }

    func seek(to position: TimeInterval) {
        Task {
            await activeController?.seek(to: position)
        }
    }

    func seek(by offset: TimeInterval) {
        guard !isLiveStream else { return }
        let duration = songDuration
        guard duration > 0 else { return }

        let current = estimatedPlaybackPosition()
        let magnitude = abs(offset)

        if offset < 0, current <= magnitude {
            previousTrack()
            return
        }

        if offset > 0, (duration - current) <= magnitude {
            nextTrack()
            return
        }

        let target = min(max(0, current + offset), duration)
        seek(to: target)
    }

    @MainActor
    func handleSkipGesture(direction: SkipDirection) {
        guard Defaults[.enableHorizontalMusicGestures] else { return }
        guard !isPlayerIdle || bundleIdentifier != nil else { return }

        let behavior = Defaults[.musicGestureBehavior]

        switch behavior {
        case .track:
            if direction == .forward {
                lastFlipDirection = .forward
                nextTrack()
            } else {
                lastFlipDirection = .backward
                previousTrack()
            }
        case .tenSecond:
            let interval = Self.skipGestureSeekInterval
            let offset = direction == .forward ? interval : -interval
            seek(by: offset)
        }

        skipGestureToken = skipGestureToken &+ 1
        skipGesturePulse = SkipGesturePulse(
            token: skipGestureToken,
            direction: direction,
            behavior: behavior
        )
    }

    /// 把**此刻在放歌的那个 app** 弄到前面来（首页音乐块的封面点一下就走这里，docs/50 D-06）。
    ///
    /// 两条路，按「用户此刻看得到什么」分（与前台应用块同一条经验，docs/38 §已知限制 9）：
    /// 1. **进程还在** → `activate(options: [.activateAllWindows])`。实测（2026-10-16，LX Music
    ///    `cn.toside.music.desktop`）：它当时只有一枚 122×128 的迷你窗在屏上、主窗口是隐藏的，
    ///    这条一调，主窗口（1114×718）当场回来——**这是音乐软件最常见的状态**（窗口藏起来放歌），
    ///    也是「点了没反应」的成因；
    /// 2. **没在跑 / 激活被系统拒绝** → `openApplication(at:configuration:)`（程序坞点一下：
    ///    启动或投递 reopen）。
    ///
    /// 拿不到 `bundleIdentifier`（会话在做但曲目来源不明）时只记一条日志，不假装成功。
    /// 失败路径**一律进日志**（`log show --subsystem com.cmeng.gourd.music`）。
    func openMusicApp() {
        guard let bundleID = bundleIdentifier, !bundleID.isEmpty else {
            lyricsLog.notice("打开音乐软件失败：当前会话没有 bundleIdentifier")
            return
        }

        if let running = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).first,
           running.activate(options: [.activateAllWindows]) {
            lyricsLog.info("打开音乐软件：激活 \(running.localizedName ?? bundleID, privacy: .public)（\(bundleID, privacy: .public)）")
            return
        }

        guard let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else {
            lyricsLog.notice("打开音乐软件失败：系统里找不到 \(bundleID, privacy: .public) 对应的包")
            return
        }

        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        NSWorkspace.shared.openApplication(at: appURL, configuration: configuration) { [weak self] app, error in
            if let error {
                self?.lyricsLog.notice("打开音乐软件失败：\(bundleID, privacy: .public) / \(error.localizedDescription, privacy: .public)")
            } else {
                self?.lyricsLog.info("打开音乐软件：启动 \(app?.localizedName ?? bundleID, privacy: .public)（\(bundleID, privacy: .public)）")
            }
        }
    }

    func forceUpdate() {
        // Request immediate update from the active controller
        Task { [weak self] in
            if self?.activeController?.isActive() == true {
                if let youtubeController = self?.activeController as? YouTubeMusicController {
                    await youtubeController.pollPlaybackState()
                } else {
                    await self?.activeController?.updatePlaybackInfo()
                }
            }
        }
    }

    // MARK: - Lyrics Methods
    func fetchLyrics() {
        prepareLyricsForCurrentTrack(forceFetch: true, prioritizeVisibleResult: Defaults[.enableLyrics])
    }

    private func handleLyricsPreferenceChange(isEnabled: Bool) {
        showLyrics = isEnabled

        if isEnabled {
            // **这一条现在会自动去问**（docs/50 D-04 的连带效果）：瞬时故障不写缓存，所以「关掉
            // 再打开」时缓存里没有结论 → 直接落到下面那条取词路径。原来它命中的是「503 也被当成
            // 没有歌词」的那份缓存，打开开关什么都不会发生——用户看到的就是「歌词标志点了没用」。
            //
            // 刻意**不**在这里 `forceFetch: true`：词库**确实没有**的歌（200 空数组）那份结论是
            // 可信的、也是可复用的，每次拨开关都重问一遍等于白打（最多 4 条候选）——重问不出来的
            // 还是问不出来，只是给公共免费词库添流量。
            prepareLyricsForCurrentTrack(prioritizeVisibleResult: true)
        } else {
            discardLyrics()
        }
    }

    /// Drops any lyrics state and stops an in-flight fetch.
    private func discardLyrics() {
        activeLyricsKey = nil
        lyricsFetchKey = nil
        lyricsFetchID = nil
        lyricsFetchTask?.cancel()
        lyricsFetchTask = nil
        lyricsTransportRetryTask?.cancel()
        lyricsTransportRetryTask = nil
        syncedLyrics = []
        currentLyrics = ""
        currentLyricIndex = -1
        stopLyricSync()
    }

    /// - Parameters:
    ///   - forceFetch: 跳过缓存（用户主动要歌词 / 重试时用）。
    ///   - prioritizeVisibleResult: 期间显示「Loading lyrics...」占位。
    ///   - allowTransportRetry: 瞬时故障后是否排一次自动重试。**自动重试自己传 false**
    ///     ——否则失败会每 20s 自转一次，把一次取词变成常驻流量。
    private func prepareLyricsForCurrentTrack(
        forceFetch: Bool = false,
        prioritizeVisibleResult: Bool = false,
        allowTransportRetry: Bool = true
    ) {
        // `enableLyrics` reached only as far as the display: with lyrics switched
        // off the placeholder was suppressed, but the track title and artist were
        // still sent to LRCLIB on every track change, and nothing consumed the
        // reply. Stop before the request rather than after it.
        guard Defaults[.enableLyrics] else {
            discardLyrics()
            return
        }

        guard let lookup = currentLyricsLookupContext() else {
            discardLyrics()
            return
        }

        let key = lookup.key
        let shouldShowLoading = prioritizeVisibleResult
        let trackChanged = activeLyricsKey != key
        activeLyricsKey = key

        if trackChanged {
            syncedLyrics = []
            currentLyricIndex = -1
            currentLyrics = shouldShowLoading ? "Loading lyrics..." : ""
            stopLyricSync()
        }

        if !forceFetch, let cachedLyrics = lyricsCache[key] {
            applyLyricsToDisplay(cachedLyrics)
            return
        }

        if lyricsFetchKey == key {
            if shouldShowLoading && syncedLyrics.isEmpty {
                currentLyrics = "Loading lyrics..."
            }
            return
        }

        lyricsFetchTask?.cancel()
        // 新一次取词 = 上一次的「稍后重试」作废（同一条 key 的重试也在其中：这次就是最新的那次问）。
        lyricsTransportRetryTask?.cancel()
        lyricsFetchKey = key
        let fetchID = UUID()
        lyricsFetchID = fetchID

        if shouldShowLoading || syncedLyrics.isEmpty {
            currentLyrics = "Loading lyrics..."
        }

        let requestArtist = lookup.requestArtist
        let requestTitle = lookup.requestTitle
        let requestAlbum = lookup.requestAlbum
        // 「只按歌名」那一档要用**本机此刻报的时长**当闸（docs/50 D-11）：取值点在进入网络之前，
        // 免得取词期间换歌把时长换掉。
        let trackDuration = songDuration

        lyricsFetchTask = Task { [weak self] in
            guard let self else { return }

            do {
                let lyrics = try await self.fetchLyricsFromAPI(
                    artist: requestArtist,
                    title: requestTitle,
                    album: requestAlbum,
                    trackDuration: trackDuration
                )
                guard !Task.isCancelled else { return }

                await MainActor.run {
                    guard self.lyricsFetchID == fetchID, self.activeLyricsKey == key else { return }
                    self.storeLyricsInCache(lyrics, for: key)
                    self.lyricsFetchKey = nil
                    self.lyricsFetchID = nil
                    self.lyricsFetchTask = nil
                    self.applyLyricsToDisplay(lyrics)
                    if lyrics.isEmpty {
                        self.lyricsLog.info("词库确实没有这条：\(lookup.requestTitle, privacy: .public) — \(lookup.requestArtist, privacy: .public)")
                    } else {
                        self.lyricsLog.info("取词命中：\(lookup.requestTitle, privacy: .public) — \(lookup.requestArtist, privacy: .public)，\(lyrics.count) 行")
                    }
                }
            } catch {
                self.lyricsLog.error("取词失败（不算「没有歌词」、不写缓存）：\(String(describing: error), privacy: .public)")
                await MainActor.run {
                    guard self.lyricsFetchID == fetchID, self.activeLyricsKey == key else { return }
                    self.lyricsFetchKey = nil
                    self.lyricsFetchID = nil
                    self.lyricsFetchTask = nil
                    self.syncedLyrics = []
                    self.currentLyricIndex = -1
                    // **不写「No lyrics found」**：那是「词库确实没有这条」的措辞（docs/50 D-04）。
                    // 这里只是这一次没问出来，字幕位置留空，别给用户一个假结论。
                    self.currentLyrics = ""
                    self.stopLyricSync()
                    if allowTransportRetry {
                        self.scheduleTransportRetry(for: key)
                    }
                }
            }
        }
    }

    /// 瞬时故障之后排**一次**延迟重试（docs/50 D-05）：LRCLIB 的 503 是秒级抖动，等 20s 再问一次
    /// 常常就有了——用户不必为此去点歌词键。只一次：重试自己带 `allowTransportRetry: false`，
    /// 不会自转成轮询。切歌 / 关歌词时被 `discardLyrics` / 新一次取词取消。
    private func scheduleTransportRetry(for key: LyricsLookupKey) {
        lyricsTransportRetryTask?.cancel()
        lyricsTransportRetryTask = Task { [weak self] in
            try? await Task.sleep(
                nanoseconds: UInt64(LyricsFetchPolicy.transientAutoRetryDelaySeconds * 1_000_000_000)
            )
            guard !Task.isCancelled, let self else { return }
            await MainActor.run {
                guard self.activeLyricsKey == key, self.syncedLyrics.isEmpty else { return }
                // 这一枚已经用掉了：清空引用，免得下面那次取词把自己取消掉（`isCancelled` 会传染给
                // 整条 URLSession 请求，重试反而变成「永远取消」）。
                self.lyricsTransportRetryTask = nil
                self.prepareLyricsForCurrentTrack(
                    forceFetch: true,
                    prioritizeVisibleResult: false,
                    allowTransportRetry: false
                )
            }
        }
    }

    /// 取词：**先问本机播放器自己的歌词缓存，再按候选阶梯问 LRCLIB**（docs/50 D-01/D-02/D-11/D-14）。
    ///
    /// 两个返回态必须分清（这是「歌词按钮点了没用」的根因）：
    /// - **返回 `[]`** = 两边都**确实没有这条**（本地库里没有 + LRCLIB 所有候选都问过、都是 200 且空）
    ///   → 调用方可缓存；
    /// - **抛 `LyricsFetchFailure`** = 这一次**没问出来**（网络 / 超时 / 429 / 5xx）→ 调用方
    ///   **不许**缓存、不许当成「没有歌词」。
    ///
    /// 三个来源各有各的验法：**本机缓存**按歌名 + 歌手（+ 时长）在 `LxMusicLyricsCache` 里匹配
    /// （离线、与播放器界面逐行一致，见那边的口径）；LRCLIB 的**原样**那条沿用既有打分匹配
    /// （行为与改动前逐字一致）、**歌手/歌名变体**过 `accepts` 的同名 + 相关歌手闸、
    /// **只按歌名**那条过 `acceptsTitleOnly` 的同名 + 时长闸。
    private func fetchLyricsFromAPI(
        artist: String,
        title: String,
        album: String,
        trackDuration: TimeInterval
    ) async throws -> [LyricLine] {
        let queries = LyricsQueryPlanner.plan(title: title, artist: artist)
        guard !queries.isEmpty else { return [] }

        // ① **本机播放器的歌词缓存**（LX Music 的本地 SQLite，见 `LxMusicLyricsCache` 的文件头）：
        //    离线、与它自己界面上显示的逐行一致，因此排在 LRCLIB 前面。取不到就当没有，继续往下走。
        let titleCandidates: [String] = {
            var seen = Set<String>()
            return queries.map(\.title).filter { seen.insert($0).inserted }
        }()
        if let localText = LxMusicLyricsCache.shared.lyricText(
            titles: titleCandidates,
            artist: artist,
            duration: trackDuration
        ) {
            let synced = parseLRC(localText)
            // 有时间轴就逐行；只有纯文本歌词（没有 [mm:ss]）就整段当 plain（同 LRCLIB 的 plain 口径）。
            let lines = synced.isEmpty ? [LyricLine(timestamp: 0, text: localText)] : synced
            if !lines.isEmpty {
                lyricsLog.info("取词命中：LX Music 本地缓存（\(title, privacy: .public) — \(artist, privacy: .public)，\(lines.count) 行）")
                return lines
            }
        }

        // ② LRCLIB 的候选阶梯（原样 → 歌手/歌名变体 → 只按歌名 + 时长）。
        var lastFailure: LyricsFetchFailure?
        for (index, query) in queries.enumerated() {
            let results: [[String: Any]]
            do {
                results = try await searchLRCLIB(trackName: query.title, artistName: query.artist)
            } catch let failure as LyricsFetchFailure {
                // 这条查询的瞬时故障：不为它再叠候选（重试已在 `searchLRCLIB` 里用完），
                // 留给调用方决定要不要稍后再来。
                lastFailure = failure
                break
            }
            guard !results.isEmpty else { continue }

            let match: [String: Any]?
            switch query.kind {
            case .exact:
                // 原样那条：输入**逐字沿用改动前**的口径（三个串都先去变音符再打分），
                // 行为因此零变化（见 `docs/50` §做法 1）。
                let folded = { (value: String) -> String in
                    value.folding(options: .diacriticInsensitive, locale: .current)
                }
                match = bestLyricsMatch(
                    in: results,
                    artist: folded(query.artist),
                    title: folded(query.title),
                    album: folded(album)
                )
            case .artistVariant:
                match = results.first {
                    LyricsQueryPlanner.accepts(
                        resultTitle: $0["trackName"] as? String ?? "",
                        resultArtist: $0["artistName"] as? String ?? "",
                        query: query
                    )
                }
            case .titleOnly:
                // 「同名 + 时长」那一档：先把过关的都挑出来，再**有 synced 的优先、其次时长最接近**
                // （同一首歌在词库里可能有多版：本机实测「如果当时」有 316 / 314 / 317 三条）。
                let accepted = results.filter {
                    LyricsQueryPlanner.acceptsTitleOnly(
                        resultTitle: $0["trackName"] as? String ?? "",
                        queryTitle: query.title,
                        duration: Self.resultDuration($0),
                        trackDuration: trackDuration
                    )
                }
                match = accepted.sorted { lhs, rhs in
                    let lhsSynced = Self.hasSyncedLyrics(lhs)
                    let rhsSynced = Self.hasSyncedLyrics(rhs)
                    if lhsSynced != rhsSynced { return lhsSynced }
                    let lhsDelta = abs((Self.resultDuration(lhs) ?? trackDuration) - trackDuration)
                    let rhsDelta = abs((Self.resultDuration(rhs) ?? trackDuration) - trackDuration)
                    return lhsDelta < rhsDelta
                }.first
            }

            guard let match else { continue }
            let lines = lyricLines(from: match)
            guard !lines.isEmpty else { continue }
            if index > 0 {
                switch query.kind {
                case .titleOnly:
                    lyricsLog.info("取词命中用的是「同名 + 时长」档：\(query.title, privacy: .public) — 词库那版是 \(match["artistName"] as? String ?? "?", privacy: .public)（\(Self.resultDuration(match) ?? 0, privacy: .public)s ≈ 本机 \(trackDuration, privacy: .public)s）")
                case .artistVariant, .exact:
                    lyricsLog.info("取词命中用的是变体查询 #\(index)：\(query.title, privacy: .public) — \(query.artist, privacy: .public)")
                }
            }
            return lines
        }

        if let lastFailure { throw lastFailure }
        lyricsLog.info("两边都没有这条（LX Music 本地缓存 + LRCLIB 的 \(queries.count) 条候选都问过）：\(title, privacy: .public) — \(artist, privacy: .public)")
        return []
    }

    /// 结果里的 `duration`（秒，LRCLIB 给整数）；没有 / 不是数 → `nil`（那一档因此不放行）。
    private static func resultDuration(_ result: [String: Any]) -> TimeInterval? {
        if let number = result["duration"] as? NSNumber { return number.doubleValue }
        if let value = result["duration"] as? Double { return value }
        return nil
    }

    /// 结果里有没有时间轴歌词（排序时给 synced 的优先）。
    private static func hasSyncedLyrics(_ result: [String: Any]) -> Bool {
        !((result["syncedLyrics"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)).isEmpty
    }

    /// 问一次 LRCLIB（**带瞬时故障重试**，`LyricsFetchPolicy`）。空数组 = 词库没有这条。
    ///
    /// `artistName` 为空 = 「只按歌名」那一档：请求里**不带** `artist_name`（LRCLIB 按歌名跨歌手
    /// 返回，本机实测「如果当时」能拿到 `許嵩` / `Xu, Song` 等不同写法的那几条）。
    private func searchLRCLIB(trackName: String, artistName: String) async throws -> [[String: Any]] {
        // Normalize input and percent-encode
        let cleanArtist = artistName.folding(options: .diacriticInsensitive, locale: .current)
        let cleanTitle = trackName.folding(options: .diacriticInsensitive, locale: .current)
        guard let encodedTitle = cleanTitle.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) else {
            return []
        }

        var urlString = "https://lrclib.net/api/search?track_name=\(encodedTitle)"
        if !cleanArtist.isEmpty {
            guard let encodedArtist = cleanArtist.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) else {
                return []
            }
            urlString += "&artist_name=\(encodedArtist)"
        }
        guard let url = URL(string: urlString) else { return [] }
        var request = URLRequest(url: url)
        // LRCLIB 是公共免费服务、明确要求带上可识别的 UA（默认的 CFNetwork 串什么都没有）。
        request.setValue("Gourd/\(MusicManager.lyricsUserAgentVersion) (macOS lyrics lookup)", forHTTPHeaderField: "User-Agent")

        let delays = LyricsFetchPolicy.retryDelaysMilliseconds
        var attempt = 0
        while true {
            attempt += 1
            do {
                let (data, response) = try await URLSession.shared.data(for: request)
                let status = (response as? HTTPURLResponse)?.statusCode ?? 200
                switch LyricsFetchPolicy.classify(statusCode: status) {
                case .ok:
                    return Self.parsedResults(from: data)
                case .permanent:
                    // 请求本身不对（4xx 里除 408/425/429）：没有重试的价值，按「没有这条」处理。
                    lyricsLog.warning("LRCLIB 确定性失败 HTTP \(status)，按「没有这条」处理")
                    return []
                case .transient:
                    guard attempt <= delays.count else {
                        throw LyricsFetchFailure(reason: "HTTP \(status)", attempts: attempt)
                    }
                    lyricsLog.warning("LRCLIB 瞬时故障 HTTP \(status)（第 \(attempt) 次），\(delays[attempt - 1])ms 后重试")
                }
            } catch let failure as LyricsFetchFailure {
                throw failure
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                guard attempt <= delays.count else {
                    throw LyricsFetchFailure(reason: error.localizedDescription, attempts: attempt)
                }
                lyricsLog.warning("LRCLIB 请求失败（第 \(attempt) 次）：\(error.localizedDescription, privacy: .public)")
            }
            try? await Task.sleep(nanoseconds: UInt64(delays[attempt - 1]) * 1_000_000)
        }
    }

    /// LRCLIB 的 UA 版本段（仓库版本号，避免每次发版漏更新——取不到就回落 `1.0`）。
    private static let lyricsUserAgentVersion: String = {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
    }()

    /// 把一次 200 的响应体变成「候选结果数组」。
    ///
    /// 数组那一支是 LRCLIB 的正常形态；非数组那一支是既有实现的兜底（把响应体当 LRC / 纯文本整段
    /// 处理），本次**逐字保留**，只是把它折叠成同一个类型——`plainLyrics` / `syncedLyrics` 两个键
    /// 就是它的两种落点，下游 `lyricLines(from:)` 因此只有一条路。
    private static func parsedResults(from data: Data) -> [[String: Any]] {
        if let jsonArray = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] {
            return jsonArray
        }

        guard let body = String(data: data, encoding: .utf8) else { return [] }
        let trimmed = body.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }

        if let json = try? JSONSerialization.jsonObject(with: data, options: []) {
            if let dict = json as? [String: Any], let synced = dict["syncedLyrics"] as? String {
                return [["syncedLyrics": synced]]
            }
            if let array = json as? [Any], array.isEmpty { return [] }
        }

        // Otherwise treat as plain lyrics blob
        return [["plainLyrics": trimmed]]
    }

    /// 从一条结果里取歌词行（synced 优先，其次 plain）。
    private func lyricLines(from result: [String: Any]) -> [LyricLine] {
        let plain = (result["plainLyrics"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let synced = (result["syncedLyrics"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        if !synced.isEmpty {
            return parseLRC(synced)
        } else if !plain.isEmpty {
            return [LyricLine(timestamp: 0, text: plain)]
        }
        return []
    }

    private func currentLyricsLookupContext() -> (key: LyricsLookupKey, requestArtist: String, requestTitle: String, requestAlbum: String)? {
        let requestArtist = normalizedLyricsRequestComponent(artistName)
        let requestTitle = normalizedLyricsTitle(songTitle)
        let requestAlbum = normalizedLyricsRequestComponent(album)

        let key = LyricsLookupKey(
            title: requestTitle.lowercased(),
            artist: requestArtist.lowercased(),
            album: requestAlbum.lowercased()
        )

        return key.isValid ? (key, requestArtist, requestTitle, requestAlbum) : nil
    }

    private func normalizedLyricsRequestComponent(_ value: String) -> String {
        value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
    }

    private func normalizedLyricsTitle(_ value: String) -> String {
        var normalized = normalizedLyricsRequestComponent(value)
        let cleanupPatterns = [
            "\\s*\\((feat\\.?|ft\\.?|featuring)[^\\)]*\\)",
            "\\s*\\[(feat\\.?|ft\\.?|featuring)[^\\]]*\\]",
            "\\s*-\\s*(feat\\.?|ft\\.?|featuring)\\s+.*$",
            "\\s*\\((remaster(ed)?|live|mono|stereo)[^\\)]*\\)$",
            "\\s*\\[(remaster(ed)?|live|mono|stereo)[^\\]]*\\]$"
        ]

        for pattern in cleanupPatterns {
            normalized = normalized.replacingOccurrences(
                of: pattern,
                with: "",
                options: [.regularExpression, .caseInsensitive]
            )
        }

        return normalizedLyricsRequestComponent(normalized)
    }

    private func bestLyricsMatch(in results: [[String: Any]], artist: String, title: String, album: String) -> [String: Any]? {
        let normalizedArtist = artist.lowercased()
        let normalizedTitle = title.lowercased()
        let normalizedAlbum = album.lowercased()

        return results.max { lhs, rhs in
            lyricsMatchScore(for: lhs, artist: normalizedArtist, title: normalizedTitle, album: normalizedAlbum)
                < lyricsMatchScore(for: rhs, artist: normalizedArtist, title: normalizedTitle, album: normalizedAlbum)
        }
    }

    private func lyricsMatchScore(for result: [String: Any], artist: String, title: String, album: String) -> Int {
        let resultArtist = ((result["artistName"] as? String) ?? "").lowercased()
        let resultTitle = ((result["trackName"] as? String) ?? "").lowercased()
        let resultAlbum = ((result["albumName"] as? String) ?? "").lowercased()

        var score = 0

        if resultTitle == title { score += 8 }
        else if resultTitle.contains(title) || title.contains(resultTitle) { score += 4 }

        if resultArtist == artist { score += 8 }
        else if resultArtist.contains(artist) || artist.contains(resultArtist) { score += 4 }

        if !album.isEmpty {
            if resultAlbum == album { score += 4 }
            else if resultAlbum.contains(album) || album.contains(resultAlbum) { score += 2 }
        }

        if !(result["syncedLyrics"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            score += 3
        }

        return score
    }

    private func applyLyricsToDisplay(_ lyrics: [LyricLine]) {
        syncedLyrics = lyrics
        currentLyricIndex = -1

        guard !lyrics.isEmpty else {
            currentLyrics = Defaults[.enableLyrics] ? "No lyrics found" : ""
            stopLyricSync()
            return
        }

        let playbackPosition = max(estimatedPlaybackPosition(), elapsedTime)
        updateCurrentLyric(for: playbackPosition)

        if currentLyricIndex == -1, let firstLine = lyrics.first?.text {
            currentLyrics = firstLine
        }

        if Defaults[.enableLyrics] {
            startLyricSync()
        } else {
            stopLyricSync()
        }
    }

    /// LRC 解析交给纯函数 `LyricsTextParser.parseLRC`（2026-10-16 / docs/50 D-15：原来这里那份
    /// 只认 1～2 位小数，带毫秒时间轴的行会被整行丢掉——实测 27 行的歌词只解出 5 行）。
    private func parseLRC(_ lrc: String) -> [LyricLine] {
        LyricsTextParser.parseLRC(lrc)
    }

    func updateCurrentLyric(for elapsedTime: TimeInterval) {
        guard !syncedLyrics.isEmpty else { return }

        // Find the current lyric based on elapsed time
        var newIndex = -1
        for (index, lyric) in syncedLyrics.enumerated() {
            if elapsedTime >= lyric.timestamp {
                newIndex = index
            } else {
                break
            }
        }

        if newIndex != currentLyricIndex {
            currentLyricIndex = newIndex
            if newIndex >= 0 && newIndex < syncedLyrics.count {
                currentLyrics = syncedLyrics[newIndex].text
            }
        }
    }

    // Start a background task that periodically updates the displayed lyric
    private func startLyricSync() {
        // If already running, keep it
        if lyricSyncTask != nil { return }

        lyricSyncTask = Task { [weak self] in
            guard let self = self else { return }
            while !Task.isCancelled {
                // Compute estimated playback position and update lyric
                let position = self.estimatedPlaybackPosition()
                await MainActor.run {
                    self.updateCurrentLyric(for: position)
                }

                // Sleep ~300ms between updates
                try? await Task.sleep(nanoseconds: 300_000_000)
            }
        }
    }

    private func stopLyricSync() {
        lyricSyncTask?.cancel()
        lyricSyncTask = nil
    }

    // MARK: - Video Artwork

    func fetchVideoArtwork() {
        guard Defaults[.lockScreenMusicFullscreenVideoArtwork] else {
            videoArtworkURL = nil
            return
        }
        // Se il player non è Apple Music, non toccare videoArtworkURL:
        // SpotifyController gestisce il canvas in modo autonomo tramite liveArtworkURL.
        guard bundleIdentifier == "com.apple.Music" else {
            return
        }

        let title = songTitle
        let artist = artistName

        Task {
            let url = await AnimatedArtworkManager.shared.fetchAnimatedArtworkURL(
                title: title, artist: artist
            )
            await MainActor.run {
                self.videoArtworkURL = url
            }
        }
    }

    func toggleLyrics() {
        // Toggle the UI state first so the views can react immediately.
        showLyrics.toggle()

        // If lyrics are requested to be shown but we don't have any yet,
        // show a loading placeholder and start fetching asynchronously.
        if showLyrics && syncedLyrics.isEmpty {
            // Provide immediate feedback so the UI can show a loading state.
            currentLyrics = "Loading lyrics..."

            Task {
                await fetchLyrics()

                // If fetch completed but no lyrics were found, show a friendly message.
                await MainActor.run {
                    if self.syncedLyrics.isEmpty && self.currentLyrics.isEmpty {
                        self.currentLyrics = "No lyrics found"
                    }
                }
            }
        }
    }
}

// MARK: - Media Branding

extension MusicManager {
    var brandAccentColor: Color {
        Self.brandAccentColor(for: Defaults[.mediaController], bundleIdentifier: bundleIdentifier)
    }

    private static func brandAccentColor(for controller: MediaControllerType, bundleIdentifier: String?) -> Color {
        switch controller {
        case .appleMusic:
            return appleMusicPink
        case .spotify:
            return spotifyGreen
        case .amazonMusic:
            return amazonOrange
        case .cider:
            return .accentColor
        case .nowPlaying:
            if let bundleIdentifier,
               let bundleColor = brandAccentColor(forBundleIdentifier: bundleIdentifier) {
                return bundleColor
            }
            fallthrough
        case .youtubeMusic:
            return .accentColor
        }
    }

    private static func brandAccentColor(forBundleIdentifier bundleIdentifier: String) -> Color? {
        switch bundleIdentifier {
        case "com.apple.Music":
            return appleMusicPink
        case "com.spotify.client":
            return spotifyGreen
        case AmazonMusicController.bundleIdentifier:
            return amazonOrange
        case CiderController.bundleIdentifier:
            return .accentColor
        default:
            return nil
        }
    }

    private static let appleMusicPink = Color(red: 0.999, green: 0.171, blue: 0.331)
    private static let spotifyGreen = Color(red: 0.0, green: 0.857, blue: 0.302)
    private static let amazonOrange = Color(red: 1.0, green: 0.6, blue: 0.0)
}

// MARK: - Album Art Flip Helper

private struct AlbumArtFlipModifier: ViewModifier {
    let angle: Double

    func body(content: Content) -> some View {
        content
            .rotation3DEffect(
                .degrees(angle),
                axis: (x: 0, y: 1, z: 0),
                anchor: .center,
                anchorZ: 0,
                perspective: 0.5
            )
            // Counter-rotate the content so the image never appears mirrored.
            // At odd multiples of 180° the 3D rotation mirrors along X;
            // applying an opposite scaleEffect cancels that out.
            .scaleEffect(x: cosineSign(for: angle), y: 1)
    }

    /// Returns +1 when the front face is showing, −1 when the back face is showing.
    private func cosineSign(for degrees: Double) -> CGFloat {
        let cos = Darwin.cos(degrees * .pi / 180)
        // Use a small tolerance to avoid flickering exactly at 90°/270°.
        if cos > 0.001 { return 1 }
        if cos < -0.001 { return -1 }
        return degrees.truncatingRemainder(dividingBy: 360) >= 0 ? -1 : 1
    }
}

extension View {
    func albumArtFlip(angle: Double) -> some View {
        modifier(AlbumArtFlipModifier(angle: angle))
    }
}
