# 🔌 A.I.D.E. Server (Unified PHP Web Server & Local Bridge)

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](../LICENSE)
[![PHP Version](https://img.shields.io/badge/PHP-%3E%3D%207.4-777BB4.svg?logo=php&logoColor=white)](https://www.php.net/)
[![Platform](https://img.shields.io/badge/Platform-Linux%20%7C%20macOS%20%7C%20BSD%20%7C%20Windows-lightgrey.svg)](https://www.php.net/)
[![Based on simple-php-webserver](https://img.shields.io/badge/Based%20on-simple--php--webserver-blueviolet.svg?logo=github)](https://github.com/Jiab77/simple-php-webserver)

A high-performance, single-file development web server powered by PHP. Within the **A.I.D.E. (AI Driven Environment)** ecosystem, it acts as the **Local Web Bridge & Dashboard Host** (serving the **A.I.D.E. Web** interface).

This project is built upon and inspired by **[simple-php-webserver](https://github.com/Jiab77/simple-php-webserver)**. It represents an optimized and unified version that merges **Linux & macOS implementations** into a single, highly portable, cross-platform utility. It works flawlessly under **Linux, MacOS, BSD, and Windows/Termux**.

---

## ✨ Features

### 🚀 1. A.I.D.E. Server (`server.php`)
Our custom development web server is optimized for high-concurrency local executions:
*   **🚀 High Concurrency (Multi-threaded Processing)**: Automatically detects your total CPU cores (`nproc`, `sysctl`, or `/proc/cpuinfo`) across Linux, macOS, BSD, and Windows/Termux, dynamically scaling `PHP_CLI_SERVER_WORKERS` to serve parallel asset requests at lightning speeds.
*   **🔧 Intelligent Dual-Mode Parser**:
    *   *Options Mode*: Configure specific flags with advanced CLI options (e.g. `-i localhost -p 9000 -c 8 -d ./my-folder`).
    *   *Classic Mode*: Backward-compatible quick start positional structure: `./server.php [interface:port] [/path/to/serve]`.
*   **🎨 Deluxe Fallback Dashboard**: If your target directory lacks an `index.html` or `index.php`, the server automatically generates a gorgeous, fully-responsive directory browser and diagnostics dashboard using **Fomantic UI**.
*   **🛡️ Bulletproof Process Launching**: Automatically leverages Unix `pcntl_exec` to replace the execution thread cleanly (no dangling zombie processes). If `pcntl` is unavailable (Windows, Termux), it falls back gracefully to a robust shell pass-through.
*   **🧬 Zero Dependencies**: Standard pure PHP, compatible across all runtimes from PHP 7.4 up to PHP 8.5+.

### 🌐 2. A.I.D.E. Web (`index.php`)
The serverless-styled web interface (formerly known as the *Jarvis Web Command Center - JWCC*) rewritten as a robust local app:
*   **🌊 Option C - Unix Pipe Stream Bridge**: Leverages native PHP `proc_open` to run the sovereign cognitive core library (`core.sh` / `cli.sh`) as an asynchronous background stream, piping real-time terminal tokens directly to your browser via **Server-Sent Events (SSE)**.
*   **📊 Live Telemetry HUD**: Aggregates hardware and system metrics in real-time:
    *   Active model, provider, and backend.
    *   CPU load average & core count.
    *   Physical memory usage.
    *   Vercel AI Gateway credits balance (automatically routed through Tor for privacy).
    *   Local Termux battery status on Android.
*   **📂 Cognitive Memory Explorer**: A high-contrast Markdown file browser and real-time live editor. Read and edit your persistent markdown files (`data/memory/` and `data/skills/`) directly from your browser, completely avoiding complex serialization schemas.
*   **🌐 Full i18n Localization**: Supporting dynamic on-the-fly **English** and **French** language switching with persistent cookie configurations.

---

## 📖 Usage

### 🚀 Launching the Server
Make sure the server script is executable:
```console
$ chmod +x web/server.php
```

To run **A.I.D.E. Web** using the server with default parameters (`127.0.0.1:8000` serving the `web/` directory):
```console
$ ./core.sh server web
```

or directly:
```console
$ ./web/server.php
```

Or quickly bind to a custom port:
```console
$ ./web/server.php -p 9000
```

### Options Reference
```text
  -h, --help           Display this help documentation.
  -i, --interface      Specify bound IP or domain (Default: 127.0.0.1)
  -p, --port           Specify port number (Default: 8000)
  -c, --cores          Number of CPU process threads (Default: Automatic core count)
  -d, --directory      Root directory folder (Default: Server folder)
  -v, --verbose        Enable debug logs and active runtime metrics
```

---

## 🏛️ Ecosystem Integration

The web server acts as the central bridge between your physical machine and your cognitive agent:

```
┌─────────────────┐       (Local Sockets)        ┌──────────────────┐
│  A.I.D.E. Web   ├─────────────────────────────►│  A.I.D.E. Server │
│   (index.php)   │◄─────────────────────────────┤   (server.php)   │
└────────┬────────┘                              └─────────┬────────┘
         │                                                 │
         │ (proc_open pipe streaming)                      │ (serves assets)
         ▼                                                 ▼
┌─────────────────┐                                ┌────────────────┐
│   cli.sh / core │                                │ User Browser   │
│   (CLI Agent)   │                                │ (Localhost)    │
└─────────────────┘                                └────────────────┘
```

---

## 👥 Contributors & Credits

Special thanks to the authors who made this unified execution possible:

*   **[@staatzstreich](https://github.com/staatzstreich)**: Who designed the elegant object-oriented macOS implementation and argument structure.
*   **Unified Development Team & [simple-php-webserver](https://github.com/Jiab77/simple-php-webserver)**: Merged both scripts into a portable, fallbacked command-line utility with a rich directory browser dashboard.
*   **Jarvis (The Great Master Flash)**: Acted as the AI co-pilot, refining the SSE pipe bridge, streamlining compatibility, localizing i18n dictionaries, and crafting the interactive interface design.

---

🤖 **Note:** This unified cross-platform version was engineered in perfect pairing harmony using: **[ai-pipeline](https://github.com/Jiab77/ai-pipeline)**. All honor and credit to the master orchestrator! 🚀
