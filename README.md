# 🚀 Minimalist Experimental AI Pipeline

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)
[![Bash Shell](https://img.shields.io/badge/Shell-Bash-4EAA25.svg?logo=gnu-bash&logoColor=white)](https://www.gnu.org/software/bash/)
[![Backend Supported](https://img.shields.io/badge/Backends-Ollama%20%7C%20llama.cpp%20%7C%20OpenRouter-orange.svg)]()
[![Status](https://img.shields.io/badge/Status-Experimental--WIP-blue.svg)]()

> A lightweight, highly extensible Bash-driven orchestration framework for interacting with local LLMs (via **Ollama** or **llama.cpp**) and external API backends (via **OpenRouter / Gemini 3.5 Flash**). Features fully integrated tool-calling capabilities and a secure fallback system utilizing Tor.

Developed with precision and scalability in mind.
* **Lead**: Jiab77
* **Reviewer**: Gemini

---

## 📖 Table of Contents
1. [Overview & Architecture](#-overview--architecture)
2. [Key Capabilities](#-key-capabilities)
3. [Core Files](#-core-files)
4. [Tool-Calling Engine (Agentic Capability)](#%EF%B8%8F-tool-calling-engine-agentic-capability)
5. [Supported Backends & Configured Models](#-supported-backends--configured-models)
6. [Prerequisites & Installation](#%EF%B8%8F-prerequisites--installation)
7. [Usage Guide](#-usage-guide)
8. [Pipeline Memory & State Logging](#%EF%B8%8F-pipeline-memory--state-logging)
9. [Project Status & License](#-project-status--license)

---

## 🔍 Overview & Architecture

This repository contains a minimalist, high-performance design of an *agentic LLM orchestration loop* written entirely in **Bash**. 

Unlike heavy, dependency-bloated Python frameworks, this implementation is exceptionally rapid, contains zero bloated virtual environments, and is easy to audit. It parses user intent, extracts structural context from external files, queries backends of your choice, implements recursive tool-calling (function calling) natively in Bash, and manages long-term memory across interactions.

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

When an inquiry is made, the **Intent Router** classifies it:
1. **QUESTION**: Direct questions or explanations about files. For the `gemini` backend, this triggers an automated Tool Execution loop with `run-tools.sh` until the model decides it has gathered enough answers to output a final reply.
2. **COMPARE**: Automated identification of structural, functional, or logical differences between two context files.
3. **TASK**: (WIP) Actionable, code-generating edits. Triggers a structured consensus flow of three specialized models: **Architect** (drafts a logic plan) $\rightarrow$ **Coder** (generates pure source code modifications) $\rightarrow$ **Judge** (performs validation / regression checks).

---

## ✨ Key Capabilities

- 🛠️ **Agentic Function Calling**: Fully conforms to advanced JSON schemas. The Gemini and OpenRouter models can dynamically request to probe directory trees, read lines of files, modify lines of code, write files, or execute sandboxed shell commands.
- 🧅 **Tor Proxy Support**: Outbound connections to `openrouter.ai` can automatically be routed over a local Tor daemon SOCKS5 proxy (`socks5h://127.0.0.1:9050`) for secure, private, and geo-independent requests.
- 💾 **Long-term Interactive Memory**: Maintains context across sessions in a markdown-based state storage ledger (`PIPELINE_MEMORY.md`).
- 🤖 **Local-First & Hybrid Approach**: Switch seamlessly between local inference servers (Ollama, llama.cpp running on GPU/CPU machines) and highly optimized cloud APIs (Google Gemini via OpenRouter).
- 🧳 **Zero Python Bloat**: Built purely on system binaries like standard GNU Unix utilities, `curl`, `jq`, and `bash`.

---

## 📂 Core Files

| File | Description |
| :--- | :--- |
| [`pipeline.sh`](pipeline.sh) | **Core Orchestrator**: Manages arguments, parses intent, builds JSON payloads, issues requests to Ollama/llama.cpp/OpenRouter, and manages memory. |
| [`run-tools.sh`](run-tools.sh) | **Execution Runner**: Parses JSON payload parameters and implements 8 core system manipulation functions carefully mapped to standard GNU binaries. |
| [`tools.json`](tools.json) | **Declaration Schemas**: Formally defines structural rules, tool descriptions, and parameters for Function Calling (matching the OpenRouter model spec). |

---

## 🛠️ Tool-Calling Engine (Agentic Capability)

The pipeline integrates 8 standard agentic actions declared in `tools.json`. When the model returns a tool request, `pipeline.sh` parses it and spawns `run-tools.sh` with the extracted arguments before feeding the results back.

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

---

## 🤖 Supported Backends & Configured Models

You can configure the active engine inside `pipeline.sh` by modifying the `BACKEND` variable (`ollama`, `llamacpp`, or `gemini`).

### 1. **Gemini / OpenRouter (`gemini`)**
* **Inference Endpoint**: `https://openrouter.ai/api/v1/chat/completions`
* **Default Model**: `google/gemini-3.5-flash`
* **Features**: Direct support for system prompts, official JSON tool specifications, reasoning capability toggles, and Tor integration.

### 2. **Ollama (`ollama`)**
* **Inference Endpoint**: `http://localhost:11434`
* **Configured Stack**:
  * **Architect / Reasoning**: `lfm2.5-thinking` (Liquid AI 2.5B Thinking)
  * **Coder**: `qwen2.5-coder:1.5b`
  * **Judge / Analyst**: `qwen2.5-coder:3b`

### 3. **llama.cpp (`llamacpp`)**
* **Inference Endpoint**: `http://localhost:8080/v1/chat/completions` (Standard Server)
* **Configured Stack**:
  * **Architect / Reasoning**: `LiquidAI/LFM2.5-1.2B-Thinking-GGUF`
  * **Coder**: `Qwen/Qwen2.5-Coder-1.5B-Instruct-GGUF`
  * **Judge / Analyst**: `ibm-granite/granite-4.0-h-micro-GGUF`

---

## ⚙️ Prerequisites & Installation

### Core Utilities
Ensure you have standard system packages installed:
```bash
# Debian / Ubuntu / Mint
sudo apt update && sudo apt install -y curl jq tor glow

# macOS (Homebrew)
brew install jq glow tor
```

### Authorization (For Gemini/OpenRouter API)
Save your OpenRouter API Key inside a private file.
```bash
echo "your-openrouter-api-key-here" > ~/.creds
chmod 600 ~/.creds
```

### Running Backend Services (When using Local Inference)

#### Option A: Ollama Service
Ensure Ollama daemon is running, then enable model pulling in `pipeline.sh` (`PULL_MODELS=true`) or pull manually:
```bash
ollama pull lfm2.5-thinking
ollama pull qwen2.5-coder:1.5b
ollama pull qwen2.5-coder:3b
```

#### Option B: llama.cpp Server
Spawn your local `llama-server` on port `8080` loaded with your active GGUF models.

---

## 🚀 Usage Guide

### General Usage
```bash
./pipeline.sh "<prompt/instructions>" [input-file-1] [input-file-2]
```

### Examples

#### 1. Ask a question about a file
The pipeline automatically parses the file context, extracts its data, routes the query to the chosen backend, and outputs structured markdown (rendered nicely via `glow` if available).
```bash
./pipeline.sh "What are the security boundaries in this script?" run-tools.sh
```

#### 2. Perform a side-by-side comparison
```bash
./pipeline.sh "compare" script_v1.sh script_v2.sh
```

#### 3. Run in Simple / Single-Inference Mode
Bypasses more complex agent pipelines if configured to run simpler individual requests.
```bash
./pipeline.sh --simple "Explain quantum computing in 3 bullets"
```

#### 4. Clean Memory Store
Clear cached logs and memory blocks kept in `PIPELINE_MEMORY.md`.
```bash
./pipeline.sh --clear
```

---

## 💾 Pipeline Memory & State Logging

If memory is enabled in `pipeline.sh` (`ENABLE_MEMORY=true`), all successful queries, tasks, planner structures, and responses are appended directly to:
```
PIPELINE_MEMORY.md
```
This serves as both an analytical audit trail and local state storage that the pipeline loads on subsequent queries to keep a running conversation history.

---

## ⚖️ License & Project Status

* **Project Phase**: Experimental Work-in-Progress (WiP).
* **Next Roadmap Milestones**: Refactoring Route C (Task Mode) to enable automated local three-stage software-engineer agent loop consensus blocks.
* **License**: Released under the terms of the **MIT License**. See [LICENSE](LICENSE) for details.
* **Copyright**: © 2026 Doctor Who.