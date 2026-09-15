<div align="center">

# 🚀 A.I.D.E CLI — AI Driven Environment <!-- omit in toc -->

### Sovereign Bash-First Cognitive Runtime <!-- omit in toc -->

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)
[![Bash Shell](https://img.shields.io/badge/Shell-Bash-4EAA25.svg?logo=gnu-bash&logoColor=white)](https://www.gnu.org/software/bash/)
[![Backend Supported](https://img.shields.io/badge/Backends-Ollama%20%7C%20llama.cpp%20%7C%2016%20external%20providers-orange.svg)]()
[![Status](https://img.shields.io/badge/Status-Stable--v1.8.1-blue.svg)]()

</div>

> A sovereign, local-first, Bash-driven cognitive runtime for orchestrating local and cloud LLMs with real tool execution, multimodal perception, privacy-aware transport, and autonomous persistent memory, and the only **capability-driven inter-provider vision fallback** implemented in Bash. Runs fully local (Ollama / llama.cpp) or connects to 16 cloud providers — your choice. No Python. No Node. No Docker. Just `curl`, `jq`, `htmlq`, `grep`, `sed`, `awk`, `htmlq`, `websocat`, `cut`, `tr`, `printf`, and a brain on fire 😝
>
> This project is not just another LLM wrapper. It is a lightweight but deeply capable agent runtime built around a practical equilibrium between **Bash** (orchestration, live browser automation), and **PHP** (local web UX) — proving that modern agentic systems do not have to be trapped inside the usual Python-heavy stack.

---

## 📖 Table of content <!-- omit in toc -->

- [🏛️ Architecture](#️-architecture)
- [⚡ Why This Exists](#-why-this-exists)
- [🔄 Inter-Provider Vision Fallback](#-inter-provider-vision-fallback)
  - [Flow A — Manual Image (`/load`)](#flow-a--manual-image-load)
  - [Flow B — Tool-Generated Image](#flow-b--tool-generated-image)
- [🚀 Quick Start](#-quick-start)
  - [⚡ Method A — One-liner (fast)](#-method-a--one-liner-fast)
    - [1. Install dependencies (required for both methods)](#1-install-dependencies-required-for-both-methods)
      - [Automatic](#automatic)
      - [Windows](#windows)
      - [Debian/Ubuntu](#debianubuntu)
      - [macOS](#macos)
        - [a. Using pre-compiled binaries (recommended for old versions)](#a-using-pre-compiled-binaries-recommended-for-old-versions)
        - [b. Using compiled binaries (recommended for modern versions)](#b-using-compiled-binaries-recommended-for-modern-versions)
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

**`core.sh`** is the agnostic engine — three backends (Ollama, llama.cpp, 16 cloud providers), ChaCha20-encrypted key chest, Tor routing, Markdown memory, and the agentic tool loop. **`cli.sh`** is the terminal client. **`tools.sh`** bridges model-declared capabilities to real host actions. One engine, multiple interfaces — local or cloud, your choice.

## ⚡ Why This Exists

- **Bash-first by conviction, not nostalgia**: 6036 lines of Bash doing things that usually "require" Python, NodeJS, Rust or even Go, including a stateless CDP browser engine and a multi-agent pipeline (Architect → Coder → Judge).
- **Local-first, cloud-capable**: Runs fully offline with Ollama/llama.cpp, or connects to 16 cloud providers. Same code, same tools, three backends.
- **Capability-driven fallback**: When a text-only model needs vision, the pipeline auto-switches provider mid-loop — same code, different backend. Nobody else has this in Bash.
- **Privacy is a feature, not an afterthought**: Tor routing, ChaCha20-encrypted API keys, Zero Data Retention injection, local backends — all first-class.

## 🔄 Inter-Provider Vision Fallback

When the pipeline is configured to run on text-only models and an image appears, it auto-switches to a vision-capable provider, processes the image, then switches back. Two triggers, one mechanism:

### Flow A — Manual Image (`/load`)

```
User: "/load photo.png" → sends message
  │
  └─ send_message()
       ├─ IS_IMAGE == true → handle_vision_request()
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
                        │  parse_cli_flags()        │
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
| **Trigger** | `IS_IMAGE=true` in `send_message` | Image detected in `run_inference_loop` |
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

## 🚀 Quick Start

### ⚡ Method A — One-liner (fast)

#### 1. Install dependencies (required for both methods)

##### Automatic

> [!NOTE]
> This method is still experimental.

You can run the **[install.sh](install.sh)** script, it should handle everything except the **Windows** part.

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
sudo apt install -y build-essential curl jq sed tor glow figlet openssl libssl-dev pkgconf cargo && cargo install htmlq websocat
```

##### macOS

Install [**brew**](brew.sh) if not done already with:

```bash
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
```

And follow printed instructions then choose one of the two methods below **not both**.

###### a. Using pre-compiled binaries (recommended for old versions)

```bash
# Pre-compiled binaries (avoid ~6h compilation phase)
# htmlq
curl -fsSL https://github.com/mgdm/htmlq/releases/latest/download/htmlq-x86_64-darwin.tar.gz | tar -xz -C /usr/local/bin

# websocat
curl -fsSL https://github.com/vi/websocat/releases/latest/download/websocat.x86_64-apple-darwin -o /usr/local/bin/websocat && chmod +x /usr/local/bin/websocat

# Then install the rest via brew
brew install jq glow tor openssl figlet
```

> [!NOTE]
> This method will prevent you to wait for around 6h to complete on old macOS versions! That's why it's the recommended method.

###### b. Using compiled binaries (recommended for modern versions)

```bash
brew install jq glow tor htmlq openssl websocat figlet
```

> [!WARNING]
> This may take around 6h to complete on old macOS versions! You should try using pre-compiled binaries first as explained above and use this method only if it does not work.

##### Arch Linux

```bash
paru -Syu curl jq sed tor glow figlet openssl websocat htmlq
```

##### Termux

```bash
pkg install git curl jq sed glow figlet openssl openssl-tool websocat android-tools tor cargo-binstall && cargo-binstall htmlq
```

##### Update your binary path

```bash
# Update current session path
export PATH=$PATH:$HOME/.cargo/bin

# Make the new binary path permanent
echo 'export PATH=$PATH:$HOME/.cargo/bin' >> ~/.bashrc
```

#### 2. Install the pipeline (clone + global 'aide' command)

```bash
curl -fsSL https://raw.githubusercontent.com/jiab77/ai-pipeline/main/install.sh | bash
```

#### 3. Launch

```bash
aide help
```

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
./cli.sh                          # Chat mode
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

### Set up your cloud providers keys

```bash
# From live chat session
/keys

# From start
./cli.sh --keys
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
| `BACKEND` | Default backend (`ollama`, `llamacpp`, `external`) |
| `PROVIDER` | Default cloud provider |
| `OLLAMA_CHAT` / `LLAMACPP_CHAT` | Chat model |
| `OLLAMA_VISION` / `LLAMACPP_VISION` | Vision model |
| `OLLAMA_CODER` / `LLAMACPP_CODER` | Code generation model |
| `OLLAMA_JUDGE` / `LLAMACPP_JUDGE` | Code review model |
| `MAX_CONTEXT` | Context window size (default: 16384) |
| `QUANTIZATION` | Model quantization level (`q4_k_m`, `q6_k`, `q8_0`, etc.) |
| `MEMORY_STRUCTURE_TYPE` | Persistent memory injection: `full` (default) or `index` |
| `MEMORY_SECTION_KB` | File-size threshold for H2 listings in `index` mode (default: 128 KiB; `0` includes every file with H2 headings) |
| `HEARTBEAT_THRESHOLD` | Messages before memory consolidation (default: 15) |
| `PBKDF_ITERATIONS` | Key derivation rounds (default: 500K, halved on Termux) |

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
  │
  ├─ data/framework/ exists?       → "Your behavioral framework files are here..."
  ├─ data/skills/ exists?          → "Your acquired skills are here..."
  ├─ data/learn/ exists?           → "Your learning resources are here..."
  ├─ data/docs/ exists?            → "Your shared documents are here..."
  │
  └─ Protected files warning (core.sh, cli.sh, tools.sh, image.sh, config/, keys/)

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

**In practice**: To teach the agent a new skill, drop a Markdown file in `data/skills/` and restart. No code changes. The prompt adapts.

## 💬 Slash Commands

| Command | Action |
|:---|:---|
| `/backend [type]` | Switch active backend |
| `/provider [name]` | Switch active provider |
| `/fallback [provider\|off]` | Set/disable vision fallback provider |
| `/model [name]` | Switch active model |
| `/effort [level]` | Set active model reasoning effort |
| `/memory [type]` | Show current memory structure, or switch to `full` / `index` for subsequent requests |
| `/launch [app] [path]` | Launch app with prepared environment variables |
| `/load <file>` | Load a text or image file into context |
| `/unload` | Unload the previously loaded file |
| `/draw [prompt] [--ratio r \| --size WxH \| --model m \| --provider p]` | Generate an image via the image engine |
| `/image [provider]` | Set/display the image generation provider |
| `/keys` | Manage encrypted API keys |
| `/clear` | Wipe active session history |
| `/commit` | Trigger memory consolidation |
| `/replay` | Resend last message |
| `/run <cmd>` | Execute shell command |
| `/quit` | Exit |

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

### Tool-Calling Surface (12 Tools) <!-- omit in toc -->
1. **`read_file`** — Read files with line ranges and line-number prefixing
2. **`file_glob_search`** — Recursive file discovery
3. **`grep_search`** — Regex search across file trees
4. **`exec_shell_command`** — Shell execution (10s timeout, protected-files guard)
5. **`write_file`** — Write/overwrite with auto parent-directory creation
6. **`edit_file`** — Surgical multi-line replace/delete/insert
7. **`apply_diff`** — Unified diff application
8. **`get_datetime`** — System date/time
9. **`web_search`** — Anonymous DuckDuckGo over Tor
10. **`web_fetch`** — Smart Markdown fetcher with domain-specific routing
11. **`web_browse`** — Pure Bash CDP browser automation (completely Node-free)
12. **`create_image`** — Generate images via the config-driven engine (cloud providers + Pollinations fallback)

</details>

<details>
<summary><b>⚙️ Backends & Providers</b></summary>

### Three Backends, One Interface <!-- omit in toc -->

| Backend | Use Case |
|:---|:---|
| **`ollama`** | Local, offline-first, easy setup — `http://localhost:11434` |
| **`llamacpp`** | Local, high-performance, fine-grained control — `http://localhost:8080` |
| **`external`** | Cloud providers (16), vision fallback, ZDR — Tor-routed |

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

### Cloud Providers (16) <!-- omit in toc -->

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
| 15-16 | Z.AI (API / Coding Plan) | https://z.ai |

>[!NOTE]
> All use the same OpenAI-compatible API. Vision fallback works across any text-only → vision-capable pair.

</details>

<details>
<summary><b>📂 Core Files</b></summary>

| File | Version | Role |
|:---|:---|:---|
| [`core.sh`](core.sh) | v1.8.1 | Sovereign Cognitive Core — 3 backends, OPSEC, memory, tool loop, fallback |
| [`cli.sh`](cli.sh) | v1.7.0 | Interactive terminal client — slash commands, session loop, reasoning display |
| [`tools.sh`](tools.sh) | v0.7.0 | Tool execution bridge — 12 tools, anti-XPIA wrapping, protected-files guard |
| [`image.sh`](image.sh) | v0.1.0 | Image rendering engine — config-driven providers, Pollinations fallback |
| [`install.sh`](install.sh) | v0.1.0 | Basic installer script |
| [`showcast.sh`](tools/showcast.sh) | v0.0.0 | `asciinema` demo recorder |
| [`web-fetch.sh`](tools/web-fetch.sh) | v0.4.2 | Multi-forge web fetcher (GitHub, GitLab, Codeberg, SourceHut, Wikipedia) |
| [`web-browse.sh`](tools/web-browse.sh) | v0.1.0 | Pure Bash CDP browser automation (desktop + Android/ADB) |
| [`tools.json`](tools/tools.json) | — | Tool schemas for function calling |
| [`config/providers.json`](config/providers.json) | — | Provider registry (endpoints, models, ZDR, vision + image flags) |
| [`config/models.json`](config/models.json) | — | Model & sampling parameter registry |

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
- **AI Sorcerer & Co-Creator**: **Jarvis** (Gemini / DeepSeek / Kimi K3 / GLM-5.2 / GLM-5.3)

## ⚖️ License & Roadmap

MIT License. **v1.8.1 — Stable & Production-Ready.**

Roadmap:

- **v1.8.1 (current)**: Image generation engine — `/draw` + `create_image`, config-driven providers, new memory structure, Pollinations fallback.
- **v1.9.0 (next)**: `voice.sh` — STT + TTS engine (local + cloud providers) and more.
- **v2.0.0 (horizon)**: A.I.D.E. Web dashboard, Cognitive Router & Proxy (CRP) Gateway, charmbracelet/gum UI modernization.

## ⭐ Star History

<a href="https://www.star-history.com/?repos=Jiab77%2Fai-pipeline&type=date&legend=top-left">
 <picture>
   <source media="(prefers-color-scheme: dark)" srcset="https://api.star-history.com/chart?repos=Jiab77/ai-pipeline&type=date&theme=dark&legend=top-left&sealed_token=z9Uw-Wfp4u1bqDTo9Mme3kg77cBmscyD7Z1_qyrkJhqzzZMPCFDfqlbApxZ6WvmLjIA7wXcL9zGwYAsqut2Bz5BCXwGrh_VObqMJe08O-eAE5Izc3vPoRQ" />
   <source media="(prefers-color-scheme: light)" srcset="https://api.star-history.com/chart?repos=Jiab77/ai-pipeline&type=date&legend=top-left&sealed_token=z9Uw-Wfp4u1bqDTo9Mme3kg77cBmscyD7Z1_qyrkJhqzzZMPCFDfqlbApxZ6WvmLjIA7wXcL9zGwYAsqut2Bz5BCXwGrh_VObqMJe08O-eAE5Izc3vPoRQ" />
   <img alt="Star History Chart" src="https://api.star-history.com/chart?repos=Jiab77/ai-pipeline&type=date&legend=top-left&sealed_token=z9Uw-Wfp4u1bqDTo9Mme3kg77cBmscyD7Z1_qyrkJhqzzZMPCFDfqlbApxZ6WvmLjIA7wXcL9zGwYAsqut2Bz5BCXwGrh_VObqMJe08O-eAE5Izc3vPoRQ" />
 </picture>
</a>
