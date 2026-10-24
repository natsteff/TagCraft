import SwiftUI
import AVFoundation

struct PlaybackTrack {
    var url: URL
    var artist: String
    var title: String
    init(_ track: Track) {
        url = track.url; artist = track.tags.artist
        title = track.tags.title.isEmpty ? track.filename : track.tags.title
    }
}
@MainActor final class PlaybackController: NSObject, ObservableObject, AVAudioPlayerDelegate {
    @Published var current: PlaybackTrack?
    @Published var isPlaying = false
    @Published var error: String?
    private var audio: AVAudioPlayer?
    var queue: () -> [PlaybackTrack] = { [] }
    var position: Double { audio?.currentTime ?? 0 }
    var duration: Double { audio?.duration ?? 0 }
    func play(_ track: PlaybackTrack) { load(track, autoplay: true) }
    func load(_ track: PlaybackTrack, autoplay: Bool = false) {
        do {
            let next = try AVAudioPlayer(contentsOf: track.url)
            next.delegate = self
            next.prepareToPlay()
            audio?.stop(); audio = next; current = track; isPlaying = false; error = nil
            if autoplay {
                isPlaying = next.play()
                if !isPlaying { error = "The audio output is unavailable. The track is loaded; try Play again." }
            }
        } catch { self.error = error.localizedDescription }
    }
    func toggle(start: PlaybackTrack?) {
        guard let audio else { if let start { play(start) }; return }
        if audio.isPlaying { audio.pause(); isPlaying = false }
        else { isPlaying = audio.play(); error = isPlaying ? nil : "The audio output is unavailable. Try Play again." }
    }
    func stop() { audio?.stop(); audio?.currentTime = 0; isPlaying = false }
    func seek(_ seconds: Double) { audio?.currentTime = max(0, min(duration, seconds)) }
    func adjacent(_ offset: Int, automatic: Bool = false) {
        let tracks = queue()
        guard !tracks.isEmpty else { if automatic { stop() }; return }
        let index = tracks.firstIndex { $0.url == current?.url }
        let next = index.map { $0 + offset } ?? (offset > 0 ? 0 : tracks.count - 1)
        guard tracks.indices.contains(next) else { if automatic { stop() }; return }
        play(tracks[next])
    }
    func canStep(_ offset: Int) -> Bool {
        let tracks = queue()
        guard !tracks.isEmpty else { return false }
        guard let index = tracks.firstIndex(where: { $0.url == current?.url }) else { return true }
        return tracks.indices.contains(index + offset)
    }
    func update(source: URL, destination: URL, tags: Tags?) {
        guard current?.url == source else { return }
        current?.url = destination
        if let tags {
            current?.artist = tags.artist
            current?.title = tags.title.isEmpty ? destination.lastPathComponent : tags.title
        }
    }
    nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        Task { @MainActor in
            guard self.audio === player else { return }
            self.isPlaying = false
            if flag { self.adjacent(1, automatic: true) }
            else { self.error = "Playback ended unexpectedly." }
        }
    }
    nonisolated func audioPlayerDecodeErrorDidOccur(_ player: AVAudioPlayer, error: Error?) {
        Task { @MainActor in
            guard self.audio === player else { return }
            self.isPlaying = false; self.error = error?.localizedDescription ?? "Audio decoding failed."
        }
    }
}
struct MiniPlayer: View {
    @EnvironmentObject var m: Model
    @ObservedObject var playback: PlaybackController
    @State private var scrub: Double?
    var body: some View {
        VStack(spacing: 8) {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(playback.current?.title ?? "Select a track to play").font(.callout.bold()).lineLimit(1)
                    Text(playback.current.map { $0.artist.isEmpty ? "Unknown artist" : $0.artist } ?? "Playback follows the filtered and sorted list")
                        .font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }.frame(maxWidth: .infinity, alignment: .leading)
                Button { playback.adjacent(-1) } label: { Image(systemName: "backward.end.fill") }
                    .disabled(!playback.canStep(-1)).help("Previous track").accessibilityLabel("Previous track")
                Button { playback.toggle(start: m.filtered.first(where: { m.selection.contains($0.url) }).map(PlaybackTrack.init) ?? m.filtered.first.map(PlaybackTrack.init)) } label: {
                    Image(systemName: playback.isPlaying ? "pause.fill" : "play.fill").frame(width: 20)
                }.disabled(playback.current == nil && m.filtered.isEmpty).help(playback.isPlaying ? "Pause" : "Play / resume").accessibilityLabel(playback.isPlaying ? "Pause playback" : "Play or resume")
                Button { playback.stop() } label: { Image(systemName: "stop.fill") }.disabled(playback.current == nil).help("Stop and return to the beginning").accessibilityLabel("Stop playback")
                Button { playback.adjacent(1) } label: { Image(systemName: "forward.end.fill") }
                    .disabled(!playback.canStep(1)).help("Next track").accessibilityLabel("Next track")
            }.buttonStyle(.borderless)
            TimelineView(.periodic(from: .now, by: 0.25)) { _ in
                HStack(spacing: 8) {
                    Text(time(scrub ?? playback.position)).monospacedDigit().frame(width: 45)
                    Slider(value: Binding(get: { min(scrub ?? playback.position, max(playback.duration, 0.001)) }, set: { scrub = $0; playback.seek($0) }), in: 0...max(playback.duration, 0.001), onEditingChanged: { editing in
                        if !editing, let scrub { playback.seek(scrub); self.scrub = nil }
                    }).disabled(playback.duration <= 0).accessibilityLabel("Playback position").help("Drag to seek within the current track")
                    Text(time(playback.duration)).monospacedDigit().frame(width: 45)
                }.font(.caption).foregroundStyle(.secondary)
            }
            if let error = playback.error { Text(error).font(.caption).foregroundStyle(.orange).textSelection(.enabled) }
        }.padding(.horizontal, 14).padding(.vertical, 10).background(.bar)
        .onChange(of: playback.current?.url) { _, _ in scrub = nil }
    }
    private func time(_ seconds: Double) -> String {
        guard seconds.isFinite else { return "0:00" }
        let value = max(0, Int(seconds))
        return value >= 3600 ? String(format: "%d:%02d:%02d", value / 3600, value / 60 % 60, value % 60) : String(format: "%d:%02d", value / 60, value % 60)
    }
}

struct PlayingFilename: View {
    let track: Track
    @ObservedObject var playback: PlaybackController
    var body: some View {
        Text(track.filename)
            .foregroundStyle(playback.isPlaying && playback.current?.url == track.url ? Color.blue : Color.primary)
    }
}
