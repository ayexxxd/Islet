import SwiftUI

/// Now playing tab with artwork, scrubbing and transport controls.
struct MediaView: View {
    @EnvironmentObject var media: MediaController
    @EnvironmentObject var settings: AppSettings
    @EnvironmentObject var state: IslandState

    private var accent: Color { settings.accent(artworkTint: media.tint) }

    var body: some View {
        ZStack {
            if let track = media.track {
                player(track)
                    .transition(.islandContent)
            } else {
                emptyState
                    .transition(.islandContent)
            }
        }
        .padding(.horizontal, inset)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        .animation(settings.animation, value: media.track == nil)
    }

    /// Equal gap on the left, top and bottom of the artwork.
    private var inset: CGFloat { 22 }
    private var artworkSize: CGFloat { max(state.contentHeight - inset * 2, 80) }

    private func player(_ track: NowPlaying) -> some View {
        HStack(spacing: 18) {
            ArtworkView(image: media.artwork, cornerRadius: 16)
                .frame(width: artworkSize, height: artworkSize)
                .contentShape(Rectangle())
                .onTapGesture { if let source = media.source { media.open(source) } }
                .help("Open the player")
                .shadow(color: media.tint.opacity(media.artwork == nil ? 0 : 0.45), radius: 16, x: 0, y: 6)
                .scaleEffect(media.isPlaying ? 1 : 0.9)
                .animation(.spring(response: 0.4, dampingFraction: 0.6), value: media.isPlaying)
                .id(track.trackID)
                .transition(.opacity.combined(with: .scale(scale: 0.85)))

            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(track.title)
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundColor(.white)
                            .lineLimit(1)
                        Text(track.artist.isEmpty ? track.album : track.artist)
                            .font(.system(size: 12))
                            .foregroundColor(Color.white.opacity(0.6))
                            .lineLimit(1)
                    }
                    .id(track.trackID)
                    .transition(.islandContent)
                    Spacer(minLength: 8)
                    if settings.showVisualizer {
                        AudioBars(isPlaying: media.isPlaying, color: accent, barCount: 6, maxHeight: 18)
                            .padding(.top, 2)
                    }
                }

                Spacer(minLength: 6)
                progress(track)
                Spacer(minLength: 4)
                controls
            }
            .frame(height: artworkSize)
        }
        .animation(settings.animation, value: track.trackID)
    }

    private func progress(_ track: NowPlaying) -> some View {
        TimelineView(.periodic(from: .now, by: 0.5)) { context in
            let elapsed = media.elapsed(at: context.date)
            let fraction = track.duration > 0 ? elapsed / track.duration : 0
            VStack(spacing: 1) {
                ScrubBar(progress: fraction, tint: accent) { value in
                    media.seek(toFraction: value)
                }
                HStack {
                    Text(formatTime(elapsed))
                    Spacer()
                    Text(formatTime(track.duration))
                }
                .font(.system(size: 10, weight: .medium, design: .rounded))
                .monospacedDigit()
                .foregroundColor(Color.white.opacity(0.5))
            }
        }
    }

    private var controls: some View {
        HStack(spacing: 0) {
            if settings.playerExtrasEnabled {
                Button(action: { media.toggleShuffle() }) {
                    Image(systemName: "shuffle")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(media.isShuffling ? accent : Color.white.opacity(0.45))
                        .frame(width: 26, height: 30)
                        .contentShape(Rectangle())
                }
                .help("Shuffle")
                .frame(width: 66, alignment: .leading)
            }

            Spacer(minLength: 0)
            HStack(spacing: 14) {
                Button(action: { media.previous() }) {
                    Image(systemName: "backward.fill")
                        .font(.system(size: 17))
                        .frame(width: 34, height: 30)
                        .contentShape(Rectangle())
                }
                Button(action: { media.togglePlayPause() }) {
                    Image(systemName: media.isPlaying ? "pause.fill" : "play.fill")
                        .font(.system(size: 24))
                        .frame(width: 38, height: 30)
                        .contentShape(Rectangle())
                }
                Button(action: { media.next() }) {
                    Image(systemName: "forward.fill")
                        .font(.system(size: 17))
                        .frame(width: 34, height: 30)
                        .contentShape(Rectangle())
                }
            }
            Spacer(minLength: 0)

            if settings.playerExtrasEnabled {
                HStack(spacing: 4) {
                    Image(systemName: media.volume < 1 ? "speaker.slash.fill" : "speaker.wave.2.fill")
                        .font(.system(size: 9))
                        .foregroundColor(Color.white.opacity(0.45))
                        .frame(width: 14)
                    ScrubBar(progress: media.volume / 100, tint: Color.white.opacity(0.75)) { value in
                        media.setVolume(value * 100)
                    }
                }
                .frame(width: 66)
                .help("Player volume")
            }
        }
        .buttonStyle(IslandButtonStyle())
        .foregroundColor(.white)
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "music.note")
                .font(.system(size: 26, weight: .semibold))
                .foregroundColor(Color.white.opacity(0.35))
            Text("Nothing playing")
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(Color.white.opacity(0.6))
            HStack(spacing: 8) {
                ForEach(MediaSource.allCases, id: \.self) { source in
                    if media.isInstalled(source) {
                        Button(action: { media.open(source) }) {
                            Text("Open \(source.appName)")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundColor(.white)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 6)
                                .background(Capsule().fill(Color.white.opacity(0.12)))
                        }
                        .buttonStyle(IslandButtonStyle())
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
