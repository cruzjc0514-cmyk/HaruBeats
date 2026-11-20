# 🎵 HaruBeats

Reproductor de música local **Hi-Res** para iOS construido de forma nativa en **SwiftUI** y **AVAudioEngine**, diseñado para disfrutar bibliotecas musicales sin pérdidas con reproducción continua (*Gapless*), ecualización avanzada y letras sincronizadas.

---

## ✨ Características principales

- **Audio Hi-Res y Multi-formato:** Reproducción nativa de `FLAC`, `ALAC`, `WAV`, `MP3`, `M4A` y `AAC` con lectura de metadatos, frecuencia de muestreo, profundidad de bits y carátulas incrustadas.
- **Reproducción Gapless y Crossfade:** Transición continua sin cortes entre pistas consecutivas del mismo formato (`sampleRate` y canales) y *crossfade* configurable.
- **Ecualizador de 5 Bandas y ReplayGain:** Presets integrados, ajuste personalizado de bandas (60 Hz – 14 kHz) y normalización de volumen segura con límite de pico para evitar *clipping*.
- **Letras Sincronizadas (.LRC):** Soporte para archivos `.lrc` externos, letras incrustadas en la pista, ajuste de desfase en tiempo real y escala de fuente personalizable.
- **Organización Inteligente:** Biblioteca organizada por canciones, álbumes, playlists personalizadas, favoritos y cola de reproducción editable, con almacenamiento por carpeta `Artista - Álbum`.
- **Importación Flexible:**
  - Selector de archivos y carpetas completas desde la app **Archivos** de iOS.
  - Importación de listas de reproducción `.m3u` y `.m3u8`.
  - **Transferencia Wi-Fi** integrada desde navegador web (PC/Mac) y escaneo de archivos compartidos por USB.
- **Integración Nativa con iOS:** Controles en pantalla de bloqueo y Centro de Control, temporizador de apagado (*Sleep Timer*), colores dinámicos extraídos de la carátula y restauración automática de sesión.

---

## 📱 Requisitos

- **iOS 17.0** o superior.
- Para compilar desde el código fuente: **Xcode 16+** y **Swift 5**.

---

## 📥 Instalación (IPA)

1. Ve a la sección [**Releases**](../../releases/latest) de este repositorio y descarga el archivo `HaruBeats.ipa` de la última versión.
2. Instálalo en tu iPhone o iPad utilizando tu herramienta de *sideloading* favorita (como **SideStore**, **AltStore**, **Sideloadly** o **TrollStore**).

---

## 🛠️ Compilación desde el código fuente

```bash
git clone [https://github.com/cruzjc0514-cmyk/HaruBeats.git](https://github.com/TU_USUARIO/HaruBeats.git)
cd HaruBeats
open HaruBeats.xcodeproj
```

Selecciona tu dispositivo o simulador en Xcode y presiona `Cmd + R` para compilar y ejecutar.

---

## 📂 Estructura del proyecto

```text
HaruBeats/
├── App/                # Punto de entrada de la aplicación
├── Core/
│   ├── AudioEngine/    # Motor AVAudioEngine, Gapless, EQ y ReplayGain
│   ├── LibraryManager/ # Caché persistente de metadatos y carátulas
│   ├── Lyrics/         # Parser de archivos .LRC
│   ├── Metadata/       # Parser nativo de metadatos FLAC
│   ├── Playlist/       # Gestión de playlists, favoritos y parser M3U/M3U8
│   └── TransferManager/# Servidor HTTP local para transferencia Wi-Fi
├── Design/             # Tema visual, colores dinámicos y visualizador de audio
├── Features/           # Vistas SwiftUI (Inicio, Biblioteca, Álbumes, Playlists, Reproductor, Ajustes)
└── Models/             # Modelos de datos (Song, Playlist)
```
