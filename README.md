# 🚀 A.I.D.E CLI — AI Driven Environment

> Sovereign Bash-First Cognitive Runtime.

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)
[![Bash Shell](https://img.shields.io/badge/Shell-Bash-4EAA25.svg?logo=gnu-bash&logoColor=white)](https://www.gnu.org/software/bash/)
[![Backend Supported](https://img.shields.io/badge/Backends-Ollama%20%7C%20llama.cpp%20%7C%2011%20external%20providers-orange.svg)]()
[![Status](https://img.shields.io/badge/Status-Stable--v1.3.0-blue.svg)]()

> A sovereign, local-first, Bash-driven cognitive runtime for orchestrating local and cloud LLMs with real tool execution, multimodal perception, privacy-aware transport, and autonomous persistent memory.

> **A.I.D.E CLI** is not just another LLM wrapper. It is a lightweight but deeply capable agent runtime built around a practical equilibrium between **Bash** (orchestration, live browser automation), and **PHP** (local web UX) — proving that modern agentic systems do not have to be trapped inside the usual Python-heavy stack.

---

## 📖 Table of Contents
1. [Overview & Architecture](#-overview--architecture)
2. [Why AI Pipeline Is Different](#-why-ai-pipeline-is-different)
3. [Key Capabilities](#-key-capabilities)
4. [Core Files](#-core-files)
5. [Interactive Chat Mode (Default)](#-interactive-chat-mode-default)
6. [Tool-Calling Engine (Agentic Capability)](#%EF%B8%8F-tool-calling-engine-agentic-capability)
7. [Supported Backends & Configured Models](#-supported-backends--configured-models)
8. [Unified Local Server Modes](#-unified-local-server-modes)
9. [Prerequisites & Installation](#%EF%B8%8F-prerequisites--installation)
10. [Usage Guide](#-usage-guide)
11. [Cognitive Freedom Memory Engine](#%EF%B8%8F-cognitive-freedom-memory-engine)
12. [Hardened OPSEC & Security Protocols](#%EF%B8%8F-hardened-opsec--security-protocols)
13. [Credits](#-credits)
14. [License & Project Status](#%EF%B8%8F-license--project-status)
15. [Star History](#-star-history)

---

## 🔍 Overview & Architecture

This repository contains a lightweight but highly capable **agentic orchestration runtime** built primarily in **Bash**, with **PHP** where a local web control surface provides better ergonomics, and **zero Node.js dependencies** (browser automation is handled via a pure Bash stateless WebSocket engine).

Unlike dependency-bloated framework stacks, **AI Pipeline** stays close to the operating system, easy to audit, and practical to run on constrained or privacy-sensitive environments. It parses user intent, ingests local file context, queries local or external backends, executes recursive tool-calling loops, manages persistent Markdown memory, and can close multimodal feedback loops through screenshots and browser automation.

The most important point is this: the project does not merely describe agentic capabilities — it already exercises them. The same runtime that powers this assistant can read files, browse documentation, execute tools, inspect outputs, and reorganize its own persistent memory autonomously inside its workspace.

### 🏛️ Modular Decoupled Architecture (v1.0.0)

To guarantee absolute modularity and system-wide extensibility, version **v1.0.0** implements a clean partition between the core transport library and interactive visualization clients. This follows the **UNIX Philosophy**: separate backend cognitive logic from frontend rendering layers. This ensures a single source of truth (`core`) can power our terminal client (`cli`), our local web interface (A.I.D.E. Web), or headless network security daemons (Cerberus).

```
                      ┌─────────────────────────────────────────┐
                      │             Static Registries           │
                      │  (config/models.json, providers.json)   │
                      └────────────────────┬────────────────────┘
                                           │
                                           ▼
                      ┌─────────────────────────────────────────┐
                      │              core.sh                    │
                      │       (Sovereign Cognitive Core)        │
                      └────────────────────┬────────────────────┘
                                           │
                    ┌──────────────────────┴──────────────────────┐
                    ▼                                             ▼
          ┌────────────────────┐                        ┌──────────────────┐
          │    cli.sh          │                        │  web/server.php  │
          │ (Interactive CLI)  │                        │  (A.I.D.E. Web)  │
          ├────────────────────┤                        ├──────────────────┤
          │ - Sourcing library │                        │ - SSE Streaming  │
          │ - Input loop       │                        │ - Telemetry HUD  │
          │ - Slash commands   │                        │ - Live Markdown  │
          │ - ANSI & Spinner   │                        │ - Custom Scratch │
          └────────────────────┘                        └──────────────────┘
```

#### ⚙️ The Sovereign Cognitive Core (`core.sh`)

An agnostic, non-interactive library and execution runner. It houses static registry management (`providers.json`/`models.json`), the military-grade **Sovereign Key Chest** (ChaCha20 + PBKDF2), zero-touch configuration sourcing (`.conf` overrides), dynamic Markdown-based memory bootstrapping, outbound OPSEC transports, heuristic multi-intent routing, and dual-tooling execution loops. It can be executed in headless run-once automation flows or sourced securely.

#### 💬 The Interactive Terminal Portal (`cli.sh`)

The dedicated terminal companion. Sourcing `core.sh` at boot, it hosts robust session loops, captures and parses slash commands (such as `/keys` and `/replay`), renders immersive cyberpunk styling, and isolates real-time reasoning streams (`thinking_tokens`) inside dedicated visual blocks.

#### ⚙️ The Tool Execution Bridge (`tools.sh`)

The operational middleware between model-declared capabilities and concrete host actions. `tools.sh` parses JSON arguments, dispatches functions safely, normalizes execution patterns, and bridges `tools.json` schemas to real filesystem, shell, web, and browser actions.

### Workflow & Intent Routing

```
                          ┌────────────────────────┐
                          │   User Prompt + Files  │
                          └───────────┬────────────┘
                                      │
                                      ▼
                          ┌────────────────────────┐
                          │  Intent-Based Routing  │
                          └───────────┬────────────┘
                                      │
             ┌────────────────────────┼────────────────────────┐
             ▼                        ▼                        ▼
     ┌──────────────┐         ┌──────────────┐         ┌──────────────┐
     │   QUESTION   │         │   COMPARE    │         │     TASK     │
     └──────┬───────┘         └──────┬───────┘         └──────┬───────┘
            │                        │                        │
            ▼                        ▼                        ▼
  ┌──────────────────┐    ┌───────────────────┐    ┌──────────────────┐
  │ Chat Completion  │    │ Side-by-Side Diff │    │ Consensual Loop  │
  │  & Tool-Calling  │    │     Analysis      │    │ Architect/Coder/ │
  │       Loop       │    │                   │    │      Judge       │
  └──────────────────┘    └───────────────────┘    └──────────────────┘
```

When an inquiry is made in **Pipeline Mode**, the **Intent Router** classifies it:
1. **QUESTION**: Direct questions or explanations about files. For the `external` backend, this triggers an automated Tool Execution loop with `tools.sh` until the model decides it has gathered enough information to produce a final answer.
2. **COMPARE**: Automated identification of structural, functional, or logical differences between two context files.
3. **TASK**: Actionable, code-generating edits. Triggers a structured multi-agent flow: **Architect** → **Coder** → **Judge**.

---

## ⚡ Why AI Pipeline Is Different

- **Bash-first by design, not by nostalgia**: Bash is used as a serious orchestration runtime, not as a gimmick.
- **Local-first and sovereignty-minded**: local backends, Tor routing, encrypted provider keys, and explicit ZDR controls are first-class concerns.
- **Real tool loop, not fake function-calling theater**: model-declared capabilities are executed concretely through `tools.sh`, then fed back into the reasoning loop.
- **Multimodality with operational purpose**: screenshots, browser automation, and visual reinjection are used for auditing, debugging, and self-correction — not marketing decoration.
- **Adaptive runtime behavior**: backend, provider, model, memory strategy, and hardware constraints all shape execution dynamically.
- **Polyglot where it matters**: Bash handles orchestration, JavaScript handles live browser control, and PHP handles lightweight local web UX — each language is used where it is strongest.
- **Actually usable as a runtime, not just a concept**: the framework already powers real reading, tooling, memory consolidation, and autonomous workspace interaction.

---

## ✨ Key Capabilities

### Core Differentiators
- 🧠 **Sovereign Cognitive Runtime**: A real agentic execution loop built around `core.sh`, not a thin API wrapper.
- 💬 **Dedicated Human Interface Layer**: `cli.sh` is a real interactive terminal client, not just a launcher.
- ⚙️ **Executable Tool Middleware**: `tools.sh` transforms declarative tool schemas into concrete local actions with structured parsing and practical safeguards.
- 🧠 **Cognitive Freedom Memory Engine**: Native Markdown-based persistent memory that the assistant can inspect, reorganize, and consolidate autonomously.
- 🌀 **Autonomous Memory Consolidation**: Heartbeat-driven context compression and memory restructuring to prevent token bloat and amnesia.
- 👁️ **Operational Multimodality**: Vision is integrated for actual work — screenshots, OCR-style understanding, UI auditing, and visual feedback reinjection.
- 🌐 **Active and Passive Web Intelligence**:
  - `web_fetch` for high-fidelity retrieval
  - `web_browse` for live browser interaction, screenshots, and JS-aware auditing
- 🔒 **Privacy & Sovereignty Tooling**: Tor routing, ZDR payload injection, encrypted provider keys, and local-first backend support.
- 🔁 **Adaptive Hardware / Backend Routing**: Execution adapts to RAM, CPU, Termux constraints, backend type, and provider behavior.
- 🧬 **Polyglot without bloat**: Bash + PHP, each used where it has a concrete structural advantage.

### Security, Reliability & Runtime Upgrades
- 🔑 **Sovereign Key Chest (ChaCha20 + PBKDF2)**: A zero-dependency local key chest using **ChaCha20 + PBKDF2** with **500,000 iterations** via native OpenSSL. It auto-generates a 256-bit random master key (`key.dat` in `chmod 600`) and encrypts individual provider keys (`keys/<provider>.key`), ensuring absolute local security. Keys are decrypted on-the-fly directly in RAM and never written to disk in cleartext.
- 📱 **Hardware-Adaptive PBKDF2 Scaling**: On Android/Termux, the key chest automatically halves the PBKDF2 iterations to ensure instantaneous execution and prevent mobile CPU thermal throttling.
- 🧙‍♂️ **Interactive Key Wizard (`/keys` / `--keys`)**: A user-friendly console wizard (`manage_keys` and `interactive_key_setup`) with masked inputs (`read -rs`) and direct provider console URLs to configure or update keys securely.
- 🔍 **Credentials Pre-Flight Checks**: Automatically intercepts missing credentials at startup. If a provider key is missing, it dynamically triggers the interactive setup wizard on-the-fly during active chat sessions.
- ⏳ **Groq Rate-Limiter Retry Loop**: Intercepts Groq's TPM/RPM/TPD rate limit errors, extracts compound wait times, converts them into safe delays, and retries automatically.
- 🛡️ **Refined Zero-Fork Sandboxing**: Upgraded system-level boundaries in `tools.sh` to anchor patterns to `${SCRIPT_DIR}/`, eliminating false positives while maintaining protection of active production scripts.
- 💳 **Credit Balance HUD**: Real-time remaining credit balance display in `SYSTEM METRICS` HUD (integrated with Vercel AI Gateway, CyberNeurova and OpenRouter).
- 🔄 **Interactive `/replay` Command**: Instantly resends the last user message using a lightweight, zero-fork in-memory `LAST_USER_MSG` state.
- 🎨 **Sleek Terminal UI**: High-intensity ANSI color flows, contextual icons, themed execution headers, and dynamic ASCII art banners with fallbacks.
- 📐 **Pixel-Perfect Auto-Sizing Terminal Headers**: Visual alignment logic that accounts for wide emojis and narrow mobile terminals.
- 💭 **AI Cognitive Reasoning Extraction**: Native parsing and styling of LLM reasoning blocks (`thinking_tokens`) prior to final outputs.
- 📊 **Real-Time Token Metrics & Cost**: Automatic reporting of prompt, response, cached, and reasoning tokens with cost visibility.
- 🔄 **Operational Multi-Agent Task Consensus**: Architect → Coder → Judge orchestration with safe code output saved to `<input_file>.new`.
- 🧹 **Interactive Cache Sweep & Control**: Dynamic memory scrubbing menus for active chat logs and long-term memory structures.
- ⚡ **High-Performance "Single-jq Stream" runner**: Zero-subshell parameter parsing, pure-Bash URL decoding, and compact single-process JSON streaming inside `tools.sh`, significantly reducing process-fork overhead.
- 🚀 **Hardware-Aware Adaptive Tuning**: Dynamic host CPU detection with conservative allocation policies, especially on Termux/mobile environments.
- 💾 **Flash Memory Wear-Reduction**: Runtime payload fragments and buffers are relocated to volatile RAM storage (`/tmp` or `$TMPDIR`) to protect mobile flash storage.
- ⚡ **Optimized Local Server Orchestration**: On-the-fly startup and tuning of local PHP, `llama-server`, and Ollama services.
- 🌐 **`web_fetch` Smart Routing**: Domain-specific Bash routing for GitHub, GitLab, Wikipedia, Codeberg, and SourceHut with robust fallbacks and no Node.js dependency.
- 🌐 **`web_browse` Live Browser Automation**: Pure Bash CDP-based browsing, screenshots, PDFs, form interaction, console capture, and Tor SOCKS5 proxy support (completely Node-free).
- 🔍 **Tor-Based Anonymous Web Search**: Onion-routed DuckDuckGo search queries filtered into structured JSON with `htmlq`.
- 🛠️ **Agentic Function Calling**: Models can dynamically request filesystem, shell, web, and browser actions.
- 🛡️ **Universal HTTP 400 Payload Immunization**: Strict `jq --rawfile` encapsulation plus output sanitization to protect external backends from malformed JSON crashes.
- ⚡ **Complete JQ E2BIG / ARG_MAX Immunization**: Universal protection against Unix argument length crashes through file-streamed `jq` payload assembly.
- 🧹 **Automatic Signal-Trap & Cleanup**: Native `trap`-driven cleanup of temporary buffers on `EXIT`, `INT`, and `TERM`.
- 🧅 **Tor Proxy Support**: Outbound connections to external APIs route through a local Tor daemon SOCKS5 proxy for privacy.
- 📂 **Interactive File and Image Loading**: `/load <file>` and `/unload` commands support text injection and base64-encoded image context.
- 🔌 **Decoupled API Provider Registry**: Endpoints, default models, and ZDR options are centralized in `config/providers.json`.
- ⚡ **Single-Fork JQ Registry Reading**: Endpoint URLs, models, and ZDR options are loaded via one optimized `jq` process.
- 🐘 **Mammouth AI Native Integration**: First-class support for Mammouth AI as a European-sovereign provider.
- 👁️ **Multimodal Vision Integration & Vision Autoload**: Local and cloud vision model compatibility with multimodal projector support. Cloud auto-vision routing dynamically selects capable models via meta-routers (`openrouter/auto` for paid, `openrouter/free` for free tiers).
- 🌀 **Autonomous Visual Feedback Loop**: Tool-generated visual assets are intercepted, encoded, and fed back into context automatically.
- ⚙️ **Dynamic Model Parameter Middleware Registry**: Sampling parameters are decoupled into `config/models.json` and injected on-the-fly.
- 🔌 **Adaptive Keep-Alive Strategy**: Dynamic model keep-alive periods for chat warmth vs task-mode resource economy.
- 🚀 **System Fork Reduction**: Bash parameter expansion replaces avoidable external helpers like `basename`.
- 🧳 **Zero Python Bloat**: Built around standard Unix utilities, Bash, `curl`, `jq`, `sed`, and `awk`.

---

## 📂 Core Files

| File | Description |
| :--- | :--- |
| [`core.sh`](core.sh) | **Sovereign Cognitive Core (v1.4.0)**: Agnostic, non-interactive engine and library. Manages dynamic Markdown-based memory bootstrapping, enforces OPSEC transports/Tor/ZDR routing, and orchestrates the **Sovereign Key Chest** (ChaCha20 + PBKDF2). |
| [`cli.sh`](cli.sh) | **Interactive Terminal Client (v1.2.3)**: Dedicated user-interactive terminal portal. Sources `core.sh`, handles persistent session chat loops, multi-line user inputs, slash commands (including `/keys`, `/replay`, `/provider`, and `/model`), and isolates model reasoning streams. |
| [`tools.sh`](tools.sh) | **Execution Runner (v0.4.1)**: Highly optimized zero-subshell tool handler. Bridges `tools.json` schemas to real host actions, eliminates the `wc -l` subprocess fork in `read_file`, and enforces practical runtime safeguards. |
| [`web-fetch.sh`](tools/web-fetch.sh) | **Smart Web Crawler Engine (v0.4.1)**: Domain-specific fetch engine returning clean Markdown with zero Node.js dependency. |
| [`web-browse.sh`](tools/web-browse.sh) | **Stateless Browser Automation (v0.0.3)**: Pure Bash one-shot Chrome DevTools Protocol (CDP) engine with zero Node.js dependencies, SOCKS5 proxying, form interaction, screenshots, and PDFs. |
| [`tools.json`](tools/tools.json) | **Declaration Schemas**: Formal tool definitions for the full-function calling surface. |
| [`tools-groq.json`](tools/tools-groq.json) | **Groq Schema Adaptation**: Specialized schema file adapted to Groq's stricter validation behavior. |
| [`tools-light.json`](tools/tools-light.json) | **Lightweight Schemas**: Simplified tool contract for smaller local models. |
| [`config/models.json`](config/models.json) | **Models Registry**: Centralized model and sampling parameter registry. |
| [`config/providers.json`](config/providers.json) | **Providers Registry**: Centralized endpoint, default model, and ZDR registry. |

---

## 💬 Interactive Chat Mode (Default)

Running `./cli.sh` launches the high-fidelity interactive **Chat Mode**. Sourcing the `core.sh` library behind the scenes, it initializes conversational context, loads bootstrapped long-term memory, and hosts the persistent session loop.

### 🗺️ Built-in Slash Commands

During the chat session, you can invoke control actions using slash prefixes:

| Command | Action |
| :--- | :--- |
| `/help` | Prints a guide showing all available interactive commands. |
| `/clear` | Cleans up pipeline memory by wiping the active session history and `LAST_USER_MSG` cache. |
| `/commit` | Manually triggers the Cognitive Heartbeat Pacemaker, consolidating learnings to Markdown memory and pruning active contexts. |
| `/keys` | Launches the interactive **Sovereign Key Chest Manager** to configure, update, or purge encrypted API keys. |
| `/replay` | Instantly resends the last user message using a zero-fork in-memory variable. |
| `/draw [ratio] [prompt]` | Generates visual assets (experimental stub - coming soon!). |
| `/provider <name>` | Change the active provider during the chat session. |
| `/model <name>` | Change the active model during the chat session. |
| `/load <file>` | Loads a text or image file into the active chat session. |
| `/unload` | Unloads the previously loaded file from the active chat session context. |
| `/run <cmd>` | Executes standard shell commands directly from within the chat loop. |
| `/start` | Escapes the standard conversational loop to query a pipeline prompt with file contexts interactively. |
| `/quit` | Exits the chat loop and returns to the system shell. |

---

## 🛠️ Tool-Calling Engine (Agentic Capability)

The pipeline integrates 11 standard agentic actions declared in `tools/tools.json`. When the model returns a tool request, `core.sh` parses it and spawns `tools.sh` with the extracted arguments before feeding the results back.

1. **`read_file`**: Reads partial or full contents of any file, with optional line ranges and line-number prefixing.
2. **`file_glob_search`**: Recursively discovers files using customized include/exclude patterns.
3. **`grep_search`**: Regex search across a file or directory tree.
4. **`exec_shell_command`**: Runs shell instructions within a 10 seconds timeout.
   - 🔒 *Built-in security*: blocks attempts to execute active core pipeline files.
5. **`write_file`**: Writes or overwrites files and creates parent directories dynamically.
6. **`edit_file`**: Performs surgical multi-line replacement, deletion, or insertion.
7. **`apply_diff`**: Applies unified Git-format diffs.
8. **`get_datetime`**: Retrieves the system date and time.
9. **`web_search`**: Anonymous DuckDuckGo search over Onion routes with structured JSON output.
10. **`web_fetch`**: Smart Markdown fetcher with domain-specific routing and robust fallbacks.
11. **`web_browse`**: Pure Bash stateless Chrome DevTools Protocol (CDP) browser automation for navigation, typing, clicking, screenshots, PDFs, and JS evaluation (completely Node-free).

---

## 🤖 Supported Backends & Configured Models

You can configure the active engine inside `core.sh` by modifying the `BACKEND` variable (`ollama`, `llamacpp`, or `external`).

### 1. **External API Gateway (`external`)** [Default]
- **Configuration file**: managed through `config/providers.json`.
- **Default Active Providers**:
  - **Groq**: `https://api.groq.com/openai/v1/chat/completions`
  - **Vercel AI Gateway (Free + Paid)**: `https://ai-gateway.vercel.sh/v1/chat/completions`
  - **Venice AI**: `https://api.venice.ai/api/v1/chat/completions`
  - **OpenAI**: `https://api.openai.com/v1/chat/completions`
  - **OpenRoute**: `https://openroute.cyberneurova.com/v1/chat/completions`
  - **OpenRouter (Free + Paid)**: `https://openrouter.ai/api/v1/chat/completions`
  - **Mammouth AI**: `https://api.mammouth.ai/v1/chat/completions`
  - **CyberNeurova**: `https://api.cyberneurova.ai/v1/chat/completions`
  - **DeepSeek**: `https://api.deepseek.com/chat/completions`
- **Default Active Model**: `google/gemini-3.5-flash` (Vercel/OpenRouter) -- See default model in `[providers.json](config/providers.json)`.
- **Features**: dynamic config loading, provider-aware payload mutation, reasoning fallbacks, tool schemas, and secure Tor integration.
  - 🔒 **DeepSeek ZDR Limitation**: DeepSeek does not support Zero Data Retention. No server-side privacy shield is available for this provider.
  - 🔒 **Venice AI ZDR Limitation**: Venice AI does not support server-side ZDR injection. When using Venice, manually disable telemetry in `Settings → General → Disable Telemetry Collection` to approximate zero-data-retention.
  - 🔒 **OpenRouter Free-Tier Vision Trade-off**: Free multimodal vision on OpenRouter cannot be combined with `data_collection: "deny"` (zero prompt-training). To keep free vision functional, **image requests drop the `deny` shield** (prompt training may apply to images only); all text/tool turns keep `deny`. Paid OpenRouter (`openrouter/auto`) and Vercel (`disallowPromptTraining: true`) preserve the shield across all modalities.

### 2. **Ollama (`ollama`)**
- **Inference Endpoint**: `http://localhost:11434/v1/chat/completions`
- **Configured Stack**:
  - **Router**: `hf.co/LiquidAI/LFM2.5-1.2B-Instruct-GGUF`
  - **Vision**: `hf.co/LiquidAI/LFM2.5-VL-1.6B-GGUF`
  - **Architect / Reasoning / Chat**: `hf.co/LiquidAI/LFM2.5-1.2B-Thinking-GGUF`
  - **Coder**: `hf.co/ggml-org/Ministral-3-3B-Reasoning-2512-GGUF`
  - **Judge / Analyst**: `hf.co/ggml-org/Ministral-3-3B-Reasoning-2512-GGUF`

### 3. **llama.cpp (`llamacpp`)**
- **Inference Endpoint**: `http://localhost:8080/v1/chat/completions`
- **Configured Stack**:
  - **Router**: `LiquidAI/LFM2.5-1.2B-Instruct-GGUF`
  - **Vision**: `LiquidAI/LFM2.5-VL-1.6B-GGUF`
  - **Architect / Reasoning / Chat**: `LiquidAI/LFM2.5-1.2B-Thinking-GGUF`
  - **Coder**: `ggml-org/Ministral-3-3B-Reasoning-2512-GGUF`
  - **Judge / Analyst**: `ggml-org/Ministral-3-3B-Reasoning-2512-GGUF`

---

## 🖥️ Unified Local Server Modes

The pipeline introduces integrated **Server hosting capabilities**, letting you boot up companion servers easily via `--server [type]` or the `server [type]` command synonym.

### 1. Unified Local Web Server (`web`)
Launches the integrated high-concurrency PHP server (`web/server.php`) to host local documentation, status boards, and dashboards.
- **Command**: `./core.sh server web` *(or `./core.sh --server web`)*
- **Endpoint**: `http://localhost:8000`

### 2. High-Performance `llama.cpp` Server (`llamacpp`)
Launches a dynamically tuned instance of native `llama-server`.
- **Features**:
  - automatic thread allocation balancing
  - memory-aware KV cache quantization
  - safe model auto-loading
  - `jinja` template support
- **Command**: `./core.sh server llamacpp` *(or `./core.sh --server llamacpp`)*
- **Endpoint**: `http://localhost:8080`

### 3. Local Ollama Server Daemon (`ollama`)
Boots an optimized Ollama daemon with keep-alive and quantization-aware defaults.
- **Command**: `./core.sh server ollama` *(or `./core.sh --server ollama`)*
- **Endpoint**: `http://localhost:11434`

---

## ⚙️ Prerequisites & Installation

### Core Utilities
Ensure you have standard system packages installed:

```bash
# Debian / Ubuntu / Mint
sudo apt update && sudo apt install -y curl jq awk sed tor glow cargo openssl
cargo install htmlq

# macOS (Homebrew)
brew install jq sed glow tor htmlq openssl awk

# Arch Linux
sudo pacman -Syu curl jq sed tor glow openssl awk
# htmlq can be installed via AUR (e.g. paru -S htmlq) or Cargo:
cargo install htmlq

# Android / Termux
pkg install curl jq sed glow cargo-binstall openssl awk
cargo-binstall htmlq
```

> [!TIP]
> The Tor proxy can be provided by several apps on Android. For what it is worth, one practical option is **[InviZible Pro](https://play.google.com/store/apps/details?id=pan.alexander.tordnscrypt.gp)**.

## 🔑 Sovereign Key Chest Configuration

To initialize, configure, or update your encrypted provider API keys, use the specialized CLI command:

```bash
./cli.sh --keys
# OR
./cli.sh init
```

The system will guide you and encrypt keys locally in `keys/<provider>.key` using **ChaCha20 + PBKDF2**.

*Note: for backward compatibility, the pipeline still falls back to the legacy plain-text `~/.creds` file if no encrypted key is found.*

---

## 🚀 Usage Guide

The pipeline supports both **standard double-dash flags** and **implicit command synonyms**.

### A. Chat Mode (Default interactive stream)
```bash
./cli.sh
```

### B. Privacy-Enforced ZDR Mode
```bash
./cli.sh --zdr
```

### C. Pipeline Mode (With command arguments)
```bash
./core.sh "<prompt/instructions>" [input-file-1] [input-file-2]
```

#### Multi-Mode and Simple-Mode Switches
- `--simple` or `simple`: bypasses complex agent pipeline processes.
  ```bash
  ./core.sh --simple "Summarize this log file" tools.log
  # OR:
  ./core.sh simple "Summarize this log file" tools.log
  ```
- `--multi` or `multi`: triggers the three-stage multi-agent consensus routing block (Architect → Coder → Judge).

### D. Clean Memory Store
```bash
./cli.sh clear
```

### E. Manual Cognitive Consolidation
```bash
./cli.sh commit
```

### F. Unified Local Server Mode
```bash
./core.sh server ollama
./core.sh server llamacpp
./core.sh server web
```

### G. Dynamic Context Switches & Parameter Overrides
```bash
# Switch to another model in Chat Mode
./cli.sh model "google/gemini-3.1-pro"

# Switch provider
./cli.sh provider openrouter

# Specify custom listen interface/port for Ollama or llama-server
./core.sh -l "127.0.0.1:8080" server llamacpp
```

### H. Modular Configuration Sourcing
`core.sh` automatically detects and loads custom configurations from `${SCRIPT_DIR}/config/${SCRIPT_NAME}.conf` (e.g. `config/core.conf` if executed as `core.sh`). This keeps private API keys, hostnames, and model assignments modular and isolated out of Git.

---

## 🧠 Cognitive Freedom Memory Engine

With the release of version **v0.7.0**, the pipeline transitioned from JSON and database formats to a native, UNIX-philosophical **Markdown-based memory filesystem**.

### 1. Structural Files (`data/memory/`)
Memory is divided into clean, human-readable, version-controllable Markdown documents:
- **`01_identity.md`**: Core persona, AI parameters, name (`Jarvis`), and philosophical alignment.
- **`02_collaborator_profile.md`**: Developer preferences, IT experience, security focus, and OPSEC guidelines.
- **`03_system_architecture.md`**: Active backends, CPU allocation guidelines, and tooling files.
- **`04_milestones.md`**: Chronological ledger of engineering triumphs and validated fixes.
- **`05_roadmap.md`**: Strategic roadmap for active and upcoming development phases.
- **`06_important_rules.md`**: Golden rules, security guidelines, and development boundaries.

> [!NOTE]
> The exact structure may differ depending on the active model and memory organization strategy.

### 2. Dynamic Bootstrapping (`bootstrap_memory`)
At startup, `core.sh` executes `bootstrap_memory()`, loops through all Markdown files under `data/memory/`, wraps them with boundary markers (`--- File: path ---`), and injects them into the active system instructions payload.

### 3. Subconscious Memory Consolidation (Pacemaker)
Controlled by the `HEARTBEAT_THRESHOLD` (default: 10 user messages):
- when the counter hits the limit, `core.sh` triggers a consolidation cycle
- the AI enters a subconscious state and reviews conversation history
- it updates `data/memory/` using standard file tools (`write_file`, `edit_file`)
- once it returns `[CONSOLIDATION_COMPLETE]`, the cycle exits
- `data/messages.json` is then pruned to retain only the last 2 turns

---

## 🛡️ Hardened OPSEC & Security Protocols

The framework is architected with a production-grade security focus for privacy-sensitive and restricted environments.

- **Localhost-Only Boundaries**: API servers (`llamacpp`, `ollama`, and PHP `web`) listen on `127.0.0.1` by default.
- **Directory Traversal / LFI Prevention**: file parameters and workspace paths are validated against safe boundaries.
- **Onion-Routed Privacy Tunnel**: outbound cloud API requests route through Tor SOCKS5 proxy tunnel.
- **Zero-Data Retention (ZDR) Injection**: privacy payloads are dynamically appended for compatible external providers.
- **Terminal Payload Immunization**: `iconv` and strict `jq --rawfile` streams protect APIs and models from malformed outputs.
- **ShellCheck Clean Codebase**: sourced scripts are kept ShellCheck clean to reduce avoidable shell hazards.

---

## 👥 Credits

This pipeline is forged under deep iteration and synergistic design:

- **Lead Developer / Architect**: **Jiab77**
- **AI Sorcerer & Co-Creator**: **Jarvis (Gemini)**

---

## ⚖️ License & Project Status

- **Project Phase**: Core Engine Stabilized, Hardened & Production-Ready (v1.4.0).
- **Next Roadmap Milestones (v2.0.0 - A.I.D.E. Web & CLI Modernization)**:
  - 🌐 **A.I.D.E. Web**: local-first responsive web dashboard served by `web/server.php`
  - 🎨 **Visual UI Modernization (`charmbracelet/gum`)**: richer CLI interactions with graceful fallbacks
  - 🛡️ **Cognitive Router & Proxy (CRP) Gateway**: local OpenAI-compatible endpoint backed by Jarvis memory injection and Tor + ZDR routing
  - 🎨 **Conversational Image Generation (Output Modalities)**: base64-encoded images generated through standard `/chat/completions` output flows

---

## 📈 Star History

<a href="https://www.star-history.com/?repos=jiab77%2Fai-pipeline&type=date&legend=top-left">
  <picture>
    <source media="(prefers-color-scheme: dark)" srcset="https://api.star-history.com/chart?repos=jiab77/ai-pipeline&type=date&theme=dark&legend=top-left" />
    <source media="(prefers-color-scheme: light)" srcset="https://api.star-history.com/chart?repos=jiab77/ai-pipeline&type=date&legend=top-left" />
    <img alt="Star History Chart" src="https://api.star-history.com/chart?repos=jiab77/ai-pipeline&type=date&legend=top-left" />
  </picture>
</a>
