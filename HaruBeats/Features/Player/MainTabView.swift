import SwiftUI

struct MainTabView: View {
    @EnvironmentObject var audioManager: AudioPlayerManager
    @AppStorage("hb_accent_color") private var accentRaw = AccentOption.indigo.rawValue
    @AppStorage("hb_dynamic_colors") private var useDynamicColors = true
    @State private var showFullPlayer = false

    private var effectiveAccent: Color {
        if useDynamicColors, let dynamic = audioManager.dynamicArtworkColor {
            return dynamic
        }
        return (AccentOption(rawValue: accentRaw) ?? .indigo).color
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            TabView {
                HomeView()
                    .tabItem { Label("Inicio", systemImage: "house.fill") }

                AlbumsView()
                    .tabItem { Label("Álbumes", systemImage: "square.stack.fill") }

                PlaylistsView()
                    .tabItem { Label("Playlists", systemImage: "music.note.list") }

                LibraryView()
                    .tabItem { Label("Biblioteca", systemImage: "music.note") }

                SettingsView()
                    .tabItem { Label("Ajustes", systemImage: "gearshape.fill") }
            }
            .tint(effectiveAccent)

            VStack(spacing: 0) {
                MiniPlayerView(showFullPlayer: $showFullPlayer)
                    .padding(.bottom, 56)
            }
        }
        .sheet(isPresented: $showFullPlayer) {
            NowPlayingView()
        }
    }
}