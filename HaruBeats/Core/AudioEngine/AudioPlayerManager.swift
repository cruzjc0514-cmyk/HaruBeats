import Foundation
import AVFoundation
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
        Task {
            await loadStoredLibrary()
        }
    }

    private func configureAudioSession() {
        do {
            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .default)
            try AVAudioSession.sharedInstance().setActive(true)
        } catch {
            print("Error configurando AVAudioSession: \(error)")
        }
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
            player?.stop()
            player = try AVAudioPlayer(contentsOf: song.fileURL)
            player?.delegate = self
            player?.prepareToPlay()
            player?.play()

            currentSong = song
            duration = player?.duration ?? song.duration
            currentTime = 0
            isPlaying = true
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
            player.play()
            isPlaying = true
            startTimer()
        }
    }

    func seek(to time: TimeInterval) {
        guard let player else { return }
        player.currentTime = time
        currentTime = time
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
                guard let self, let player = self.player else { return }
                self.currentTime = player.currentTime
            }
        }
    }

    private func stopTimer() {
        timer?.invalidate()
        timer = nil
    }
}