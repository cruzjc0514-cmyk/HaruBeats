import SwiftUI

struct AlbumsView: View {
    @EnvironmentObject var audioManager: AudioPlayerManager

    var groupedAlbums: [(album: String, songs: [Song])] {
        let dict = Dictionary(grouping: audioManager.library) { $0.album }
        return dict.keys.sorted().map { ($0, dict[$0] ?? []) }
    }

    var body: some View {
        NavigationStack {
            List {
                ForEach(groupedAlbums, id: \.album) { group in
                    Section(header: Text(group.album).foregroundStyle(.indigo)) {
                        ForEach(group.songs) { song in
                            Button {
                                audioManager.play(song: song)
                            } label: {
                                VStack(alignment: .leading) {
                                    Text(song.title)
                                        .foregroundStyle(.white)
                                    Text(song.artist)
                                        .font(.caption)
                                        .foregroundStyle(AppTheme.secondaryText)
                                }
                            }
                            .listRowBackground(AppTheme.cardBackground)
                        }
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(AppTheme.background)
            .navigationTitle("Álbumes")
        }
    }
}