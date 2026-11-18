import SwiftUI

struct EqualizerSheetView: View {
    @EnvironmentObject var audioManager: AudioPlayerManager
    @Environment(\.dismiss) private var dismiss

    private let labels = ["60 Hz", "230 Hz", "910 Hz", "3.6 kHz", "14 kHz"]

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                // Interruptor principal
                Toggle(isOn: $audioManager.isEQEnabled) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Ecualizador activo")
                            .font(.headline)
                        Text("Ajuste en tiempo real de 5 bandas")
                            .font(.caption)
                            .foregroundStyle(AppTheme.secondaryText)
                    }
                }
                .tint(.indigo)
                .padding()
                .background(AppTheme.cardBackground)
                .clipShape(RoundedRectangle(cornerRadius: 16))

                // Selector de Presets
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        ForEach(EqualizerPreset.allCases) { preset in
                            Button {
                                audioManager.applyPreset(preset)
                            } label: {
                                Text(preset.rawValue)
                                    .font(.subheadline.weight(.semibold))
                                    .padding(.horizontal, 16)
                                    .padding(.vertical, 9)
                                    .background(audioManager.selectedPreset == preset ? Color.indigo : AppTheme.cardBackground)
                                    .foregroundStyle(.white)
                                    .clipShape(Capsule())
                            }
                        }
                    }
                }

                // Deslizadores de 5 bandas (-12 dB a +12 dB)
                VStack(spacing: 18) {
                    ForEach(0..<5, id: \.self) { index in
                        HStack(spacing: 14) {
                            Text(labels[index])
                                .font(.caption.monospacedDigit())
                                .foregroundStyle(AppTheme.secondaryText)
                                .frame(width: 56, alignment: .leading)

                            Slider(
                                value: Binding(
                                    get: { audioManager.bandGains[index] },
                                    set: { audioManager.updateBand(index: index, gain: $0) }
                                ),
                                in: -12...12,
                                step: 0.5
                            )
                            .tint(.indigo)
                            .disabled(!audioManager.isEQEnabled)

                            Text(String(format: "%+.1f dB", audioManager.bandGains[index]))
                                .font(.caption.monospacedDigit())
                                .foregroundStyle(.white)
                                .frame(width: 62, alignment: .trailing)
                        }
                    }
                }
                .padding()
                .background(AppTheme.cardBackground)
                .clipShape(RoundedRectangle(cornerRadius: 18))
                .opacity(audioManager.isEQEnabled ? 1.0 : 0.5)

                Spacer()
            }
            .padding()
            .background(AppTheme.background)
            .navigationTitle("Ecualizador")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Listo") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}