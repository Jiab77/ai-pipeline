# Libraries

Reusable, source-only Bash libraries shared by the AI Pipeline. They provide primitives rather than standalone commands: native media components live in [`../engines/`](../engines/), while optional capabilities live in [`../plugins/`](../plugins/).

The libraries come in two families:

- **Portable standalone libs** — zero coupling with `core.sh` internals, safe to source from any Bash script (Base64, Base82, Nightmare, SHA-256, Timeout, Animate).
- **Pipeline core libs** — extracted from `core.sh` during the 2.0.0 refactor (2026-11-19). They are the modular anatomy of the pipeline: UI, device tag, key management, Tor, JarNet, media, memory, history, backend transport, and external app launching.

| File | Family | Role |
| --- | --- | --- |
| [`helpers.sh`](helpers.sh) | Core | Global helpers: `die`, case helpers (`to_lower`/`to_upper`), provider model helpers (`filter_provider_models`, `normalize_provider_models`, `normalize_numbers`, `render_models_table`), and the config-driven `engine_v2_*` capability API. |
| [`ui.sh`](ui.sh) | Core | Terminal UI: responsive width (`WINCH` trap), lines and headers (`draw_line`, `draw_header`, `draw_symmetric_header`), hyperlinks (`create_link`), banner, and Markdown rendering (`render_markdown`). |
| [`animate.sh`](animate.sh) | Portable | Emoji based animation library (see [Animation semantics](#animation-semantics)). |
| [`nightmare.sh`](nightmare.sh) | Portable | Hexadecimal + Base82 form obfuscation (see [Security](#security-and-data-handling)). |
| [`base64.sh`](base64.sh) | Portable | Base64 for GNU/BSD userlands (see [Public functions](#public-functions)). |
| [`base82.sh`](base82.sh) | Portable | Stream-first form obfuscation on top of Base64. |
| [`sha256.sh`](sha256.sh) | Portable | SHA-256 streaming, backend probed (see [Security](#security-and-data-handling)). |
| [`timeout.sh`](timeout.sh) | Portable | Bounded command execution (see [Timeout semantics](#timeout-semantics)). |
| [`tag.sh`](tag.sh) | Core | Experimental Anti-XPIA layer: per-session device tag and output redaction. |
| [`keychest.sh`](keychest.sh) | Core | Key chest management: master key handling, keyring, encrypted provider keys, interactive setup. |
| [`tor.sh`](tor.sh) | Core | Tor routing helpers: config loading, detection, detached startup, reachability checks, service lifecycle. |
| [`jarnet.sh`](jarnet.sh) | Core | JarNet P2P network helpers (`jarnet_start`). |
| [`media.sh`](media.sh) | Core | Media helpers: MIME detection (`get_mime_type`), type probes (`is_image_file`, `is_video_file`, `is_audio_file`), Base64 payload (`media_to_b64`), and `analyze_media`. |
| [`memory.sh`](memory.sh) | Core | LLM memory management: self-architecture generation, memory bootstrapping, index scanning, consolidation, and heartbeat triggering. |
| [`history.sh`](history.sh) | Core | LLM history management: normalization, healing of poisoned history files, and persistence. |
| [`backend.sh`](backend.sh) | Core | LLM transport layer: the complete `api_call` family — per-protocol handlers (`completions`, `responses`, `messages`), error/response handling, and tool result building. |
| [`apps.sh`](apps.sh) | Core | External managed apps launcher: exports provider credentials as app-specific environment variables, then `exec`s the app. |

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

Within the pipeline, required libraries are loaded through `load_libs()` in `core.sh`, driven by the `LIB_DEPS` array — the living contract of the pipeline:

```bash
LIB_DEPS=(              # Orders matter!
  "helpers"             # Global helpers
  "ui"                  # UI
  "animate"             # Animation
  "nightmare"           # Nightmare obfuscation
  "base64"              # Base64 encoding
  "sha256"              # SHA256 hashing
  "timeout"             # Timeout helper
  "tag"                 # Device tag
  "keychest"            # Key chest management
  "tor"                 # Tor routing helpers
  "jarnet"              # JarNet helpers
  "media"               # media helpers
  "memory"              # LLM memory management
  "history"             # LLM history management
  "backend"             # LLM backend management
  "statusbar"           # LLM / Tor traffic status bar
  "apps"                # External managed apps
)
```

> **Contract (2026-11-19):** `core.sh` is the single consumer of the core libs.
> While that holds, `LIB_DEPS` is the authoritative dependency and ordering
> documentation. The moment another component sources a core lib directly, that
> module must be given a real header contract (version, dependencies, globals
> consumed).

Library dependencies are resolved relative to the sourcing file, never relative to the caller's working directory. `AIDE_LIB_DIR` can override that location for sandboxed copies. All libraries must stay compatible with Bash 3.2 (macOS stock Bash) — `local`, herestrings, and `sed -E` are safe; avoid Bash 4+ features (`declare -A`, `${var,,}`, etc.).

## Public functions

Portable standalone libs:

| Library | String API | Stream API | Command API |
| --- | --- | --- | --- |
| Animate | — | — | `start_anim`, `stop_anim`, `is_anim_running` |
| Base64 | — | `b64e`, `b64d` | — |
| Base82 | `b82_encode`, `b82_decode` | `b82_enc_stream`, `b82_dec_stream` | — |
| Nightmare | `nm_encode`, `nm_decode` | `nm_enc_stream`, `nm_dec_stream` | — |
| Hexadecimal stage | — | `nm_hex_enc_stream`, `nm_hex_dec_stream` | — |
| SHA-256 | — | `_sha256sum` | — |
| Timeout | — | — | `_timeout` |

Pipeline core libs (selection of the most relevant entry points — read the module for the full list):

| Library | Key functions |
| --- | --- |
| Helpers | `die`, `to_lower`, `to_upper`, `filter_provider_models`, `normalize_provider_models`, `normalize_numbers`, `render_models_table`, `engine_v2_block_field`, `engine_v2_capable`, `engine_v2_http` |
| UI | `set_term_width`, `get_term_width`, `draw_line`, `draw_header`, `draw_symmetric_header`, `create_link`, `show_banner`, `render_markdown` |
| Tag | `compute_device_tag`, `set_auth_tag`, `strip_tag_from_display` |
| Keychest | `read_master_key`, `init_key_chest`, `migrate_key_chest`, `has_provider_key`, `encrypt_provider_key`, `decrypt_provider_key`, `load_provider_key`, `manage_keys` |
| Tor | `load_tor_config`, `detect_tor`, `wait_for_tor`, `check_tor`, `handle_tor`, `start_tor_detached`, `kill_tor_svc` |
| JarNet | `jarnet_start` |
| Media | `get_mime_type`, `is_image_file`, `is_video_file`, `is_audio_file`, `media_to_b64`, `analyze_media` |
| Memory | `generate_self_architecture`, `get_memory_structure`, `bootstrap_memory`, `index_dir`, `clear_memory`, `consolidate_memory`, `check_and_trigger_heartbeat` |
| History | `normalize_history`, `heal_history_file`, `persist_history` |
| Backend | `api_call` (+ `api_call_type_completions`, `api_call_type_responses`, `api_call_type_messages`), `handle_errors`, `handle_response`, `build_tool_result` |
| Apps | `launch_ext_app` |

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

## Core lib semantics

**Tag (`tag.sh`)** — `compute_device_tag` hashes `machine-id` (with fallback chain: `/etc/machine-id`, `/var/lib/dbus/machine-id`, `settings get secure android_id` on Termux) with the hostname and the current UNIX timestamp, producing a 16-hex-character tag that **changes every session**. `set_auth_tag` caches it in `AUTH_TAG`. `strip_tag_from_display` redacts any `[AUTH:<16-hex>]` tag echoed back by the LLM, substituting `[REDACTED]` (not deleting) so surrounding Markdown stays valid. The tag is an input-path-only authenticator; output redaction is defense in depth.

**Backend (`backend.sh`)** — the transport layer. `api_call` routes a JSON payload to the configured endpoint, honoring Tor routing and per-provider quirks; protocol-specific handlers (`api_call_type_completions`, `api_call_type_responses`, `api_call_type_messages`) build and send the requests; `handle_errors` and `handle_response` normalize what comes back, and `build_tool_result` formats tool outputs for the LLM. It is deliberately stateless with respect to provider selection — that decision lives in `core.sh` (`set_api_provider`, routing).

**Memory (`memory.sh`)** — `bootstrap_memory` prepares the memory tree; `consolidate_memory` and `check_and_trigger_heartbeat` drive the periodic self-consolidation cycle; `generate_self_architecture` produces the agent's self-knowledge document. Because it embeds line-number references to the pipeline source, keep this module in sync when code moves between files.

**Apps (`apps.sh`)** — `launch_ext_app <app> <path>` maps provider credentials to the environment variables of the target application (`aider`, `claude`, `copilot`, `crush`, `cyberneurova`, `hf`, `openai`) and executes it from the given directory.

## Security and data handling

**Base64, Base82, and Nightmare do not provide encryption.** Base64 is only an encoding; Base82 and Nightmare add form obfuscation, with no added entropy, no key-based confidentiality, and no integrity protection. Their output must never be described as encrypted or used as a substitute for authenticated encryption.

SHA-256 is an unkeyed cryptographic hash, not encryption or authentication. Use a MAC when authenticity is required.

Base82 corruption can be silent; the calling format must provide its own checksum or MAC when integrity matters.

Use the stream APIs for binary payloads or data containing NUL bytes: shell variables cannot hold NUL characters. The string APIs are intended for text convenience.

The implementations avoid platform-specific `base64 -w0` and `xxd` dependencies. Base64 decoding is selected by probing `--decode`, `-d`, then `-D`, and the result is cached per shell/process. The libraries are designed for Linux, macOS, and Termux.

**Keychest (`keychest.sh`)** stores provider API keys encrypted (keyring KDF + cipher probing) and protects them with a Nightmare-obfuscated master key; the encryption stage is real cryptography, unlike the obfuscation stage described above. The Anti-XPIA device tag (`tag.sh`) is a session-scoped authenticator for prompt provenance, not a secret: it is derived, not stored, and must never be relied upon as a credential.
