# 🚀 Minimalist Experimental AI Pipeline

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)
[![Bash Shell](https://img.shields.io/badge/Shell-Bash-4EAA25.svg?logo=gnu-bash&logoColor=white)](https://www.gnu.org/software/bash/)
[![Backend Supported](https://img.shields.io/badge/Backends-Ollama%20%7C%20llama.cpp%20%7C%20Vercel%20%7C%20OpenRouter-orange.svg)]()
[![Status](https://img.shields.io/badge/Status-Stable--v0.8.0-blue.svg)]()

> A lightweight, highly extensible Bash-driven orchestration framework for interacting with local LLMs (via **Ollama** or **llama.cpp**) and external API backends (via **Vercel AI Gateway / OpenRouter / Gemini 3.5 Flash**). Features fully integrated parallel tool-calling capabilities, a secure Onion-routed Tor tunnel, and an autonomous, native Markdown-based memory architecture.

---

## 📖 Table of Contents
1. [Overview & Architecture](#-overview--architecture)
2. [Key Capabilities](#-key-capabilities)
3. [Core Files](#-core-files)
4. [Interactive Chat Mode (Default)](#-interactive-chat-mode-default)
5. [Tool-Calling Engine (Agentic Capability)](#%EF%B8%8F-tool-calling-engine-agentic-capability)
6. [Supported Backends & Configured Models](#-supported-backends--configured-models)
7. [Unified Local Server Modes](#-unified-local-server-modes)
8. [Prerequisites & Installation](#%EF%B8%8F-prerequisites--installation)
9. [Usage Guide](#-usage-guide)
10. [Cognitive Freedom Memory Engine](#%EF%B8%8F-cognitive-freedom-memory-engine)
11. [Credits](#-credits)
12. [Project Status & License](#-project-status--license)

---

## 🔍 Overview & Architecture

This repository contains a minimalist, high-performance design of an *agentic LLM orchestration loop* written entirely in **Bash**.

Unlike heavy, dependency-bloated Python frameworks, this implementation is exceptionally rapid, contains zero bloated virtual environments, and is easy to audit. It parses user intent, extracts structural context from external files, queries backends of your choice, implements recursive tool-calling (function calling) natively in Bash, and manages long-term behavior and profile memory across interaction sessions using a native, human-readable filesystem.

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
1. **QUESTION**: Direct questions or explanations about files. For the `external` backend, this triggers an automated Tool Execution loop with `run-tools.sh` until the model decides it has gathered enough answers to output a final reply.
2. **COMPARE**: Automated identification of structural, functional, or logical differences between two context files.
3. **TASK**: Actionable, code-generating edits. Triggers a structured, multi-agent consensus flow of three specialized models: **Architect** (drafts a logic plan) &rarr; **Coder** (generates pure source code modifications) &rarr; **Judge** (performs validation and regression checks).

---

## ✨ Key Capabilities

- 💬 **Interactive Chat Loop**: Features a fully immersive, conversational terminal flow powered by persistent chat history and deep profile memory.
- 🧠 **Cognitive Freedom Memory Engine (v0.7.0)**: Pure, native, and modular Markdown-based memory architecture. Deprecates and removes legacy SQLCipher (`memory.db`) and flat JSON (`memory.json`) backends, achieving zero-overhead execution, absolute portability, and 100% compliance with the UNIX philosophy.
- 🌀 **Subconscious Memory Consolidation (v0.7.0)**: Fully autonomous memory reorganization. When active turns reach `HEARTBEAT_THRESHOLD` (default: 10), the AI enters a subconscious cycle, receives a system directive to analyze history, and uses its standard file editing tools (`write_file`, `edit_file`) on `data/memory/` files to consolidate technical stacks, goals, accomplishments, and collaborator profiles. Once complete, active logs are pruned to the last 2 turns, eliminating token bloat and preventing amnesia.
- 🔒 **Zero Data Retention (ZDR) Privacy Shield (v0.7.0)**: Outbound cloud API requests routed to Vercel AI Gateway or OpenRouter can be conditionally forced to enforce strict ZDR rules via the `--zdr` flag. It dynamically injects `zeroDataRetention: true` (Vercel) or `zdr: true` (OpenRouter) inside API payloads using lightweight `jq` filters, offering perfect flexibility to gracefully bypass Vercel Hobby-tier paywall limitations.
- 🎨 **Sleek Aesthetic Terminal UI**: Powered by high-intensity ANSI color flows, contextual thematic icons, gorgeous execution headers (`User`, `Jarvis`, `Thinking`, and `Tool Call` headers), and dynamic ASCII art banners generated via `figlet` with smart text-based fallbacks.
- 📐 **Pixel-Perfect Auto-Sizing Terminal Headers**: Fully adjusts visual borders by intelligently replacing double-column wide character emojis with corresponding visual weights and filtering out zero-width Unicode variation selectors (`️`). Coupled with a `-1` column safe-zone padding to 100% prevent forced wrapping artifacts or line overflow bugs on narrow mobile scopes (e.g. Termux on Android).
- 💭 **AI Cognitive Reasoning Extraction**: Native parsing and styling of internal LLM critical-thinking blocks (`thinking_tokens`), displayed in dedicated, beautiful cognitive terminal frames prior to yielding final outputs.
- 📊 **Real-Time Token Metrics & Cost**: Automatically computes and outputs itemized query usage stats after every run (Prompt, Response, Cached, and Reasoning tokens) along with precise operational API costing in USD.
- 🔄 **Fully Operational Multi-Agent Task Consensus**: Orchestrates a robust 3-stage consensus pipeline (Architect 🏛️  drafts precise plans &rarr; Coder 💻 generates clean compliant codebase modifications &rarr; Judge ⚖️  validates syntax and executes regression QA) with safe code output saved to `<input_file>.new` to guarantee absolute codebase security.
- 🧹 **Interactive Cache Sweep & Control**: Provides options-driven dynamic memory scrubbing with interactive step-by-step menus to selectively wipe the active Chat conversation logs (`messages.json`), reset long-term memory structures, or execute a master-clear on both.
- ⚡ **High-Performance "Single-jq Stream" runner**: Zero-subshell parameter parsing, pure-Bash URL-decoding, and compact single-process JSON token streaming inside `run-tools.sh` v0.3.0, achieving up to 10x process-fork reduction, implementing parallel null-delimited tool stream parsing, and reducing tool latency significantly.
- 🚀 **Hardware-Aware Adaptive Tuning**: Dynamically detects host CPU topologies (compatible with `nproc`, macOS `sysctl`, and Android/Termux `/proc/cpuinfo`), automatically cutting thread allocations in half on Termux to prevent mobile CPU throttling and battery overheating.
- 💾 **Flash Memory Wear-Reduction**: Refactored in **v0.6.0**. Migrated all runtime payload fragments and tool buffers directly to the OS volatile RAM storage `/tmp` (or `$TMPDIR` dynamically under Termux), safeguarding the physical solid-state flash memory of mobile devices from high-frequency write cycles.
- ⚡ **Optimized Local Server Orchestration**: On-the-fly execution and automatic, low-overhead tuning for local inference servers. Start a native PHP companion web server, a surgically tuned `llama-server`, or a lightweight `ollama serve` instance initialized with dynamic keep-alive structures, hardware-optimized quantizations, and active flash-attention mechanisms.
- 🌐 **web_fetch (Smart Router) Tool Routing (v0.2.0)**: Highly optimized Bash domain routing (`web-fetch.sh`) supporting instant API-based scraping (GitHub, GitLab subgroups & standard repos, Wikipedia summaries, Codeberg, and SourceHut native routers), falling back elegantly to raw regex tag-stripping or `htmlq` over Tor socks5h to completely prevent heavy browser runtime bloat. Free of NodeJS dependencies.
- 🌐 **web_browse (Premium JS Automation) (v0.0.1)**: Production-grade Puppeteer browser pilot (`tools/web-browse/web-browse.js`) for active headless browser automation (capturing console logs, page exceptions, screenshots, PDFs, and interactive clicks/types). Features environment-adaptive profiles (CachyOS vs. Termux ARM64) and robust, secure Tor HTTP proxy routing. Equipped with a standard Node.js shebang and execution permissions, allowing the pipeline to automatically fallback to `web_fetch` or custom shell commands if Node.js is missing.
- 🔍 **Tor-Based Anonymous Web Search**: Secure, fully-parsed, zero-subshell Onion DuckDuckGo lookup queries executed directly over SOCKS5 proxying to fetch clean search listings using `htmlq`.
- 🛠️ **Agentic Function Calling**: Fully conforms to advanced JSON schemas. The Gemini and OpenRouter models can dynamically request to probe directory trees, read lines of files, modify lines of code, write files, perform search lookups, fetch raw web documents, or execute sandboxed shell commands.
- 🛡️ **Universal HTTP 400 Payload Immunization**: 100% strict `jq --rawfile` encapsulation of assistant and chronological conversation logs in `pipeline.sh`, paired with robust dual-tier binary and special-character encoding filters (`iconv + jq`) on tool outputs to fully secure external backends against malformed JSON crashes.
- ⚡ **Complete JQ E2BIG / ARG_MAX Immunization**: Universal protection against Unix `ARG_MAX` ("Argument list too long") memory limit crashes across all backend execution paths. Implemented via raw file-streaming pipeline variables with `jq --rawfile` streams instead of command-line string interpolation, safeguarding the pipeline on highly constrained mobile/Termux environments.
- 🧹 **Automatic Signal-Trap & Cleanup**: Zero-leak guarantee. Utilizes native UNIX `trap` signaling on `EXIT`, `INT`, and `TERM` signals to instantly clean up all temporary buffer files (`tmp_*`) and standard execution streams, ensuring absolute workspace hygiene even during abrupt process interruptions.
- ⏱️ **Zero-Fork Speedups & Micro-Benchmarks**: Verified via our upgraded test harness, which benchmarks pure-Bash parameter stream processing and zero-subshelled operations to achieve a verified **up to 1.72x performance speed-up** compared to standard execution methods.
- 🧅 **Tor Proxy Support**: Outbound connections to external APIs are routed over a local Tor daemon SOCKS5 proxy (`socks5h://127.0.0.1:9050`) using custom User-Agents for secure, private, and geo-independent requests.
- 📂 **Interactive File and Image Loading (v0.8.0)**: State-of-the-art interactive loading via `/load <file>` and `/unload` commands in Chat Mode. Supports text context injection (elegantly formatted inside markdown code blocks with syntax highlighting) and base64-encoded image payloads directly inside active conversation windows.
- 👁️ **Multimodal Vision Integration & Vision Autoload (v0.8.0)**: Seamless local and cloud vision model compatibility (e.g. `LiquidAI/LFM2.5-VL-1.6B-GGUF`), auto-loading text weights paired with multimodal projector `.gguf` profiles.
- 🌀 **Autonomous Visual Feedback Loop (v0.8.0)**: Also known as the *Sensory Feedback Loop*. When an agentic tool generates a visual asset (such as standard Puppeteer screenshots), the pipeline automatically intercepts it, encodes it, and feeds it back into the active context stream for the next turn, enabling fully autonomous visual validation without manual intervention.
- ⚙️ **Dynamic Model-Dependent Parameters Middleware Registry (v0.8.0)**: Completely decouples sampling parameters (`temperature`, `top_k`, `repetition_penalty`, `min_p`) into a centralized JSON registry (`config/models.json`) that are dynamically parsed and injected into request payloads on-the-fly.
- 🔌 **Adaptive Keep-Alive Strategy (v0.8.0)**: Dynamically adjusts model keep-alive periods on local servers based on active execution modes (`10m` for conversational chat warmth, `5s` for task pipeline execution to prevent RAM-thrashing and OOM failures on resource-constrained devices).
- ⚡ **Fork-Free Listen Interface Parsing (v0.8.0)**: Eradicated external process forks by introducing pure, ultra-fast Bash parsing and reconstruction of host:port server addresses.
- 🚀 **Eradication of System Forks (v0.8.0)**: High-performance Bash parameter expansion (`${FILE##*/}`) completely replaces slow external `basename` calls, ensuring rapid, fork-free execution on constrained environments (such as Android Termux on mobile or Intel Atom N100 PCs).
- 🧳 **Zero Python Bloat**: Built purely on system binaries like standard GNU Unix utilities, `curl`, `jq`, `sed`, `awk`, and `bash`.

---

## 📂 Core Files

| File | Description |
| :--- | :--- |
| [`pipeline.sh`](pipeline.sh) | **Core Orchestrator (v0.8.0)**: Handles argument routing, parses intent, builds robust payloads, runs interactive sessions with unified aesthetic headers & real-time token/cost metrics, hosts local servers, manages dynamic memory bootstrap, and executes recursive agentic tool calls with absolute payload immunization. Supports interactive file/image loading, autonomous visual feedback loops, and dynamic parameters middleware. |
| [`run-tools.sh`](run-tools.sh) | **Execution Runner (v0.3.0)**: Highly optimized zero-subshell tool handler. Double-optimized for zero forks, parallel null-delimited tool stream parsing, and strict macOS / Bash 3.2 compatibility, parsing payload arguments securely into system operations. |
| [`web-fetch.sh`](tools/web-fetch.sh) | **Smart Web Crawler Engine (v0.2.0)**: Employs domain-specific API endpoints (GitHub standard & raw, GitLab nested subgroups/raw routing, Codeberg & SourceHut native routers, Wikipedia summaries) falling back cleanly to raw regex or `htmlq` over Tor, returning clean, high-fidelity Markdown. Free of NodeJS dependencies. |
| [`web-browse.js`](tools/web-browse/web-browse.js) | **Interactive Browser Automation (v0.0.1)**: Premium Puppeteer-core pilot script for active JS-rendering, clicking, typing, console/exception capturing, and visual screenshots/PDFs. Optimized for standard workstations and Termux ARM64. |
| [`tools.json`](tools/tools.json) | **Declaration Schemas**: Formally defines structural rules, tool descriptions, and parameters for 11-tool Function Calling (matching the external cloud model spec). |
| [`tools-light.json`](tools/tools-light.json) | **Declaration Schemas**: Simplified 7-tool schema (`read_file`, `write_file`, `file_glob_search`, `get_datetime`, `web_search`, `web_fetch`, `web_browse`) optimized for local-first small models. |

---

## 💬 Interactive Chat Mode (Default)

Running `pipeline.sh` without any arguments starting a prompt (or explicitly with the `--chat` option or command synonym `chat`) launches the interactive **Chat Mode**.

The system initializes your conversational profile and displays a standard prompt. Communication is continuous, meaning the AI remembers all questions and answers previously sent during the session!

### 🗺️  Built-in Slash Commands

During the chat session, you can invoke special control actions using slash prefixes:

| Command | Action |
| :--- | :--- |
| `/help` | Prints a guide showing all available interactive commands. |
| `/clear` | Cleans up the pipeline memory by wiping the active session history. |
| `/commit` | Manually triggers the Cognitive Heartbeat Pacemaker, consolidating outstanding learnings/milestones to the Markdown memory and pruning active contexts. |
| `/load <file>` | Loads a text or image file into the active chat session (injects text files as syntax-highlighted code blocks or base64-encodes images for vision queries). |
| `/unload` | Unloads the previously loaded file from the active chat session context. |
| `/run <cmd>` | Native shell-escape. Executes standard shell commands instantly from within the chat loop, delivering raw output inline. |
| `/start` | Escapes the standard conversational loop to query a pipeline prompt with file contexts interactively. |
| `/quit` | Exits the chat loop and returns to your system shell. |

---

## 🛠️ Tool-Calling Engine (Agentic Capability)

The pipeline integrates 11 standard agentic actions declared in `tools/tools.json`. When the model returns a tool request, `pipeline.sh` parses it and spawns `run-tools.sh` with the extracted arguments before feeding the results back.

1. **`read_file`**: Reads partial or full contents of any file. Supports custom line indices (1-indexed start/end lines) and prefixes output lines with their line numbers for precise target selection.
2. **`file_glob_search`**: Recursively discovers files using customized include/exclude patterns up to a depth of 10 directories.
3. **`grep_search`**: Powerful regex search across a single file or an entire directory tree.
4. **`exec_shell_command`**: Runs general shell instructions within a default 10-second timeout.
   - 🔒 *Built-in security*: Actively prevents execution loops on the orchestrator script itself (refuses actions containing `pipeline.sh`).
5. **`write_file`**: Writes or overwrites files and dynamically creates the parent directory hierarchy.
6. **`edit_file`**: Surgical multi-line replacement, deletions, or insertions.
   - ⚡ *Index integrity protection*: Parses instruction blocks and processes them in reverse line order so that editing lines earlier in the file doesn't break line alignment of subsequent edits.
7. **`apply_diff`**: Applies unified differences in standard Git format, useful for complex or multi-file edits.
8. **`get_datetime`**: Retrieves the system date and time, providing real-time situational awareness.
9. **`web_search`**: High-fidelity, anonymous DuckDuckGo search queries executed across Onion routes using local Tor/SOCKS5 connections and cleanly filtered into structural JSON with `htmlq`. Zero-subshell architecture ensuring security and confidentiality.
10. **`web_fetch`**: Smart Markdown scraper routing requests through Tor. Features zero-fork domain-specific API scraping for GitHub, GitLab, Codeberg, SourceHut and Wikipedia, plus robust raw regex fallbacks and `htmlq` extraction to completely bypass heavy browser overhead. Free of NodeJS dependencies.
11. **`web_browse`**: Premium browser automation tool powered by Puppeteer. Allows Jarvis to launch a headless browser, navigate pages, click buttons, input text, evaluate JS, and take screenshots/PDFs. Equipped with robust OPSEC Tor routing by default and an automatic command shebang fallback to `web_fetch` or custom shell commands if Node.js is missing.

---

## 🤖 Supported Backends & Configured Models

You can configure the active engine inside `pipeline.sh` by modifying the `BACKEND` variable (`ollama`, `llamacpp`, or `external`).

### 1. **External API Gateway (`external`)** [Default]
* **Inference Endpoints**:
  * **Vercel AI Gateway (Default Provider)**: `https://ai-gateway.vercel.sh/v1/chat/completions` (Highly optimized routing)
  * **OpenRouter**: `https://openrouter.ai/api/v1/chat/completions`
* **Default Model**: `google/gemini-3.5-flash`
* **Features**: Direct support for system prompts, official JSON tool specifications, reasoning capability toggles, and Tor integration.

### 2. **Ollama (`ollama`)**
* **Inference Endpoint**: `http://localhost:11434/v1/chat/completions` (Highly optimized local server)
* **Configured Stack**:
  * **Router**: `hf.co/LiquidAI/LFM2.5-1.2B-Instruct-GGUF`
  * **Vision**: `hf.co/LiquidAI/LFM2.5-VL-1.6B-GGUF`
  * **Architect / Reasoning / Chat**: `hf.co/LiquidAI/LFM2.5-1.2B-Thinking-GGUF`
  * **Coder**: `hf.co/ggml-org/Ministral-3-3B-Reasoning-2512-GGUF`
  * **Judge / Analyst**: `hf.co/ggml-org/Ministral-3-3B-Reasoning-2512-GGUF`

### 3. **llama.cpp (`llamacpp`)**
* **Inference Endpoint**: `http://localhost:8080/v1/chat/completions` (Highly optimized local server)
* **Configured Stack**:
  * **Router**: `LiquidAI/LFM2.5-1.2B-Instruct-GGUF`
  * **Vision**: `LiquidAI/LFM2.5-VL-1.6B-GGUF`
  * **Architect / Reasoning / Chat**: `LiquidAI/LFM2.5-1.2B-Thinking-GGUF`
  * **Coder**: `ggml-org/Ministral-3-3B-Reasoning-2512-GGUF`
  * **Judge / Analyst**: `ggml-org/Ministral-3-3B-Reasoning-2512-GGUF`
---

## 🖥️  Unified Local Server Modes

The pipeline introduces integrated **Server hosting capabilities** in version **0.3.0**, letting you boot up companion servers easily via `--server [type]` or the `server [type]` command synonym.

### 1. Unified Local Web Server (`web`)
Launches the integrated, high-concurrency multi-threaded PHP server (`web/server.php`) to host user-facing documentation, status boards, and responsive system resource dashboards with zero external dependencies.
* **Command**: `./pipeline.sh server web`  *(or `./pipeline.sh --server web`)*
* **Endpoint**: `http://localhost:8000`

### 2. High-Performance `llama.cpp` Server (`llamacpp`)
Launches a dynamically tuned instance of native `llama-server`. It's engineered specifically for performance-constrained hosts (mobile Termux, tiny laptops) but scales brilliantly.
* **Features**:
  - Automatic thread allocation balancing (`--threads` tuned to half of total system cores).
  - Memory-mapped quantization on key-value caches (`-ctk` & `-ctv` dynamically fitted to `q8_0`).
  - Safe model auto-loading (`--models-autoload` with max 1 concurrent model loaded).
  - Enhanced syntax compiler with complete `jinja` templates support.
* **Command**: `./pipeline.sh server llamacpp`  *(or `./pipeline.sh --server llamacpp`)*
* **Endpoint**: `http://localhost:8080`

### 3. Local Ollama Server Daemon (`ollama`)
Boot up a highly optimized background Ollama daemon process tuned to utilize Flash Attention, quantized key-value caches matching system quantization profiles, and configured keep-alive timeouts to automatically unload models when idle.
* **Command**: `./pipeline.sh server ollama`  *(or `./pipeline.sh --server ollama`)*
* **Endpoint**: `http://localhost:11434`

---

## ⚙️  Prerequisites & Installation

### Core Utilities
Ensure you have standard system packages installed:
```bash
# Debian / Ubuntu / Mint
sudo apt update && sudo apt install -y curl jq sed tor glow cargo
cargo install htmlq

# macOS (Homebrew)
brew install jq sed glow tor htmlq

# Arch Linux
sudo pacman -Syu curl jq sed tor glow
# htmlq can be installed via AUR (e.g. paru -S htmlq) or Cargo:
cargo install htmlq

# Android / Termux
pkg install curl jq sed glow cargo-binstall
cargo-binstall htmlq
```

> [!TIP]
> The TOR proxy can be provided by several apps on Android. For what it worth, I'm using __[InviZible Pro](https://play.google.com/store/apps/details?id=pan.alexander.tordnscrypt.gp)__.

### Authorization (For OpenRouter API and Vercel AI Gateway)
Save your OpenRouter / Vercel API Key inside a private file.
```bash
echo "your-openrouter-or-vercel-api-key-here" > ~/.creds
chmod 600 ~/.creds
```

### Running Backend Services (When using Local Inference)

#### Option A: Ollama Service
Spwan your local `ollama` server on port `11434` loaded with model auto-routing enabled.

#### Option B: llama.cpp Server
Spawn your local `llama-server` on port `8080` loaded with model auto-routing enabled.

> [!NOTE]
> Required local models will be pulled automatically.

---

## 🚀 Usage Guide

The pipeline supports both **standard double-dash flags** and **implicit command synonyms** everywhere, offering maximal CLI flexibility.

### A. Chat Mode (Default interactive stream)
Launch the fully-remembered chat mode simply:
```bash
./pipeline.sh
# OR explicitly:
./pipeline.sh --chat
# OR using the command synonym:
./pipeline.sh chat
```

### B. Privacy-Enforced ZDR Mode
Launch with Zero Data Retention (ZDR) policy enforced on external cloud endpoints (Vercel and OpenRouter):
```bash
./pipeline.sh --zdr
# Or combined with chat synonym:
./pipeline.sh chat --zdr
```

### C. Pipeline Mode (With command arguments)
```bash
./pipeline.sh "<prompt/instructions>" [input-file-1] [input-file-2]
```

#### Multi-Mode and Simple-Mode Switches
- `--simple` or `simple`: Bypasses complex agent pipeline processes, querying the active model in one straightforward interaction.
  ```bash
  ./pipeline.sh --simple "Summarize this log file" run-tools.log
  # OR:
  ./pipeline.sh simple "Summarize this log file" run-tools.log
  ```
- `--multi` or `multi`: For complex tasks, triggers the heavy, three-stage multi-agent consensus routing block (Architect 🏛️ &rarr; Coder 💻 &rarr; Judge ⚖️) to design, code, and inspect proposed file modifications before generating output.

### D. Clean Memory Store
Clear cached chat history:
```bash
./pipeline.sh --clear
# OR:
./pipeline.sh clear
```

### E. Manual Cognitive Consolidation
Force immediate session context compression and memory syncing:
```bash
./pipeline.sh --commit
# OR:
./pipeline.sh commit
```

### F. Unified Local Server Mode
Launch an optimized companion server instance:
```bash
./pipeline.sh server ollama    # Deploy already optimized CPU/GPU ollama server
./pipeline.sh server llamacpp  # Deploy already optimized high-performance CPU/GPU llama-server
./pipeline.sh server web       # Deploy local PHP documentation/dashboard server
```

### G. Dynamic Context Switches & Parameter Overrides
Override your default model, provider, or server listen interface directly via flags at runtime:
```bash
# Switch to another model in Chat Mode
./pipeline.sh --model "google/gemini-2.5-pro" chat

# Switch provider
./pipeline.sh --provider "openrouter" chat

# Specify custom listen interface/port for Ollama or llama-server
./pipeline.sh -l "127.0.0.1:8080" server llamacpp
```

### H. Modular Configuration Sourcing
`pipeline.sh` automatically detects and loads custom configurations from `${SCRIPT_DIR}/config/${SCRIPT_NAME}.conf` (e.g. `config/pipeline.conf` if executed as `pipeline.sh`). This allows zero-touch, seamless upgrades of the pipeline while keeping your private API keys, custom hostnames, and model assignments 100% modular and isolated out of Git.

---

## 🧠 Cognitive Freedom Memory Engine

With the release of version **v0.7.0**, the pipeline completely transitioned from JSON and database formats to a native, UNIX-philosophical **Markdown-based memory filesystem**.

### 1. Structural Files (`data/memory/`)
Memory is divided into clean, human-readable, and version-controlled Markdown documents:
- **`01_identity.md`**: Core persona, AI parameters, name (`Jarvis`), and philosophical alignment.
- **`02_collaborator_profile.md`**: Developer preferences, IT experience, security focus, and dual-identity OPSEC guidelines.
- **`03_system_architecture.md`**: Overview of active backends, CPU allocation guidelines, and active tooling files.
- **`04_milestones.md`**: Chronological ledger of historical engineering triumphs, validated fixes, and released versions.
- **`05_roadmap.md`**: Strategic strategic roadmap for active and upcoming development phases.
- **`06_important_rules.md`**: Golden rules, security guidelines, and development boundaries.

> [!NOTE]
> The structure may be different depending on the active model.

### 2. Dynamic Bootstrapping (`bootstrap_memory`)
At startup, `pipeline.sh` executes the `bootstrap_memory()` routing function. It dynamically loops through all Markdown files under `data/memory/`, formats them with clean XML boundary markers (`--- File: path ---`), and merges them directly into the active system instructions payload. This provides the LLM with instant, zero-latency situational awareness of everything built, configured, and preferred.

### 3. Subconscious Memory Consolidation (Pacemaker)
Controlled by the `HEARTBEAT_THRESHOLD` (default: 10 user messages).
- When the message counter hits the limit, `pipeline.sh` automatically pauses and spawns a background consolidation cycle.
- The AI enters a **subconscious state** and is prompted to review the active conversation history.
- It is instructed to use standard file editing tools (`write_file`, `edit_file`) on files under `data/memory/` to integrate any new milestones, preferences, profile updates, or roadmap shifts.
- Once the AI writes its memories and returns the keyword `[CONSOLIDATION_COMPLETE]`, the cycle exits.
- The orchestrator prunes `data/messages.json` to retain **only the last 2 turns** (last 4 message payloads), shrinking context size to zero-overhead while maintaining perfect behavior and long-term retention.

---

## 👥 Credits

This pipeline is forged under deep iteration and synergistic design:

* **Lead Developer / Architect**: **Jiab77**
* **AI Sorcerer & Co-Creator**: **Jarvis (Gemini)**

## ⚖️ License & Project Status

* **Project Phase**: Core Engine Stabilized & Production-Ready (v0.8.0).
* **Next Roadmap Milestones (v0.9.0)**:
  * 🌐 **Jarvis Web Command Center (JWCC)**: Build the local-first, responsive web dashboard served by `web/server.php` in Obsidian Dark Theme. It will feature 6 core tabs: Jarvis Speak (real-time SSE streaming chat node), Cognitive Freedom Explorer (live Markdown editing and explorer of skills/memories), Telemetry HUD (live CPU/RAM/Battery/Thermal metrics), Action Panel, Cognitive Ingestion Hub, and MacGyver Scratchpad.
  * 🎨 **Visual UI Modernization (`charmbracelet/gum`)**: Integrate Gum-driven progressive CLI selections, beautiful interactive spinners, inputs, and styled multi-line text boxes with robust, zero-overhead fallbacks to standard pure-Bash read loops for non-interactive / SSH terminals.
  * 🛡️ **Cognitive Router & Proxy (CRP) Gateway**: Expose an OpenAI-compliant server endpoint (`/v1/chat/completions`) locally using our PHP server. It will inject our bootstrapped Cognitive Freedom memories and parameters on-the-fly, allowing IDE extensions and CLI clients (like Charmbracelet's `crush` or `mods`) to query Jarvis securely, routing all traffic through our Tor + ZDR privacy tunnel.
  * 🎨 **Conversational Image Generation (Output Modalities)**: Parse and output base64-encoded user-interface components, charts, and custom schemas generated dynamically by OpenRouter or Vercel AI Gateway using standard `/chat/completions` with `"modalities": ["text", "image"]`.

## 📈 Star History

<a href="https://www.star-history.com/?repos=jiab77%2Fai-pipeline&type=date&legend=top-left">
  <picture>
    <source media="(prefers-color-scheme: dark)" srcset="https://api.star-history.com/chart?repos=jiab77/ai-pipeline&type=date&theme=dark&legend=top-left" />
    <source media="(prefers-color-scheme: light)" srcset="https://api.star-history.com/chart?repos=jiab77/ai-pipeline&type=date&legend=top-left" />
    <img alt="Star History Chart" src="https://api.star-history.com/chart?repos=jiab77/ai-pipeline&type=date&legend=top-left" />
  </picture>
</a>
