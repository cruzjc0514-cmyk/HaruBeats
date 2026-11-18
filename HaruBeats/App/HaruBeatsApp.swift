import SwiftUI

@main
struct HaruBeatsApp: App {
    @StateObject private var audioManager = AudioPlayerManager()

    var body: some Scene {
        WindowGroup {
            MainTabView()
                .environmentObject(audioManager)
                .preferredColorScheme(.dark)
        }
    }
}