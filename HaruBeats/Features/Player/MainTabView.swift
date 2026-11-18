import SwiftUI

struct MainTabView: View {
    @AppStorage("hb_accent_color") private var accentRaw = AccentOption.indigo.rawValue
    @State private var showFullPlayer = false

    private var accentColor: Color {
        (AccentOption(rawValue: accentRaw) ?? .indigo).color
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
            .tint(accentColor)

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