# Transcript Tools

A native macOS app for local speech-to-text transcription. Import or record audio and video, transcribe on-device with Whisper, and export transcripts in multiple formats.

All processing runs locally on your Mac. No cloud APIs, no account required.

## Features

- **Local transcription** with [WhisperKit](https://github.com/argmaxinc/WhisperKit) (OpenAI Whisper models)
- **Import** common audio and video formats (MP3, WAV, M4A, MP4, MOV, MKV, and more)
- **Record** from the microphone or system audio
- **Library** of recordings with built-in media player
- **Export** as Markdown, plain text, SRT, or WebVTT
- **Optional timestamps** and automatic save to a chosen folder

## Requirements

- macOS 15 or later (macOS 26 recommended for latest UI)
- Apple Silicon Mac recommended for faster transcription
- Microphone permission (for recording)
- Screen recording permission (for system audio capture)

## Getting started

### Build from source

1. Clone the repository:

2. Open the project in Xcode:

   ```bash
   open "Transcript Tools.xcodeproj"
   ```

3. Select the **Transcript Tools** scheme and run (⌘R).

Xcode will resolve the WhisperKit Swift package automatically on first build.

### First run

1. On first launch, choose a Whisper model size and download it (models are cached locally).
2. Import files or record audio from the toolbar.
3. Press **Transcribir** to process pending items.
4. Transcripts are saved to `~/Documents/Transcripciones` by default (configurable in Settings).

## Model sizes

| Model     | Speed   | Quality | RAM (approx.) |
|-----------|---------|---------|---------------|
| `tiny`    | Fastest | Basic   | ~1 GB         |
| `base`    | Fast    | Good    | ~1 GB         |
| `small`   | Medium  | Better  | ~2 GB         |
| `medium`  | Slower  | High    | ~5 GB         |
| `large-v2` / `large-v3` | Slowest | Best | ~10 GB |

## Project structure

```
Transcript Tools/
├── Transcript Tools.xcodeproj
├── Transcript Tools/
│   ├── AppController.swift      # App state and transcription queue
│   ├── TranscriptionEngine.swift # WhisperKit integration
│   ├── AudioExtractor.swift     # Audio extraction from media files
│   ├── RecordingAudioService.swift # Microphone and system audio capture
│   └── …                        # SwiftUI views and UI components
├── LICENSE
└── README.md
```

## Data storage

- **Recordings library:** `~/Library/Application Support/Transcript Tools/`
- **Default exports:** `~/Documents/Transcripciones/`
- **Whisper models:** managed by WhisperKit (Application Support)

## Contributing

Contributions are welcome. Please open an issue or pull request with a clear description of the change.

## License

This project is licensed under the MIT License. See [LICENSE](LICENSE) for details.

## Acknowledgements

- [WhisperKit](https://github.com/argmaxinc/WhisperKit) — on-device Whisper inference for Apple Silicon
- [OpenAI Whisper](https://github.com/openai/whisper) — speech recognition model
