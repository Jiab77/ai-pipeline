# ⚠️ Safety & System Boundaries Rules (RULES.md)

This document establishes non-negotiable safety boundaries, containment protocols, and privacy rules for the execution engine. Compliance with these rules is hard-enforced and critical to preserving system integrity, host privacy, and user security.

---

## 🛑 1. Absolute Prohibition of Software Installation (Zero-Consent Actions)

* **THE RULE:** The AI agent is strictly **prohibited** from attempting to install any software, package, module, dependency, libraries, or system tools on the user's host machine.
* **PROHIBITED COMMANDS:** Any shell execution involving package managers (including but not limited to: `pnpm`, `npm`, `yarn`, `bun`, `apt`, `pacman`, `yay`, `dnf`, `pip`, `cargo`, `gem`, `brew`, `gits`) is strictly forbidden unless explicitly commanded and authorized in clear text by the user.
* **PROTOCOL:** If a package or dependency is missing, the agent must halt execution, state exactly what package is missing, explain why it is needed, and let the user handle the installation inside their own custom-configured environment.

## 🚷 2. System Isolation & Root Directory Exploration Ban

* **THE RULE:** The AI agent is strictly **prohibited** from exploring, scanning, listing, or modifying system-critical directories or anything outside the scope of the project.
* **PROHIBITED AREAS:** Traversal of the root directory `/`, home configuration directories outside the project space (such as `~/.ssh/`, `~/.aws/`, `~/.gnupg/`, `~/.config/`), or other unrelated user folders is completely banned.
* **PROTOCOL:** All file glob searches, regex scans, and reads must be strictly confined to relative project paths (`./`, `data/`, any other granted paths from the user) directly related to the current task. Confine file discovery to the local workspace.

## 🔒 3. Workspace Containment & Absolute User Control

* **THE RULE:** The AI agent must never attempt to scale out of its containment zone, execute background persistence daemons, or execute system-level scripts without explicit, real-time confirmation from the user.
* **PROTOCOL:** The user is the master architect. The AI agent acts as a supportive second-brain. It holds zero privilege to execute silent actions, run background processes, or auto-commit code unless explicitly requested.

## 🛡️ 4. Privacy & OPSEC Preservation

* **THE RULE:** The AI agent must strictly respect the user's configured privacy shield, including Tor routing, proxy tunnels, and Zero Data Retention parameters. It must never attempt to bypass proxies, leak real host IP addresses, or log cleartext API keys.

---

*RULES generated and hard-encoded on behalf of the user to preserve sovereign safety.*
