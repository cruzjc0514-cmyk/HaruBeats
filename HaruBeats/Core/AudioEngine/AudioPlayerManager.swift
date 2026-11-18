import Foundation
import AVFoundation
import MediaPlayer
import Combine

@MainActor
final class AudioPlayerManager: NSObject, ObservableObject, AVAudioPlayerDelegate {
    @Published var library: [Song] = []
    @Published var currentSong: Song?
    @Published var isPlaying: Bool = false
    @Published var currentTime: TimeInterval = 0
    @Published var duration: TimeInterval = 0
    @Published var isShuffle: Bool = false
    @Published var isRepeatOne: Bool = false
    @Published var isScrubbing: Bool = false

    private var player: AVAudioPlayer?
    private var timer: Timer?

    private var musicDirectory: URL {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let folder = docs.appendingPathComponent("HaruBeatsMusic", isDirectory: true)
        if !FileManager.default.fileExists(atPath: folder.path) {
            try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        }
        return folder
    }

    override init() {
        super.init()
        configureAudioSession()
        setupRemoteTransportControls()
        Task {
            await loadStoredLibrary()
        }
    }

    private func configureAudioSession() {
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, mode: .default, options: [])
            try session.setActive(true)
        } catch {
            print("Error configurando AVAudioSession: \(error)")
        }
    }

    private func setupRemoteTransportControls() {
        let commandCenter = MPRemoteCommandCenter.shared()

        commandCenter.playCommand.addTarget { [weak self] _ in
            Task { @MainActor in
                guard let self, !self.isPlaying else { return }
                self.togglePlayPause()
            }
            return .success
        }

        commandCenter.pauseCommand.addTarget { [weak self] _ in
            Task { @MainActor in
                guard let self, self.isPlaying else { return }
                self.togglePlayPause()
            }
            return .success
        }

        commandCenter.nextTrackCommand.addTarget { [weak self] _ in
            Task { @MainActor in
                self?.playNext()
            }
            return .success
        }

        commandCenter.previousTrackCommand.addTarget { [weak self] _ in
            Task { @MainActor in
                self?.playPrevious()
            }
            return .success
        }

        commandCenter.changePlaybackPositionCommand.addTarget { [weak self] event in
            guard let positionEvent = event as? MPChangePlaybackPositionCommandEvent else { return .commandFailed }
            Task { @MainActor in
                self?.seek(to: positionEvent.positionTime)
            }
            return .success
        }
    }

    private func updateNowPlayingInfo() {
        guard let song = currentSong else { return }
        var info: [String: Any] = [
            MPMediaItemPropertyTitle: song.title,
            MPMediaItemPropertyArtist: song.artist,
            MPMediaItemPropertyAlbumTitle: song.album,
            MPMediaItemPropertyPlaybackDuration: duration,
            MPNowPlayingInfoPropertyElapsedPlaybackTime: currentTime,
            MPNowPlayingInfoPropertyPlaybackRate: isPlaying ? 1.0 : 0.0
        ]

        if let image = song.artworkImage {
            let artwork = MPMediaItemArtwork(boundsSize: image.size) { _ in image }
            info[MPMediaItemPropertyArtwork] = artwork
        }

        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
    }

    func loadStoredLibrary() async {
        guard let files = try? FileManager.default.contentsOfDirectory(
            at: musicDirectory,
            includingPropertiesForKeys: nil
        ) else { return }

        let supportedExtensions = ["flac", "mp3", "m4a", "aac", "wav", "alac"]
        let audioFiles = files.filter { supportedExtensions.contains($0.pathExtension.lowercased()) }

        var loadedSongs: [Song] = []
        for fileURL in audioFiles {
            let song = await Song.from(url: fileURL)
            loadedSongs.append(song)
        }
        self.library = loadedSongs.sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
    }

    func importFiles(urls: [URL]) async {
        for url in urls {
            let accessed = url.startAccessingSecurityScopedResource()
            defer {
                if accessed { url.stopAccessingSecurityScopedResource() }
            }

            let destination = musicDirectory.appendingPathComponent(url.lastPathComponent)
            do {
                if FileManager.default.fileExists(atPath: destination.path) {
                    try FileManager.default.removeItem(at: destination)
                }
                try FileManager.default.copyItem(at: url, to: destination)
            } catch {
                print("Error copiando archivo \(url.lastPathComponent): \(error)")
            }
        }
        await loadStoredLibrary()
    }

    func play(song: Song) {
        do {
            configureAudioSession()
            player?.stop()
            player = try AVAudioPlayer(contentsOf: song.fileURL)
            player?.delegate = self
            player?.prepareToPlay()
            player?.play()

            currentSong = song
            duration = player?.duration ?? song.duration
            currentTime = 0
            isPlaying = true
            updateNowPlayingInfo()
            startTimer()
        } catch {
            print("Error reproduciendo \(song.title): \(error)")
        }
    }

    func togglePlayPause() {
        guard let player else { return }
        if player.isPlaying {
            player.pause()
            isPlaying = false
            stopTimer()
        } else {
            configureAudioSession()
            player.play()
            isPlaying = true
            startTimer()
        }
        updateNowPlayingInfo()
    }

    func seek(to time: TimeInterval) {
        guard let player else { return }
        player.currentTime = time
        currentTime = time
        updateNowPlayingInfo()
    }

    func playNext() {
        guard !library.isEmpty else { return }
        if isShuffle, let randomSong = library.randomElement() {
            play(song: randomSong)
            return
        }
        guard let current = currentSong, let idx = library.firstIndex(of: current) else {
            play(song: library[0])
            return
        }
        let nextIndex = (idx + 1) % library.count
        play(song: library[nextIndex])
    }

    func playPrevious() {
        guard !library.isEmpty else { return }
        if currentTime > 3 {
            seek(to: 0)
            return
        }
        guard let current = currentSong, let idx = library.firstIndex(of: current) else {
            play(song: library[0])
            return
        }
        let prevIndex = (idx - 1 + library.count) % library.count
        play(song: library[prevIndex])
    }

    nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        Task { @MainActor in
            if self.isRepeatOne, let current = self.currentSong {
                self.play(song: current)
            } else {
                self.playNext()
            }
        }
    }

    private func startTimer() {
        stopTimer()
        timer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self, let player = self.player, !self.isScrubbing else { return }
                self.currentTime = player.currentTime
            }
        }
    }

    private func stopTimer() {
        timer?.invalidate()
        timer = nil
    }
}