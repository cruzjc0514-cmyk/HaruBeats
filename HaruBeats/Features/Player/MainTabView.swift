import SwiftUI

struct MainTabView: View {
    @EnvironmentObject var audioManager: AudioPlayerManager
    @AppStorage("hb_accent_color") private var accentRaw = AccentOption.indigo.rawValue
    @AppStorage("hb_dynamic_colors") private var useDynamicColors = true
    @State private var showNowPlaying = false

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
                    .tabItem {
                        Label("Inicio", systemImage: "house.fill")
                    }

                LibraryView()
                    .tabItem {
                        Label("Biblioteca", systemImage: "music.note.list")
                    }

                AlbumsView()
                    .tabItem {
                        Label("Álbumes", systemImage: "square.stack.fill")
                    }

                PlaylistsView()
                    .tabItem {
                        Label("Playlists", systemImage: "text.badge.star")
                    }

                SettingsView()
                    .tabItem {
                        Label("Ajustes", systemImage: "gearshape.fill")
                    }
            }
            .tint(effectiveAccent)

            if audioManager.currentSong != nil {
                MiniPlayerView(showNowPlaying: $showNowPlaying)
                    .padding(.horizontal, 12)
                    .padding(.bottom, 54)
            }
        }
        .fullScreenCover(isPresented: $showNowPlaying) {
            NowPlayingView()
        }
    }
}