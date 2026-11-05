# Engines

Native media and multimodal engines used by the AI Pipeline. They are explicitly loaded runtime components, not optional plugins or a dynamically discovered extension registry.

The pipeline defaults to modern **v2 engines** via `ENGINE_VERSION="${ENGINE_VERSION:-.v2}"` in `core.sh`. Legacy v1 engines are retained for backward compatibility and offline fallback.

## Active Engines (v2)

| Engine | Version | Role | Key Features |
| --- | --- | --- | --- |
| [`image.v2.sh`](image.v2.sh) | 0.4.0 | Text-to-Image (t2i), Image-to-Image (i2i), and Image Editing | Multi-provider adapter, dynamic model resolution, automatic EXIF metadata stripping (`exiftool`), format conversion (`webp`/`png`/`jpeg`), and keyless Pollinations fallback. |
| [`video.v2.sh`](video.v2.sh) | 0.3.0 | Text-to-Video (t2v) and Image-to-Video (i2v) | Asynchronous polling loop, job resume without double-billing, validated MP4 header inspection via `ffprobe`, duration/fps/ratio constraints validation. |
| [`voice.v2.sh`](voice.v2.sh) | 0.3.0 | Text-to-Speech (TTS) | Multi-provider synthesis (ElevenLabs, OpenAI, Groq, Venice, local Piper), voice/gender resolution, persistent audio caching, non-blocking playback. |
| [`speech.v2.sh`](speech.v2.sh) | 0.3.0 | Speech-to-Text (STT) & Audio Transcription | Multi-provider transcription (local Whisper.cpp, Groq, OpenAI, Fal, Venice), audio format normalization, language hint injection, automatic temp cleanup. (Symlinked as `speech.sh`). |

## Legacy Engines (v1)

| File | Role |
| --- | --- |
| [`image.sh`](image.sh) | Legacy image generation engine. |
| [`video.sh`](video.sh) | Legacy video generation engine. |
| [`voice.sh`](voice.sh) | Legacy combined TTS & STT voice engine. |

## Architecture & Principles

- **Pure Bash & Modular** : Each engine can be sourced as a library by `core.sh` / `tools.sh` or executed as a standalone CLI tool.
- **Fail-Fast & Zero Duplication** : Paid generation jobs are never retried automatically to prevent duplicate billing.
- **Metadata Hygiene** : Generated artifacts have metadata stripped before exposure.
- **Universal Portability** : Compatible with GNU Bash 3.2+ through Bash 5.3+ (macOS, Linux, Termux).

## Standalone Command-Line Usage

From the repository root:

```bash
./engines/image.v2.sh --help
./engines/video.v2.sh --help
./engines/voice.v2.sh --help
./engines/speech.v2.sh --help
```
