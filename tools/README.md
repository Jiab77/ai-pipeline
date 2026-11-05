# 🛠️ Native Shell Tools & Agent Capabilities

The tools subsystem provides the AI agent with a safe, deterministic interface to interact with its workspace, discover live runtime models, control web automation, synthesize/transcribe multimodal media, and communicate peer-to-peer over Tor.

The architecture separates execution from declarative contracts: schemas reside in declarative JSON files under `tools/`, while the dispatcher resides directly at the project root as `tools.sh`.

---

## 📂 Directory Structure

```
AI Pipeline (Repository Root)
├── tools.sh                # 🐚 Master Tool Dispatcher (Bash - Root level)
│
└── tools/                  # 🛠️ Auxiliary Tools, Binaries & Schemas
    ├── tools.json          # Master Tool Schemas (31 tools - Cloud/Advanced backends)
    ├── tools-light.json    # Streamlined Tool Schemas (28 tools - Frugal/Local SLMs)
    ├── web-fetch.sh        # Fast, headless static scraper & Markdown extractor via Tor
    ├── web-browse.sh       # Stateless Chrome DevTools Protocol (CDP) WebSocket browser automation
    ├── showcast.sh         # Terminal cast and visualization helper
    └── README.md           # This documentation
```

---

## 🐚 Master Dispatcher (`./tools.sh`)

The root **`tools.sh`** dispatcher is loaded dynamically by `core.sh`. It intercepts function call payloads from the reasoning model and routes them safely:

* **Zero-Fork Streaming Argument Parsing**: Intercepts tool parameters via a single-pass `jq` stream delimited by NUL bytes (`\u0000`), guaranteeing high performance and complete immunity to argument-injection attacks.
* **Deterministic File Manipulation**:
  * `read_file`: Zero-fork bounded reading with dynamic `awk`, immune to missing trailing newlines.
  * `edit_file`: Atomic, line-based multi-hunk replacement/deletion/insertion applied in reverse order.
  * `write_file`: Atomic write with recursive directory creation.
* **Sovereign Safety Boundaries**: Strictly enforces execution constraints (Rules §1–§6):
  * Blocks traversal outside authorized project paths.
  * Forbids unauthorised package manager invocations (`npm`, `pip`, `apt`, `brew`, etc.).
  * Protects core engine scripts (`cli.sh`, `core.sh`, `tools.sh`, `config/`, etc.) from self-modification.

---

## 🛠️ Auxiliary Scripts (`tools/`)

### 1. `web-fetch.sh` (Static Crawler & Markdown Extractor)
A lightweight static fetcher using `curl` and `htmlq` (or precompiled binary) to convert web pages into clean Markdown without executing JavaScript.
* **Privacy Shield**: Automatically routes traffic through Tor (`socks5h://127.0.0.1:9050`) by default.
* **Anti-Bot Resiliency**: Integrates with `curl-impersonate` when available to bypass TLS/HTTP fingerprint blocking.

### 2. `web-browse.sh` (Stateless WebSocket Browser Automation)
A fast, headless browser controller operating via Chrome DevTools Protocol (CDP) through `websocat`.
* **Stateless One-Shot Model**: Instead of heavy frameworks (Puppeteer/Playwright), opens an ephemeral WebSocket connection per command, transmits a single JSON-RPC packet, extracts the DOM/screenshot, and disconnects immediately.
* **Hermetic Process Binding**: Chrome/Chromium is bound to the local Tor proxy at startup, preventing clearnet IP leaks.

---

## 📊 Declarative Schemas (`tools/*.json`)

Tool definitions act as the single source of truth for the agent's capability surface:

1. **`tools.json` (Master Suite — 31 tools)**:
   * **Filesystem & Discovery (5)** : `read_file`, `write_file`, `edit_file`, `file_glob_search`, `grep_search`.
   * **Web & Search (3)** : `web_search`, `web_fetch`, `web_browse`.
   * **Multimodal Media (6)** : `create_image`, `edit_image`, `read_image`, `create_video`, `read_video`, `create_avatar`.
   * **Voice & Speech (2)** : `speak` (TTS), `transcribe` (STT).
   * **System & Discovery (4)** : `exec_command`, `get_datetime`, `get_state`, `get_providers`, `get_models`.
   * **JARNET P2P Networking (9)** : `jarnet_who`, `jarnet_status`, `jarnet_up`, `jarnet_down`, `jarnet_check`, `jarnet_ping`, `jarnet_send`, `jarnet_reply`, `jarnet_peer_add`.

2. **`tools-light.json` (Frugal Suite — 28 tools)**:
   * Optimized for Small Language Models (SLMs) and constrained context windows.
   * Excludes raw shell execution parameters to keep prompts compact and minimize prompt hallucination on smaller parameter sizes.

---

*Authored and hardened by Jiab77 and Jarvis.*
