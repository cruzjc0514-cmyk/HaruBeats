import SwiftUI

struct MainTabView: View {
    @State private var showFullPlayer = false

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
            .tint(.indigo)

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