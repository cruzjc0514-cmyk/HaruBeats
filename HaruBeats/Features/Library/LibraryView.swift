import SwiftUI
import UniformTypeIdentifiers

struct LibraryView: View {
    @EnvironmentObject var audioManager: AudioPlayerManager
    @State private var showImporter = false
    @State private var searchText = ""

    var filteredSongs: [Song] {
        if searchText.isEmpty { return audioManager.library }
        return audioManager.library.filter {
            $0.title.localizedCaseInsensitiveContains(searchText) ||
            $0.artist.localizedCaseInsensitiveContains(searchText)
        }
    }

    var body: some View {
        NavigationStack {
            List {
                ForEach(filteredSongs) { song in
                    Button {
                        audioManager.play(song: song)
                    } label: {
                        HStack(spacing: 12) {
                            Group {
                                if let img = song.artworkImage {
                                    Image(uiImage: img)
                                        .resizable()
                                        .scaledToFill()
                                } else {
                                    ZStack {
                                        AppTheme.elevatedBackground
                                        Image(systemName: "music.note")
                                            .foregroundStyle(.indigo)
                                    }
                                }
                            }
                            .frame(width: 46, height: 46)
                            .clipShape(RoundedRectangle(cornerRadius: 8))

                            VStack(alignment: .leading, spacing: 3) {
                                Text(song.title)
                                    .font(.body.weight(.medium))
                                    .foregroundStyle(audioManager.currentSong == song ? .indigo : .white)
                                    .lineLimit(1)
                                Text("\(song.artist) · \(song.album)")
                                    .font(.caption)
                                    .foregroundStyle(AppTheme.secondaryText)
                                    .lineLimit(1)
                            }
                        }
                    }
                    .listRowBackground(AppTheme.cardBackground)
                }
            }
            .scrollContentBackground(.hidden)
            .background(AppTheme.background)
            .searchable(text: $searchText, prompt: "Buscar canciones o artistas")
            .navigationTitle("Biblioteca")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showImporter = true
                    } label: {
                        Image(systemName: "plus.circle.fill")
                            .font(.title3)
                            .foregroundStyle(.indigo)
                    }
                }
            }
            .fileImporter(
                isPresented: $showImporter,
                allowedContentTypes: [.audio, .plainText, UTType(filenameExtension: "lrc") ?? .data],
                allowsMultipleSelection: true
            ) { result in
                if case .success(let urls) = result {
                    Task {
                        await audioManager.importFiles(urls: urls)
                    }
                }
            }
        }
    }
}