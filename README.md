# 🚀 Minimalist Experimental AI Pipeline

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)
[![Bash Shell](https://img.shields.io/badge/Shell-Bash-4EAA25.svg?logo=gnu-bash&logoColor=white)](https://www.gnu.org/software/bash/)
[![Backend Supported](https://img.shields.io/badge/Backends-Ollama%20%7C%20llama.cpp%20%7C%20OpenRouter-orange.svg)]()
[![Status](https://img.shields.io/badge/Status-Experimental--WIP-blue.svg)]()

> A lightweight, highly extensible Bash-driven orchestration framework for interacting with local LLMs (via **Ollama** or **llama.cpp**) and external API backends (via **OpenRouter / Gemini 3.5 Flash**). Features fully integrated parallel tool-calling capabilities and structured, persistent JSON-based memory.

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
10. [Pipeline Memory & State Logging](#%EF%B8%8F-pipeline-memory--state-logging)
11. [Credits](#-credits)
12. [Project Status & License](#-project-status--license)

---

## 🔍 Overview & Architecture

This repository contains a minimalist, high-performance design of an *agentic LLM orchestration loop* written entirely in **Bash**. 

Unlike heavy, dependency-bloated Python frameworks, this implementation is exceptionally rapid, contains zero bloated virtual environments, and is easy to audit. It parses user intent, extracts structural context from external files, queries backends of your choice, implements recursive tool-calling (function calling) natively in Bash, and manages long-term chat and profile memory across interaction sessions.

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
1. **QUESTION**: Direct questions or explanations about files. For the `gemini` backend, this triggers an automated Tool Execution loop with `run-tools.sh` until the model decides it has gathered enough answers to output a final reply.
2. **COMPARE**: Automated identification of structural, functional, or logical differences between two context files.
3. **TASK**: Actionable, code-generating edits. Triggers a structured, multi-agent consensus flow of three specialized models: **Architect** (drafts a logic plan) &rarr; **Coder** (generates pure source code modifications) &rarr; **Judge** (performs validation and regression checks).

---

## ✨ Key Capabilities

- 💬 **Interactive Chat Loop**: Features a fully immersive, conversational terminal flow powered by persistent JSON state history.
- 🎨 **Sleek & Immersive Aesthetic Shell UI**: Integrated in **v0.4.0**. Powered by high-intensity ANSI color flows, contextual thematic icons, gorgeous execution headers (`User`, `Jarvis`, `Thinking`, and `Tool Call` headers), and dynamic ASCII art banners generated via `figlet` with smart text-based fallbacks.
- 🧠 **Cognitive Heartbeat Pacemaker**: Dynamic background consolidation. Automatically tracks message lengths and executes active context compression into long-term structures once a threshold is met (default: 15 messages), pruning active logs cleanly to maintain high performance with zero amnesia.
- 💭 **AI Cognitive Reasoning Extraction**: Native parsing and styling of internal LLM critical-thinking blocks (`thinking_tokens`) in **v0.4.0**, displayed in dedicated, beautiful cognitive terminal frames prior to yielding final outputs.
- 📊 **Real-Time Token Metrics & Operational Cost**: Automatically computes and outputs itemized query usage stats after every run in **v0.4.0** (Prompt, Response, Cached, and Reasoning tokens) along with precise operational API costing in USD.
- 🔄 **Fully Operational Multi-Agent Task Consensus**: Completed in **v0.4.0** for Gemini. Features robust 3-stage consensus pipeline orchestration (Architect 🏛️ drafts precise plans &rarr; Coder 💻 generates clean compliant codebase modifications &rarr; Judge ⚖️ validates syntax and executes regression QA) with safe code output saved to `<input_file>.new` to guarantee absolute codebase security.
- 🧹 **Interactive Cache Sweep & Control**: Provides options-driven dynamic memory scrubbing in **v0.4.0** with interactive step-by-step menus to selectively wipe Long-Term profile behaviors (`memory.json`), Chat conversation logs (`messages.json`), or execute a master-clear on both.
- ⚡ **High-Performance "Single-jq Stream" runner**: Zero-subshell parameter parsing, pure-Bash URL-decoding, and compact single-process JSON token streaming inside `run-tools.sh` v0.2.1, achieving up to 10x process-fork reduction and reducing tool latency significantly.
- 🖥️ **Unified Local Server Orchestration**: Launches optimized companion services on-the-fly. Boot up a local multi-threaded PHP dashboard to inspect files and documentations, or deploy a surgically configured `llama-server` tuned with dynamic thread mapping, KV-quantization limits, and auto-loading templates.
- 🌐 **web_fetch (Smart Router) Tool Routing**: Highly optimized Bash domain routing (`web_fetch.sh`) supporting instant API-based scraping (GitHub, GitLab, and Wikipedia summaries), falling back elegantly to raw regex tag-stripping or `htmlq` over Tor socks5h to completely prevent heavy browser runtime bloat.
- 🔍 **Tor-Based Anonymous Web Search**: Secure, fully-parsed, zero-subshell Onion DuckDuckGo lookup queries executed directly over SOCKS5 proxying to fetch clean search listings using `htmlq`.
- 🛠️ **Agentic Function Calling**: Fully conforms to advanced JSON schemas. The Gemini and OpenRouter models can dynamically request to probe directory trees, read lines of files, modify lines of code, write files, perform search lookups, fetch raw web documents, or execute sandboxed shell commands.
- 🛡️ **Universal HTTP 400 Payload Immunization**: 100% strict `jq --rawfile` encapsulation of assistant and chronological conversation logs in `pipeline.sh` **v0.4.0**, paired with robust dual-tier binary and special-character encoding filters (`iconv + jq`) on tool outputs to fully secure external backends against malformed JSON crashes.
- ⚡ **Complete JQ E2BIG / ARG_MAX Immunization**: Universal protection against Unix `ARG_MAX` ("Argument list too long") memory limit crashes across all backend execution paths. Implemented via raw file-streaming pipeline variables with `jq --rawfile` streams instead of command-line string interpolation, safeguarding the pipeline on highly constrained mobile/Termux environments.
- 🧹 **Automatic Signal-Trap & Cleanup**: Zero-leak guarantee. Utilizes native UNIX `trap` signaling on `EXIT`, `INT`, and `TERM` signals to instantly clean up all temporary buffer files (`tmp_*`) and standard execution streams, ensuring absolute workspace hygiene even during abrupt process interruptions.
- ⏱️ **Zero-Fork Speedups & Micro-Benchmarks**: Verified via our upgraded test harness, which benchmarks pure-Bash parameter stream processing and zero-subshelled operations to achieve a verified **up to 1.72x performance speed-up** compared to standard execution methods.
- 🧅 **Tor Proxy Support**: Outbound connections to `openrouter.ai` can automatically be routed over a local Tor daemon SOCKS5 proxy (`socks5h://127.0.0.1:9050`) using custom User-Agents for secure, private, and geo-independent requests.
- 💾 **Structured JSON Memory**: Keeps a running context of your conversation in `data/messages.json` and persistent user/system profile rules in `data/memory.json`.
- 🤖 **Local-First & Hybrid Approach**: Switch seamlessly between local inference servers (Ollama, llama.cpp running on GPU/CPU machines) and highly optimized cloud APIs (Google Gemini via OpenRouter).
- 🧳 **Zero Python Bloat**: Built purely on system binaries like standard GNU Unix utilities, `curl`, `jq`, and `bash`.

---

## 📂 Core Files

| File | Description |
| :--- | :--- |
| [`pipeline.sh`](pipeline.sh) | **Core Orchestrator (v0.4.0)**: Manages arguments (both flags and seamless command synonyms), parses intent, builds robust payloads, runs interactive sessions with unified aesthetic headers & real-time token/cost metrics, handles server-hosting modes, issues requests to Ollama/llama.cpp/OpenRouter, and manages memory with complete robust JQ payload immunization. |
| [`run-tools.sh`](run-tools.sh) | **Execution Runner (v0.2.1)**: Highly optimized zero-subshell tool handler. Double-optimized for zero forks and strict macOS / Bash 3.2 compatibility, parsing payload arguments securely into system operations. |
| [`web_fetch.sh`](web_fetch.sh) | **Smart Web Crawler Engine**: Employs domain-specific API endpoints (GitHub, GitLab, Wikipedia) falling back cleanly to raw regex or `htmlq` over Tor, returning clean, high-fidelity Markdown. |
| [`tools.json`](tools.json) | **Declaration Schemas**: Formally defines structural rules, tool descriptions, and parameters for Function Calling (matching the OpenRouter model spec). |

---

## 💬 Interactive Chat Mode (Default)

Running `pipeline.sh` without any arguments starting a prompt (or explicitly with the `--chat` option or command synonym `chat`) launches the interactive **Chat Mode**. 

The system initializes your conversational profile and displays a standard prompt. Communication is continuous, meaning the AI remembers all questions and answers previously sent during the session!

### 🗺️ Built-in Slash Commands

During the chat session, you can invoke special control actions using slash prefixes:

| Command | Action |
| :--- | :--- |
| `/help` | Prints a guide showing all available interactive commands. |
| `/clear` | Cleans up the pipeline memory by wiping the session history and user files inside the `data/` directory. |
| `/commit` | Manually triggers the Cognitive Heartbeat Pacemaker, consolidating outstanding learnings/milestones to `memory.json` and pruning active contexts. |
| `/run <cmd>` | Native shell-escape. Executes standard shell commands instantly from within the chat loop, delivering raw output inline. |
| `/start` | Escapes the standard conversational loop to query a pipeline prompt with file contexts interactively. |
| `/quit` | Exits the chat loop and returns to your system shell. |

---

## 🛠️ Tool-Calling Engine (Agentic Capability)

The pipeline integrates 10 standard agentic actions declared in `tools.json`. When the model returns a tool request, `pipeline.sh` parses it and spawns `run-tools.sh` with the extracted arguments before feeding the results back.

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
10. **`web_fetch`**: Smart Markdown scraper routing requests through Tor. Features zero-fork domain-specific API scraping for GitHub, GitLab, and Wikipedia, plus robust raw regex fallbacks and `htmlq` extraction to completely bypass heavy browser overhead.

---

## 🤖 Supported Backends & Configured Models

You can configure the active engine inside `pipeline.sh` by modifying the `BACKEND` variable (`ollama`, `llamacpp`, or `gemini`).

### 1. **Gemini / OpenRouter (`gemini`)** [Default]
* **Inference Endpoint**: `https://openrouter.ai/api/v1/chat/completions`
* **Default Model**: `google/gemini-3.5-flash`
* **Features**: Direct support for system prompts, official JSON tool specifications, reasoning capability toggles, and Tor integration.

### 2. **Ollama (`ollama`)**
* **Inference Endpoint**: `http://localhost:11434`
* **Configured Stack**:
  * **Router**: `hf.co/LiquidAI/LFM2.5-1.2B-Instruct-GGUF`
  * **Architect / Reasoning**: `hf.co/LiquidAI/LFM2.5-1.2B-Thinking-GGUF`
  * **Coder**: `hf.co/Qwen/Qwen2.5-Coder-1.5B-Instruct-GGUF`
  * **Judge / Analyst**: `hf.co/Qwen/Qwen2.5-Coder-3B-Instruct-GGUF`

### 3. **llama.cpp (`llamacpp`)**
* **Inference Endpoint**: `http://localhost:8080/v1/chat/completions` (Standard Server)
* **Configured Stack**:
  * **Router**: `LiquidAI/LFM2.5-1.2B-Instruct-GGUF`
  * **Architect / Reasoning**: `LiquidAI/LFM2.5-1.2B-Thinking-GGUF`
  * **Coder**: `Qwen/Qwen2.5-Coder-1.5B-Instruct-GGUF`
  * **Judge / Analyst**: `Qwen/Qwen2.5-Coder-3B-Instruct-GGUF`

---

## 🖥️ Unified Local Server Modes

The pipeline introduces integrated **Server hosting capabilities** in version **0.3.0**, letting you boot up companion servers easily via `--server [type]` or the `server [type]` command synonym.

### 1. Unified Local Web Server (`web`)
Launches the integrated, high-concurrency multi-threaded PHP server (`web/server.php`) to host user-facing documentation, interactive status boards, and responsive system resource dashboards with zero external dependencies.
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
*(Under Active Development / Coming Soon)* Designed to provide unified management and orchestration of the background Ollama daemon API natively.

---

## ⚙️ Prerequisites & Installation

### Core Utilities
Ensure you have standard system packages installed:
```bash
# Debian / Ubuntu / Mint
sudo apt update && sudo apt install -y curl jq tor glow cargo
cargo install htmlq

# macOS (Homebrew)
brew install jq glow tor htmlq

# Arch Linux
sudo pacman -Syu curl jq tor glow
# htmlq can be installed via AUR (e.g. paru -S htmlq) or Cargo:
cargo install htmlq

# Android / Termux
pkg install curl jq glow cargo-binstall
cargo-binstall htmlq
```

> [!TIP]
> The TOR proxy can be provided by several apps on Android. For what it worth, I'm using __[InviZible Pro](https://play.google.com/store/apps/details?id=pan.alexander.tordnscrypt.gp)__.

### Authorization (For Gemini/OpenRouter API)
Save your OpenRouter API Key inside a private file.
```bash
echo "your-openrouter-api-key-here" > ~/.creds
chmod 600 ~/.creds
```

### Running Backend Services (When using Local Inference)

#### Option A: Ollama Service
Ensure Ollama daemon is running, then enable model pulling in `pipeline.sh` (`PULL_MODELS=true`) or pull manually.

#### Option B: llama.cpp Server
Spawn your local `llama-server` on port `8080` loaded with your active GGUF models.

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

### B. Pipeline Mode (With command arguments)
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

### C. Clean Memory Store
Clear cached chat history and profile structures:
```bash
./pipeline.sh --clear
# OR:
./pipeline.sh clear
```

### D. Manual Cognitive Consolidation
Force immediate session context compression and memory syncing:
```bash
./pipeline.sh --commit
# OR:
./pipeline.sh commit
```

### E. Unified Local Server Mode
Launch an optimized companion server instance:
```bash
./pipeline.sh server web       # Deploy local PHP documentation/dashboard server
./pipeline.sh server llamacpp  # Deploy the high-performance CPU/GPU llama-server
```

---

## 🧠 Pipeline Memory & State Logging

The pipeline's active memory and automated housekeeping are divided inside the `data/` subdirectory:

1. **`data/messages.json`**: An array of objects keeping the chronological sequence of active conversation logs. The orchestrator reconstructs your full interaction history on every new query, allowing realistic back-and-forth communication.
2. **`data/memory.json`**: A deep, persistent JSON-based profile memory containing long-term achievements/milestones, technical stacks, user guidelines, configurations, and future roadmaps.
3. **🧠 Cognitive Heartbeat Pacemaker (Housekeeping)**: Controlled by the `HEARTBEAT_THRESHOLD` variable (default: `15`).
   - When active messages in `messages.json` reach the threshold, the orchestrator triggers an automatic, background, lossless consolidation process.
   - It invokes the active reasoning LLM to synthesize fresh developments (accomplishments, stack additions, roadmaps) directly into `data/memory.json`.
   - It then prunes `data/messages.json`, preserving only the foundational system prompt and the **4 most recent messages** to guarantee seamless flow with a feather-light context window.
   - This process can also be triggered manually using either the `/commit` slash command inside interactive mode or the `--commit` CLI option.

---

## 👥 Credits

This pipeline is forged under deep iteration and synergistic design:

* **Lead Developer / Architect**: **Jiab77**
* **AI Sorcerer & Co-Creator**: **Jarvis (Gemini)**

---

## ⚖️ License & Project Status

* **Project Phase**: Experimental Work-in-Progress (WiP).
* **Next Roadmap Milestones**: Generalizing Route C (Task Mode) consensus blocks to support fully-local workflows (Ollama & llama.cpp), and integrating `charmbracelet/gum` for a next-generation visual terminal experience with elegant fallback support for progressive visual CLI inputs and selections.
* **License**: Released under the terms of the **MIT License**. See [LICENSE](LICENSE) for details.

---

## 📈 Star History

<a href="https://www.star-history.com/?repos=jiab77%2Fai-pipeline&type=date&legend=top-left">
  <picture>
    <source media="(prefers-color-scheme: dark)" srcset="https://api.star-history.com/chart?repos=jiab77/ai-pipeline&type=date&theme=dark&legend=top-left" />
    <source media="(prefers-color-scheme: light)" srcset="https://api.star-history.com/chart?repos=jiab77/ai-pipeline&type=date&legend=top-left" />
    <img alt="Star History Chart" src="https://api.star-history.com/chart?repos=jiab77/ai-pipeline&type=date&legend=top-left" />
  </picture>
</a>
