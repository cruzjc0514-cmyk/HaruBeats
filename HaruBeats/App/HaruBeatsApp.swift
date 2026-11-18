import SwiftUI

@main
struct HaruBeatsApp: App {
    var body: some Scene {
        WindowGroup {
            PrototypePlayerView()
                .preferredColorScheme(.dark)
        }
    }
}