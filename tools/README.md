# 🛠️ AI Pipeline Unified Tools Directory

This directory contains the isolated, modular tools and schemas utilized by the AI Pipeline's tool-calling (function calling) engine (`run-tools.sh` / `pipeline.sh`).

---

## 📂 Directory Structure

```
tools/
├── tools.json             # 11-tool schema (Premium/Cloud backends)
├── tools-light.json       # 6-tool schema (Frugal/Local backends)
├── web-fetch.sh           # Smart Crawler (Zero-NodeJS dependency)
└── web-browse/            # Active Browser Automation (Puppeteer)
    ├── web-browse.js      # Unified JS Driver
    ├── package.json       # Node dependency declaration
    └── package-lock.json  # Node dependency lockfile
```

---

## ⚡ Setup & Dependency Installation

The tools are designed with strict boundaries between **System-Native (universal)** and **Web-Developer (opt-in)** stacks.

### 1. `web-fetch.sh` (Universal, No-NodeJS)
Requires only standard shell utilities and `htmlq`. No installation is needed within this directory.
* **Dependencies**: `curl`, `jq`, `sed`, `htmlq`, `tor` (optional, for Onion routing).

### 2. `web-browse/` (Opt-In, Puppeteer)
To enable active browser automation, JS rendering, screenshot/PDF capturing, and interactive page actions, you must explicitly install the NodeJS dependencies.

```bash
# Navigate to the browser tool subdirectory
cd tools/web-browse

# Install Puppeteer and dependencies locally
npm install
```

#### 🌐 Chromium Setup Guidelines
* **CachyOS / Arch Linux**:
  ```bash
  sudo pacman -S chromium
  ```
* **Debian / Ubuntu**:
  ```bash
  sudo apt install -y chromium-browser
  ```
* **Termux (Android)**:
  Requires the specialized ARM64 Chromium package:
  ```bash
  pkg install tur-repo
  pkg install chromium
  ```

---

## 🛡️ Graceful Fallback Design

If NodeJS or its required packages are not installed, running `./tools/web-browse/web-browse.js` will return a clean system execution error (`env: 'node': No such file or directory` or missing package errors).

The main orchestrator (`pipeline.sh`) is designed to capture this error dynamically and **gracefully degrade**:
1. It detects the missing runtime dependency.
2. It automatically redirects the task to `web_fetch` (for static content retrieval) or crafts custom shell-native extraction command lines via `exec_shell_command` to bypass the limitation, ensuring continuous execution.
