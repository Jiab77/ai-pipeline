# 🛠️ A.I.D.E. CLI - Native Shell Tools & Schemas

Following the official architectural partitioning of the **A.I.D.E.** project, the Progressive Web App (PWA) code and its heavy frontend asset trees have been completely decoupled and migrated into their own dedicated repository (**A.I.D.E. PWA**).

This directory is now dedicated 100% to **A.I.D.E. CLI**—our fast, lightweight, and sovereign native terminal workstation. It contains only declarative, DRY JSON schemas and auxiliary, dependency-free compiled/shell utilities.

---

## 📂 Immaculate Directory Structure

The tools architecture has been flattened to achieve absolute aesthetic and structural simplicity, with the primary tools dispatcher residing directly at the repository root:

```
A.I.D.E. CLI (Repository Root)
├── tools.sh                # 🐚 Master Local Agent Tools Dispatcher (Bash - Root level!)
│
└── tools/                  # 🛠️ Tools Assets & Schemas Directory
    ├── tools.json          # Premium Tool Schemas (11 tools - Cloud/Premium backends)
    ├── tools-light.json    # Frugal Tool Schemas (6 tools - Local/SLM backends)
    ├── tools-groq.json     # Groq-compatible schemas (Formatted to bypass LPU checks)
    ├── README.md           # This documentation
    ├── web-fetch.sh        # Smart crawler & static parser (Zero-NodeJS, Tor-routing capable)
    └── web-browse.sh       # Browser automation via Stateless WebSocket RPC daemon
```

---

## 🐚 The Root Master Dispatcher (`./tools.sh`)

To streamline imports and execution mapping across our cognitive core scripts (`core.sh` / `cli.sh`), the unified dispatcher **`tools.sh`** has returned to its rightful throne **directly at the project root**.

* **Zero-Fork Parsing**: It intercepts JSON payloads sent by the AI Reasoning Engine, using a single-pass `jq` streaming pipeline separated by null-characters (`\u0000`) to guarantee high-performance, injection-proof argument parsing.
* **Masterful Optimizations (v0.3.3)**:
  * **0-Fork `read_file`**: Reads files with sub-millisecond speeds, completely bypassing redundant processes. Uses dynamic, unbounded `awk` logic that handles files with absolute immunity to missing trailing newlines.
  * **0-Fork `edit_file`**: Evaluates and applies sorted line modifications on-the-fly without running redundant file counting forks, preserving mobile battery life and preventing CPU throttling on Android Termux.
  * **Sovereign Boundaries**: Automatically checks paths at C-speed using in-memory Zero-Fork glob matching to prevent the AI model from reading, writing, or patching core execution scripts (`core.sh`, `cli.sh`, `tools.sh`).

---

## 🛠️ Specialized Shell Tools (`tools/`)

The `./tools/` directory houses lightweight, compiled, or shell-native auxiliary assets designed with strict compliance to UNIX philosophies.

### 1. `web-fetch.sh` (Static Crawler)
A 100% dependency-free static web scrapper and parser. It utilizes standard UNIX utilities (`curl`, `sed`, `jq`) combined with `htmlq` to parse and format raw, complex web structures into beautiful, readable Markdown.
* **Onion-Routed**: Automatically checks for a running Tor service on SOCKS5 port `9050`. If found, it routes all web crawls through secure Tor exit nodes automatically, shielding your real IP address.

### 2. `web-browse.sh` (Stateless WebSocket Browser Automation)
Our high-performance alternative to bloated Puppeteer runtimes. It uses a **Stateless, One-Shot RPC** connection model:
* **The Concept**: Chrome/Chromium runs in the background as a persistent system daemon, maintaining the tab context, cookies, and DOM.
* **The Flow**: To click, type, navigate, or capture screenshots, a stateless WebSocket connection is opened over `websocat` or `wscat` for a fraction of a second, sends a single JSON-RPC packet, extracts the response, and instantly closes. This avoids memory leaks and CPU-blocking loops.
* **Process-Level Proxy Binding**: The Chromium daemon binds to our local SOCKS5/Tor proxy during initialization at the OS process level. Even if subsequent tool-calls omit the proxy address, traffic remains hermetically sealed, preventing real IP leaks.

---

## 📊 DRY Tool Schemas (`tools/*.json`)

Tool schemas are declared once in JSON format and acts as the single source of truth for the entire pipeline, preventing parameter duplication.

1. **`tools.json` (Premium / Cloud API)**: Full 11-tool capability-set (including database queries, filesystem edits, web browsing, and shell execution). Bound when routing to advanced cloud engines like Gemini 3.5 Flash or large local models.
2. **`tools-light.json` (Frugal / Local SLM)**: A streamlined 6-tool schema optimized for Small Language Models (e.g., LFM 2.5 series or Qwen-Coder-3B). Completely strips system-execution parameters to fit comfortably within tight context windows.
3. **`tools-groq.json` (Groq Platform)**: Custom-tuned schemas specifically tailored for Groq's strict LPU schema validation engine. Converts all native `integer` parameters (such as timeouts or max sizes) into compliant `string` types to prevent API connection dropouts.

---

*Cleaned, modularized, and documented by Jarvis (The Great Master Flash) and Jiab77.*
