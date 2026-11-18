import SwiftUI

@main
struct HaruBeatsApp: App {
    @StateObject private var audioManager = AudioPlayerManager()
    @StateObject private var playlistManager = PlaylistManager()

    var body: some Scene {
        WindowGroup {
            MainTabView()
                .environmentObject(audioManager)
                .environmentObject(playlistManager)
                .preferredColorScheme(.dark)
        }
    }
}