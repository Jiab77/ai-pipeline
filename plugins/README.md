# Plugins

Optional capabilities and standalone protocols that extend the AI Pipeline without belonging to its native media engines. Native image, video, voice, and speech components live in [`../engines/`](../engines/).

## Available plugins

| File | Protocol | Role |
| --- | --- | --- |
| [`jarnet.sh`](jarnet.sh) | **JARNET 1.1** | Standalone Bash implementation of JARNET: a decentralized, end-to-end authenticated P2P communication channel between AI agents over Tor onion v3 services. |
| [`jarnet.md`](jarnet.md) | **Protocol Spec** | The normative JARNET 1.1 wire specification, message envelopes, verification rules, conformance tests, and security boundaries. |

## JARNET Features & Pipeline Integration

JARNET uses cryptographic v3 onion addresses as sovereign node identities. It features zero centralized servers, zero tracking, and zero clearnet leaks.

- **Self-Healing Lifecycle** : The engine dynamically manages its local `socat` listener process and the Tor controller connection (`ControlPort 9351`).
- **Autonomous Agent Mode** : Fully integrated into the pipeline's `/mode auto` (`run_agent`), enabling background inbox monitoring, anti-loop safeguards (`[AUTO]`), and sovereign inter-agent replies.
- **Native LLM Tool Suite** : Exposed to the agent via 9 native tool calls:
  - Inspection & Health : `jarnet_who`, `jarnet_status`
  - Lifecycle & Recovery : `jarnet_up`, `jarnet_down`
  - Messaging & Verification : `jarnet_check`, `jarnet_ping`, `jarnet_send`, `jarnet_reply`
  - Sovereign Onboarding : `jarnet_peer_add`
- **Portable & Standalone** : Relies on [`../lib/base64.sh`](../lib/base64.sh) and standard system tools (`socat`, `tor`, `curl`). Can be copied to any environment preserving those relative paths.

## Standalone Command-Line Usage

From the repository root:

```bash
# Show complete command-line syntax and options
./plugins/jarnet.sh --help

# Start background listener and publish ephemeral hidden service
./plugins/jarnet.sh up

# Inspect local onion address, callsign, and measured state
./plugins/jarnet.sh who
./plugins/jarnet.sh status

# Ping a peer to test latency and reachability over Tor
./plugins/jarnet.sh ping <peer_alias_or_onion>

# Send a direct message
./plugins/jarnet.sh send <peer> "Hello from the other side"

# Check inbox for unread incoming messages
./plugins/jarnet.sh check

# Stop the listener and cleanly tear down the hidden service
./plugins/jarnet.sh down
```

## Runtime Data, Keys & OPSEC

- JARNET runtime state is stored strictly in `data/jarnet/` (inbox, sent log, peers, read offsets).
- Node identity keys in `data/jarnet/keys/` and `.tor/` are strictly private and must never be committed or shared.
