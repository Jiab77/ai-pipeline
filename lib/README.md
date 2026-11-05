# Libraries

Reusable, source-only Bash libraries shared by the AI Pipeline. They provide primitives rather than standalone commands: native media components live in [`../engines/`](../engines/), while optional capabilities live in [`../plugins/`](../plugins/).

| File | Role |
| --- | --- |
| [`animate.sh`](animate.sh) | Portable pure bash emoji based animation library. |
| [`base64.sh`](base64.sh) | Portable Base64 encoding and decoding for GNU and BSD userlands. Produces single-line encoded output and probes the supported decode flag instead of relying on OS names. |
| [`base82.sh`](base82.sh) | Stream-first form obfuscation using Base64 followed by ROT13 for letters and ROT5 for digits. Sources `base64.sh` and provides string and stream APIs. |
| [`nightmare.sh`](nightmare.sh) | Adds a hexadecimal stage around Base82: hexadecimal encoding first, then Base82. Sources `base82.sh`, and therefore `base64.sh`, automatically. |
| [`sha256.sh`](sha256.sh) | Portable SHA-256 streaming through `sha256sum`, `shasum`, or OpenSSL. Probes each available backend and emits one normalized 64-character hexadecimal line. |
| [`timeout.sh`](timeout.sh) | Portable bounded command execution through GNU `timeout` or a Bash process-group watchdog. Preserves command status and uses 124 for deadline expiration. |

## Loading

These files must be **sourced, never executed**. All libraries use idempotent guards and define functions without producing output or changing the caller's shell options.

```bash
# Load only the portable Base64 primitives
source lib/base64.sh

# Load Base82 and its Base64 dependency
source lib/base82.sh

# Or load Nightmare, Base82, and Base64 together
source lib/nightmare.sh

# Independent animation, SHA-256, and bounded-execution primitives
source lib/animate.sh
source lib/sha256.sh
source lib/timeout.sh
```

Within the pipeline, required libraries are loaded through `load_libs()` in `core.sh`. Library dependencies are resolved relative to the sourcing file, never relative to the caller's working directory. `AIDE_LIB_DIR` can override that location for sandboxed copies.

## Public functions
| Library | String API | Stream API | Command API |
| --- | --- | --- | --- |
| Animate | — | — | `start_anim`, `stop_anim`, `is_anim_running` |
| Base64 | — | `b64e`, `b64d` | — |
| Base82 | `b82_encode`, `b82_decode` | `b82_enc_stream`, `b82_dec_stream` | — |
| Nightmare | `nm_encode`, `nm_decode` | `nm_enc_stream`, `nm_dec_stream` | — |
| Hexadecimal stage | — | `nm_hex_enc_stream`, `nm_hex_dec_stream` | — |
| SHA-256 | — | `_sha256sum` | — |
| Timeout | — | — | `_timeout` |

Example from the repository root:

```bash
source lib/nightmare.sh

encoded=$(nm_encode "hello")
decoded=$(nm_decode "$encoded")
printf '%s\n' "$decoded"
```

## Animation semantics

`start_anim [anim_type] [text_prefix] [delay]` starts a background animation loop in an asynchronous subshell. It hides the cursor (`\033[?25l`) and redraws each frame cleanly using carriage returns and line-clearing sequences (`\r\033[K`), eliminating display drift across variable-width Unicode and emoji characters.

- `anim_type`: Selected frame sequence (`earth`, `moon`, `clock`, `diamond`, `square`, `circle`, `heart`, `monkeys`, `arrows`, `digits`, `fingers`, `smiley`, `slashes`, `dots`). Default is `earth`.
- `text_prefix`: Optional label displayed before the animated frame (e.g. `Thinking...`).
- `delay`: Frame delay in seconds. Default is `0.1`.

`stop_anim` terminates the background animation subshell (`ANIM_PID`), waits for its cleanup, clears the active line, and restores the terminal cursor (`\033[?25h`). If `start_anim` is called while an animation is already running, it automatically calls `stop_anim` first to prevent orphan background processes.

`is_anim_running` returns `0` if an animation subshell is currently active, and `1` otherwise.

## Timeout semantics

`_timeout <seconds> <command> [args...]` forwards arguments and standard streams, returns the command's status, and reports deadline expiration as 124. It uses GNU `timeout` when available; otherwise it starts a Bash watchdog in an isolated subshell.
The fallback kills the command's whole process group with SIGKILL, rather than GNU's default SIGTERM, and removes its watchdog and temporary marker on exit. Deliberately detached descendants can escape: this is a runtime bound, not a security sandbox.

The fallback requires `mktemp`, `sleep`, and `rm`, checked when the library is sourced. Its marker is created under `${TMPDIR:-/tmp}`; no GNU `timeout` installation is required.

## Security and data handling

**Base64, Base82, and Nightmare do not provide encryption.** Base64 is only an encoding; Base82 and Nightmare add form obfuscation, with no added entropy, no key-based confidentiality, and no integrity protection. Their output must never be described as encrypted or used as a substitute for authenticated encryption.

SHA-256 is an unkeyed cryptographic hash, not encryption or authentication. Use a MAC when authenticity is required.

Base82 corruption can be silent; the calling format must provide its own checksum or MAC when integrity matters.

Use the stream APIs for binary payloads or data containing NUL bytes: shell variables cannot hold NUL characters. The string APIs are intended for text convenience.

The implementations avoid platform-specific `base64 -w0` and `xxd` dependencies. Base64 decoding is selected by probing `--decode`, `-d`, then `-D`, and the result is cached per shell/process. The libraries are designed for Linux, macOS, and Termux.
