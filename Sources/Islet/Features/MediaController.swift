import AppKit
import SwiftUI

struct NowPlaying: Equatable {
    var title: String
    var artist: String
    var album: String
    var duration: Double
    var trackID: String
}

enum MediaSource: String, CaseIterable {
    case spotify, music

    var appName: String {
        switch self {
        case .spotify: return "Spotify"
        case .music: return "Music"
        }
    }

    var bundleID: String {
        switch self {
        case .spotify: return "com.spotify.client"
        case .music: return "com.apple.Music"
        }
    }

    var notificationName: Notification.Name {
        switch self {
        case .spotify: return Notification.Name("com.spotify.client.PlaybackStateChanged")
        case .music: return Notification.Name("com.apple.Music.playerInfo")
        }
    }

    var isRunning: Bool {
        NSRunningApplication.runningApplications(withBundleIdentifier: bundleID)
            .contains(where: { !$0.isTerminated })
    }
}

/// Reads now playing info from Spotify and Apple Music through AppleScript
/// and sends transport commands back. macOS asks for Automation permission
/// the first time each player is contacted.
final class MediaController: ObservableObject {
    @Published private(set) var track: NowPlaying?
    @Published private(set) var isPlaying = false
    @Published private(set) var artwork: NSImage?
    @Published private(set) var tint: Color = .white
    @Published private(set) var source: MediaSource?
    @Published private(set) var position: Double = 0
    @Published private(set) var positionDate = Date()
    @Published private(set) var volume: Double = 50
    @Published private(set) var isShuffling = false

    private struct SourceState {
        var track: NowPlaying
        var isPlaying: Bool
        var position: Double
        var date: Date
        var artworkURL: String?
        var volume: Double?
        var isShuffling: Bool?
    }

    private static let separator = "|~|"
    private let queue = DispatchQueue(label: "islet.applescript", qos: .userInitiated)
    private var states: [MediaSource: SourceState] = [:]
    private var lastActive: MediaSource?
    private var pollTimer: Timer?
    private var artworkKey: String?
    private var observers: [NSObjectProtocol] = []
    private var volumeSetAt = Date.distantPast

    // MARK: - Lifecycle

    /// Stops listening to players and clears what is shown.
    func stop() {
        pollTimer?.invalidate()
        pollTimer = nil
        observers.forEach { DistributedNotificationCenter.default().removeObserver($0) }
        observers.removeAll()
        states.removeAll()
        resolve()
    }

    func start() {
        guard pollTimer == nil else { return }
        for source in MediaSource.allCases {
            let token = DistributedNotificationCenter.default().addObserver(
                forName: source.notificationName, object: nil, queue: .main
            ) { [weak self] note in
                self?.handleNotification(note, from: source)
            }
            observers.append(token)
        }

        let timer = Timer(timeInterval: 2.0, repeats: true) { [weak self] _ in self?.refreshAll() }
        RunLoop.main.add(timer, forMode: .common)
        pollTimer = timer
        refreshAll()
    }

    /// Elapsed seconds in the current track, interpolated between polls.
    func elapsed(at date: Date = Date()) -> Double {
        guard let track else { return 0 }
        let value = isPlaying ? position + date.timeIntervalSince(positionDate) : position
        return min(max(value, 0), max(track.duration, 0))
    }

    // MARK: - Commands

    func togglePlayPause() {
        guard let source else { return }
        position = elapsed()
        positionDate = Date()
        isPlaying.toggle()
        if var state = states[source] {
            state.isPlaying = isPlaying
            state.position = position
            state.date = positionDate
            states[source] = state
        }
        run("tell application \"\(source.appName)\" to playpause")
        refreshSoon(source)
    }

    func next() {
        guard let source else { return }
        run("tell application \"\(source.appName)\" to next track")
        refreshSoon(source)
    }

    func previous() {
        guard let source else { return }
        run("tell application \"\(source.appName)\" to previous track")
        refreshSoon(source)
    }

    func seek(toFraction fraction: Double) {
        guard let source, let track, track.duration > 0 else { return }
        let target = min(max(fraction, 0), 1) * track.duration
        position = target
        positionDate = Date()
        if var state = states[source] {
            state.position = target
            state.date = positionDate
            states[source] = state
        }
        let seconds = String(format: "%.2f", locale: Locale(identifier: "en_US_POSIX"), target)
        run("tell application \"\(source.appName)\" to set player position to \(seconds)")
    }

    /// Sets the player's own volume, from 0 to 100.
    func setVolume(_ value: Double) {
        guard let source else { return }
        let clamped = min(max(value, 0), 100)
        volume = clamped
        volumeSetAt = Date()
        run("tell application \"\(source.appName)\" to set sound volume to \(Int(clamped.rounded()))")
    }

    func toggleShuffle() {
        guard let source else { return }
        let newValue = !isShuffling
        isShuffling = newValue
        volumeSetAt = Date()
        let property = source == .spotify ? "shuffling" : "shuffle enabled"
        run("tell application \"\(source.appName)\" to set \(property) to \(newValue)")
    }

    func open(_ source: MediaSource) {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: source.bundleID) else { return }
        NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration(), completionHandler: nil)
    }

    func isInstalled(_ source: MediaSource) -> Bool {
        NSWorkspace.shared.urlForApplication(withBundleIdentifier: source.bundleID) != nil
    }

    // MARK: - Refreshing

    private func handleNotification(_ note: Notification, from source: MediaSource) {
        let playerState = (note.userInfo?["Player State"] as? String)?.lowercased()
        if playerState == "stopped" {
            // The player may be quitting. Scripting it now would relaunch it.
            states[source] = nil
            resolve()
            return
        }
        if playerState == "playing" { lastActive = source }
        refreshSoon(source, delay: 0.05)
    }

    private func refreshSoon(_ source: MediaSource, delay: TimeInterval = 0.25) {
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
            self?.refresh(source)
        }
    }

    private func refreshAll() {
        for source in MediaSource.allCases { refresh(source) }
    }

    private func refresh(_ source: MediaSource) {
        guard source.isRunning else {
            if states[source] != nil {
                states[source] = nil
                resolve()
            }
            return
        }
        run(stateScript(for: source)) { [weak self] descriptor in
            guard let self else { return }
            self.states[source] = self.parse(descriptor?.stringValue, source: source)
            self.resolve()
        }
    }

    private func stateScript(for source: MediaSource) -> String {
        let sep = Self.separator
        switch source {
        case .spotify:
            return """
            tell application "Spotify"
                if player state is stopped then return "stopped"
                set t to current track
                return (player state as string) & "\(sep)" & (name of t) & "\(sep)" & (artist of t) & "\(sep)" & (album of t) & "\(sep)" & (duration of t) & "\(sep)" & (player position) & "\(sep)" & (id of t) & "\(sep)" & (artwork url of t) & "\(sep)" & (sound volume) & "\(sep)" & (shuffling)
            end tell
            """
        case .music:
            return """
            tell application "Music"
                if player state is stopped then return "stopped"
                set t to current track
                return (player state as string) & "\(sep)" & (name of t) & "\(sep)" & (artist of t) & "\(sep)" & (album of t) & "\(sep)" & (duration of t) & "\(sep)" & (player position) & "\(sep)" & (name of t) & (artist of t) & (album of t) & "\(sep)" & "" & "\(sep)" & (sound volume) & "\(sep)" & (shuffle enabled)
            end tell
            """
        }
    }

    private func parse(_ raw: String?, source: MediaSource) -> SourceState? {
        guard let raw, raw != "stopped" else { return nil }
        let parts = raw.components(separatedBy: Self.separator)
        guard parts.count >= 7 else { return nil }

        func number(_ text: String) -> Double {
            Double(text.replacingOccurrences(of: ",", with: ".")) ?? 0
        }

        var duration = number(parts[4])
        if source == .spotify { duration /= 1000 } // Spotify reports milliseconds

        let track = NowPlaying(title: parts[1], artist: parts[2], album: parts[3], duration: duration, trackID: parts[6])
        return SourceState(
            track: track,
            isPlaying: parts[0].lowercased() == "playing",
            position: number(parts[5]),
            date: Date(),
            artworkURL: parts.count > 7 && !parts[7].isEmpty ? parts[7] : nil,
            volume: parts.count > 8 ? number(parts[8]) : nil,
            isShuffling: parts.count > 9 ? parts[9].lowercased() == "true" : nil
        )
    }

    /// Chooses which player the island should show.
    private func resolve() {
        let playing = states.filter { $0.value.isPlaying }
        let chosen: MediaSource?
        if let last = lastActive, playing[last] != nil {
            chosen = last
        } else if let first = playing.keys.first {
            chosen = first
        } else if let last = lastActive, states[last] != nil {
            chosen = last
        } else {
            chosen = states.keys.first
        }

        guard let chosen, let state = states[chosen] else {
            if track != nil { track = nil }
            if isPlaying { isPlaying = false }
            if source != nil { source = nil }
            if artwork != nil { artwork = nil }
            if tint != .white { tint = .white }
            artworkKey = nil
            return
        }

        if state.isPlaying { lastActive = chosen }
        if source != chosen { source = chosen }
        if track != state.track { track = state.track }
        if isPlaying != state.isPlaying { isPlaying = state.isPlaying }
        position = state.position
        positionDate = state.date
        // Skip values read just after a local change, so the controls do not jump back.
        if Date().timeIntervalSince(volumeSetAt) > 2.5 {
            if let newVolume = state.volume, abs(newVolume - volume) > 0.5 { volume = newVolume }
            if let shuffling = state.isShuffling, shuffling != isShuffling { isShuffling = shuffling }
        }
        loadArtworkIfNeeded(for: chosen, state: state)
    }

    // MARK: - Artwork

    private func loadArtworkIfNeeded(for source: MediaSource, state: SourceState) {
        let key = source.rawValue + state.track.trackID
        guard key != artworkKey else { return }
        artworkKey = key

        switch source {
        case .spotify:
            guard let text = state.artworkURL, let url = URL(string: text) else {
                setArtwork(nil, key: key)
                return
            }
            URLSession.shared.dataTask(with: url) { [weak self] data, _, _ in
                let image = data.flatMap { NSImage(data: $0) }
                DispatchQueue.main.async { self?.setArtwork(image, key: key) }
            }.resume()
        case .music:
            run("tell application \"Music\" to get raw data of artwork 1 of current track") { [weak self] descriptor in
                let image = descriptor.flatMap { NSImage(data: $0.data) }
                self?.setArtwork(image, key: key)
            }
        }
    }

    private func setArtwork(_ image: NSImage?, key: String) {
        guard key == artworkKey else { return }
        artwork = image
        tint = image?.vibrantAverageColor.map { Color(nsColor: $0) } ?? .white
    }

    // MARK: - AppleScript

    private func run(_ script: String, completion: ((NSAppleEventDescriptor?) -> Void)? = nil) {
        queue.async {
            var error: NSDictionary?
            let result = NSAppleScript(source: script)?.executeAndReturnError(&error)
            guard let completion else { return }
            let value = error == nil ? result : nil
            DispatchQueue.main.async { completion(value) }
        }
    }
}

extension NSImage {
    /// Average color of the image, lifted so it stays readable on black.
    var vibrantAverageColor: NSColor? {
        guard let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: 1, pixelsHigh: 1,
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 4, bitsPerPixel: 32
        ), let context = NSGraphicsContext(bitmapImageRep: rep) else { return nil }

        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = context
        draw(in: NSRect(x: 0, y: 0, width: 1, height: 1), from: .zero, operation: .copy, fraction: 1)
        context.flushGraphics()
        NSGraphicsContext.restoreGraphicsState()

        guard let color = rep.colorAt(x: 0, y: 0)?.usingColorSpace(.deviceRGB) else { return nil }
        var hue: CGFloat = 0
        var saturation: CGFloat = 0
        var brightness: CGFloat = 0
        var alpha: CGFloat = 0
        color.getHue(&hue, saturation: &saturation, brightness: &brightness, alpha: &alpha)
        return NSColor(
            hue: hue,
            saturation: min(max(saturation, 0.35), 0.75),
            brightness: max(brightness, 0.85),
            alpha: 1
        )
    }
}
