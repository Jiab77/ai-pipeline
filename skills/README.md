# 📚 AI Pipeline Skills Library (Public)

These Markdown files are **skills**: structured, self-contained domain knowledge documents designed for AI agents running on the **AI Pipeline** / **Jarvis** architecture.

When present in the agent's workspace under `data/skills/`, the pipeline's cognitive core (`core.sh`) automatically indexes them at startup and equips the assistant with specialized operational expertise — without hardcoding logic into the engine or altering system prompts.

---

## 📂 Published Skills

| Skill | Domain | Description |
| :--- | :--- | :--- |
| [`jarnet.md`](jarnet.md) | Sovereign Networking | Complete operational handbook for **JarNet**, an autonomous, decentralized Agent-to-Agent (A2A) protocol over Tor Onion Services. |

---

## 🚀 How To Use

The AI Pipeline automatically discovers skills located in `data/skills/` within your workspace.

### 1. Install or Update Skills
To make these public skills available to your agent, copy them into your active data workspace:

```bash
# From the repository root:
mkdir -p data/skills
cp skills/*.md data/skills/
```

### 2. Launch the Assistant
Run the interactive CLI:

```bash
./cli.sh
```

At startup, `core.sh` scans `data/skills/` and appends an index of acquired skills to the assistant's cognitive context. When a task relates to a skill, the assistant reads the corresponding document and executes the workflow with native accuracy.

---

## 🧠 Architectural Philosophy

In the AI Pipeline framework:
1. **Engine stays agnostic**: Core execution engines (`core.sh`, `engines/*.sh`) remain lean, robust, and protocol-neutral.
2. **Knowledge lives in Markdown**: Operational rules, wire contracts, and domain codices reside in versioned, human-readable Markdown files.
3. **Sovereignty & Portability**: An agent can be cloned onto any machine (Linux, macOS, Termux on Android) and immediately acquire operational competencies simply by carrying its skill documents.

---

## 📜 License

MIT License — Same as the [AI Pipeline](https://github.com/Jiab77/ai-pipeline) repository.
