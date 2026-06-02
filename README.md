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
7. [Prerequisites & Installation](#%EF%B8%8F-prerequisites--installation)
8. [Usage Guide](#-usage-guide)
9. [Pipeline Memory & State Logging](#%EF%B8%8F-pipeline-memory--state-logging)
10. [Credits](#-credits)
11. [Project Status & License](#-project-status--license)

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
     │   QUESTION   │         │   COMPARE    │         │  TASK (WIP)  │
     └──────┬───────┘         └──────┬───────┘         └──────┬───────┘
            │                        │                        │
            ▼                        ▼                        ▼
  ┌──────────────────┐    ┌──────────────────┐    ┌──────────────────┐
  │ Chat Completion  │    │ Side-by-Side Diff│    │ Consensual Loop  │
  │  & Tool-Calling  │    │     Analysis     │    │Architect/Coder/  │
  │       Loop       │    │                  │    │      Judge       │
  └──────────────────┘    └──────────────────┘    └──────────────────┘
```

When an inquiry is made in **Pipeline Mode**, the **Intent Router** classifies it:
1. **QUESTION**: Direct questions or explanations about files. For the `gemini` backend, this triggers an automated Tool Execution loop with `run-tools.sh` until the model decides it has gathered enough answers to output a final reply.
2. **COMPARE**: Automated identification of structural, functional, or logical differences between two context files.
3. **TASK**: (WIP) Actionable, code-generating edits. Triggers a structured consensus flow of three specialized models: **Architect** (drafts a logic plan) $\rightarrow$ **Coder** (generates pure source code modifications) $\rightarrow$ **Judge** (performs validation / regression checks).

---

## ✨ Key Capabilities

- 💬 **Interactive Chat Loop**: Features a fully immersive, conversational terminal flow powered by persistent JSON state history.
- 🧠 **Cognitive Heartbeat Pacemaker**: Dynamic background consolidation. Automatically tracks message lengths and executes active context compression into long-term structures once a threshold is met (default: 15 messages), pruning active logs cleanly to maintain high performance with zero amnesia.
- 🔍 **Tor-Based Anonymous Web Search**: Secure, fully-parsed, zero-subshell Onion DuckDuckGo lookup queries executed directly over SOCKS5 proxying to fetch clean search listings using `htmlq`.
- 🛠️ **Agentic Function Calling**: Fully conforms to advanced JSON schemas. The Gemini and OpenRouter models can dynamically request to probe directory trees, read lines of files, modify lines of code, write files, perform search lookups, or execute sandboxed shell commands.
- 🧅 **Tor Proxy Support**: Outbound connections to `openrouter.ai` can automatically be routed over a local Tor daemon SOCKS5 proxy (`socks5h://127.0.0.1:9050`) for secure, private, and geo-independent requests.
- 💾 **Structured JSON Memory**: Keeps a running context of your conversation in `data/messages.json` and persistent user/system profile rules in `data/memory.json`.
- 🤖 **Local-First & Hybrid Approach**: Switch seamlessly between local inference servers (Ollama, llama.cpp running on GPU/CPU machines) and highly optimized cloud APIs (Google Gemini via OpenRouter).
- 🧳 **Zero Python Bloat**: Built purely on system binaries like standard GNU Unix utilities, `curl`, `jq`, and `bash`.
---

## 📂 Core Files

| File | Description |
| :--- | :--- |
| [`pipeline.sh`](pipeline.sh) | **Core Orchestrator**: Manages arguments, parses intent, builds JSON payloads, runs the interactive chat session, issues requests to Ollama/llama.cpp/OpenRouter, and manages memory. |
| [`run-tools.sh`](run-tools.sh) | **Execution Runner**: Parses JSON payload parameters and implements 9 core system manipulation and retrieval functions carefully mapped to standard GNU binaries. |
| [`tools.json`](tools.json) | **Declaration Schemas**: Formally defines structural rules, tool descriptions, and parameters for Function Calling (matching the OpenRouter model spec). |
---

## 💬 Interactive Chat Mode (Default)

Running `pipeline.sh` without any arguments starting a prompt (or explicitly with the `--chat` option) launches the interactive **Chat Mode**. 

The system initializes your conversational profile and displays a standard prompt. Communication is continuous, meaning the AI remembers all questions and answers previously sent during the session!

### 🗺️ Built-in Slash Commands

During the chat session, you can invoke special control actions using slash prefixes:

| Command | Action |
| :--- | :--- |
| `/help` | Prints a guide showing all available interactive commands. |
| `/clear` | Cleans up the pipeline memory by wiping the session history and user files inside the `data/` directory. |
| `/commit` | Manually triggers the Cognitive Heartbeat Pacemaker, consolidating outstanding learnings/milestones to `memory.json` and pruning active contexts. |
| `/start` | Escapes the standard conversational loop to query a pipeline prompt with file contexts interactively. |
| `/quit` | Exits the chat loop and returns to your system shell. |
---
## 🛠️ Tool-Calling Engine (Agentic Capability)

The pipeline integrates 9 standard agentic actions declared in `tools.json`. When the model returns a tool request, `pipeline.sh` parses it and spawns `run-tools.sh` with the extracted arguments before feeding the results back.

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
# htmlq can be installed via AUR (e.g. yay -S htmlq) or Cargo:
cargo install htmlq
```

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

### A. Chat Mode (Default interactive stream)
Launch the fully-remembered chat mode simply:
```bash
./pipeline.sh
# OR explicitly:
./pipeline.sh --chat
```

### B. Pipeline Mode (With command arguments)
```bash
./pipeline.sh "<prompt/instructions>" [input-file-1] [input-file-2]
```

#### Multi-Mode and Simple-Mode Switches
- `--simple`: Bypasses complex agent pipeline processes, querying the active model in one straightforward interaction.
  ```bash
  ./pipeline.sh --simple "Summarize this log file" run-tools.log
  ```
- `--multi`: For complex tasks, triggers heavy consensus routing blocks (WIP).

### C. Clean Memory Store
Clear cached chat history and profile structures:
```bash
./pipeline.sh --clear
```

### D. Manual Cognitive Consolidation
Force immediate session context compression and memory syncing:
```bash
./pipeline.sh --commit
```
---

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
* **AI Collaborators / Reviewers**: **Gemini**

---

## ⚖️ License & Project Status

* **Project Phase**: Experimental Work-in-Progress (WiP).
* **Next Roadmap Milestones**: Refactoring Route C (Task Mode) to enable automated local three-stage software-engineer agent loop consensus blocks.
* **License**: Released under the terms of the **MIT License**. See [LICENSE](LICENSE) for details.
