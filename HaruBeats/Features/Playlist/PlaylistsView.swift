import SwiftUI

struct PlaylistsView: View {
    var body: some View {
        NavigationStack {
            VStack(spacing: 14) {
                Image(systemName: "music.note.list")
                    .font(.system(size: 48))
                    .foregroundStyle(.indigo)
                Text("Playlists y soporte .m3u8")
                    .font(.headline)
                Text("Lo construiremos en la Etapa 6 junto con la resolución de rutas de descargas.m3u8.")
                    .font(.caption)
                    .foregroundStyle(AppTheme.secondaryText)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(AppTheme.background)
            .navigationTitle("Playlists")
        }
    }
}