import Foundation
import SwiftUI
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

    // Color ambiental dinámico extraído de la portada
    @Published var dynamicArtworkColor: Color? = nil

    // Ecualizador de 5 bandas
    @Published var isEQEnabled: Bool = true {
        didSet { eqNode.bypass = !isEQEnabled; saveEQSettings() }
    }
    @Published var selectedPreset: EqualizerPreset = .flat
    @Published var bandGains: [Float] = [0, 0, 0, 0, 0]

    // ReplayGain (normalización de volumen por pista)
    @Published var isReplayGainEnabled: Bool = true {
        didSet {
            UserDefaults.standard.set(isReplayGainEnabled, forKey: "hb_replaygain_enabled")
            updateTargetGain()
        }
    }

    // Temporizador de apagado
    @Published var sleepTimerRemaining: TimeInterval? = nil
    @Published var stopAfterCurrentSong: Bool = false

    // Sincronización LRC en vivo (desfase en segundos) y tamaño de fuente
    @Published var lyricsOffset: TimeInterval = 0
    @Published var lyricsFontScale: Double = 1.0 {
        didSet { UserDefaults.standard.set(lyricsFontScale, forKey: "hb_lyrics_scale") }
    }

    // Crossfade entre pistas (0 = Gapless puro sin pausas, 2, 4, 6 segundos)
    @Published var crossfadeDuration: Double = 0 {
        didSet { UserDefaults.standard.set(crossfadeDuration, forKey: "hb_crossfade_duration") }
    }

    // Historial y estadísticas de reproducción
    @Published var recentFileNames: [String] = []
    @Published var playCounts: [String: Int] = [:]

    // Motor AVAudioEngine
    private let engine = AVAudioEngine()
    private let playerNode = AVAudioPlayerNode()
    private let eqNode = AVAudioUnitEQ(numberOfBands: 5)
    private let frequencies: [Float] = [60, 230, 910, 3600, 14000]

    private var audioFile: AVAudioFile?
    private var seekFrameOffset: AVAudioFramePosition = 0
    private var totalFrames: AVAudioFramePosition = 0
    private var fileSampleRate: Double = 44100
    private var playbackGeneration: UInt64 = 0
    private var lastCommandTime: Date = .distantPast
    private var seekHoldUntil: Date = .distantPast
    private var fadeInRemaining: Double = 0
    private var targetLinearGain: Float = 1.0

    // Estado para transición Gapless (sin pausas)
    private var preScheduledNextSong: Song? = nil
    private var preScheduledNextFile: AVAudioFile? = nil
    private var didPreScheduleGapless: Bool = false

    private var timer: Timer?
    private var sleepTimer: Timer?
    private var lastSessionSaveTime: Date = .distantPast

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

    var recentSongs: [Song] {
        recentFileNames.compactMap { name in
            library.first(where: { $0.fileURL.lastPathComponent == name })
        }
    }

    var topPlayedSongs: [(song: Song, count: Int)] {
        playCounts
            .compactMap { fileName, count -> (Song, Int)? in
                guard count > 0, let song = library.first(where: { $0.fileURL.lastPathComponent == fileName }) else { return nil }
                return (song, count)
            }
            .sorted { $0.1 > $1.1 }
    }

    override init() {
        super.init()
        setupAudioEngine()
        loadEQSettings()
        loadUserPreferencesAndStats()
        configureAudioSession()
        observeSystemAudioNotifications()
        setupRemoteTransportControls()
        Task {
            await loadStoredLibrary()
            restoreLastPlaybackSession()
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
        engine.prepare()
    }

    // MARK: - Interrupciones del sistema (Llamadas, AirPods, Hardware)

    private func observeSystemAudioNotifications() {
        let nc = NotificationCenter.default

        nc.addObserver(forName: AVAudioSession.interruptionNotification, object: nil, queue: .main) { [weak self] notification in
            guard let userInfo = notification.userInfo,
                  let typeValue = userInfo[AVAudioSessionInterruptionTypeKey] as? UInt,
                  let type = AVAudioSession.InterruptionType(rawValue: typeValue) else { return }

            let optionsValue = userInfo[AVAudioSessionInterruptionOptionKey] as? UInt ?? 0
            let options = AVAudioSession.InterruptionOptions(rawValue: optionsValue)

            Task { @MainActor in
                guard let self else { return }
                switch type {
                case .began:
                    if self.isPlaying {
                        self.playerNode.pause()
                        self.isPlaying = false
                        self.stopTimer()
                        self.savePlaybackSession(force: true)
                        self.updateNowPlayingInfo()
                    }
                case .ended:
                    if options.contains(.shouldResume), self.audioFile != nil, !self.isPlaying {
                        self.configureAudioSession()
                        if !self.engine.isRunning { try? self.engine.start() }
                        self.playerNode.play()
                        self.isPlaying = true
                        self.startTimer()
                        self.updateNowPlayingInfo()
                    }
                @unknown default:
                    break
                }
            }
        }

        nc.addObserver(forName: AVAudioSession.routeChangeNotification, object: nil, queue: .main) { [weak self] notification in
            guard let userInfo = notification.userInfo,
                  let reasonValue = userInfo[AVAudioSessionRouteChangeReasonKey] as? UInt,
                  let reason = AVAudioSession.RouteChangeReason(rawValue: reasonValue) else { return }

            if reason == .oldDeviceUnavailable {
                Task { @MainActor in
                    guard let self, self.isPlaying else { return }
                    self.playerNode.pause()
                    self.isPlaying = false
                    self.stopTimer()
                    self.savePlaybackSession(force: true)
                    self.updateNowPlayingInfo()
                }
            }
        }

        nc.addObserver(forName: .AVAudioEngineConfigurationChange, object: engine, queue: .main) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                let wasPlaying = self.isPlaying
                let savedTime = self.currentTime
                if !self.engine.isRunning {
                    self.engine.prepare()
                    try? self.engine.start()
                }
                if wasPlaying, self.audioFile != nil {
                    self.seek(to: savedTime)
                    self.playerNode.play()
                }
            }
        }
    }

    // MARK: - Restauración de sesión

    private func savePlaybackSession(force: Bool = false) {
        let now = Date()
        if !force && now.timeIntervalSince(lastSessionSaveTime) < 3.0 { return }
        lastSessionSaveTime = now

        guard let song = currentSong else {
            UserDefaults.standard.removeObject(forKey: "hb_session_song")
            return
        }
        UserDefaults.standard.set(song.fileURL.lastPathComponent, forKey: "hb_session_song")
        UserDefaults.standard.set(currentTime, forKey: "hb_session_time")
        let queueNames = playbackQueue.map { $0.fileURL.lastPathComponent }
        UserDefaults.standard.set(queueNames, forKey: "hb_session_queue")
    }

    private func restoreLastPlaybackSession() {
        guard currentSong == nil,
              let savedSongName = UserDefaults.standard.string(forKey: "hb_session_song"),
              let song = library.first(where: { $0.fileURL.lastPathComponent == savedSongName }) else {
            return
        }

        let savedQueueNames = UserDefaults.standard.stringArray(forKey: "hb_session_queue") ?? []
        let restoredQueue = savedQueueNames.compactMap { name in
            library.first(where: { $0.fileURL.lastPathComponent == name })
        }
        playbackQueue = restoredQueue.isEmpty ? library : restoredQueue

        let savedTime = UserDefaults.standard.double(forKey: "hb_session_time")
        prepareSongPaused(song, atTime: savedTime)
    }

    private func prepareSongPaused(_ song: Song, atTime time: TimeInterval) {
        guard FileManager.default.fileExists(atPath: song.fileURL.path),
              let file = try? AVAudioFile(forReading: song.fileURL) else { return }

        let format = file.processingFormat
        guard format.sampleRate > 0, file.length > 0 else { return }

        playbackGeneration &+= 1
        let gen = playbackGeneration

        playerNode.stop()
        playerNode.reset()

        audioFile = file
        fileSampleRate = format.sampleRate
        totalFrames = file.length
        duration = Double(totalFrames) / fileSampleRate

        let clampedTime = min(max(time, 0), max(duration - 0.5, 0))
        let targetFrame = min(max(AVAudioFramePosition(clampedTime * fileSampleRate), 0), totalFrames - 1)
        seekFrameOffset = targetFrame
        currentSong = song
        currentTime = clampedTime
        isPlaying = false
        dynamicArtworkColor = ArtworkColorExtractor.dominantColor(from: song.artworkImage)
        updateTargetGain()
        playerNode.volume = targetLinearGain

        scheduleSegment(fromFrame: targetFrame, generation: gen)
        loadLyrics(for: song)
        updateNowPlayingInfo()
    }

    // MARK: - Preferencias, Estadísticas, ReplayGain y Desfase LRC

    private func loadUserPreferencesAndStats() {
        if let scale = UserDefaults.standard.object(forKey: "hb_lyrics_scale") as? Double, scale >= 0.8 {
            lyricsFontScale = scale
        }
        if UserDefaults.standard.object(forKey: "hb_replaygain_enabled") != nil {
            isReplayGainEnabled = UserDefaults.standard.bool(forKey: "hb_replaygain_enabled")
        }
        crossfadeDuration = UserDefaults.standard.double(forKey: "hb_crossfade_duration")
        recentFileNames = UserDefaults.standard.stringArray(forKey: "hb_recent_files") ?? []
        if let savedCounts = UserDefaults.standard.dictionary(forKey: "hb_play_counts") as? [String: Int] {
            playCounts = savedCounts
        }
    }

    private func updateTargetGain() {
        guard isReplayGainEnabled, let db = currentSong?.replayGainDB else {
            targetLinearGain = 1.0
            if fadeInRemaining <= 0 {
                playerNode.volume = 1.0
            }
            return
        }
        // Limitar ganancia entre -12 dB y +6 dB para proteger contra saturación
        let clampedDB = min(max(db, -12.0), 6.0)
        targetLinearGain = Float(pow(10.0, clampedDB / 20.0))
        if fadeInRemaining <= 0 {
            playerNode.volume = targetLinearGain
        }
    }

    private func recordSongPlayed(_ song: Song) {
        let fileName = song.fileURL.lastPathComponent

        recentFileNames.removeAll { $0 == fileName }
        recentFileNames.insert(fileName, at: 0)
        if recentFileNames.count > 25 {
            recentFileNames = Array(recentFileNames.prefix(25))
        }
        UserDefaults.standard.set(recentFileNames, forKey: "hb_recent_files")

        playCounts[fileName, default: 0] += 1
        UserDefaults.standard.set(playCounts, forKey: "hb_play_counts")
    }

    func adjustLyricsOffset(by delta: TimeInterval) {
        lyricsOffset = ((lyricsOffset + delta) * 10).rounded() / 10
        if let song = currentSong {
            UserDefaults.standard.set(lyricsOffset, forKey: "hb_lrc_offset_\(song.fileURL.lastPathComponent)")
        }
    }

    func resetLyricsOffset() {
        lyricsOffset = 0
        if let song = currentSong {
            UserDefaults.standard.removeObject(forKey: "hb_lrc_offset_\(song.fileURL.lastPathComponent)")
        }
    }

    // MARK: - Ecualizador

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
        guard let song = currentSong else {
            MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
            return
        }
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

    // MARK: - Biblioteca, Cola e Importación

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
        playbackGeneration &+= 1
        clearGaplessPreSchedule()
        stopTimer()

        if currentSong?.fileURL == song.fileURL {
            if playerNode.isPlaying {
                playerNode.stop()
            }
            audioFile = nil
            isPlaying = false
            currentSong = nil
            dynamicArtworkColor = nil
            currentTime = 0
            duration = 0
            currentLyrics = []
            MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
            savePlaybackSession(force: true)
        }

        library.removeAll { $0.fileURL == song.fileURL }
        playbackQueue.removeAll { $0.fileURL == song.fileURL }

        try? FileManager.default.removeItem(at: song.fileURL)
        let lrcURL = musicDirectory.appendingPathComponent("\(song.fileURL.deletingPathExtension().lastPathComponent).lrc")
        try? FileManager.default.removeItem(at: lrcURL)
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
        clearGaplessPreSchedule()
    }

    func moveInQueue(from source: IndexSet, to destination: Int) {
        playbackQueue.move(fromOffsets: source, toOffset: destination)
        clearGaplessPreSchedule()
        savePlaybackSession(force: true)
    }

    func removeFromQueue(at offsets: IndexSet) {
        playbackQueue.remove(atOffsets: offsets)
        clearGaplessPreSchedule()
        savePlaybackSession(force: true)
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
        lyricsOffset = UserDefaults.standard.double(forKey: "hb_lrc_offset_\(song.fileURL.lastPathComponent)")

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

    // MARK: - Reproducción con Gapless real, Crossfade, ReplayGain y Barra Fluida

    func play(song: Song, inQueue queue: [Song]? = nil) {
        if let queue, !queue.isEmpty {
            playbackQueue = queue
        } else if playbackQueue.isEmpty {
            playbackQueue = library
        }

        guard FileManager.default.fileExists(atPath: song.fileURL.path) else { return }

        playbackGeneration &+= 1
        let gen = playbackGeneration
        clearGaplessPreSchedule()

        do {
            configureAudioSession()
            let file = try AVAudioFile(forReading: song.fileURL)
            let format = file.processingFormat
            guard format.sampleRate > 0, format.channelCount > 0, file.length > 0 else { return }

            playerNode.stop()
            playerNode.reset()

            audioFile = file
            fileSampleRate = format.sampleRate
            totalFrames = file.length
            duration = Double(totalFrames) / fileSampleRate
            seekFrameOffset = 0
            currentSong = song
            currentTime = 0
            seekHoldUntil = Date().addingTimeInterval(0.25)
            dynamicArtworkColor = ArtworkColorExtractor.dominantColor(from: song.artworkImage)
            updateTargetGain()

            if crossfadeDuration > 0 {
                playerNode.volume = 0.05 * targetLinearGain
                fadeInRemaining = crossfadeDuration
            } else {
                playerNode.volume = targetLinearGain
                fadeInRemaining = 0
            }

            if !engine.isRunning {
                engine.prepare()
                try engine.start()
            }

            scheduleSegment(fromFrame: 0, generation: gen)
            playerNode.play()

            isPlaying = true
            recordSongPlayed(song)
            loadLyrics(for: song)
            updateNowPlayingInfo()
            savePlaybackSession(force: true)
            startTimer()
        } catch {
            print("Error reproduciendo \(song.title): \(error)")
        }
    }

    private func clearGaplessPreSchedule() {
        preScheduledNextSong = nil
        preScheduledNextFile = nil
        didPreScheduleGapless = false
    }

    private func nextSequentialSong() -> Song? {
        let activeQueue = playbackQueue.filter { FileManager.default.fileExists(atPath: $0.fileURL.path) }
        guard !activeQueue.isEmpty, !isShuffle, !isRepeatOne, !stopAfterCurrentSong else { return nil }
        guard let current = currentSong,
              let idx = activeQueue.firstIndex(where: { $0.fileURL == current.fileURL }) else {
            return nil
        }
        let nextIndex = (idx + 1) % activeQueue.count
        return activeQueue[nextIndex]
    }

    /// Pre-programa el siguiente archivo en AVAudioPlayerNode cuando falta poco para acabar (Gapless sample-accurate)
    private func tryPreScheduleGaplessNext(generation: UInt64) {
        guard crossfadeDuration == 0, !didPreScheduleGapless, let nextSong = nextSequentialSong() else { return }
        guard let nextFile = try? AVAudioFile(forReading: nextSong.fileURL),
              nextFile.processingFormat.sampleRate == fileSampleRate,
              nextFile.processingFormat.channelCount == audioFile?.processingFormat.channelCount else {
            return
        }

        didPreScheduleGapless = true
        preScheduledNextSong = nextSong
        preScheduledNextFile = nextFile

        playerNode.scheduleFile(nextFile, at: nil, completionCallbackType: .dataPlayedBack) { [weak self] _ in
            Task { @MainActor in
                guard let self, self.playbackGeneration == generation, self.isPlaying else { return }
                self.handleTrackCompleted()
            }
        }
    }

    private func promotePreScheduledGaplessTrack(nextSong: Song, nextFile: AVAudioFile, generation: UInt64) {
        clearGaplessPreSchedule()
        audioFile = nextFile
        fileSampleRate = nextFile.processingFormat.sampleRate
        totalFrames = nextFile.length
        duration = Double(totalFrames) / fileSampleRate
        seekFrameOffset = -AVAudioFramePosition(currentTime * fileSampleRate)
        currentSong = nextSong
        currentTime = 0
        seekHoldUntil = Date().addingTimeInterval(0.25)
        dynamicArtworkColor = ArtworkColorExtractor.dominantColor(from: nextSong.artworkImage)
        updateTargetGain()

        recordSongPlayed(nextSong)
        loadLyrics(for: nextSong)
        updateNowPlayingInfo()
        savePlaybackSession(force: true)
    }

    private func scheduleSegment(fromFrame startFrame: AVAudioFramePosition, generation: UInt64) {
        guard let file = audioFile else { return }
        let framesRemaining = AVAudioFrameCount(max(totalFrames - startFrame, 0))
        guard framesRemaining > 0 else { return }

        playerNode.scheduleSegment(
            file,
            startingFrame: startFrame,
            frameCount: framesRemaining,
            at: nil,
            completionCallbackType: .dataPlayedBack
        ) { [weak self] _ in
            Task { @MainActor in
                guard let self, self.playbackGeneration == generation, self.isPlaying else { return }
                if let gaplessSong = self.preScheduledNextSong, let gaplessFile = self.preScheduledNextFile {
                    self.promotePreScheduledGaplessTrack(nextSong: gaplessSong, nextFile: gaplessFile, generation: generation)
                } else {
                    self.handleTrackCompleted()
                }
            }
        }
    }

    private func handleTrackCompleted() {
        playerNode.volume = targetLinearGain
        if stopAfterCurrentSong {
            stopAfterCurrentSong = false
            isPlaying = false
            stopTimer()
            currentTime = 0
            savePlaybackSession(force: true)
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
        let now = Date()
        guard now.timeIntervalSince(lastCommandTime) > 0.12 else { return }
        lastCommandTime = now

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
            savePlaybackSession(force: true)
        } else {
            configureAudioSession()
            if !engine.isRunning {
                try? engine.start()
            }
            playerNode.volume = targetLinearGain
            playerNode.play()
            isPlaying = true
            startTimer()
        }
        updateNowPlayingInfo()
    }

    func seek(to time: TimeInterval) {
        guard audioFile != nil, duration > 0 else { return }
        let clampedTime = min(max(time, 0), duration)
        let targetFrame = min(max(AVAudioFramePosition(clampedTime * fileSampleRate), 0), totalFrames - 1)
        let wasPlaying = isPlaying

        playbackGeneration &+= 1
        let gen = playbackGeneration
        clearGaplessPreSchedule()

        playerNode.stop()
        playerNode.reset()
        playerNode.volume = targetLinearGain
        fadeInRemaining = 0
        seekFrameOffset = targetFrame
        currentTime = clampedTime
        // Evita cualquier micro-rebote visual de la barra mientras el buffer reinicia
        seekHoldUntil = Date().addingTimeInterval(0.30)

        scheduleSegment(fromFrame: targetFrame, generation: gen)
        if wasPlaying {
            if !engine.isRunning { try? engine.start() }
            playerNode.play()
        }
        savePlaybackSession(force: true)
        updateNowPlayingInfo()
    }

    func playNext() {
        let now = Date()
        guard now.timeIntervalSince(lastCommandTime) > 0.12 else { return }
        lastCommandTime = now

        let activeQueue = playbackQueue.filter { FileManager.default.fileExists(atPath: $0.fileURL.path) }
        guard !activeQueue.isEmpty else { return }

        if isShuffle, let randomSong = activeQueue.randomElement() {
            play(song: randomSong, inQueue: activeQueue)
            return
        }
        guard let current = currentSong,
              let idx = activeQueue.firstIndex(where: { $0.fileURL == current.fileURL }) else {
            play(song: activeQueue[0], inQueue: activeQueue)
            return
        }
        let nextIndex = (idx + 1) % activeQueue.count
        play(song: activeQueue[nextIndex], inQueue: activeQueue)
    }

    func playPrevious() {
        let now = Date()
        guard now.timeIntervalSince(lastCommandTime) > 0.12 else { return }
        lastCommandTime = now

        let activeQueue = playbackQueue.filter { FileManager.default.fileExists(atPath: $0.fileURL.path) }
        guard !activeQueue.isEmpty else { return }

        if currentTime > 3 {
            seek(to: 0)
            return
        }
        guard let current = currentSong,
              let idx = activeQueue.firstIndex(where: { $0.fileURL == current.fileURL }) else {
            play(song: activeQueue[0], inQueue: activeQueue)
            return
        }
        let prevIndex = (idx - 1 + activeQueue.count) % activeQueue.count
        play(song: activeQueue[prevIndex], inQueue: activeQueue)
    }

    private func startTimer() {
        stopTimer()
        let tickInterval = 0.05 // 20 FPS para barra de progreso y letras ultra fluidas
        timer = Timer.scheduledTimer(withTimeInterval: tickInterval, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self, self.isPlaying, !self.isScrubbing else { return }
                if Date() < self.seekHoldUntil { return }

                guard let nodeTime = self.playerNode.lastRenderTime,
                      nodeTime.isSampleTimeValid,
                      let playerTime = self.playerNode.playerTime(forNodeTime: nodeTime) else { return }

                let playedSeconds = Double(playerTime.sampleTime) / playerTime.sampleRate
                let offsetSeconds = Double(self.seekFrameOffset) / self.fileSampleRate
                let computed = offsetSeconds + playedSeconds
                if computed >= 0 && computed <= self.duration {
                    self.currentTime = computed
                    self.applyCrossfadeGain(at: computed, tick: tickInterval)
                    self.savePlaybackSession(force: false)

                    if self.duration - computed <= 1.8 {
                        self.tryPreScheduleGaplessNext(generation: self.playbackGeneration)
                    }
                }
            }
        }
    }

    private func applyCrossfadeGain(at time: TimeInterval, tick: Double) {
        guard crossfadeDuration > 0, duration > crossfadeDuration * 2 else {
            if abs(playerNode.volume - targetLinearGain) > 0.005 {
                playerNode.volume = targetLinearGain
            }
            return
        }

        let remaining = duration - time
        if fadeInRemaining > 0 {
            fadeInRemaining = max(fadeInRemaining - tick, 0)
            let progress = 1.0 - (fadeInRemaining / crossfadeDuration)
            playerNode.volume = Float(min(max(progress, 0.05), 1.0)) * targetLinearGain
        } else if remaining <= crossfadeDuration && remaining > 0 {
            let progress = remaining / crossfadeDuration
            playerNode.volume = Float(min(max(progress, 0.05), 1.0)) * targetLinearGain
        } else if abs(playerNode.volume - targetLinearGain) > 0.005 {
            playerNode.volume = targetLinearGain
        }
    }

    private func stopTimer() {
        timer?.invalidate()
        timer = nil
    }
}