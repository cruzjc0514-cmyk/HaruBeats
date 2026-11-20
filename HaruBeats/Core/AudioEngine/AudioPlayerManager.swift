import Foundation
import SwiftUI
import AVFoundation
import MediaPlayer
import Combine

@MainActor
final class PlaybackProgress: ObservableObject {
    @Published var currentTime: TimeInterval = 0
    @Published var duration: TimeInterval = 0
    @Published var activeLineIndex: Int? = nil
}

@MainActor
final class AudioPlayerManager: NSObject, ObservableObject {
    let progress = PlaybackProgress()

    @Published var library: [Song] = []
    @Published var songsWithLyrics: Set<String> = []
    @Published var playbackQueue: [Song] = []
    @Published var currentSong: Song?
    @Published var currentLyrics: [LyricLine] = []
    @Published var plainLyricsText: String? = nil
    @Published var isPlaying: Bool = false
    @Published var isShuffle: Bool = false
    @Published var isRepeatOne: Bool = false
    @Published var isScrubbing: Bool = false
    @Published var isScanningLibrary: Bool = false

    @Published var dynamicArtworkColor: Color? = nil

    // Ecualizador de 5 bandas (nunca usa eqNode.bypass = true para no apagar ReplayGain)
    @Published var isEQEnabled: Bool = true {
        didSet {
            syncEQBands()
            saveEQSettings()
        }
    }
    @Published var selectedPreset: EqualizerPreset = .flat
    @Published var bandGains: [Float] = [0, 0, 0, 0, 0]

    // ReplayGain real mediante preamp del EQ (soporta +dB y -dB con límite de pico)
    @Published var isReplayGainEnabled: Bool = true {
        didSet {
            UserDefaults.standard.set(isReplayGainEnabled, forKey: "hb_replaygain_enabled")
            updateTargetGain()
        }
    }

    // Temporizador de apagado
    @Published var sleepTimerRemaining: TimeInterval? = nil
    @Published var stopAfterCurrentSong: Bool = false

    // Sincronización LRC y escala de fuente
    @Published var lyricsOffset: TimeInterval = 0
    @Published var lyricsFontScale: Double = 1.0 {
        didSet { UserDefaults.standard.set(lyricsFontScale, forKey: "hb_lyrics_scale") }
    }

    // Crossfade (0 = Gapless continuo cuando coincide formato)
    @Published var crossfadeDuration: Double = 0 {
        didSet { UserDefaults.standard.set(crossfadeDuration, forKey: "hb_crossfade_duration") }
    }

    // Historial y estadísticas por relativePath (con fallback a nombre migrado)
    @Published var recentSongKeys: [String] = []
    @Published var playCounts: [String: Int] = [:]

    // Motor AVAudioEngine recreable ante mediaServicesWereResetNotification
    private var engine = AVAudioEngine()
    private var playerNode = AVAudioPlayerNode()
    private var eqNode = AVAudioUnitEQ(numberOfBands: 5)
    private let frequencies: [Float] = [60, 230, 910, 3600, 14000]

    private var audioFile: AVAudioFile?
    private var seekFrameOffset: AVAudioFramePosition = 0
    private var totalFrames: AVAudioFramePosition = 0
    private var fileSampleRate: Double = 44100
    private var playbackGeneration: UInt64 = 0

    // Debounce independiente por acción remota
    private var lastToggleTime: Date = .distantPast
    private var lastNextTime: Date = .distantPast
    private var lastPrevTime: Date = .distantPast

    private var seekHoldUntil: Date = .distantPast
    private var fadeInRemaining: Double = 0
    private var targetPreampDB: Float = 0.0

    // Pre-programación Gapless encadenada (1 -> 2 -> 3 -> N)
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
        recentSongKeys.compactMap { findSong(byKey: $0) }
    }

    var topPlayedSongs: [(song: Song, count: Int)] {
        playCounts
            .compactMap { key, count -> (Song, Int)? in
                guard count > 0, let song = findSong(byKey: key) else { return nil }
                return (song, count)
            }
            .sorted { $0.1 > $1.1 }
    }

    override init() {
        super.init()
        rebuildAudioEngineGraph()
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

    private func findSong(byKey key: String) -> Song? {
        if let exact = library.first(where: { $0.relativePath == key }) {
            return exact
        }
        return library.first(where: { $0.fileURL.lastPathComponent == key })
    }

    // MARK: - Construcción y arranque seguro de AVAudioEngine

    private func rebuildAudioEngineGraph() {
        engine.stop()
        engine = AVAudioEngine()
        playerNode = AVAudioPlayerNode()
        eqNode = AVAudioUnitEQ(numberOfBands: 5)

        engine.attach(playerNode)
        engine.attach(eqNode)

        for (index, freq) in frequencies.enumerated() {
            let band = eqNode.bands[index]
            band.filterType = .parametric
            band.frequency = freq
            band.bandwidth = 1.0
            band.gain = isEQEnabled && index < bandGains.count ? bandGains[index] : 0
            band.bypass = false
        }

        eqNode.bypass = false
        eqNode.globalGain = targetPreampDB

        engine.connect(playerNode, to: eqNode, format: nil)
        engine.connect(eqNode, to: engine.mainMixerNode, format: nil)
        engine.prepare()
    }

    private func ensureEngineRunning() -> Bool {
        if engine.isRunning { return true }
        configureAudioSession()
        engine.prepare()
        do {
            try engine.start()
            return engine.isRunning
        } catch {
            print("Error arrancando AVAudioEngine: \(error)")
            return false
        }
    }

    // MARK: - Interrupciones y reinicio de servicios de audio de iOS

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
                        guard self.ensureEngineRunning() else { return }
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

        // Apple: tras mediaServicesWereResetNotification todos los objetos de audio quedan inválidos y deben recrearse
        nc.addObserver(forName: AVAudioSession.mediaServicesWereResetNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                let wasPlaying = self.isPlaying
                let savedTime = self.progress.currentTime
                let savedSong = self.currentSong

                self.playbackGeneration &+= 1
                self.clearGaplessPreSchedule()
                self.stopTimer()
                self.rebuildAudioEngineGraph()
                self.configureAudioSession()

                if let song = savedSong {
                    if wasPlaying {
                        self.play(song: song)
                        if savedTime > 0.5 {
                            self.seek(to: savedTime)
                        }
                    } else {
                        self.prepareSongPaused(song, atTime: savedTime)
                    }
                }
            }
        }

        nc.addObserver(forName: .AVAudioEngineConfigurationChange, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                let wasPlaying = self.isPlaying
                let savedTime = self.progress.currentTime
                guard self.ensureEngineRunning() else { return }
                if wasPlaying, self.audioFile != nil {
                    self.seek(to: savedTime)
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
        UserDefaults.standard.set(song.relativePath, forKey: "hb_session_song")
        UserDefaults.standard.set(progress.currentTime, forKey: "hb_session_time")
        UserDefaults.standard.set(playbackQueue.map { $0.relativePath }, forKey: "hb_session_queue")
    }

    private func restoreLastPlaybackSession() {
        guard currentSong == nil,
              let savedSongKey = UserDefaults.standard.string(forKey: "hb_session_song"),
              let song = findSong(byKey: savedSongKey) else {
            return
        }

        let savedQueueKeys = UserDefaults.standard.stringArray(forKey: "hb_session_queue") ?? []
        let restoredQueue = savedQueueKeys.compactMap { findSong(byKey: $0) }
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
        let totalSecs = Double(totalFrames) / fileSampleRate
        progress.duration = totalSecs

        let clampedTime = min(max(time, 0), max(totalSecs - 0.5, 0))
        let targetFrame = min(max(AVAudioFramePosition(clampedTime * fileSampleRate), 0), totalFrames - 1)
        seekFrameOffset = targetFrame
        currentSong = song
        progress.currentTime = clampedTime
        isPlaying = false
        dynamicArtworkColor = ArtworkColorExtractor.dominantColor(from: song.artworkImage)
        updateTargetGain()
        playerNode.volume = 1.0

        scheduleSegment(fromFrame: targetFrame, generation: gen)
        loadLyrics(for: song)
        updateNowPlayingInfo()
    }

    // MARK: - Preferencias, Estadísticas y ReplayGain Real (sin eqNode.bypass)

    private func loadUserPreferencesAndStats() {
        if let scale = UserDefaults.standard.object(forKey: "hb_lyrics_scale") as? Double, scale >= 0.8 {
            lyricsFontScale = scale
        }
        if UserDefaults.standard.object(forKey: "hb_replaygain_enabled") != nil {
            isReplayGainEnabled = UserDefaults.standard.bool(forKey: "hb_replaygain_enabled")
        }
        crossfadeDuration = UserDefaults.standard.double(forKey: "hb_crossfade_duration")
        recentSongKeys = UserDefaults.standard.stringArray(forKey: "hb_recent_files") ?? []
        if let savedCounts = UserDefaults.standard.dictionary(forKey: "hb_play_counts") as? [String: Int] {
            playCounts = savedCounts
        }
    }

    private func updateTargetGain() {
        if isReplayGainEnabled, let song = currentSong, song.replayGainDB != nil {
            targetPreampDB = song.safeReplayGainDB
        } else {
            targetPreampDB = 0.0
        }
        eqNode.bypass = false
        eqNode.globalGain = targetPreampDB
    }

    private func recordSongPlayed(_ song: Song) {
        let key = song.relativePath

        recentSongKeys.removeAll { $0 == key || $0 == song.fileURL.lastPathComponent }
        recentSongKeys.insert(key, at: 0)
        if recentSongKeys.count > 25 {
            recentSongKeys = Array(recentSongKeys.prefix(25))
        }
        UserDefaults.standard.set(recentSongKeys, forKey: "hb_recent_files")

        playCounts[key, default: 0] += 1
        UserDefaults.standard.set(playCounts, forKey: "hb_play_counts")
    }

    func adjustLyricsOffset(by delta: TimeInterval) {
        lyricsOffset = ((lyricsOffset + delta) * 10).rounded() / 10
        if let song = currentSong {
            UserDefaults.standard.set(lyricsOffset, forKey: "hb_lrc_offset_\(song.relativePath)")
        }
        updateActiveLyricLine(at: progress.currentTime)
    }

    func resetLyricsOffset() {
        lyricsOffset = 0
        if let song = currentSong {
            UserDefaults.standard.removeObject(forKey: "hb_lrc_offset_\(song.relativePath)")
        }
        updateActiveLyricLine(at: progress.currentTime)
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
        eqNode.bypass = false
        for index in 0..<eqNode.bands.count {
            if isEQEnabled && index < bandGains.count {
                eqNode.bands[index].gain = bandGains[index]
            } else {
                eqNode.bands[index].gain = 0
            }
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
        syncEQBands()
    }

    // MARK: - Temporizador de apagado

    func startSleepTimer(minutes: Int) {
        cancelSleepTimer()
        stopAfterCurrentSong = false
        sleepTimerRemaining = TimeInterval(minutes * 60)

        let newSleepTimer = Timer(timeInterval: 1.0, repeats: true) { [weak self] _ in
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
        RunLoop.main.add(newSleepTimer, forMode: .common)
        sleepTimer = newSleepTimer
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

    // MARK: - Sesión y controles remotos (1 toque en Lock Screen y Control Center)

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

        commandCenter.playCommand.isEnabled = true
        commandCenter.playCommand.addTarget { [weak self] _ in
            Task { @MainActor in
                guard let self, !self.isPlaying else { return }
                self.togglePlayPause()
            }
            return .success
        }

        commandCenter.pauseCommand.isEnabled = true
        commandCenter.pauseCommand.addTarget { [weak self] _ in
            Task { @MainActor in
                guard let self, self.isPlaying else { return }
                self.togglePlayPause()
            }
            return .success
        }

        commandCenter.togglePlayPauseCommand.isEnabled = true
        commandCenter.togglePlayPauseCommand.addTarget { [weak self] _ in
            Task { @MainActor in
                self?.togglePlayPause()
            }
            return .success
        }

        commandCenter.nextTrackCommand.isEnabled = true
        commandCenter.nextTrackCommand.addTarget { [weak self] _ in
            Task { @MainActor in
                self?.playNext()
            }
            return .success
        }

        commandCenter.previousTrackCommand.isEnabled = true
        commandCenter.previousTrackCommand.addTarget { [weak self] _ in
            Task { @MainActor in
                self?.playPrevious()
            }
            return .success
        }

        commandCenter.changePlaybackPositionCommand.isEnabled = true
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

        var liveElapsed = progress.currentTime
        if isPlaying,
           let nodeTime = playerNode.lastRenderTime,
           nodeTime.isSampleTimeValid,
           let playerTime = playerNode.playerTime(forNodeTime: nodeTime) {
            let computed = (Double(seekFrameOffset) / fileSampleRate) + (Double(playerTime.sampleTime) / playerTime.sampleRate)
            if computed >= 0 && computed <= progress.duration {
                liveElapsed = computed
            }
        }

        var info: [String: Any] = [
            MPMediaItemPropertyTitle: song.title,
            MPMediaItemPropertyArtist: song.artist,
            MPMediaItemPropertyAlbumTitle: song.album,
            MPMediaItemPropertyPlaybackDuration: progress.duration,
            MPNowPlayingInfoPropertyElapsedPlaybackTime: liveElapsed,
            MPNowPlayingInfoPropertyPlaybackRate: isPlaying ? 1.0 : 0.0,
            MPNowPlayingInfoPropertyDefaultPlaybackRate: 1.0
        ]

        if let image = song.artworkImage {
            let artwork = MPMediaItemArtwork(boundsSize: image.size) { _ in image }
            info[MPMediaItemPropertyArtwork] = artwork
        }

        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
    }

    // MARK: - Saneamiento estricto y carpetas únicas "Artista - Álbum"

    private func sanitizeFolderComponent(_ raw: String) -> String {
        var cleaned = raw
            .replacingOccurrences(of: "..", with: "_")
            .replacingOccurrences(of: "[\\\\/:*?\"<>|]", with: "_", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        while cleaned.hasPrefix(".") {
            cleaned.removeFirst()
        }
        return cleaned.isEmpty ? "General" : String(cleaned.prefix(72))
    }

    private func uniqueDirectoryURL(forDesiredName rawName: String, avoidCollisionWithExistingFiles: Bool) -> URL {
        let baseName = sanitizeFolderComponent(rawName)
        let candidate = musicDirectory.appendingPathComponent(baseName, isDirectory: true)

        if !avoidCollisionWithExistingFiles || !FileManager.default.fileExists(atPath: candidate.path) {
            try? FileManager.default.createDirectory(at: candidate, withIntermediateDirectories: true)
            return candidate
        }

        var counter = 2
        while true {
            let numbered = musicDirectory.appendingPathComponent("\(baseName) (\(counter))", isDirectory: true)
            if !FileManager.default.fileExists(atPath: numbered.path) {
                try? FileManager.default.createDirectory(at: numbered, withIntermediateDirectories: true)
                return numbered
            }
            counter += 1
        }
    }

    private func resolveDestinationFolder(preferredFolder: String?, audioSourceURL: URL?) async -> URL {
        // Si viene de subida de carpeta Wi-Fi o selector de carpeta, respetamos su carpeta saneada
        if let preferredFolder, !preferredFolder.isEmpty {
            return uniqueDirectoryURL(forDesiredName: preferredFolder, avoidCollisionWithExistingFiles: false)
        }

        // Si es un archivo individual, construimos "Artista - Álbum" para evitar choque entre homónimos ("Greatest Hits")
        if let audioSourceURL {
            let ext = audioSourceURL.pathExtension.lowercased()
            if ext == "flac" {
                let meta = FLACMetadataParser.parse(url: audioSourceURL)
                let artistPart = meta.albumArtist ?? meta.artist
                let albumPart = meta.album
                if let albumPart, !albumPart.isEmpty {
                    let combined = (artistPart?.isEmpty == false) ? "\(artistPart!) - \(albumPart)" : albumPart
                    return uniqueDirectoryURL(forDesiredName: combined, avoidCollisionWithExistingFiles: false)
                }
            } else if ["mp3", "m4a", "aac", "wav", "alac"].contains(ext) {
                let asset = AVURLAsset(url: audioSourceURL)
                if let metadata = try? await asset.load(.commonMetadata) {
                    var artistPart: String? = nil
                    var albumPart: String? = nil
                    for item in metadata {
                        if item.commonKey == .commonKeyCreator || item.commonKey == .commonKeyArtist {
                            if artistPart == nil, let val = try? await item.load(.stringValue), !val.isEmpty {
                                artistPart = val
                            }
                        } else if item.commonKey == .commonKeyAlbumName {
                            if let val = try? await item.load(.stringValue), !val.isEmpty {
                                albumPart = val
                            }
                        }
                    }
                    if let albumPart, !albumPart.isEmpty {
                        let combined = (artistPart?.isEmpty == false) ? "\(artistPart!) - \(albumPart)" : albumPart
                        return uniqueDirectoryURL(forDesiredName: combined, avoidCollisionWithExistingFiles: false)
                    }
                }
            }
        }

        return uniqueDirectoryURL(forDesiredName: "General", avoidCollisionWithExistingFiles: false)
    }

    // MARK: - Escaneo Recursivo con Set<String> de letras en una sola pasada

    func loadStoredLibrary() async {
        isScanningLibrary = true
        defer { isScanningLibrary = false }

        let supportedExtensions = ["flac", "mp3", "m4a", "aac", "wav", "alac"]
        guard let enumerator = FileManager.default.enumerator(
            at: musicDirectory,
            includingPropertiesForKeys: [.isRegularFileKey, .fileSizeKey, .contentModificationDateKey],
            options: [.skipsHiddenFiles]
        ) else { return }

        let allURLs = enumerator.allObjects.compactMap { $0 as? URL }
        let basePath = musicDirectory.standardizedFileURL.path + "/"

        // Indexar todos los archivos .lrc / .txt existentes en una sola pasada
        var sidecarBasePaths = Set<String>()
        var audioEntries: [(url: URL, relPath: String, baseRelPath: String)] = []

        for fileURL in allURLs {
            let ext = fileURL.pathExtension.lowercased()
            let fullPath = fileURL.standardizedFileURL.path
            let relPath = fullPath.hasPrefix(basePath) ? String(fullPath.dropFirst(basePath.count)) : fileURL.lastPathComponent
            let baseRel = (relPath as NSString).deletingPathExtension

            if ext == "lrc" || ext == "txt" {
                sidecarBasePaths.insert(baseRel)
            } else if supportedExtensions.contains(ext) {
                audioEntries.append((url: fileURL, relPath: relPath, baseRelPath: baseRel))
            }
        }

        let existingRelPaths = Set(audioEntries.map { $0.relPath })
        let existingIndex = LibraryCacheManager.shared.loadIndex()
        var updatedRecords: [CachedSongRecord] = []
        var loadedSongs: [Song] = []
        var lyricRelPaths = Set<String>()

        for (cachedRelPath, cachedRecord) in existingIndex where !existingRelPaths.contains(cachedRelPath) {
            LibraryCacheManager.shared.removeArtwork(forKey: cachedRecord.artworkCacheKey)
        }

        for entry in audioEntries {
            let resourceValues = try? entry.url.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey])
            let fileSize = Int64(resourceValues?.fileSize ?? 0)
            let modTime = resourceValues?.contentModificationDate?.timeIntervalSince1970 ?? 0

            let song: Song
            if let cached = existingIndex[entry.relPath],
               cached.fileSize == fileSize,
               abs(cached.modificationTimestamp - modTime) < 1.0 {
                song = Song.fromCached(cached, fileURL: entry.url)
            } else {
                song = await Song.from(url: entry.url, relativePath: entry.relPath)
            }

            if sidecarBasePaths.contains(entry.baseRelPath) || (song.embeddedLyrics?.isEmpty == false) {
                lyricRelPaths.insert(entry.relPath)
            }

            loadedSongs.append(song)
            updatedRecords.append(song.toCachedRecord(fileSize: fileSize, modTime: modTime))
        }

        LibraryCacheManager.shared.saveIndex(updatedRecords)
        self.songsWithLyrics = lyricRelPaths
        self.library = loadedSongs.sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
        if playbackQueue.isEmpty {
            playbackQueue = self.library
        }
    }

    func deleteSong(_ song: Song) async {
        playbackGeneration &+= 1
        clearGaplessPreSchedule()
        stopTimer()

        if currentSong?.relativePath == song.relativePath {
            if playerNode.isPlaying {
                playerNode.stop()
            }
            audioFile = nil
            isPlaying = false
            currentSong = nil
            dynamicArtworkColor = nil
            progress.currentTime = 0
            progress.duration = 0
            progress.activeLineIndex = nil
            currentLyrics = []
            plainLyricsText = nil
            MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
            savePlaybackSession(force: true)
        }

        LibraryCacheManager.shared.removeArtwork(forKey: song.artworkCacheKey)
        songsWithLyrics.remove(song.relativePath)
        library.removeAll { $0.relativePath == song.relativePath }
        playbackQueue.removeAll { $0.relativePath == song.relativePath }

        try? FileManager.default.removeItem(at: song.fileURL)
        let baseURL = song.fileURL.deletingPathExtension()
        try? FileManager.default.removeItem(at: baseURL.appendingPathExtension("lrc"))
        try? FileManager.default.removeItem(at: baseURL.appendingPathExtension("txt"))
    }

    func enqueueNext(_ song: Song) {
        guard song.relativePath != currentSong?.relativePath else { return }
        if playbackQueue.isEmpty {
            playbackQueue = library
        }
        playbackQueue.removeAll { $0.relativePath == song.relativePath }
        if let current = currentSong, let idx = playbackQueue.firstIndex(where: { $0.relativePath == current.relativePath }) {
            playbackQueue.insert(song, at: idx + 1)
        } else {
            playbackQueue.insert(song, at: 0)
        }
        clearGaplessPreSchedule()
        savePlaybackSession(force: true)
    }

    func appendToQueue(_ song: Song) {
        guard song.relativePath != currentSong?.relativePath else { return }
        if playbackQueue.isEmpty {
            playbackQueue = library
        }
        playbackQueue.removeAll { $0.relativePath == song.relativePath }
        playbackQueue.append(song)
        clearGaplessPreSchedule()
        savePlaybackSession(force: true)
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
        var folderByBaseName: [String: URL] = [:]
        let audioExtensions = ["flac", "mp3", "m4a", "aac", "wav", "alac"]

        for url in urls {
            let ext = url.pathExtension.lowercased()
            guard audioExtensions.contains(ext) else { continue }
            let accessed = url.startAccessingSecurityScopedResource()
            defer { if accessed { url.stopAccessingSecurityScopedResource() } }

            let destFolder = await resolveDestinationFolder(preferredFolder: nil, audioSourceURL: url)
            let baseName = url.deletingPathExtension().lastPathComponent
            folderByBaseName[baseName] = destFolder

            let destination = destFolder.appendingPathComponent(url.lastPathComponent)
            if FileManager.default.fileExists(atPath: destination.path) {
                try? FileManager.default.removeItem(at: destination)
            }
            try? FileManager.default.copyItem(at: url, to: destination)
        }

        for url in urls {
            let ext = url.pathExtension.lowercased()
            guard ["lrc", "txt"].contains(ext) else { continue }
            let accessed = url.startAccessingSecurityScopedResource()
            defer { if accessed { url.stopAccessingSecurityScopedResource() } }

            let baseName = url.deletingPathExtension().lastPathComponent
            let destFolder = folderByBaseName[baseName]
                ?? library.first(where: { $0.fileURL.deletingPathExtension().lastPathComponent == baseName })?.fileURL.deletingLastPathComponent()
                ?? uniqueDirectoryURL(forDesiredName: "General", avoidCollisionWithExistingFiles: false)

            let destination = destFolder.appendingPathComponent(url.lastPathComponent)
            if FileManager.default.fileExists(atPath: destination.path) {
                try? FileManager.default.removeItem(at: destination)
            }
            try? FileManager.default.copyItem(at: url, to: destination)
        }

        await loadStoredLibrary()
        if let currentSong {
            loadLyrics(for: currentSong)
        }
    }

    func importFolder(url folderURL: URL) async -> (folderName: String, importedSongs: [Song]) {
        let folderName = folderURL.lastPathComponent
        let accessed = folderURL.startAccessingSecurityScopedResource()
        defer { if accessed { folderURL.stopAccessingSecurityScopedResource() } }

        let allowedExtensions = ["flac", "mp3", "m4a", "aac", "wav", "alac", "lrc", "txt"]
        let audioExtensions = ["flac", "mp3", "m4a", "aac", "wav", "alac"]
        var copiedRelativePaths: [String] = []
        let destFolder = uniqueDirectoryURL(forDesiredName: folderName, avoidCollisionWithExistingFiles: true)
        let folderSlug = destFolder.lastPathComponent

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

                let destination = destFolder.appendingPathComponent(fileURL.lastPathComponent)
                do {
                    if FileManager.default.fileExists(atPath: destination.path) {
                        try FileManager.default.removeItem(at: destination)
                    }
                    try FileManager.default.copyItem(at: fileURL, to: destination)
                    if audioExtensions.contains(ext) {
                        copiedRelativePaths.append("\(folderSlug)/\(fileURL.lastPathComponent)")
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

        let orderedSongs = copiedRelativePaths.compactMap { relPath in
            library.first(where: { $0.relativePath == relPath })
        }
        return (folderName, orderedSongs)
    }

    func saveTransferredFile(fileName: String, folderName: String?, data: Data) async -> (destination: URL, song: Song?)? {
        let safeFileName = sanitizeFolderComponent(fileName)
        let ext = (safeFileName as NSString).pathExtension.lowercased()
        let baseName = (safeFileName as NSString).deletingPathExtension

        // Si el navegador envía folderName, lo usamos directo sin necesidad de leer metadatos antes
        if let folderName, !folderName.isEmpty {
            let destFolder = uniqueDirectoryURL(forDesiredName: folderName, avoidCollisionWithExistingFiles: false)
            let destination = destFolder.appendingPathComponent(safeFileName)
            do {
                try data.write(to: destination, options: .atomic)
                await loadStoredLibrary()
                if let currentSong {
                    loadLyrics(for: currentSong)
                }
                let relPath = "\(destFolder.lastPathComponent)/\(safeFileName)"
                return (destination, library.first(where: { $0.relativePath == relPath }))
            } catch {
                print("Error guardando archivo en carpeta Wi-Fi \(safeFileName): \(error)")
                return nil
            }
        }

        // Archivo suelto sin carpeta: si es .lrc/.txt y ya existe la canción, va junto a ella; si es audio, lee "Artista - Álbum"
        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + "_" + safeFileName)
        do {
            try data.write(to: tempURL, options: .atomic)
            defer { try? FileManager.default.removeItem(at: tempURL) }

            let destFolder: URL
            if ["lrc", "txt"].contains(ext),
               let matchingSong = library.first(where: { $0.fileURL.deletingPathExtension().lastPathComponent == baseName }) {
                destFolder = matchingSong.fileURL.deletingLastPathComponent()
            } else {
                destFolder = await resolveDestinationFolder(preferredFolder: nil, audioSourceURL: tempURL)
            }

            let destination = destFolder.appendingPathComponent(safeFileName)
            if FileManager.default.fileExists(atPath: destination.path) {
                try FileManager.default.removeItem(at: destination)
            }
            try FileManager.default.moveItem(at: tempURL, to: destination)

            await loadStoredLibrary()
            if let currentSong {
                loadLyrics(for: currentSong)
            }
            let relPath = "\(destFolder.lastPathComponent)/\(safeFileName)"
            return (destination, library.first(where: { $0.relativePath == relPath }))
        } catch {
            print("Error guardando archivo suelto Wi-Fi \(safeFileName): \(error)")
            return nil
        }
    }

    func scanUSBSharedFiles() async -> Int {
        guard let rootFiles = try? FileManager.default.contentsOfDirectory(
            at: documentsDirectory,
            includingPropertiesForKeys: nil
        ) else { return 0 }

        let allowedExtensions = ["flac", "mp3", "m4a", "aac", "wav", "alac", "lrc", "txt"]
        var importedCount = 0

        for fileURL in rootFiles {
            let ext = fileURL.pathExtension.lowercased()
            guard allowedExtensions.contains(ext) else { continue }

            let destFolder = await resolveDestinationFolder(preferredFolder: nil, audioSourceURL: fileURL)
            let destination = destFolder.appendingPathComponent(fileURL.lastPathComponent)
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

    // MARK: - Letras e índice de línea activa (solo cambia al cambiar de verso)

    func loadLyrics(for song: Song) {
        let baseURL = song.fileURL.deletingPathExtension()
        let lrcURL = baseURL.appendingPathExtension("lrc")
        let txtURL = baseURL.appendingPathExtension("txt")
        lyricsOffset = UserDefaults.standard.double(forKey: "hb_lrc_offset_\(song.relativePath)")

        currentLyrics = []
        plainLyricsText = nil
        progress.activeLineIndex = nil

        if FileManager.default.fileExists(atPath: lrcURL.path),
           let content = try? String(contentsOf: lrcURL, encoding: .utf8) {
            let parsed = LRCParser.parse(content: content)
            if !parsed.isEmpty {
                currentLyrics = parsed
                updateActiveLyricLine(at: progress.currentTime)
            } else {
                plainLyricsText = content.trimmingCharacters(in: .whitespacesAndNewlines)
            }
            return
        }

        if FileManager.default.fileExists(atPath: txtURL.path),
           let content = try? String(contentsOf: txtURL, encoding: .utf8) {
            plainLyricsText = content.trimmingCharacters(in: .whitespacesAndNewlines)
            return
        }

        if let embedded = song.embeddedLyrics, !embedded.isEmpty {
            let parsed = LRCParser.parse(content: embedded)
            if !parsed.isEmpty {
                currentLyrics = parsed
                updateActiveLyricLine(at: progress.currentTime)
            } else {
                plainLyricsText = embedded.trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }
    }

    private func updateActiveLyricLine(at time: TimeInterval) {
        guard !currentLyrics.isEmpty else {
            if progress.activeLineIndex != nil {
                progress.activeLineIndex = nil
            }
            return
        }

        let adjustedTime = time + lyricsOffset
        var newIndex: Int? = nil
        for index in stride(from: currentLyrics.count - 1, through: 0, by: -1) {
            if currentLyrics[index].timestamp <= adjustedTime {
                newIndex = index
                break
            }
        }

        if progress.activeLineIndex != newIndex {
            progress.activeLineIndex = newIndex
        }
    }

    func attachManualLRC(from sourceURL: URL) {
        guard let song = currentSong else { return }
        let accessed = sourceURL.startAccessingSecurityScopedResource()
        defer { if accessed { sourceURL.stopAccessingSecurityScopedResource() } }

        let destination = song.fileURL.deletingPathExtension().appendingPathExtension("lrc")
        do {
            if FileManager.default.fileExists(atPath: destination.path) {
                try FileManager.default.removeItem(at: destination)
            }
            try FileManager.default.copyItem(at: sourceURL, to: destination)
            songsWithLyrics.insert(song.relativePath)
            loadLyrics(for: song)
        } catch {
            print("Error vinculando .lrc manual: \(error)")
        }
    }

    // MARK: - Reproducción Gapless encadenada (mismo formato) + Fallback seguro (cambio de sampleRate/canales)

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
            guard ensureEngineRunning() else { return }
            let file = try AVAudioFile(forReading: song.fileURL)
            let format = file.processingFormat
            guard format.sampleRate > 0, format.channelCount > 0, file.length > 0 else { return }

            playerNode.stop()
            playerNode.reset()

            audioFile = file
            fileSampleRate = format.sampleRate
            totalFrames = file.length
            progress.duration = Double(totalFrames) / fileSampleRate
            seekFrameOffset = 0
            currentSong = song
            progress.currentTime = 0
            seekHoldUntil = Date().addingTimeInterval(0.25)
            dynamicArtworkColor = ArtworkColorExtractor.dominantColor(from: song.artworkImage)
            updateTargetGain()

            if crossfadeDuration > 0 {
                playerNode.volume = 0.05
                fadeInRemaining = crossfadeDuration
            } else {
                playerNode.volume = 1.0
                fadeInRemaining = 0
            }

            scheduleSegment(fromFrame: 0, generation: gen)
            guard ensureEngineRunning() else { return }
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
              let idx = activeQueue.firstIndex(where: { $0.relativePath == current.relativePath }) else {
            return nil
        }
        let nextIndex = (idx + 1) % activeQueue.count
        return activeQueue[nextIndex]
    }

    /// Pre-programa la siguiente pista solo si comparte sampleRate y canales; si difieren, cae al camino normal con pausa breve
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
                self.onScheduledBufferFinished(generation: generation)
            }
        }
    }

    private func onScheduledBufferFinished(generation: UInt64) {
        if let gaplessSong = preScheduledNextSong, let gaplessFile = preScheduledNextFile {
            promotePreScheduledGaplessTrack(nextSong: gaplessSong, nextFile: gaplessFile)
        } else {
            handleTrackCompleted()
        }
    }

    private func promotePreScheduledGaplessTrack(nextSong: Song, nextFile: AVAudioFile) {
        // Calculamos seekFrameOffset estrictamente desde el sampleTime exacto del render thread
        var exactOffsetFrames: AVAudioFramePosition = 0
        if let nodeTime = playerNode.lastRenderTime,
           nodeTime.isSampleTimeValid,
           let playerTime = playerNode.playerTime(forNodeTime: nodeTime) {
            exactOffsetFrames = -playerTime.sampleTime
        }

        clearGaplessPreSchedule()
        audioFile = nextFile
        fileSampleRate = nextFile.processingFormat.sampleRate
        totalFrames = nextFile.length
        progress.duration = Double(totalFrames) / fileSampleRate
        seekFrameOffset = exactOffsetFrames
        currentSong = nextSong
        progress.currentTime = 0
        seekHoldUntil = Date().addingTimeInterval(0.20)
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
                self.onScheduledBufferFinished(generation: generation)
            }
        }
    }

    private func handleTrackCompleted() {
        playerNode.volume = 1.0
        if stopAfterCurrentSong {
            stopAfterCurrentSong = false
            isPlaying = false
            stopTimer()
            progress.currentTime = 0
            savePlaybackSession(force: true)
            updateNowPlayingInfo()
            return
        }

        if isRepeatOne, let current = currentSong {
            play(song: current)
        } else {
            advanceToNextTrack()
        }
    }

    func togglePlayPause() {
        let now = Date()
        guard now.timeIntervalSince(lastToggleTime) > 0.10 else { return }
        lastToggleTime = now

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
            guard ensureEngineRunning() else { return }
            playerNode.volume = 1.0
            playerNode.play()
            isPlaying = true
            startTimer()
        }
        updateNowPlayingInfo()
    }

    func seek(to time: TimeInterval) {
        guard audioFile != nil, progress.duration > 0 else { return }
        let clampedTime = min(max(time, 0), progress.duration)
        let targetFrame = min(max(AVAudioFramePosition(clampedTime * fileSampleRate), 0), totalFrames - 1)
        let wasPlaying = isPlaying

        playbackGeneration &+= 1
        let gen = playbackGeneration
        clearGaplessPreSchedule()

        playerNode.stop()
        playerNode.reset()
        playerNode.volume = 1.0
        fadeInRemaining = 0
        seekFrameOffset = targetFrame
        progress.currentTime = clampedTime
        updateActiveLyricLine(at: clampedTime)
        seekHoldUntil = Date().addingTimeInterval(0.30)

        scheduleSegment(fromFrame: targetFrame, generation: gen)
        if wasPlaying {
            guard ensureEngineRunning() else { return }
            playerNode.play()
        }
        savePlaybackSession(force: true)
        updateNowPlayingInfo()
    }

    func playNext() {
        let now = Date()
        guard now.timeIntervalSince(lastNextTime) > 0.10 else { return }
        lastNextTime = now
        advanceToNextTrack()
    }

    private func advanceToNextTrack() {
        let activeQueue = playbackQueue.filter { FileManager.default.fileExists(atPath: $0.fileURL.path) }
        guard !activeQueue.isEmpty else { return }

        if isShuffle, let randomSong = activeQueue.randomElement() {
            play(song: randomSong, inQueue: activeQueue)
            return
        }
        guard let current = currentSong,
              let idx = activeQueue.firstIndex(where: { $0.relativePath == current.relativePath }) else {
            play(song: activeQueue[0], inQueue: activeQueue)
            return
        }
        let nextIndex = (idx + 1) % activeQueue.count
        play(song: activeQueue[nextIndex], inQueue: activeQueue)
    }

    func playPrevious() {
        let now = Date()
        guard now.timeIntervalSince(lastPrevTime) > 0.10 else { return }
        lastPrevTime = now

        let activeQueue = playbackQueue.filter { FileManager.default.fileExists(atPath: $0.fileURL.path) }
        guard !activeQueue.isEmpty else { return }

        if progress.currentTime > 3 {
            seek(to: 0)
            return
        }
        guard let current = currentSong,
              let idx = activeQueue.firstIndex(where: { $0.relativePath == current.relativePath }) else {
            play(song: activeQueue[0], inQueue: activeQueue)
            return
        }
        let prevIndex = (idx - 1 + activeQueue.count) % activeQueue.count
        play(song: activeQueue[prevIndex], inQueue: activeQueue)
    }

    private func startTimer() {
        stopTimer()
        let tickInterval = 0.05
        let newTimer = Timer(timeInterval: tickInterval, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self, self.isPlaying, !self.isScrubbing else { return }
                if Date() < self.seekHoldUntil { return }

                guard self.ensureEngineRunning() else { return }

                guard let nodeTime = self.playerNode.lastRenderTime,
                      nodeTime.isSampleTimeValid,
                      let playerTime = self.playerNode.playerTime(forNodeTime: nodeTime) else { return }

                let playedSeconds = Double(playerTime.sampleTime) / playerTime.sampleRate
                let offsetSeconds = Double(self.seekFrameOffset) / self.fileSampleRate
                let computed = offsetSeconds + playedSeconds
                if computed >= 0 && computed <= self.progress.duration {
                    self.progress.currentTime = computed
                    self.updateActiveLyricLine(at: computed)
                    self.applyCrossfadeGain(at: computed, tick: tickInterval)
                    self.savePlaybackSession(force: false)

                    if self.progress.duration - computed <= 1.8 {
                        self.tryPreScheduleGaplessNext(generation: self.playbackGeneration)
                    }
                }
            }
        }
        RunLoop.main.add(newTimer, forMode: .common)
        timer = newTimer
    }

    private func applyCrossfadeGain(at time: TimeInterval, tick: Double) {
        let totalDur = progress.duration
        guard crossfadeDuration > 0, totalDur > crossfadeDuration * 2 else {
            if abs(playerNode.volume - 1.0) > 0.005 {
                playerNode.volume = 1.0
            }
            return
        }

        let remaining = totalDur - time
        if fadeInRemaining > 0 {
            fadeInRemaining = max(fadeInRemaining - tick, 0)
            let ratio = 1.0 - (fadeInRemaining / crossfadeDuration)
            playerNode.volume = Float(min(max(ratio, 0.05), 1.0))
        } else if remaining <= crossfadeDuration && remaining > 0 {
            let ratio = remaining / crossfadeDuration
            playerNode.volume = Float(min(max(ratio, 0.05), 1.0))
        } else if abs(playerNode.volume - 1.0) > 0.005 {
            playerNode.volume = 1.0
        }
    }

    private func stopTimer() {
        timer?.invalidate()
        timer = nil
    }
}