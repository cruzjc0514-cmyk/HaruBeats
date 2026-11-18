import SwiftUI

struct HomeView: View {
    @EnvironmentObject var audioManager: AudioPlayerManager

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    Text("Tu colección lossless")
                        .font(.subheadline)
                        .foregroundStyle(AppTheme.secondaryText)

                    if audioManager.library.isEmpty {
                        VStack(spacing: 14) {
                            Image(systemName: "hifispeaker.2.fill")
                                .font(.system(size: 44))
                                .foregroundStyle(.indigo)
                            Text("Aún no has importado música")
                                .font(.headline)
                            Text("Ve a la pestaña Biblioteca y toca + para importar tu carpeta James Gunn VIBES.")
                                .font(.caption)
                                .foregroundStyle(AppTheme.secondaryText)
                                .multilineTextAlignment(.center)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(28)
                        .background(AppTheme.cardBackground)
                        .clipShape(RoundedRectangle(cornerRadius: 20))
                    } else {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Agregadas recientemente")
                                .font(.title3.bold())

                            ForEach(audioManager.library.prefix(6)) { song in
                                Button {
                                    audioManager.play(song: song)
                                } label: {
                                    HStack(spacing: 12) {
                                        RoundedRectangle(cornerRadius: 10)
                                            .fill(AppTheme.elevatedBackground)
                                            .frame(width: 48, height: 48)
                                            .overlay {
                                                if let img = song.artworkImage {
                                                    Image(uiImage: img)
                                                        .resizable()
                                                        .scaledToFill()
                                                        .clipShape(RoundedRectangle(cornerRadius: 10))
                                                } else {
                                                    Image(systemName: "music.note")
                                                        .foregroundStyle(.indigo)
                                                }
                                            }
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(song.title)
                                                .font(.body.weight(.medium))
                                                .foregroundStyle(.white)
                                                .lineLimit(1)
                                            Text(song.artist)
                                                .font(.caption)
                                                .foregroundStyle(AppTheme.secondaryText)
                                                .lineLimit(1)
                                        }
                                        Spacer()
                                    }
                                    .padding(10)
                                    .background(AppTheme.cardBackground)
                                    .clipShape(RoundedRectangle(cornerRadius: 14))
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }
                .padding()
                .padding(.bottom, 80)
            }
            .background(AppTheme.background)
            .navigationTitle("Inicio")
        }
    }
}