import Foundation
import AVFoundation
import MediaPlayer
import Combine

@MainActor
final class AudioPlayerManager: NSObject, ObservableObject {
    @Published var library: [Song] = []
    @Published var playbackQueue: [Song] = []
    @Published var currentSong: Song?
    @Published var currentLyrics: [LyricLine] = []
    @Published var isPlaying: Bool = false
    @Published var currentTime: TimeInterval = 0
    @Published var duration: TimeInterval = 0
    @Published var isShuffle: Bool = false
    @Published var isRepeatOne: Bool = false
    @Published var isScrubbing: Bool = false

    // Ecualizador de 5 bandas
    @Published var isEQEnabled: Bool = true {
        didSet { eqNode.bypass = !isEQEnabled; saveEQSettings() }
    }
    @Published var selectedPreset: EqualizerPreset = .flat
    @Published var bandGains: [Float] = [0, 0, 0, 0, 0]

    // Temporizador de apagado
    @Published var sleepTimerRemaining: TimeInterval? = nil
    @Published var stopAfterCurrentSong: Bool = false

    // Motor AVAudioEngine
    private let engine = AVAudioEngine()
    private let playerNode = AVAudioPlayerNode()
    private let eqNode = AVAudioUnitEQ(numberOfBands: 5)
    private let frequencies: [Float] = [60, 230, 910, 3600, 14000]

    private var audioFile: AVAudioFile?
    private var seekFrameOffset: AVAudioFramePosition = 0
    private var totalFrames: AVAudioFramePosition = 0
    private var sampleRate: Double = 44100
    private var playbackSessionID = UUID()
    private var lastToggleTimestamp: Date = .distantPast

    private var timer: Timer?
    private var sleepTimer: Timer?

    private var documentsDirectory: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
    }

    private var musicDirectory: URL {
        let folder = documentsDirectory.appendingPathComponent("HaruBeatsMusic", isDirectory: true)
        if !FileManager.default.fileExists(atPath: folder.path) {
            try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        }
        return folder
    }

    override init() {
        super.init()
        setupAudioEngine()
        loadEQSettings()
        configureAudioSession()
        setupRemoteTransportControls()
        Task {
            await loadStoredLibrary()
        }
    }

    private func setupAudioEngine() {
        engine.attach(playerNode)
        engine.attach(eqNode)

        for (index, freq) in frequencies.enumerated() {
            let band = eqNode.bands[index]
            band.filterType = .parametric
            band.frequency = freq
            band.bandwidth = 1.0
            band.gain = 0
            band.bypass = false
        }

        engine.connect(playerNode, to: eqNode, format: nil)
        engine.connect(eqNode, to: engine.mainMixerNode, format: nil)
    }

    func applyPreset(_ preset: EqualizerPreset) {
        selectedPreset = preset
        if preset != .custom {
            bandGains = preset.gains
        }
        syncEQBands()
        saveEQSettings()
    }

    func updateBand(index: Int, gain: Float) {
        guard index >= 0, index < bandGains.count else { return }
        bandGains[index] = gain
        selectedPreset = .custom
        syncEQBands()
        saveEQSettings()
    }

    private func syncEQBands() {
        for (index, gain) in bandGains.enumerated() where index < eqNode.bands.count {
            eqNode.bands[index].gain = gain
        }
    }

    private func saveEQSettings() {
        UserDefaults.standard.set(isEQEnabled, forKey: "hb_eq_enabled")
        UserDefaults.standard.set(selectedPreset.rawValue, forKey: "hb_eq_preset")
        UserDefaults.standard.set(bandGains, forKey: "hb_eq_gains")
    }

    private func loadEQSettings() {
        if UserDefaults.standard.object(forKey: "hb_eq_enabled") != nil {
            isEQEnabled = UserDefaults.standard.bool(forKey: "hb_eq_enabled")
        }
        if let rawPreset = UserDefaults.standard.string(forKey: "hb_eq_preset"),
           let preset = EqualizerPreset(rawValue: rawPreset) {
            selectedPreset = preset
        }
        if let savedGains = UserDefaults.standard.array(forKey: "hb_eq_gains") as? [Float], savedGains.count == 5 {
            bandGains = savedGains
        }
        eqNode.bypass = !isEQEnabled
        syncEQBands()
    }

    // MARK: - Temporizador de apagado

    func startSleepTimer(minutes: Int) {
        cancelSleepTimer()
        stopAfterCurrentSong = false
        sleepTimerRemaining = TimeInterval(minutes * 60)

        sleepTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self, let remaining = self.sleepTimerRemaining else { return }
                if remaining <= 1 {
                    self.cancelSleepTimer()
                    if self.isPlaying {
                        self.togglePlayPause()
                    }
                } else {
                    self.sleepTimerRemaining = remaining - 1
                }
            }
        }
    }

    func enableStopAfterCurrentSong() {
        cancelSleepTimer()
        stopAfterCurrentSong = true
    }

    func cancelSleepTimer() {
        sleepTimer?.invalidate()
        sleepTimer = nil
        sleepTimerRemaining = nil
        stopAfterCurrentSong = false
    }

    // MARK: - Sesión y controles remotos

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

    // MARK: - Biblioteca e importación

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
        if playbackQueue.isEmpty {
            playbackQueue = self.library
        }
    }

    func deleteSong(_ song: Song) async {
        if currentSong?.fileURL == song.fileURL {
            playbackSessionID = UUID()
            playerNode.stop()
            stopTimer()
            isPlaying = false
            currentSong = nil
            audioFile = nil
            MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
        }
        try? FileManager.default.removeItem(at: song.fileURL)
        let lrcURL = musicDirectory.appendingPathComponent("\(song.fileURL.deletingPathExtension().lastPathComponent).lrc")
        try? FileManager.default.removeItem(at: lrcURL)

        playbackQueue.removeAll { $0.fileURL == song.fileURL }
        await loadStoredLibrary()
    }

    func enqueueNext(_ song: Song) {
        if playbackQueue.isEmpty {
            playbackQueue = library
        }
        playbackQueue.removeAll { $0.fileURL == song.fileURL }
        if let current = currentSong, let idx = playbackQueue.firstIndex(where: { $0.fileURL == current.fileURL }) {
            playbackQueue.insert(song, at: idx + 1)
        } else {
            playbackQueue.insert(song, at: 0)
        }
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
        if let currentSong {
            loadLyrics(for: currentSong)
        }
    }

    func importFolder(url folderURL: URL) async -> (folderName: String, importedSongs: [Song]) {
        let folderName = folderURL.lastPathComponent
        let accessed = folderURL.startAccessingSecurityScopedResource()
        defer {
            if accessed { folderURL.stopAccessingSecurityScopedResource() }
        }

        let allowedExtensions = ["flac", "mp3", "m4a", "aac", "wav", "alac", "lrc"]
        let audioExtensions = ["flac", "mp3", "m4a", "aac", "wav", "alac"]
        var copiedAudioFileNames: [String] = []

        if let enumerator = FileManager.default.enumerator(
            at: folderURL,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) {
            let fileURLs = enumerator.allObjects.compactMap { $0 as? URL }
                .sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }

            for fileURL in fileURLs {
                let ext = fileURL.pathExtension.lowercased()
                guard allowedExtensions.contains(ext) else { continue }

                let destination = musicDirectory.appendingPathComponent(fileURL.lastPathComponent)
                do {
                    if FileManager.default.fileExists(atPath: destination.path) {
                        try FileManager.default.removeItem(at: destination)
                    }
                    try FileManager.default.copyItem(at: fileURL, to: destination)
                    if audioExtensions.contains(ext) {
                        copiedAudioFileNames.append(fileURL.lastPathComponent)
                    }
                } catch {
                    print("Error copiando desde carpeta \(fileURL.lastPathComponent): \(error)")
                }
            }
        }

        await loadStoredLibrary()
        if let currentSong {
            loadLyrics(for: currentSong)
        }

        let orderedSongs = copiedAudioFileNames.compactMap { fileName in
            library.first(where: { $0.fileURL.lastPathComponent == fileName })
        }
        return (folderName, orderedSongs)
    }

    func saveTransferredFile(fileName: String, data: Data) async -> (destination: URL, song: Song?)? {
        let destination = musicDirectory.appendingPathComponent(fileName)
        do {
            if FileManager.default.fileExists(atPath: destination.path) {
                try FileManager.default.removeItem(at: destination)
            }
            try data.write(to: destination, options: .atomic)
            await loadStoredLibrary()
            if let currentSong {
                loadLyrics(for: currentSong)
            }
            let matchedSong = library.first(where: { $0.fileURL.lastPathComponent == fileName })
            return (destination, matchedSong)
        } catch {
            print("Error guardando archivo Wi-Fi \(fileName): \(error)")
            return nil
        }
    }

    func scanUSBSharedFiles() async -> Int {
        guard let rootFiles = try? FileManager.default.contentsOfDirectory(
            at: documentsDirectory,
            includingPropertiesForKeys: nil
        ) else { return 0 }

        let allowedExtensions = ["flac", "mp3", "m4a", "aac", "wav", "alac", "lrc"]
        var importedCount = 0

        for fileURL in rootFiles {
            let ext = fileURL.pathExtension.lowercased()
            guard allowedExtensions.contains(ext) else { continue }

            let destination = musicDirectory.appendingPathComponent(fileURL.lastPathComponent)
            do {
                if FileManager.default.fileExists(atPath: destination.path) {
                    try FileManager.default.removeItem(at: destination)
                }
                try FileManager.default.moveItem(at: fileURL, to: destination)
                importedCount += 1
            } catch {
                print("Error moviendo archivo USB \(fileURL.lastPathComponent): \(error)")
            }
        }

        if importedCount > 0 {
            await loadStoredLibrary()
            if let currentSong {
                loadLyrics(for: currentSong)
            }
        }
        return importedCount
    }

    func loadLyrics(for song: Song) {
        let baseName = song.fileURL.deletingPathExtension().lastPathComponent
        let lrcURL = musicDirectory.appendingPathComponent("\(baseName).lrc")

        if FileManager.default.fileExists(atPath: lrcURL.path),
           let content = try? String(contentsOf: lrcURL, encoding: .utf8) {
            currentLyrics = LRCParser.parse(content: content)
        } else {
            currentLyrics = []
        }
    }

    func attachManualLRC(from sourceURL: URL) {
        guard let song = currentSong else { return }
        let accessed = sourceURL.startAccessingSecurityScopedResource()
        defer {
            if accessed { sourceURL.stopAccessingSecurityScopedResource() }
        }

        let baseName = song.fileURL.deletingPathExtension().lastPathComponent
        let destination = musicDirectory.appendingPathComponent("\(baseName).lrc")
        do {
            if FileManager.default.fileExists(atPath: destination.path) {
                try FileManager.default.removeItem(at: destination)
            }
            try FileManager.default.copyItem(at: sourceURL, to: destination)
            loadLyrics(for: song)
        } catch {
            print("Error vinculando .lrc manual: \(error)")
        }
    }

    // MARK: - Reproducción con AVAudioEngine (protegida contra toques rápidos)

    func play(song: Song, inQueue queue: [Song]? = nil) {
        if let queue, !queue.isEmpty {
            playbackQueue = queue
        } else if playbackQueue.isEmpty {
            playbackQueue = library
        }

        guard FileManager.default.fileExists(atPath: song.fileURL.path) else { return }

        do {
            configureAudioSession()
            let file = try AVAudioFile(forReading: song.fileURL)
            let format = file.processingFormat
            guard format.sampleRate > 0, format.channelCount > 0 else { return }

            // Invalidar cualquier sesión previa antes de detener el nodo
            playbackSessionID = UUID()
            playerNode.stop()

            audioFile = file
            sampleRate = format.sampleRate
            totalFrames = file.length
            duration = Double(totalFrames) / sampleRate
            seekFrameOffset = 0
            currentSong = song
            currentTime = 0

            engine.disconnectNodeOutput(playerNode)
            engine.disconnectNodeOutput(eqNode)
            engine.connect(playerNode, to: eqNode, format: format)
            engine.connect(eqNode, to: engine.mainMixerNode, format: format)

            if !engine.isRunning {
                try engine.start()
            }

            scheduleSegment(fromFrame: 0)
            playerNode.play()

            isPlaying = true
            loadLyrics(for: song)
            updateNowPlayingInfo()
            startTimer()
        } catch {
            print("Error reproduciendo con AVAudioEngine \(song.title): \(error)")
        }
    }

    private func scheduleSegment(fromFrame startFrame: AVAudioFramePosition) {
        guard let file = audioFile else { return }
        let framesRemaining = AVAudioFrameCount(max(totalFrames - startFrame, 0))
        guard framesRemaining > 0 else { return }

        let sessionID = UUID()
        playbackSessionID = sessionID

        playerNode.scheduleSegment(
            file,
            startingFrame: startFrame,
            frameCount: framesRemaining,
            at: nil
        ) { [weak self] in
            Task { @MainActor in
                guard let self, self.playbackSessionID == sessionID, self.isPlaying else { return }
                self.handleTrackCompleted()
            }
        }
    }

    private func handleTrackCompleted() {
        if stopAfterCurrentSong {
            stopAfterCurrentSong = false
            isPlaying = false
            stopTimer()
            currentTime = 0
            updateNowPlayingInfo()
            return
        }

        if isRepeatOne, let current = currentSong {
            play(song: current)
        } else {
            playNext()
        }
    }

    func togglePlayPause() {
        // Evitar colisiones de AVAudioEngine si se presiona el botón repetidamente muy rápido
        let now = Date()
        guard now.timeIntervalSince(lastToggleTimestamp) > 0.15 else { return }
        lastToggleTimestamp = now

        guard audioFile != nil else {
            if let first = library.first {
                play(song: first)
            }
            return
        }

        if isPlaying {
            playerNode.pause()
            isPlaying = false
            stopTimer()
        } else {
            configureAudioSession()
            if !engine.isRunning {
                try? engine.start()
            }
            playerNode.play()
            isPlaying = true
            startTimer()
        }
        updateNowPlayingInfo()
    }

    func seek(to time: TimeInterval) {
        guard audioFile != nil else { return }
        let clampedTime = min(max(time, 0), duration)
        let targetFrame = AVAudioFramePosition(clampedTime * sampleRate)
        let wasPlaying = isPlaying

        playbackSessionID = UUID()
        playerNode.stop()
        seekFrameOffset = targetFrame
        currentTime = clampedTime

        if targetFrame < totalFrames {
            scheduleSegment(fromFrame: targetFrame)
            if wasPlaying {
                if !engine.isRunning { try? engine.start() }
                playerNode.play()
            }
        }
        updateNowPlayingInfo()
    }

    func playNext() {
        let activeQueue = playbackQueue.isEmpty ? library : playbackQueue
        guard !activeQueue.isEmpty else { return }

        if isShuffle, let randomSong = activeQueue.randomElement() {
            play(song: randomSong)
            return
        }
        guard let current = currentSong,
              let idx = activeQueue.firstIndex(where: { $0.fileURL == current.fileURL }) else {
            play(song: activeQueue[0])
            return
        }
        let nextIndex = (idx + 1) % activeQueue.count
        play(song: activeQueue[nextIndex])
    }

    func playPrevious() {
        let activeQueue = playbackQueue.isEmpty ? library : playbackQueue
        guard !activeQueue.isEmpty else { return }

        if currentTime > 3 {
            seek(to: 0)
            return
        }
        guard let current = currentSong,
              let idx = activeQueue.firstIndex(where: { $0.fileURL == current.fileURL }) else {
            play(song: activeQueue[0])
            return
        }
        let prevIndex = (idx - 1 + activeQueue.count) % activeQueue.count
        play(song: activeQueue[prevIndex])
    }

    private func startTimer() {
        stopTimer()
        timer = Timer.scheduledTimer(withTimeInterval: 0.15, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self, !self.isScrubbing,
                      let nodeTime = self.playerNode.lastRenderTime,
                      let playerTime = self.playerNode.playerTime(forNodeTime: nodeTime) else { return }

                let playedSeconds = Double(playerTime.sampleTime) / self.sampleRate
                let offsetSeconds = Double(self.seekFrameOffset) / self.sampleRate
                self.currentTime = min(max(offsetSeconds + playedSeconds, 0), self.duration)
            }
        }
    }

    private func stopTimer() {
        timer?.invalidate()
        timer = nil
    }
}