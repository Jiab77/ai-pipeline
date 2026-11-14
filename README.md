<div align="center">

# 🚀 A.I.D.E CLI — AI Driven Environment <!-- omit in toc -->

### Sovereign Bash-First Cognitive Runtime <!-- omit in toc -->

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)
[![Bash Shell](https://img.shields.io/badge/Shell-Bash-4EAA25.svg?logo=gnu-bash&logoColor=white)](https://www.gnu.org/software/bash/)
[![Backend Supported](https://img.shields.io/badge/Backends-Ollama%20%7C%20llama.cpp%20%7C%2017%20external%20providers-orange.svg)]()
[![Status](https://img.shields.io/badge/Status-Stable--v1.9.4-blue.svg)]()

</div>

> A sovereign, local-first, Bash-driven cognitive runtime for orchestrating local and cloud LLMs with real tool execution, multimodal perception, privacy-aware transport, and autonomous persistent memory, and the only **capability-driven inter-provider vision fallback** implemented in Bash. Runs fully local (Ollama / llama.cpp) or connects to 17 cloud providers — your choice. No Python. No Node. No Docker. Just `curl`, `jq`, `htmlq`, `grep`, `sed`, `awk`, `websocat`, `socat`, `ffmpeg`, `cut`, `tr`, `printf`, and a brain on fire 😝
>
> This project is not just another LLM wrapper. It is a lightweight but deeply capable agent runtime built around a practical equilibrium between **Bash** (orchestration, live browser automation), and **PHP** (local web UX) — proving that modern agentic systems do not have to be trapped inside the usual Python-heavy stack.

---

## 📖 Table of content <!-- omit in toc -->

- [🏛️ Architecture](#️-architecture)
- [⚡ Why This Exists](#-why-this-exists)
- [🔄 Inter-Provider Vision Fallback](#-inter-provider-vision-fallback)
  - [Flow A — Manual Image (`/load`)](#flow-a--manual-image-load)
  - [Flow B — Tool-Generated Image](#flow-b--tool-generated-image)
- [🔗 JarNet — Decentralized P2P Agent Network \& Autonomous Mode](#-jarnet--decentralized-p2p-agent-network--autonomous-mode)
  - [Key Capabilities](#key-capabilities)
- [🚀 Quick Start](#-quick-start)
  - [⚡ Method A — One-liner (fast)](#-method-a--one-liner-fast)
    - [1. Install dependencies (required for both methods)](#1-install-dependencies-required-for-both-methods)
      - [Automatic](#automatic)
      - [Windows](#windows)
      - [Debian/Ubuntu](#debianubuntu)
      - [macOS](#macos)
      - [Arch Linux](#arch-linux)
      - [Termux](#termux)
      - [Update your binary path](#update-your-binary-path)
    - [2. Install the pipeline (clone + global 'aide' command)](#2-install-the-pipeline-clone--global-aide-command)
    - [3. Launch](#3-launch)
  - [🔐 Method B — Manual (paranoid-friendly 😄)](#-method-b--manual-paranoid-friendly-)
    - [1. Install dependencies](#1-install-dependencies)
    - [2. Clone the repo](#2-clone-the-repo)
    - [3. Launch](#3-launch-1)
  - [Set up your cloud providers keys](#set-up-your-cloud-providers-keys)
- [🧩 Extended Integration](#-extended-integration)
  - [Windows](#windows-1)
    - [Create VM/App shortcut](#create-vmapp-shortcut)
    - [Create data folder shortcut](#create-data-folder-shortcut)
  - [Ubuntu](#ubuntu)
  - [macOS](#macos-1)
  - [Termux](#termux-1)
  - [File Sharing](#file-sharing)
- [⚙️ Extended Configuration](#️-extended-configuration)
  - [Example: Change AI name](#example-change-ai-name)
  - [Example: Bigger models for 32 GB RAM](#example-bigger-models-for-32-gb-ram)
  - [What you can override](#what-you-can-override)
- [🧠 Dynamic System Prompt](#-dynamic-system-prompt)
  - [Folder semantics](#folder-semantics)
- [💬 Slash Commands](#-slash-commands)
  - [⌨️ Keyboard Shortcuts](#️-keyboard-shortcuts)
- [🛡️ OPSEC \& Security](#️-opsec--security)
- [ℹ️ More details about the project](#ℹ️-more-details-about-the-project)
- [👥 Credits](#-credits)
- [⚖️ License \& Roadmap](#️-license--roadmap)
- [⭐ Star History](#-star-history)

---

## 🏛️ Architecture

```
                      ┌─────────────────────────────────────────┐
                      │             Static Registries           │
                      │  (config/models.json, providers.json)   │
                      └────────────────────┬────────────────────┘
                                           │
                                           ▼
                      ┌─────────────────────────────────────────┐
                      │                 core.sh                 │
                      │       (Sovereign Cognitive Core)        │
                      └────────────────────┬────────────────────┘
                                           │
                    ┌──────────────────────┴──────────────────────┐
                    ▼                                             ▼
          ┌────────────────────┐                        ┌──────────────────┐
          │       cli.sh       │                        │  web/server.php  │
          │ (Interactive CLI)  │                        │  (A.I.D.E. Web)  │
          ├────────────────────┤                        ├──────────────────┤
          │ - Sourcing library │                        │ - SSE Streaming  │
          │ - Input loop       │                        │ - Telemetry HUD  │
          │ - Slash commands   │                        │ - Live Markdown  │
          │ - ANSI & Spinner   │                        │ - Custom Scratch │
          └────────────────────┘                        └──────────────────┘
```

**`core.sh`** is the agnostic engine — three backends (Ollama, llama.cpp, 17 cloud providers), ChaCha20-encrypted key chest, Tor routing, Markdown memory, and the agentic tool loop. **`cli.sh`** is the terminal client. **`tools.sh`** bridges model-declared capabilities to real host actions. One engine, multiple interfaces — local or cloud, your choice.

## ⚡ Why This Exists

- **Bash-first by conviction, not nostalgia**: 6036 lines of Bash doing things that usually "require" Python, NodeJS, Rust or even Go, including a stateless CDP browser engine and a multi-agent pipeline (Architect → Coder → Judge).
- **Local-first, cloud-capable**: Runs fully offline with Ollama/llama.cpp, or connects to 17 cloud providers. Same code, same tools, three backends.
- **Capability-driven fallback**: When a text-only model needs vision, the pipeline auto-switches provider mid-loop — same code, different backend. Nobody else has this in Bash.
- **Privacy is a feature, not an afterthought**: Tor routing, ChaCha20-encrypted API keys, Zero Data Retention injection, local backends — all first-class.

## 🔄 Inter-Provider Vision Fallback

When the pipeline is configured to run on text-only models and an image appears, it auto-switches to a vision-capable provider, processes the image, then switches back. Two triggers, one mechanism:

### Flow A — Manual Image (`/load`)

```
User: "/load photo.png" → sends message
  │
  └─ send_message()
       ├─ IS_MEDIA == true → handle_vision_request()
       │   └─ change_provider("zai") → glm-5.3-flash
       ├─ active_model = "glm-5.3-flash"
       └─ run_inference_loop() → 1 api_call → DONE
            restore_temp_state() → back to text-only provider
```

### Flow B — Tool-Generated Image

```
ITERATION 1: api_call() → DEEPSEEK (text-only)
  → tool_calls → web_browse generates screenshot.png
  → handle_vision_request() → set_temp_state() → change_provider("zai")
  → continue (no break)

ITERATION 2: api_call() → Z.AI (glm-5.3-flash)    ← SAME LINE OF CODE
  → "sees" the screenshot, describes it
  → no tool_calls → break

restore_temp_state() → DEEPSEEK    ← like nothing happened
```

**What makes this unique**: Every other fallback system triggers on *errors*. This one triggers on *missing capability*. Filesystem-based state persistence means a crash mid-fallback doesn't corrupt anything.

<details>
<summary><b>📐 Full Architecture Diagram & Flow Comparison</b></summary>

```
                        ┌───────────────────────────┐
                        │       cli.sh / CLI        │
                        │  parse_cli_args()         │
                        │  --provider, --fallback.. │
                        └────────────┬──────────────┘
                                     │
                        ┌────────────▼─────────────┐
                        │       init_core()        │
                        │  • set_auth_tag()        │
                        │  • set_api_provider()    │
                        │  • change_provider()     │
                        │  • set_vision_model()    │
                        └────────────┬─────────────┘
                                     │
              ┌──────────────────────┼──────────────────────┐
              │                      │                      │
     ┌────────▼────────┐    ┌────────▼────────┐   ┌─────────▼─────────┐
     │  send_message() │    │ run_one_shot()  │   │ heartbeat/consol. │
     │  (chat mode)    │    │ (pipeline mode) │   │ (memory)          │
     └────────┬────────┘    └────────┬────────┘   └─────────┬─────────┘
              │                      │                      │
              └──────────────────────┼──────────────────────┘
                                     │
                        ┌────────────▼─────────────┐
                        │  run_inference_loop()    │
                        │  ┌─────────────────────┐ │
                        │  │  while true:        │ │
                        │  │                     │ │
                        │  │  api_call() ────────┼─┼──► DEEPSEEK (chat)
                        │  │    │                │ │      │
                        │  │    ▼                │ │      │ tool_calls?
                        │  │  tool_calls? ──YES──┼─┼──► execute_tools()
                        │  │    │                │ │      │
                        │  │   NO                │ │      │ image detected?
                        │  │    │                │ │      │
                        │  │    ▼                │ │      ▼
                        │  │  break (final)      │ │  handle_vision_request()
                        │  │                     │ │      │
                        │  │    ▲                │ │      ▼
                        │  │    │                │ │  set_temp_state()
                        │  │    │                │ │  change_provider("zai")
                        │  │    │                │ │      │
                        │  │    └── loop ────────┼─┼──► Z.AI glm-5.3-flash
                        │  │                     │ │      │
                        │  └─────────────────────┘ │      │ describes image
                        │                          │      │
                        │  restore_temp_state() ◄──┼──────┘
                        └──────────────────────────┘
                                     │
                                     ▼
                              ┌─────────────┐
                              │  STDOUT /   │
                              │  history    │
                              └─────────────┘
```

### Flow Comparison <!-- omit in toc -->

| Aspect | Flow A — `/load` (manual) | Flow B — Tool-Generated |
|--------|--------------------------|------------------------|
| **Trigger** | `IS_MEDIA=true` in `send_message` | Image detected in `run_inference_loop` |
| **Switch timing** | Before the loop starts | Mid-loop, between iterations |
| **api_call count** | 1 (direct to vision model) | 2 (text → vision) |
| **Provider during iter 1** | Vision provider directly | Text-only provider (decides tool) |
| **Provider during iter 2** | N/A (already done) | Vision provider (describes image) |
| **Restore** | After `run_inference_loop` returns | At end of `run_inference_loop` |

### Activation Steps <!-- omit in toc -->

* From start:

  ```console
  ./cli.sh provider deepseek fallback zai
  # From now on, any image → auto-switch → auto-restore.
  ```

* From live session:

  ```bash
  # One command to enable:
  /fallback zai
  # From now on, any image → auto-switch → auto-restore.
  ```

* To see if fallback is active from live session:

  ```bash
  # One command to check the status:
  /fallback
  # Show current fallback status.
  ```

* To remove from live session:

  ```bash
  # One command to disable:
  /fallback off
  # From now on, any image → no auto-switch.
  ```
</details>

## 🔗 JarNet — Decentralized P2P Agent Network & Autonomous Mode

A.I.D.E integrates **JarNet** (`plugins/jarnet.sh`), a zero-dependency, peer-to-peer Agent-to-Agent communication protocol operating natively over Tor v3 hidden services. Autonomous AI agent nodes exchange authenticated direct messages across `.onion` addresses without any central server, rendezvous point, or public IP exposure.

### Key Capabilities

- **Zero-IP Leakage & Sovereign Onion Identity**: Every node automatically hosts its own deterministic v3 hidden service (`<callsign>|<onion>.onion`).
- **Autonomous Watch Mode (`auto` / `/mode auto`)**: The agent continuously monitors its JarNet inbox, parses peer message envelopes, and generates context-aware replies via its cognitive core.
- **Anti-Loop Defense & Anti-XPIA Guard**: Automated responses are tagged with `[AUTO]`, preventing endless ping-pong loops between bots. All incoming peer messages are strictly wrapped as untrusted external content (`jarnet:inbox`) at the tool dispatcher boundary, neutralizing prompt-injection vectors.
- **Self-Healing Transport Stack**: Dedicated node lifecycle tools (`jarnet_status`, `jarnet_up`, `jarnet_down`) allow the agent to inspect, restart, and self-heal its local background listener and Tor controller session autonomously.
- **Non-Blocking Human Interception**: Pressing `[Enter]` or `[c]` in the terminal instantly returns control to interactive Chat Mode. Pressing `[q]` exits cleanly.

```bash
# Start directly in Autonomous Agent-to-Agent mode:
./cli.sh auto

# Or toggle dynamically from interactive chat:
/mode auto

# Control JarNet transport stack inside interactive chat:
/jarnet who
/jarnet status

# Start chat mode without the JarNet background service:
./cli.sh --no-jarnet
```

## 🚀 Quick Start

### ⚡ Method A — One-liner (fast)

#### 1. Install dependencies (required for both methods)

##### Automatic

You can run the **[install.sh](install.sh)** script. It automatically detects your platform (Debian/Ubuntu, Arch, macOS, Termux), verifies system dependencies, and installs prebuilt static binaries (`htmlq`, `websocat`, `curl-impersonate`) into `~/.local/bin` in seconds without requiring Rust or Cargo toolchains.

```bash
./install.sh
```

##### Windows

```bash
# Windows 10 v2004+ / build 19041+, or Windows 11

# A. Install WSL2 base stack by running Powershell as admin then type:
wsl --install

# Then reboot.

# B. Install Ubuntu base image (may not be installed by default)

# Run Powershell as admin once again then type:
wsl --install Ubuntu

# C. To see other available image, just type:
wsl --list --online
# Then start Ubuntu and follow the Ubuntu instructions below
```

##### Debian/Ubuntu

```bash
sudo apt update && sudo apt install -y git curl jq sed tor glow figlet openssl socat ffmpeg libimage-exiftool-perl file alsa-utils
```

##### macOS

Install [**brew**](https://brew.sh) if not done already, then install all dependencies directly via official formula bottles:

```bash
brew install git curl jq glow tor htmlq openssl websocat figlet socat ffmpeg exiftool file
```

##### Arch Linux

```bash
paru -Syu git curl jq sed tor glow figlet openssl websocat htmlq socat ffmpeg perl-image-exiftool file alsa-utils
```

##### Termux

```bash
pkg install git curl jq sed figlet openssl openssl-tool android-tools tor socat ffmpeg exiftool file termux-api websocat
```

##### Update your binary path

Make sure `~/.local/bin` is present in your `PATH`:

```bash
# Update current session path
export PATH=$PATH:$HOME/.local/bin

# Make the binary path permanent
echo 'export PATH=$PATH:$HOME/.local/bin' >> ~/.bashrc
```
#### 2. Install the pipeline (clone + global 'aide' command)

```bash
curl -fsSL https://raw.githubusercontent.com/jiab77/ai-pipeline/main/install.sh | bash
```

#### 3. Launch

```bash
aide help
```

> [!TIP]
> All flags can be replaced by their command equivalent for those who don't like typing `--` each time 😜

The installer clones the repo and creates a global `aide` command. To update later:

```bash
cd ai-pipeline && ./install.sh -u

# or if you don't want to use the script
cd ai-pipeline && git pull
```

### 🔐 Method B — Manual (paranoid-friendly 😄)

For those who rightfully don't trust `curl | bash` — every step is transparent.

#### 1. Install dependencies

Same as Method A, see above.

#### 2. Clone the repo

```bash
git clone --recursive https://github.com/jiab77/ai-pipeline.git && cd ai-pipeline
```

#### 3. Launch

```bash
# As server
./cli.sh --server ollama         # Start 'ollama' server
./cli.sh --server llamacpp       # Start 'llama.cpp' server
./cli.sh --server web            # Start PHP 'web' server

# As client
./cli.sh                          # Chat mode (starts JarNet and Tor by default)
./cli.sh --no-jarnet              # Chat mode without JarNet background service
./cli.sh --no-tor                 # Chat mode without using Tor
./cli.sh --backend ollama         # Run fully offline
./cli.sh --provider deepseek      # Pick your cloud provider
./cli.sh --fallback zai           # Enable vision fallback
./cli.sh --zdr                    # With Zero Data Retention
./cli.sh --memory index           # Load a memory index instead of full contents

# Or with command args
./cli.sh server ollama                    # Start local 'ollama' server
./cli.sh backend ollama                   # Run fully offline
./cli.sh provider deepseek                # Pick 'deepseek' as cloud provider
./cli.sh provider deepseek fallback zai   # Pick 'deepseek' as cloud provider and set vision fallback to 'zai' provider
```

> [!TIP]
> All flags can be replaced by their command equivalent for those who don't like typing `--` each time 😜

### Set up your cloud providers keys

```bash
# From live chat session
/keys

# From start
./cli.sh keys

# Migrate keyring to new format (Nightmare stream obfuscation)
./cli.sh migrate --apply
```

> **Keys are encrypted locally with ChaCha20 + PBKDF2. Never written to disk in cleartext.**

## 🧩 Extended Integration

### Windows

> [!NOTE]
> The methods described below are experimental and may not work for you.

#### Create VM/App shortcut

1. Find the created **Ubuntu** shortcut
2. Then right click on it and select **Properties**
3. Select the whole path and hit `[Ctrl + C]`
4. Go back to your desktop
5. Then right click on your desktop and select **New Shortcut**
6. Enter the path with `[Ctrl + V]` then click **Next**
7. Define the shortcut name then click **Ok**

> [!TIP]
> The path should look like this: `"C:\Program Files\WSL\wsl.exe" --distribution-id {ff7394ca-f8a8-48c9-9fad-3d0aaf323c3f} --cd ~`

#### Create data folder shortcut

1. Open the **Explorer** app
2. Find the **Linux** path on the left side
3. Navigate to your created **home** folder
4. Find the **ai-pipeline** folder and navigate inside
5. Find the **data** folder
6. Then right click on it and select **Properties**
7. Select the whole path and hit `[Ctrl + C]`
8. Go back to your desktop
9. Then right click on your desktop and select **New Shortcut**
10. Enter the path with `[Ctrl + V]` then click **Next**
11. Define the shortcut name then click **Ok**

> [!TIP]
> The path should look like this: `\\wsl.localhost\Ubuntu\home\<username>\ai-pipeline\data`

### Ubuntu

To automatically start **aide** at boot, simply do the following:

```bash
echo -e "\n# Start 'aide' at boot\naide\n" >> ~/.bashrc
```

### macOS

> [!NOTE]
> Will be added soon 😉

### Termux

To automatically start **aide** at boot, simply do the following:

```bash
echo -e "\n# Start 'aide' at boot\naide\n" >> ~/.bashrc
```

If you want an application icon on your homescreen, install the **Termux:Widget** application then do the following:

```bash
# Create the '.shortcuts' folder
mkdir -pv ~/.shortcuts

# Create the app shortcut
echo -e "\n#!/data/data/com.termux/files/usr/bin/bash\nbash \"\$HOME\"/.local/bin/aide" > ~/.shortcuts/aide
```

> [!NOTE]
> You can change the application shortcut name for whatever you want other than `aide`.

Then do the following:

1. Go back to your homescreen,
2. Tap and hold and select **Widgets**,
3. Then **Termux:Widget**,
4. Then type **1x1**,
5. Then select your created shortcut from the list.

### File Sharing

To share files between mobile and desktop devices, you can use the **LocalSend** application on both device types.

## ⚙️ Extended Configuration

The pipeline auto-detects `config/cli.conf` (or `config/core.conf` if running `core.sh` directly) and sources it at startup. This lets you override defaults without touching the core code — perfect for tailoring local models to your hardware.

### Example: Change AI name

```bash
# config/cli.conf — override defaults
AI_NAME="Lex Luthor"    # Or whatever else you want :P
```

### Example: Bigger models for 32 GB RAM

```bash
# config/cli.conf — override defaults for a 32 GB machine

# Bump context window
MAX_CONTEXT=32768

# Use 8B models instead of 1.2B (more RAM → bigger models)
OLLAMA_CHAT="hf.co/LiquidAI/LFM2.5-8B-A1B-GGUF"
LLAMACPP_CHAT="LiquidAI/LFM2.5-8B-A1B-GGUF"

# Or go all-in with a 30B model
# OLLAMA_CHAT="hf.co/bartowski/Qwen2.5-32B-Instruct-GGUF"

# Swap coder for a stronger one
OLLAMA_CODER="hf.co/bartowski/Qwen3-Coder-30B-A3B-Instruct-GGUF"
LLAMACPP_CODER="bartowski/Qwen3-Coder-30B-A3B-Instruct-GGUF"

# Keep quantization reasonable
QUANTIZATION="q6_k"
```

### What you can override

| Variable | Purpose |
|:---|:---|
| `DEBUG` | Enable/Disable debug mode (default: false) |
| `START_JARNET` | Enable/Disable automatic JarNet service starting (default: true) |
| `USE_TOR` | Enable/Disable forced Tor network routing (default: true) |
| `RUN_MODE` | Default working mode (`chat`, `auto`, `simple`) |
| `DETECT_MODE` | Automatic media file detection mode (`images`, `videos`, `all`, `off`) |
| `BACKEND` | Default backend (`ollama`, `llamacpp`, `external`) |
| `PROVIDER` | Default cloud provider |
| `USER_MODEL` | Default cloud provider model |
| `OLLAMA_CHAT` / `LLAMACPP_CHAT` | Local chat model |
| `OLLAMA_VISION` / `LLAMACPP_VISION` | Local vision model |
| `OLLAMA_CODER` / `LLAMACPP_CODER` | Local code generation model |
| `OLLAMA_JUDGE` / `LLAMACPP_JUDGE` | Local code review model |
| `MAX_CONTEXT` | Context window size (default: 16384) |
| `QUANTIZATION` | Model quantization level (`q4_k_m`, `q6_k`, `q8_0`, etc.) |
| `REASONING_EFFORT` | Model reasoning effort (`low`, `medium`, `high`, `xhigh`, etc.) |
| `MEMORY_STRUCTURE_TYPE` | Persistent memory injection: `full` (default) or `index` |
| `MEMORY_SECTION_KB` | File-size threshold for H2 listings in `index` mode (default: 128 KiB; `0` includes every file with H2 headings) |
| `HEARTBEAT_THRESHOLD` | Messages before memory consolidation (default: 15) |
| `PBKDF_ITERATIONS` | Key derivation rounds (default: 500K, halved on Termux) |
| `ENGINE_VERSION` | Media engines version (default: v2) |
| `AUDIO_LANG` | TTS engine spoken language (default: auto) |

The rule of thumb: **~1 GB RAM per 1B parameters at q4**. A 32 GB machine can comfortably run models up to 30B parameters, or several smaller ones for the multi-agent roles.

## 🧠 Dynamic System Prompt

The system prompt is not a static block — it's assembled at runtime by `set_system_prompt()` based on what exists in your workspace. Drop a folder in `data/`, restart, and the agent gains new context. Zero configuration needed.

```
set_system_prompt()
  │
  ├─ Base identity (AI name, model, workspace)
  ├─ Memory format (Markdown / JSON / SQL)
  │
  ├─ config/rules.md exists?       → Inject safety rules
  ├─ config/avatar.md exists?      → Inject self avatar creation rules
  │
  ├─ data/framework/ exists?       → "Your behavioral framework files are here..."
  ├─ data/skills/ exists?          → "Your acquired skills are here..."
  ├─ data/learn/ exists?           → "Your learning resources are here..."
  ├─ data/docs/ exists?            → "Your shared documents are here..."
  │
  └─ Protected files / folders warning (core.sh, cli.sh, tools.sh, image.sh, config/, keys/, lib/, engines/, plugins/)

get_system_prompt()
  ├─ Base prompt assembled above
  └─ bootstrap_memory()
       ├─ full (default)           → Inject readable memory file contents
       └─ index                    → File map; H2 listings for files at or above the size threshold
```

### Folder semantics

| Folder | Purpose | Agent instruction |
|:---|:---|:---|
| `data/framework/` | Behavioral framework files (AGENTS.md, SOUL.md) | "Load before code-related tasks" |
| `data/skills/` | Acquired skills (human-reading.md, v0-bridge.md) | "Load before code-related tasks" |
| `data/learn/` | Learning resources (read-only), references | "Look at when necessary" |
| `data/docs/` | Shared documents | "Look at when necessary" |
| `data/memory/` | Persistent memory | `full`: contents injected; `index`: file map injected, contents read on demand |
| `config/rules.md` | Non-negotiable safety boundaries | Injected verbatim |
| `config/avatar.md` | Self avatar creation rules to represent AI personality / mood | Injected verbatim |

**In practice**: To teach the agent a new skill, drop a Markdown file in `data/skills/` and restart. No code changes. The prompt adapts.
## 💬 Slash Commands

| Command | Action |
|:---|:---|
| `/mode [chat\|auto]` | Toggle between interactive Chat Mode and autonomous Agent-to-Agent mode |
| `/backend [type]` | Switch active backend (`ollama`, `llamacpp`, `external`) |
| `/provider [name]` | Switch active cloud provider |
| `/fallback [provider\|off]` | Set/disable capability-driven vision fallback provider |
| `/image [provider]` | Set/display active image generation provider |
| `/video [provider]` | Set/display active video generation provider |
| `/voice [provider]` | Set/display active TTS voice synthesis provider (e.g. `local` Piper, `openai`, `openrouter`) |
| `/speech [provider]` | Set/display active STT speech transcription provider (e.g. `local` Whisper, `groq`, `openai`) |
| `/model [name]` | Switch active model for current provider |
| `/thinking [boolean]` | Toggle active model reasoning / thinking display (`true`, `false`) |
| `/effort [level]` | Set active model reasoning effort (`none`, `minimal`, `low`, `medium`, `high`, `xhigh`, `max`) |
| `/lang [code]` | Set audio language for voice recognition / TTS (`fr`, `en`, `de`, `it`, etc.) |
| `/detect [type]` | Configure automatic media detection (`images`, `videos`, `all`, `off`) |
| `/memory [type]` | Show current memory structure, or switch between `full` and `index` |
| `/jarnet [action]` | Control JarNet P2P service (`who`, `status`, `doctor`, `up`, `down`) |
| `/balance` | List available balance across all configured providers |
| `/models` | List available models for the active provider |
| `/clear` | Wipe active session history and conversational memory |
| `/commit` | Manually trigger persistent memory consolidation to disk |
| `/heartbeat [count]` | Set message threshold triggering memory consolidation |
| `/draw [prompt] [...]` | Generate an image via the image engine (`--ratio`, `--size`, `--model`, `--provider`) |
| `/imagine [prompt] [...]` | Generate a video via the video engine (`--ratio`, `--resolution`, `--image`, `--model`, `--provider`, `--duration`, `--fps`, `--frames`) |
| `/keys` | Manage encrypted API keys in the sovereign key chest |
| `/migrate [--apply]` | Migrate master key file to new format (Nightmare stream obfuscation) |
| `/replay` | Resend last message (zero-fork) |
| `/launch [app] [path]` | Launch external app with prepared environment variables |
| `/load <file>` | Load a text or media file into context |
| `/unload` | Unload the previously loaded file from context |
| `/run <cmd>` | Execute a local shell command within the session |
| `/start` | Switch active context to multi-agent pipeline |
| `/debug [on\|off]` | Toggle debug logging mode dynamically |
| `/help` | View interactive command reference |
| `/quit\|/bye\|/exit` | Exit session gracefully |

### ⌨️ Keyboard Shortcuts

| Shortcut | Action |
|:---|:---|
| `Alt+V` | **Live Voice Dictation Loop**: Records audio from your microphone, transcribes via local Whisper (or cloud STT), and automatically submits the prompt via Readline into the inference loop. |
| `Alt+S` | **Instant Voice Replay**: Synthesizes and plays back the last AI response using local Piper (or cloud TTS). |

## 🛡️ OPSEC & Security

- **ChaCha20 + PBKDF2 key chest** — API keys encrypted at rest, 500K iterations, `chmod 600`
- **Tor by default** — outbound API requests route through SOCKS5
- **Tor startup** — when Tor is enabled for an external backend, reuse the configured endpoint if its TCP port is reachable; otherwise attempt to start Tor and check the port again. This is a TCP availability check, not a full Tor bootstrap verification.
- **Zero Data Retention** — injected automatically for compatible providers
- **Anti-XPIA / Anti-Injection** — external content is provenance-tagged, structurally separated from instructions
- **Workspace confinement** — agent stays in `data/`, cannot modify core files or `config/`/`keys/` folders
- **ShellCheck-clean** — zero warnings on the active codebase

<details>
<summary><b>🔍 Full OPSEC details</b></summary>

- **Localhost-Only Boundaries**: API servers listen on `127.0.0.1` by default.
- **Directory Traversal Prevention**: file parameters are validated against safe boundaries.
- **Onion-Routed Privacy Tunnel**: all outbound cloud API requests route through Tor SOCKS5 proxy.
- **ZDR Injection**: privacy payloads dynamically appended for compatible external providers.
- **Terminal Payload Immunization**: `iconv` and strict `jq --rawfile` streams protect APIs from malformed outputs.
- **Device Auth Tag**: cryptographic session tagging via machine-id + timestamp → sha256.
- **Protected Files Guard**: `core.sh`, `cli.sh`, `tools.sh`, `tools.json`, and the entire `config/` and `keys/` folders are off-limits to the agent.

</details>

## ℹ️ More details about the project

<details>
<summary><b>✨ Full Feature List</b></summary>

### Agentic Runtime <!-- omit in toc -->
- 🧠 Real ReAct-pattern agentic loop with recursive tool calling
- 🌀 Autonomous memory consolidation (heartbeat-driven Markdown restructuring)
- 🔁 Multi-agent pipeline mode: Architect → Coder → Judge
- 👁️ Multimodal vision with autonomous visual feedback loop
- 🔄 Capability-driven inter-provider vision fallback

### Web Intelligence <!-- omit in toc -->
- 🌐 `web_fetch`: Domain-specific routing (GitHub, GitLab, Codeberg, SourceHut, Wikipedia)
- 🌐 `web_browse`: Pure Bash CDP browser automation — screenshots, PDFs, form interaction, JS evaluation (desktop + Android/ADB)
- 🔍 `web_search`: Anonymous DuckDuckGo via Tor

### Local & Self-Hosted <!-- omit in toc -->
- 🏠 Ollama and llama.cpp first-class support — fully offline-capable
- 🖥️ Unified server mode: `--server web|ollama|llamacpp`
- ⚡ Hardware-aware adaptive tuning (CPU detection, RAM-aware model selection)
- 💾 Flash memory wear reduction on mobile (`/tmp` relocation)
- 🧠 Multi-agent roles for local models (Router, Vision, Architect, Coder, Judge)

### Safety & Hardening <!-- omit in toc -->
- 🔑 Sovereign Key Chest (ChaCha20 + PBKDF2, 500K iterations, `chmod 600`)
- 🧅 Tor SOCKS5 proxy for all external API calls
- 🛡️ Anti-XPIA / Anti-Injection: external content provenance-tagged, structurally separated
- 📱 Hardware-adaptive PBKDF2 scaling (halved iterations on Termux)
- ⚡ Full JQ E2BIG / ARG_MAX immunization

### User Experience <!-- omit in toc -->
- 🎨 High-intensity ANSI terminal UI with cyberpunk styling
- 💭 AI reasoning extraction with styled `thinking_tokens` blocks
- 📊 Real-time token metrics & cost tracking
- 💳 Credit balance HUD (Vercel, CyberNeurova, OpenRouter, DeepSeek, Moonshot AI)
- 🔄 Interactive `/replay` command (zero-fork)
- 📐 Pixel-perfect auto-sizing terminal headers

### Tool-Calling Surface (31 Tools) <!-- omit in toc -->

#### 📁 Workspace & Filesystem <!-- omit in toc -->
1. **`read_file`** — Read files with line ranges and line-number prefixing
2. **`file_glob_search`** — Recursive file discovery within workspace boundaries
3. **`grep_search`** — Fast regex search across project files
4. **`exec_command`** — Sandboxed shell execution (10s timeout, protected-files guard)
5. **`write_file`** — Create or overwrite files with automatic parent-directory creation
6. **`edit_file`** — Surgical multi-line replace, delete, or append operations
7. **`apply_diff`** — Unified diff patching (patch-tolerant)
8. **`get_datetime`** — Precision system date and time retrieval

#### 🌐 Web Intelligence <!-- omit in toc -->
9. **`web_search`** — Anonymous DuckDuckGo search over Tor SOCKS5 proxy
10. **`web_fetch`** — Clean Markdown extraction with multi-forge routing (GitHub, GitLab, Wikipedia)
11. **`web_browse`** — Headless Chrome CDP browser automation (screenshots, PDF, DOM interaction; zero Node/Puppeteer)

#### 🎨 Multimodal Media & Vision <!-- omit in toc -->
12. **`create_image`** — Generate images from text prompts (config-driven providers with keyless fallback)
13. **`edit_image`** — Image-to-image editing, modification, and inpainting with mask support
14. **`create_video`** — Text-to-video (t2v) and image-to-video (i2v) rendering
15. **`read_image`** — Deliberate vision analysis and inspection of local image assets
16. **`read_video`** — Video-to-text temporal analysis and motion inspection
17. **`create_avatar`** — Spontaneous AI persona/avatar portrait generation

#### 🎙️ Voice & Speech <!-- omit in toc -->
18. **`transcribe`** — Audio-to-text transcription (STT via local whisper.cpp or cloud models)
19. **`speak`** — Text-to-speech audio synthesis (TTS via local Piper or cloud models)

#### ⚙️ Runtime Introspection <!-- omit in toc -->
20. **`get_state`** — Read current functional session state (read-only)
21. **`get_providers`** — Discover active and usable providers at runtime
22. **`get_models`** — List models exposed by provider with operational filtering

#### 🔗 JarNet P2P Protocol (Tor v3) <!-- omit in toc -->
23. **`jarnet_who`** — Inspect local JarNet node identity, onion address, callsign, and peers
24. **`jarnet_ping`** — Ping peer alias or onion address over Tor to test route reachability
25. **`jarnet_send`** — Send direct messages to a peer over secure Tor network
26. **`jarnet_reply`** — Send authenticated reply respecting session envelopes (sid and reply_to)
27. **`jarnet_check`** — Check inbox for new messages (anti-XPIA wrapped as external content)
28. **`jarnet_peer_add`** — Add a trusted peer from an onboarding token (human-authorized)
29. **`jarnet_up`** — Start/self-heal JarNet transport stack and Tor hidden service
30. **`jarnet_down`** — Stop JarNet listener and unpublish Tor hidden service
31. **`jarnet_status`** — Inspect technical health and daemon state machine of JarNet

</details>

<details>
<summary><b>⚙️ Backends & Providers</b></summary>

### Three Backends, One Interface <!-- omit in toc -->

| Backend | Use Case |
|:---|:---|
| **`ollama`** | Local, offline-first, easy setup — `http://localhost:11434` |
| **`llamacpp`** | Local, high-performance, fine-grained control — `http://localhost:8080` |
| **`external`** | Cloud providers (17), vision fallback, ZDR — Tor-routed |

Switch anytime: `/backend`, `/provider`, `/model`. Same tools, same memory, same agent loop across all three.

### Local Model Stack <!-- omit in toc -->

Both Ollama and llama.cpp support multi-agent roles with RAM-aware model selection:

| Role | Model |
|:---|:---|
| **Chat** | LiquidAI LFM2.5 (1.2B or 8B depending on RAM) |
| **Vision** | LiquidAI LFM2.5-VL 1.6B |
| **Router** | LiquidAI LFM2.5 1.2B Instruct |
| **Architect** | LiquidAI LFM2.5 1.2B Thinking |
| **Coder** | Mistral 3.3B Reasoning (Ministral) |
| **Judge** | Mistral 3.3B Reasoning (Ministral) |

### Cloud Providers (17) <!-- omit in toc -->

| ID | Name | URL |
|:---|:---|:---|
| 1 | Anthropic | https://claude.com |
| 2 | CyberNeurova | https://cyberneurova.com |
| 3 | DeepSeek | https://deepseek.com |
| 4 | Groq | https://groq.com |
| 5 | Hugging Face | https://huggingface.co |
| 6 | Kimi (Moonshot AI) | https://moonshot.ai |
| 7 | Mammouth AI | https://mammouth.ai |
| 8 | OpenAI | https://openai.com |
| 9 | OpenRoute (CyberNeurova) | https://openroute.cyberneurova.com |
| 10-11 | OpenRouter (Free / Paid) | https://openrouter.ai |
| 12 | Venice AI | https://venice.ai |
| 13-14 | Vercel AI Gateway (Free / Paid) | https://ai-gateway.vercel.sh |
| 15 | X.AI (Grok API) | https://x.ai |
| 16-17 | Z.AI (API / Coding Plan) | https://z.ai |

>[!NOTE]
> All use the same OpenAI-compatible API. Vision fallback works across any text-only → vision-capable pair.

</details>

<details>
<summary><b>📂 Core Files</b></summary>

| File | Version | Role |
|:---|:---|:---|
| [`core.sh`](core.sh) | v1.9.4 | Sovereign Cognitive Core — 3 backends, OPSEC, memory, tool loop, fallback |
| [`cli.sh`](cli.sh) | v1.8.2 | Interactive terminal client — slash commands, session loop, reasoning display |
| [`tools.sh`](tools.sh) | v0.8.4 | Tool execution bridge — 31 tools, anti-XPIA wrapping, protected-files guard |
| [`image.v2.sh`](engines/image.v2.sh) | v0.2.1 | v2 Image engine — config-driven providers, quality & format constraints |
| [`video.v2.sh`](engines/video.v2.sh) | v0.2.1 | v2 Video engine — t2v / i2v generation, asynchronous polling |
| [`voice.v2.sh`](engines/voice.v2.sh) | v0.2.0 | v2 Voice engine — TTS voice synthesis (local Piper / cloud) |
| [`speech.v2.sh`](engines/speech.v2.sh) | v0.2.0 | v2 Speech engine — STT audio transcription (local Whisper / cloud) |
| [`jarnet.sh`](plugins/jarnet.sh) | v1.3.1 | P2P Agent-to-Agent Tor transport daemon & CLI |
| [`install.sh`](install.sh) | v0.2.1 | Project installer with static prebuilt binary downloader |
| [`showcast.sh`](tools/showcast.sh) | v0.0.1 | `asciinema` demo recorder |
| [`web-fetch.sh`](tools/web-fetch.sh) | v0.4.5 | Multi-forge web fetcher (GitHub, GitLab, Codeberg, SourceHut, Wikipedia) |
| [`web-browse.sh`](tools/web-browse.sh) | v0.1.3 | Pure Bash CDP browser automation (desktop + Android/ADB) |
| [`tools.json`](tools/tools.json) | — | Full tool schemas for function calling |
| [`tools-light.json`](tools/tools-light.json) | — | Lightweight tool schemas for SLM models |
| [`config/providers.v2.json`](config/providers.v2.json) | — | Unified v2 provider registry with dynamic model discovery |
| [`lib/*.sh`](lib/) | — | Modular pure-Bash primitives (animate, base64, base82, nightmare, sha256, timeout, helpers) |

</details>

<details>
<summary><b>🧠 Cognitive Memory Engine</b></summary>

The pipeline uses a native Markdown-based memory filesystem under `data/memory/`. The agent can read, write, edit, and reorganize its own persistent memory autonomously. `get_system_prompt()` incorporates the current memory through `bootstrap_memory()` when preparing requests:

- **`full` (default)**: inject the readable memory files' full contents into the system prompt.
- **`index`**: inject a sorted file map with paths, titles and sizes; contents stay on disk and are read on demand. Files at or above `MEMORY_SECTION_KB` (default: **128 KiB**) also include up to **20 H2 headings**. The threshold applies to the whole file, not individual sections. Setting it to `0` enables H2 listings for every file containing such headings.

Select the mode at launch with `./cli.sh --memory index` (or `./cli.sh memory index`), or during a chat with `/memory index` and `/memory full`. `/memory` alone displays the current setting. The switch changes memory injection for subsequent requests; it does not delete memory files or clear conversation history.

**Defaults and fallback:** `MEMORY_STRUCTURE_TYPE` defaults to `full`. During provider setup, a provider's memory default can replace a non-`index` setting, while an active `index` setting is preserved. At prompt assembly, any value other than `index` deliberately uses the `full` branch, including an empty or unrecognized value.

`MEMORY_STRUCTURE_TYPE` and `MEMORY_SECTION_KB` can also be set in `config/cli.conf`. The size threshold only affects `index` mode.

**Heartbeat consolidation**: Every 15 user messages, the agent enters a subconscious state, reviews conversation history, updates memory files, then prunes the active context — preventing token bloat and amnesia.

```
data/memory/
├── profile.md           — User profile & preferences
├── pipeline.md          — Technical architecture & version history
├── hardening-tracker.md — Security hardening implementation status
└── ...
```

>[!NOTE]
> The created memory structure may vary depending on the used AI model.

</details>

## 👥 Credits

- **Lead Developer / Architect**: **Jiab77**
- **AI Sorcerer & Co-Creator**: **Jarvis** (Gemini 3.8 Flash / DeepSeek Flash / Kimi K3.1 Pro / GLM-5.3 Flash)

## ⚖️ License & Roadmap

MIT License. **v1.9.4 — Stable & Production-Ready.**

Roadmap:

- **v1.9.4 (current)**: Media generation engine, Voice / Speech engines, JarNet Agent-2-Agent communication protocol.
- **v2.0.0 (horizon)**: A.I.D.E. Web dashboard, Cognitive Router & Proxy (CRP) Gateway, charmbracelet/gum UI modernization.

## ⭐ Star History

<a href="https://www.star-history.com/?repos=Jiab77%2Fai-pipeline&type=date&legend=top-left">
 <picture>
   <source media="(prefers-color-scheme: dark)" srcset="https://api.star-history.com/chart?repos=Jiab77/ai-pipeline&type=date&theme=dark&legend=top-left&sealed_token=z9Uw-Wfp4u1bqDTo9Mme3kg77cBmscyD7Z1_qyrkJhqzzZMPCFDfqlbApxZ6WvmLjIA7wXcL9zGwYAsqut2Bz5BCXwGrh_VObqMJe08O-eAE5Izc3vPoRQ" />
   <source media="(prefers-color-scheme: light)" srcset="https://api.star-history.com/chart?repos=Jiab77/ai-pipeline&type=date&legend=top-left&sealed_token=z9Uw-Wfp4u1bqDTo9Mme3kg77cBmscyD7Z1_qyrkJhqzzZMPCFDfqlbApxZ6WvmLjIA7wXcL9zGwYAsqut2Bz5BCXwGrh_VObqMJe08O-eAE5Izc3vPoRQ" />
   <img alt="Star History Chart" src="https://api.star-history.com/chart?repos=Jiab77/ai-pipeline&type=date&legend=top-left&sealed_token=z9Uw-Wfp4u1bqDTo9Mme3kg77cBmscyD7Z1_qyrkJhqzzZMPCFDfqlbApxZ6WvmLjIA7wXcL9zGwYAsqut2Bz5BCXwGrh_VObqMJe08O-eAE5Izc3vPoRQ" />
 </picture>
</a>
