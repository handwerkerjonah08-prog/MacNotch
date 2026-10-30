import AppKit
import NotchCore
import SwiftUI

struct NowPlayingCard: View {
    @EnvironmentObject private var music: MusicController

    var body: some View {
        WidgetCard(width: IslandMetrics.cardWidth(for: .nowPlaying, shortcutCount: 0)) {
            if music.needsPermission {
                permissionState
            } else if let track = music.track, music.hasTrack {
                player(track)
            } else {
                idleState
            }
        }
    }

    private func player(_ track: TrackInfo) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .center, spacing: 10) {
                Button { music.openMusic() } label: {
                    ArtworkView(image: music.artwork, size: 46, radius: 11)
                        .id(track.key)
                        .transition(.scale(scale: 0.8).combined(with: .opacity))
                        .shadow(color: music.accent.opacity(0.35), radius: 8, y: 2)
                }
                .buttonStyle(.plain)
                .help("Open Music")

                VStack(alignment: .leading, spacing: 1) {
                    Text(track.title)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.white)
                    Text(track.artist.isEmpty ? track.album : track.artist)
                        .font(.system(size: 12, weight: .regular))
                        .foregroundStyle(Theme.secondary)
                }
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)

                WaveformView(isPlaying: music.isPlaying, color: music.accent, barCount: 5, barWidth: 2.6, maxHeight: 16)
                    .frame(width: 24)
            }

            Spacer(minLength: 6)

            TimelineView(.periodic(from: .now, by: 0.5)) { context in
                let duration = track.duration
                let elapsed = music.elapsed(at: context.date)
                HStack(spacing: 8) {
                    Text(TimeFormatting.clock(elapsed))
                        .frame(width: 34, alignment: .leading)
                    ScrubBar(
                        progress: duration > 0 ? elapsed / duration : 0,
                        isEnabled: duration > 0,
                        onSeek: { music.seek(toFraction: $0) }
                    )
                    Text(duration > 0 ? TimeFormatting.remaining(elapsed: elapsed, duration: duration) : "LIVE")
                        .frame(width: 38, alignment: .trailing)
                }
                .font(.system(size: 10, weight: .medium).monospacedDigit())
                .foregroundStyle(Theme.secondary)
            }

            Spacer(minLength: 2)

            HStack(spacing: 22) {
                Button { music.previousTrack() } label: {
                    Image(systemName: "backward.fill").font(.system(size: 15, weight: .semibold))
                }
                .buttonStyle(IslandButtonStyle(diameter: 32))

                Button { music.togglePlayPause() } label: {
                    Image(systemName: music.isPlaying ? "pause.fill" : "play.fill")
                        .font(.system(size: 21, weight: .semibold))
                        .contentTransition(.symbolEffect(.replace))
                }
                .buttonStyle(IslandButtonStyle(diameter: 38))

                Button { music.nextTrack() } label: {
                    Image(systemName: "forward.fill").font(.system(size: 15, weight: .semibold))
                }
                .buttonStyle(IslandButtonStyle(diameter: 32))
            }
            .frame(maxWidth: .infinity)
        }
        .animation(Theme.openSpring, value: track.key)
    }

    private var idleState: some View {
        HStack(spacing: 12) {
            Group {
                if let icon = Self.musicIcon {
                    Image(nsImage: icon).resizable().aspectRatio(contentMode: .fit)
                } else {
                    ArtworkView(image: nil, size: 48, radius: 11)
                }
            }
            .frame(width: 52, height: 52)

            VStack(alignment: .leading, spacing: 4) {
                Text("Not Playing")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.white)
                Text("Play something in Apple Music")
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.secondary)
                    .lineLimit(2)
                Button(music.isMusicRunning ? "Play" : "Open Music") {
                    if music.isMusicRunning {
                        music.togglePlayPause()
                    } else {
                        music.openMusic()
                    }
                }
                .buttonStyle(CapsuleButtonStyle())
                .padding(.top, 2)
            }
            Spacer(minLength: 0)
        }
        .frame(maxHeight: .infinity)
    }

    private var permissionState: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label("Allow Music Access", systemImage: "lock.fill")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.white)
            Text("Turn on MacNotch › Music in Privacy & Security › Automation to see artwork and use the controls.")
                .font(.system(size: 11))
                .foregroundStyle(Theme.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
            Button("Open Settings") { music.openAutomationSettings() }
                .buttonStyle(CapsuleButtonStyle())
        }
    }

    private static let musicIcon: NSImage? = {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.Music") else { return nil }
        return NSWorkspace.shared.icon(forFile: url.path)
    }()
}
