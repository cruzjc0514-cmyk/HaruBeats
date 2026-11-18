import SwiftUI

struct EqualizerSheetView: View {
    @EnvironmentObject var audioManager: AudioPlayerManager
    @AppStorage("hb_accent_color") private var accentRaw = AccentOption.indigo.rawValue
    @Environment(\.dismiss) private var dismiss

    private let labels = ["60 Hz", "230 Hz", "910 Hz", "3.6 kHz", "14 kHz"]

    private var accentColor: Color {
        (AccentOption(rawValue: accentRaw) ?? .indigo).color
    }

    var body: some View {
        VStack(spacing: 20) {
            // Encabezado propio con margen cómodo para evitar cualquier solapamiento
            HStack {
                Text("Ecualizador")
                    .font(.title3.bold())
                    .foregroundStyle(.white)
                Spacer()
                Button("Listo") {
                    dismiss()
                }
                .font(.body.weight(.semibold))
                .foregroundStyle(accentColor)
            }
            .padding(.top, 22)

            // Interruptor principal
            Toggle(isOn: $audioManager.isEQEnabled) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Ecualizador activo")
                        .font(.headline)
                        .foregroundStyle(.white)
                    Text("Ajuste en tiempo real de 5 bandas")
                        .font(.caption)
                        .foregroundStyle(AppTheme.secondaryText)
                }
            }
            .tint(accentColor)
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
                                .background(audioManager.selectedPreset == preset ? accentColor : AppTheme.cardBackground)
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
                        .tint(accentColor)
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
        .padding(.horizontal, 20)
        .background(AppTheme.background.ignoresSafeArea())
        .presentationDetents([.large])
    }
}