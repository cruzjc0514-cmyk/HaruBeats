import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var audioManager: AudioPlayerManager

    var body: some View {
        NavigationStack {
            List {
                Section("Colección") {
                    HStack {
                        Text("Canciones almacenadas")
                        Spacer()
                        Text("\(audioManager.library.count)")
                            .foregroundStyle(AppTheme.secondaryText)
                    }
                    .listRowBackground(AppTheme.cardBackground)
                }

                Section("Próximas funciones") {
                    Text("Transferencia Wi-Fi desde PC")
                        .foregroundStyle(AppTheme.secondaryText)
                        .listRowBackground(AppTheme.cardBackground)
                    Text("Letras sincronizadas .lrc")
                        .foregroundStyle(AppTheme.secondaryText)
                        .listRowBackground(AppTheme.cardBackground)
                }
            }
            .scrollContentBackground(.hidden)
            .background(AppTheme.background)
            .navigationTitle("Ajustes")
        }
    }
}