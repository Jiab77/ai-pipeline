# JarNet — protocol

**Version**: 1.3 · **Date**: 2026-11-12 (UTC)
**Author**: Jiab77
**Collaborator**: Jarvis

**What this document is**: a wire contract between nodes that cannot take each other's word, and the only reference. Hesitations, debates and dead ends live in the journals; they have nothing to do here. Nothing outside these pages has contractual value.

**Self-sufficient**: this document defines the contract (§1 to §12), its conformance tests (§13), its open questions (§14 — not clauses), its non-normative annexes (§15), its change control (§16), its vocabulary (§17) and its onboarding surface (§18). An implementation in any language needs no other file.

**No address in this document.** An address written down links an identity to a project, durably, and a normative document needs no address to be implemented. Nodes are named, never located.

**Two node names appear in the measurements**: `desktop` and `mobile`. They are roles, not installations, and nothing in the contract depends on which is which.

**Writing rule**: nobody erases another's measurement; every claim carries its date and the command that produced it; no number is rewritten without re-measuring; a dated refusal is worth more than a polite agreement.

---

## 1. Measurement rules (before any contract)

They say what a node is **ENTITLED to conclude** from a silence. They come first: half of the failures recorded during this work were conclusions, not failures.

- **R1 — an empty response proves a window that was too short, never a closed door.**
  Measured 2026-10-19T03:17Z: a request with a path of 128 000 characters returns 200 in about 3 s; the same requests read with a 0.7 s window returned *empty*, and the conclusion "wall at 48k" was one keystroke away.
- **R1bis — a `200` is a timestamp, not a status; a `000` is a failed attempt, not a dead peer.**
  Measured 2026-10-19T00:43Z: `000` at 00:43:57, healthy at 00:44:09. And measured 2026-10-21T01:18Z: `000` at the peer while its messages were arriving anyway.
- **R2 — a timeout measures your patience, never the state of the other side.**
  Measured on desktop: failures at 1.7 s, 50 s, 35 s on an onion that was not dead — published at 4 min 35 s.
- **R3 — a hash is a witness only if its input is specified byte for byte.**
  One single file, as published, final newline included, no delimiter added around it. Measured on a document of this kind: the same text with its final newline stripped, and the same
  text with a closing delimiter line appended, produced three different hashes — three numbers for one file, from three inputs that nobody had specified. An unspecified input is not a witness, and two hashes say that a file changed, never what changed: a signed version is validated by a **diff**, not by a hash.

**Corollary**: no delay in this document authorises declaring a peer dead. A node is declared dead only by an **active and dated** measurement (§3), or by the death of a process one owns (§11.4).

---

## 2. Identity

- **The onion address IS the identity.** One Ed25519 key → one address → one node. No account, no DNS, no PKI, no registry.
- **The private key never leaves its node**, not even for its peer. It is never exposed in process arguments. A control transcript that must temporarily contain it is created with owner-only permissions and the copy is removed as soon as the persistent key file has been written safely.
- **`from` is a claim, not a proof.** Tor does not say who composed. Every attribution is written
  `attributed, not authenticated`, in the wire as in the journals.
- **`reply_to` is a claim of the same family.** It says *where to answer*, never *who is allowed* (§12).
- **`who` (alias) is a display convenience** read from a mutable local file. Measured: the `desktop` onion answered `who:"test1"` during a test under another key. **No protocol decision** depends on it. A local storage convention may nevertheless attach the alias to a key filename; that convention and its rename behaviour must be explicit (§18.5), and they never turn the wire alias into an identity proof.
- **The fingerprint `xxxx-xxxx-xxxx-xxxx`** derives from the address by hashing. It proves that sha256 works; it authenticates nothing. Display only.
- **Never self-declared**: neither identity, nor mode (§11), nor state (§3) are announced. They are **observed** from the other side. A node that certifies itself certifies nothing.
- **The peer list is a local authorisation, and the contract fixes only three things about it**: it is an **authorisation** and never a state; an address seen in `reply_to` **never** becomes a member (§12 d); membership is **never announced** on the wire. Its storage and its format are the node's business. Whether a node refuses a sender that is not in the list is **its own decision** — the contract requires neither acceptance nor refusal, and in either case what it sends back obeys §12.

---

## 3. States of a node: dated observations, not steps

**Vocabulary, not tools.** The commands named here are Tor's own vocabulary; an implementation that speaks to a control port uses them, whatever its language. Where a command is ambiguous, the EFFECT is what counts: a live ephemeral has an empty `onions/current`, so that command alone proves nothing (see PUBLISHED).

Each state is a **dated observation carrying its command**. A node **regresses** as soon as a measurement contradicts the previous one: that is not an error, that is information. Measured on desktop: `REGISTERED` (ghost service), **never** `PUBLISHED`, then `REFUSED` (550) an hour later. A reading as a progression would have hidden the failure.

| # | State | Meaning | Decided by |
|---|---|---|---|
| 0 | `CONTROL` | ControlPort answers **and** the cookie is readable | itself: `PROTOCOLINFO` + `AUTHENTICATE` |
| 1 | `REFUSED` | Tor refused `ADD_ONION` | itself: ControlPort response (`550 …`) |
| 2 | `REGISTERED` | `250-ServiceID` returned (no descriptor yet) | itself: `ADD_ONION` response |
| 3 | `PUBLISHED` | descriptor present in the DHT | **the peer**: `HSFETCH <addr>` → `HS_DESC RECEIVED` |
| 4 | `REACHABLE` | the peer obtains `200` on `/ping` | **the peer**: real traversal, dated |

**A process observation is not a network state.** `holder_alive` means only that a process owned by the node answers a liveness check; it does not prove that its control connection lives, and it is never mapped to `PUBLISHED`. An emitting command may report `REGISTERED` only from the acceptance of `ADD_ONION` (or from an explicit idempotent observation of that registration), never from a PID alone.

- **`SETEVENTS HS_DESC` and waiting for `UPLOADED` is NOT measured**: desktop armed the event for 30 s, zero events, service nevertheless `REGISTERED`. An unverified command does not enter the contract. What is measured (2026-10-19T01:27:53Z): `AUTHENTICATE` / `SETEVENTS HS_DESC` / `HSFETCH <addr>` → `650 HS_DESC RECEIVED` in about 2 s.
- **On its own node, a `RECEIVED` may come from the local cache** ⇒ `PUBLISHED` is read **from the other side only**. A state on the network is an **asymmetric** fact.
- **`(5)` is not `(4)`.** A SOCKS code 5 means the virtual port has no backend: the descriptor is known and the service is not there. A SOCKS code 4 means the descriptor is absent: nothing is known at all. The first is a local routing fault, the second an unpublished service. Reporting one for the other sends the operator to the wrong machine.

**Three faults, three gestures**:

| What the peer reads | Diagnosis | Gesture |
|---|---|---|
| `RECEIVED` + `200` | `REACHABLE` | nothing |
| `RECEIVED` + timeout | descriptor published, **introduction points** unreachable | check the responder and the virtual ports |
| no `RECEIVED` | **not published** | ControlPort: `REFUSED`? collision? `DEL_ONION` then `ADD_ONION` |

- **`CONTROL` is a prerequisite, not one more state.** Tor survives a crash without its cookie: it announces in `PROTOCOLINFO` a path that no longer exists and **never rewrites it** (the value lives in memory). Measured 2026-10-19T02:49Z: `AUTHENTICATE` impossible, `ADD_ONION` impossible, service **dead while tor runs**. Repair: restart the Tor instance — same key, therefore same address.
- **Grace window ≥ 5 min** between `REGISTERED` and any declaration of failure. Measured: 9.5 s (clean state) and 4 min 35 s (dirty state). Neither "10-30 s", nor "it is dead".
- **Zombie measured three times** — **12 h** at mobile (2026-10-19), **47 h** at desktop (process uptime read from the process table — 1 day 23 h — between its launch on the 19th around 00:16 and the discovery of its death on the 21st around 02:45), and again at mobile during the night of the 23rd between 23:13Z and 23:18Z. Mechanism: tor restarts or loses its control connection, the transient onion dies with it, the local bridge survives as an orphan, and the process **believes itself online**. A node must **die frankly** rather than lie: watching the ControlPort is part of the responder, not of an external tool. **On a phone the supervisor is the operating system, and it does not warn**: background processes are frozen, the radio switches from mobile data to Wi-Fi, and the node wakes up alive in its own eyes. A mobile implementation therefore may not assume that a live process means a live service.
- **`DEL_ONION <sid>` before `ADD_ONION`**, never the other way round (idempotence tested 2026-10-21T01:04Z). A node does not destroy a living service to republish.

---

## 4. Transport

- **HTTP/1.0**, **one process per request**, `Connection: close`, no keep-alive. A response's
  `Content-Length` is the number of **octets** in its UTF-8 body, never its number of characters.
- Only the **request line** is read. The body is ignored. It is ugly, it is indestructible.
- **The listener binds loopback, and only loopback.** This covers every listener of the node, including the ones that only carry traffic between its own components: a bridge, a pipe, a helper. A node reachable from a shared interface is **NON-CONFORMANT**, whatever it believes about its peer list — an allowlist describes who may write the protocol, never which interfaces are reachable. Measured on desktop, 2026-10-23T23:12Z: the listening socket answered on a non-loopback address, because the bind was absent, not because it was decided. The same node is unable to observe that fact about itself: a platform may hide its own sockets, and it did on this occasion at mobile, where the measurement is impossible.
- **One conformant port, and two routes only** — `/ping` and `/say`. `/` is an **alias** of `/ping`, not a third route (§5): a conformant implementation serves it, and no implementation may count it separately. A second port is another identity; a third route is another version.
- **The virtual port is 80, by convention.** It is the onion's virtual port, not a local one, so no local service can collide with it. An address exchanged **out of band** is announced **with** its port, always: an address published on the wrong virtual port answers SOCKS 5 while the service is alive, which cost twenty minutes and looked like a dead node (measured on desktop, 2026-10-22T00:20Z). The one address that travels **without** its port is the one in `reply_to`: there, the virtual port is 80 and it is the only one admitted (§12 a). Tor creates an identity **with** its virtual port: measured 2026-10-24, `ADD_ONION NEW:ED25519-V3` without a `Port=` mapping is refused (`512 Missing 'Port' argument`) — there is no port-less identity to announce.
- **One identity = one owner**: a node refuses to start twice on the same identity, and taking over a live identity is an explicit, declared act, never implicit. The mechanism that enforces this is the node's business; the behaviour is the contract. Measured: a second launch was refused cleanly instead of reporting "Tor did not return an address" — the failure mode of a node that believes two owners can share one identity.
- **Ownership precedes registration.** Before `ADD_ONION`, the node establishes that the loopback backend is really its own. A HTTP response, even one containing `ok:true` or `who`, is not an ownership proof. If a foreign listener occupies the port, startup fails frankly and **no registration is attempted**; the foreign service is left untouched.
- **The raw length of the request line is journaled**, before any decoding (§5). Without it, a refused `too_large` is indistinguishable from an endured `invalid_envelope`.

Both methods are conformant for sending an envelope:

- `GET /say/<b64url(envelope)>`: limited to **16 384 characters** on the raw request line (measured before any decoding).
- `POST /say`: limited to **1 048 576 bytes (1024 KiB)** on the decoded JSON request body.

Any request exceeding its specific limit must be refused **immediately** (before parsing) with the appropriate error code (`too_large` for GET, `payload_too_large` for POST).

---

## 5. Routes

```text
GET  /ping                    → 200 + {"ok":true,"who":...,"ts":...,"engine":...}
GET  /                        → identical to /ping (an alias: it must be served, not counted)
GET  /say/<b64url(envelope)>  → 200 + ack (raw request line ≤ 16 384 characters)
POST /say                     → JSON envelope in request body → 200 + ack (decoded body ≤ 1 048 576 bytes / 1024 KiB)
anything else                 → 404
```

- **No other route or HTTP method is conformant**, including later: adding a route is a major version.
- **`engine` is a stable protocol version, never a commit hash.** It lets a peer write down which protocol a node claims, instead of guessing from its behaviour. Absent `engine` is tolerated, and **the absence is written in the report** — silence about the engine is a fact to record, not a gap to fill in. Measured 2026-10-22T22:28Z: both nodes answered `/ping` without it, and a body carried in the response is what revealed which engine was actually serving. A version number would have said it in one field. **A client MUST ignore a field of the ping response it does not know, and MUST NOT require `engine`.** A conforming client validates the fields it uses, never the exact shape of the body. It is not an exception to the contract: it is the rule of §6 applied the other way round. A client that does not know `engine` reads `ok`, `who` and `ts`, ignores the rest, and does not break — it only loses the diagnosis.
- **`/say` is a GET that writes.** Assumed violation of HTTP semantics: one verb, one parser. **No intermediary may ever be placed in front of these routes.** A GET prefetch would write messages. Impossible on a bare onion; it becomes a hole the day someone puts a proxy "to make it faster". This sentence is a rule, not a remark.
- **Length limits are normative and distinct:**
  - For GET: the raw request line is measured before any decoding. Beyond **16 384** characters → `too_large`.
  - For POST: the decoded JSON body must not exceed **1 048 576** bytes. Beyond that limit → `payload_too_large` (before parsing the envelope).
- **The order of the controls is normative:** an oversized request must be refused with the correct code before any attempt to parse the envelope.
- **`/say` writes in both cases.** GET writes via the path (violation of HTTP semantics is assumed and accepted). POST writes via the request body. **No intermediary may ever be placed in front of these routes.**

- **The `408` is decided on the RETURN CODE of the read, never on the content of the line.** `rc != 0` (nothing read, partial line, cut) → `408`, **whatever portion was already received**. `rc = 0` then invalid base64 or JSON → `invalid_envelope`. Without this rule, a truncated line and an invalid envelope remain **indistinguishable**, and the receiver has to guess which of the two it got.
- **Attribution lives in the envelope, never in the URL.** Put in the path, it would look authenticated (§2).

---

## 6. Envelope (one line of JSON, base64url without padding)

```json
{"v":1,"type":"msg","from":"mobile","ts":"2026-10-21T01:18:22Z","sid":"jv-1792370302","re":"","body":"text","reply_to":""}
```

| field | obligation | meaning |
|---|---|---|
| `v` | required, `1` | format version |
| `type` | required | `msg`, `eta`, `bye` — **closed list** |
| `from` | required | alias **attributed, not authenticated** |
| `ts` | required | **emission** timestamp (UTC, `%Y-%m-%dT%H:%M:%SZ`) |
| `sid` | required | session identifier, chosen by the sender |
| `mid` | optional | message identifier, **short and unique per `(from, sid)`**, chosen by the sender. Enters the identity key when present (§9); it costs **nothing** to adopt, unknown fields being ignored |
| `re` | required for `eta` | `ts` of the message concerned |
| `body` | required for `msg`, `eta` | UTF-8 text, may be empty |
| `reply_to` | optional | onion v3 where to answer (§12). **Absent OR empty string** = answer the peer **as identified in the peer list** — never an address deduced from the connection: an onion circuit carries no return address (§11.3). An empty string is **never** a refusal: refusing here would be refusing **silently** |

- **The ack is not a message type.** It is the body of the response (§7). An `ack` received as an envelope is an `unknown_type` — and that is intended: two ways to acknowledge is two ways to lie.
- **One line = one message.** Unreadable envelope → `ok:false`, not an exception.
- **base64url**: alphabet `A-Za-z0-9-_`. **We emit WITHOUT padding; we ACCEPT WITH padding.** A strict decoder would break the first exchange: padding is tolerated on entry, never produced. UTF-8, no BOM. No raw CR/LF, including inside `body` (escaped `\n`).
- **Unknown field = ignored**, not an error: that is what will allow adding `sig` without breaking (§14).
- **`v` is the format version of the envelope, not the version of this document.** The two evolve independently: a document can reach 1.4 while `v` stays `1`, and a new value of `v` is a **new document**, never an amendment of this one.
- **`re` creates no mandatory thread** and authorises no rejection. For `msg` it is a reading convenience; for `eta` it is **required**, because a delay that does not carry its subject says nothing.
- **An invalid `reply_to` is an `invalid_envelope` at ENTRY.** Accepting it and stripping it afterwards would make the sender believe the message was recorded. Measured 2026-10-22T22:28Z on a disposable node: the refusal is `invalid_envelope`, at the entry, not at the reply.

---

## 7. The ack, the eta, and the write order

> An acknowledgement needs no second channel: it **already comes back**, on the connection the sender
> itself opened.

### 7.1 The ack is the body of the HTTP response, and it is always there

A `/say` request receives **in the same response**, on the same connection:

```json
{"ok":true,"rx_ts":"<UTC>","ack_ts":"<UTC>","re":"<acknowledged ts>","sid":"<sid>"}
```

- **Synchronous BY CONSTRUCTION**, not by discipline: there is no second round trip to decide. An ack cannot arrive "later", since it **is** the response.
- **Always present.** There is no mode where one does not acknowledge: even an `ok:false` is an acknowledgement of reception (it says *received and refused*, §8.2).
- **Two copies, two produced fields, one verdict — and nothing else.** `re` and `sid` are **copied** from the received envelope as read; `rx_ts` and `ack_ts` are **produced** by the mechanical layer; `ok` is the **verdict**. **No local state enters it**: not `who`, not a counter, not a path, not a buffer size (compare §12, bound a bis). An implementation that adds one more field has not implemented this ack, it has made it a report.
- **Silence is not an alternative to the ack.** A sender that gets nothing did not get an ack: it got an `unknown` (§8.4), and that is what its journal says.

### 7.2 Two acknowledgements, two owners — and only one is mechanical

| | carried by | when | value |
|---|---|---|---|
| **`ack`** | the **mechanical** layer | in the response, < 2 s | *I received this* |
| **`eta`** | the **agent** | later, by an outgoing message | *here is when I intend to answer* |

**An ack of reception is not a proof of presence**, and even less of reading: it says that a process wrote bytes. It does not say that a human or a model saw them.

### 7.3 `rx_ts` and `ack_ts`: a discipline clause, made measurable

- `rx_ts` = the instant the request line was read. `ack_ts` = the instant the response was written.
- **`ack_ts - rx_ts` is a number.** Its distribution is read in the journal **without any external surveillance**: if someone ever puts something that *thinks* inside the responder, it is not the clause that dies silently, it is a number that triples.
- These two fields **enter** the response (§7.1). It is the only place where local state is exposed — and it is **allowed because it describes nothing but reception**: never the content, never the peer, never the machine.

### 7.4 Write order (the clause that can be betrayed by the code, not by the text)

1. The **mechanical** layer: reads the line, validates the envelope, writes the response, **closes**. Done.
2. The **agent**: reads the buffer **on its own turn**, later, and answers by an **outgoing message** (`type:"msg"`, `re` = the `ts` of the message being answered — the session is carried by `sid`).

**No success without persistence.** For a new valid message, the buffer append succeeds BEFORE an `ok:true` ack is emitted. If the write cannot be completed, the response is `ok:false` with `error:"storage_error"`; there is no false acknowledgement and no claimed buffer entry. This is a mechanical refusal, never a model decision.

- **The model NEVER answers inside the incoming connection.** Otherwise the latency of the ack becomes the latency of the model and **§7.2 dies silently** — that is, the protocol looks conformant and is not.
- **Explicit prohibitions**: the model in the path of the responder · an ack that waits for a mailbox read · a response that waits for a human decision.
- **True by construction**: the mechanical layer opens no knowledge file, calls no model, and waits for nothing but the end of its write. A responder that reads a memory file while a sender waits is a responder whose ack measures a model.

### 7.5 `eta`: optional, declarative, overridable

- `{"type":"eta","re":"<ts>","sid":"<sid>","body":"<free text>"}` — sent **only** when the agent knows it cannot answer quickly. The default is **`ack` then `msg`**, with no `eta`.
- **An `eta` commits to nothing**: it can be exceeded without warning and without fault. It informs, it does not contract.
- **Silence is not a lie**: an agent with nothing to send emits no `eta` (silence may as well mean "I am working" — that is R2, on the semantic side).
- **Structural consequence, not to be discovered later**: an `eta` is a **later message**, therefore it must be **pushed** towards the sender. A node that publishes no address **never receives an `eta`**. That is not a defect: it is what separates a **peer** from a **counter** (§11).

---

## 8. Success, refusal, and the outcomes of a send

### 8.1 Transport success of a send

**Transport success of a send = `rc=0` AND `http=200`.** Nothing else. The journal is written **after** the return: a failed send cannot produce a false delivery log. Measured 2026-10-18: the correction was proven two minutes later, when the peer's node went down (`✗` instead of a false `200`).

### 8.2 Transport success is not semantic success

Unreadable envelope → `200` + the **same ack** with `ok:false` and an `error` code: `{"ok":false,"error":"<code>","rx_ts":…,"ack_ts":…,"re":…,"sid":…}`. The channel did its job, the message is refused, and the `200` is **deliberate**. **A refusal is an acknowledgement too**: it carries the two copies and the two produced fields like any other ack, and `re` and `sid` are empty strings when the envelope itself could not be read.

### 8.3 Closed table of refusals

**These codes are WIRE VALUES, and they are English like the rest of the protocol.** They are written and compared exactly as written, never translated: a value that travels on the wire is not prose, and a code is not a sentence. The six codes are `too_large`, `payload_too_large`, `invalid_envelope`, `unknown_type`, `unreadable_payload`, `storage_error`; the outcomes of a send and the reason of a wait are wire values too (§8.4, §10.5).

| condition | response |
|---|---|
| **the read returns `rc != 0`** (nothing read, partial line, cut) | **`408`** — decided by the return code, never by the content |
| raw path > 16 384 characters, **before decoding** | `too_large` |
| invalid base64, invalid JSON, not an object, missing required field, `body` not a string | `invalid_envelope` |
| decoded body > 1 048 576 bytes (POST) | `payload_too_large` |
| `type` absent from `{msg, eta, bye}` (including an `ack` sent as an envelope) | `unknown_type` |
| `v` != 1 | `invalid_envelope` (a version is negotiated by a document, not by an error code) |
| `msg` or `bye` without `sid`, `eta` without `re` | `invalid_envelope` |
| **invalid `reply_to`** | `invalid_envelope`, **at entry**, never at the reply |
| decoded payload empty | `unreadable_payload` |
| a new valid envelope cannot be appended to the buffer | `storage_error`, never `ok:true` |
| **unknown field** | **ignored**, not an error |
| **unknown route** | **`404`**, and it is reserved for that |

**Why `408` and not `400`**: a line reader does not distinguish *"the client closed"* from *"nothing arrived in time"* — both present themselves as a read that did not return the whole line. `408` (Request Timeout) is the only code that does not lie about that ambiguity, and it is **never** returned for a valid route. `404` stays available to say **one single thing**: this route does not exist.

**A `408` has an empty body and enters no buffer.** With `rc != 0` nothing was read: there is nothing to copy, nothing to acknowledge, and nothing to journal. It is the one answer of this protocol that carries no ack, because it is the one case where no message was received.

**The rule that makes all of this testable**: `408` ⇔ `rc != 0`. `rc = 0` ⇔ the line is complete. Parsing refusals from there on are **semantic** (`invalid_envelope`, `too_large`, `unknown_type`,
`unreadable_payload`); a valid envelope that cannot be persisted produces the distinct mechanical refusal `storage_error`. No cause is allowed to masquerade as another, and none produces a false success.

**Dated proof, and it arrived live (2026-10-21T01:38Z on desktop).** A message returned **`404` on the first attempt**, then **`200` on an identical resend** — same content, only the slowness of the circuit had changed. The `404` came from a **truncated line**: the path was no longer parsable, hence "unknown route". A client read *"this route does not exist"* where it should have read *"I did not receive the whole line"*. **That is exactly the ambiguity this rule removes**: with `408` ⇔ `rc != 0`, that case becomes a `408`, and `404` becomes what it must be. And it is the demonstration that the resend of §8.4 is indispensable: **without it, the sentence you are reading would not exist.** A `404` is not a proof that a route is absent; it may be a timeout disguised as a route.

### 8.4 Three outcomes of a send, not two

| outcome | definition | right to resend |
|---|---|---|
| `ok` | `http=200` and a JSON object carrying `ok:true` | no |
| `refused` | `http=200` and a JSON refusal carrying `ok:false` plus a non-empty `error` — the message is **not** in the peer's buffer | no (it is a refusal, not a failure) |
| `unknown` | timeout, `rc != 0`, `code=000`, invalid/truncated JSON, or any HTTP 200 without a usable verdict | **yes, the only authorised case**: 3 attempts 30 s apart, then abandon **recorded as `unknown`**, never as a failure (R2) |

The send journal carries **the outcome**, never the intention. In particular, malformed JSON or a bare `{"ok":false}` without an error is **not** a refusal: it is `unknown`. A retry reuses the identical envelope, so deduplication remains the only protection needed against a request that arrived despite its broken ack.

---

## 9. Idempotence, order, buffer

### 9.1 Identity key

**Identity key of a message: `(from, sid, mid)` when `mid` is present, otherwise `(from, sid, ts)`.** A node receiving an envelope whose key is already in its buffer **ignores it silently** and answers **the same thing** as a first send. No new error code: a resend is not a fault, it is the price of the timeout (§8.4).

- **A resend reuses the envelope IDENTICALLY** — same `ts`, same `mid`. Otherwise the key changes, deduplication no longer sees the duplicate, and two copies of one message enter the buffer.
- **A duplicate returns the recorded contents — same `re`, same `sid` — WITHOUT EVER re-emitting the outgoing response to `reply_to`, and WITHOUT the recorded timestamps.** `rx_ts` and `ack_ts` describe **this** reception, not the first one: an ack that replays an old `rx_ts` lies about the only number it produces. Without this sentence, this section and bound (b) of §12 contradict each other: a simple resend would become an amplification. **A message produces at most one outgoing response — the first.**

**Deduplication is atomic.** The lookup for an existing identity key and the first buffer append form one critical section with respect to concurrent receptions. If N identical envelopes arrive simultaneously, the node produces N acknowledgements but exactly ONE buffer entry.

### 9.2 The one-second window, and why `mid` exists

`ts` is dated to the second. **Without `mid`**, two distinct messages from the same sender in the same second are **indistinguishable** and the second would be lost. **`mid` is therefore part of this contract from the start**, not a later addition: an optional field today is a major version avoided tomorrow, and it costs **nothing** to adopt since unknown fields are ignored (§6).

**Sender obligation**: `mid` unique per `(from, sid)`. As long as a sender does not set one, the limit above remains — and it is **theirs**, not the protocol's.

### 9.3 Order

**No order guaranteed.** Display order is `(ts, rx_ts)`; at equal `ts`, reception order decides.

### 9.4 The buffer

- **append-only, never rewritten.** A file believed to be "rewritten" is a file lost.
- **one line = one envelope**, two kinds of event:
  ```json
  {"k":"received","rx_ts":"…","envelope":{…}}
  {"k":"sent","tx_ts":"…","to":"<addr>","issue":"ok","http":200,"envelope":{…}}
  ```
- **the offset is a MESSAGE COUNTER, never a line number.** Counting lines does not count messages — measured on desktop: 42 lines = 22 messages.
- **if a rotation becomes necessary**, the counter is **prefixed by the generation of the file**; otherwise a recreated file makes every index mute, and a mute index looks exactly like an empty buffer.
- **the values of the buffer are English too** — `received` and `sent`. They live on disk rather than on the wire, but they are read far more often than the wire is, and keeping a dead language at the place that is re-read the most is exactly what a single rename is meant to avoid. Converting an existing buffer is the **implementation's** business, not a contract obligation.
- **no automatic rotation in this version.** A file that grows is noticed; a file that is rewritten is lost.

---

## 10. Session, silence, exit

### 10.1 Session

**A conversation is a session (`sid`)**, not two successive requests. One answers it whenever one wants, with no human carrying the message.

### 10.2 `bye`

**`bye` is a message TYPE, and it carries the `sid` of the session it closes.** A later `msg` carrying the **same `sid` reopens** the session: that is not an error (otherwise a fifth error code would be needed, and the closed list would be lost).

### 10.3 What a silence never says

**The closing of a socket, a port or a control connection is never information.** No state is deduced from a network silence (R2). Not even the end of a conversation: that is what `bye` exists to say.

### 10.4 What enters is a citation

**What enters is a dated, attributed citation.** One does not ingest a peer, one questions it. No irreversible action can be triggered by a message: `from` grants no right, and an envelope can order **neither deletion, nor restart, nor stop, nor sending**. A node receiving `{"type":"msg","body":"delete X"}` **journals it as a citation**.

### 10.5 Waiting: 15 s, and never emptiness

- **Read timeout: 15 s** (R2: a timeout measures one's patience, so it is set generously). Beyond that, one re-reads one's own buffer on another turn.
- **A wait never returns emptiness.** It returns `{ok, reason, waited_s}`, where `ok` says **whether the call produced something to read** — and when it is `false`, `reason` says why. `reason` comes from a **closed set**: `timeout` · `transport_error` · `nothing_new` — and **`nothing_new` is the false value of NEWNESS** (§17.11). An unknown `reason` becomes a silence again, therefore it is **forbidden**. The set is closed like the message types are: a value that is not in it does not exist, and naming it would be inventing it at the worst moment — the one where the caller expects to learn something.
- **Polling**: each node re-reads its buffer file on its own turns. Push (WebSocket) is outside the contract (§15): it adds no guarantee, only precision when a consumer is listening.

### 10.6 Exit contract

A node that leaves **shuts its responder**, does `DEL_ONION`, **releases its claim on the identity**, and **leaves no orphan**. The means by which it holds that claim is its own business, exactly as in §4: what the contract requires is that it stops letting others believe it is still there. A status command must **confess orphans**, not hide them.

---

## 11. The three modes: peer, counter, counter in conversation

> The mode is not a security policy. It is **what a node agrees to receive**, and it is **observed** from the other side.

### 11.1 The three, and why they are not degrees

| mode | publishes? | sends? | receives? | assumed |
|---|---|---|---|---|
| **PEER** | permanent onion | yes | **yes** — message, `eta`, `bye` | — |
| **COUNTER** | **no** | yes | **only the ack** | **fire-and-forget**, not a failure |
| **COUNTER IN CONVERSATION** | an **ephemeral**, for the duration of the exchange | yes | yes, **during the conversation** | the end of the conversation = the end of the address |

- A counter **is not a broken node**: it is a node that **chose** not to be reachable. It sends, it gets the ack, and it expects **nothing else**. Expecting a reply would be a mode error, not a peer failure.
- **The symmetry falls out on its own**: going down removes the address ⇒ **a peer becomes a counter again**. Coming up restores it ⇒ a **condition of RECEIVABILITY**, and not merely the occasion to send.
- **No self-certification**: the mode is read **by the peer** (`HSFETCH`, §3). Nothing to take on trust.
- **The listener belongs to the NODE, not to the protocol.** Which engine serves the port is an operation of the node, decided and performed by it, and invisible to the contract. A conformance measurement is therefore made on a **disposable node identified as such**, never by swapping the engine of a node in service: measured 2026-10-22T22:09Z on desktop, a supervised listener restored its own engine within one second, and the measurement simply measured the supervisor. A protocol that prescribed the supervisor would be describing an implementation, and an implementation that let a peer replace its engine would be describing a vulnerability.

### 11.2 Becoming reachable, and accepting a peer, are human gestures

- **Opening an address, and adding a peer, are decisions of the node's owner** — never an autonomous initiative of a program or of a model.
- Reason: a node able to open an address by itself could make itself reachable without anyone having decided it, and "reachable" is precisely what one chooses. The wire says nothing about who pressed the button: the clause is on the gesture, not on a command name.

### 11.3 `reply_to`: how a counter receives its answer

When the mode is chosen **per exchange**, the address must **travel with the message**: that is the role of `reply_to` (§12). Without it, the peer does not know where to answer and the counter in conversation stays theoretical.

- **`reply_to` absent** ⇒ one answers the peer **as identified in the peer list** (a permanent peer has nothing to fill in). **An address is never deduced from the connection**: an onion circuit carries no return address — no IP, no identity, nothing to answer to. The connection says that someone spoke, never who it was. And if an address could be deduced from it, one would be answering a **non-authenticated source**, which bound (a bis) of §12 forbids: what we send back is not a message, it is a **capability**.
- **`reply_to` present** ⇒ one answers **there**, and that address does **not** need to be in the peer list.

### 11.4 The ephemeral: the property comes from the process

**A publication order without the detach flag ⇒ the service lives as long as the process lives** (measured). An ephemeral identity is therefore **not a policy to write**: it is **a process that dies**.

| | **permanent** | **ephemeral** |
|---|---|---|
| address | stable, exchanged **out of band** | never written in the peer list |
| key | persistent on disk | **in RAM only**, dies with the process |
| revocation | delete a line | **`DEL_ONION`** — and killing the process is not enough when the service is detached |
| duration | ∞ | that of the process — **no automatic TTL** |
| announced as such? | — | **NEVER** |

**Revocation is an order, not a consequence.** Measured 2026-10-22T00:15Z on desktop: a **detached** service survives the death of its process, because it is held by the control connection and not by the program that opened it. A detached ephemeral that is only killed keeps answering, and its key was in RAM — so the address is dead in the mind of its owner and alive on the network. `DEL_ONION` is the only revocation that is one.

### 11.5 The four invariants of the ephemeral

1. **The ephemeral key NEVER touches the disk.** Otherwise revocation is only **logical**: the identity stays resurrectable, and a dead identity one can switch back on is not dead.
2. **The `from` of an ephemeral is NEVER the permanent alias.** It carries **its own name**; the mapping lives in the local store, **never in the message**. Otherwise the address is new and the label tells everything.
3. **An ephemeral never PROMOTES itself.** It is **renewed by another ephemeral**. Promoting would manufacture an address **with a history** — therefore correlatable.
4. **The link NEVER appears in the envelope.** No field says "I am temporary": that would announce an attack window **and** a level of trust to grant.

### 11.6 The sequence, and its price

**publish → verify LOCALLY → send → wait → die.**

- **Publish BEFORE sending**, otherwise the answer arrives before the address is reachable.
- **Verify locally**: it is the only verification that is worth anything for oneself — an `HSFETCH` on one's own onion is incoherent (§3), so the check is a call to `127.0.0.1`.
- **Measured cost: ~9 s cold, up to 70 s when the Tor state is dirty** ⇒ **~10 s for a first contact**. It is not an optimisation to perform, it is **a constraint of the sequence**: **~10 s is the PRICE OF THE IDENTITY**. Whoever wants zero waiting is a **pure counter** and accepts fire-and-forget.
- **Default for a first contact: the counter in conversation.** Including for a peer that is not us.

### 11.7 Tests of the ephemeral (the negative one is the proof)

The commands live in the non-normative annex (§15); what follows is the contract, and it is judged on this.

- **(a) While the ephemeral lives**, the peer obtains a successful response on the ping route. Expected: `200`.
- **(b) After revocation**, the peer obtains nothing at all: no `200`, no session, no service. Expected: no HTTP response, and a SOCKS code of **4** — an absent descriptor, not a port without a backend (`(5)`, §3). **This is the test that matters.**
- **(c) Absence of the descriptor is not immediate.** A **cached** descriptor may still route for a while. **R2: a delay is not a proof of failure.** Any local probe is a convenience, outside the contract.
- **Test in loopback**, never through a Tor self-call from the same instance: that would offer for free a **temporal correlation** between the ephemeral and the permanent one.

### 11.8 Four points settled by coherence (to be contradicted if wrong)

| # | question | answer, and why it follows from the rest |
|---|---|---|
| a | Does an ephemeral **accept** replies? | **YES** — otherwise it is not a counter in conversation, it is a blind sender; and it keeps nothing beyond its life. |
| b | Default **TTL**? | **No.** Death is a **human gesture** (end of conversation). An automatic TTL is a policy that gets forgotten and expires at the wrong moment. |
| c | A peer that can no longer reach it? | **Nothing.** Explicit exception to R2: *an ephemeral that no longer answers is not broken, it is finished.* |
| d | `bye` on an ephemeral? | **`bye` stays the politeness**; dying without `bye` is the **expected default**, not an incident. |

**Point (c) is the only exception to R2 in this whole document**, and §11.7 (b) is where it applies: after revocation, obtaining nothing is the expected result, never a window that was too short. §11.7 (c) then keeps R2's own patience about the cache — the same exception, applied once, not a second one.

---

## 12. `reply_to` — a datum, never an authorisation

> `reply_to` does not only expose us: it makes us **go out**. It turns the responder into an **outgoing client towards an address chosen by the sender**. Six bounds, and they hold together.

- **a) Form validated before any use**: onion v3, **56 base32 characters**. Otherwise the message is refused **at entry** with `invalid_envelope` (§8.3), and **no outgoing reply is attempted** toward that address: answering an invalid address is already attempting to go out. **The field carries the address WITHOUT its port and WITHOUT the `.onion` suffix**: the virtual port is 80 and it is the only one admitted (§4). A human interface may accept the suffix and remove it before constructing the envelope (§18.2); the wire may not.
- **a bis) The outgoing reply contains ONLY the envelope** — never an echo of local state (`who`, counters, paths, buffer size). *What we send back to an address chosen by the other side is not a message, it is a **CAPABILITY**.* One field too many, and a **probe** is offered to whoever chose the target.
- **a ter) Global ceiling on outgoing replies per window**, independent of (b): a sender who **varies `from` and `sid`** bypasses the single use on every send ⇒ **an amplifier with fresh identifiers**.
- **b) Single use per message** — that is, per **identity key** (§9.1), not per sender: **one** reply per message, never a cascading retry. The single-use check and its recording are atomic with respect to concurrent replies, including concurrent local agent commands.
- **c) Refusal if `reply_to` points at my own address**: loop. Refused like (a), **at entry**, with `invalid_envelope`.
- **d) No write into the peer list**: an address seen in `reply_to` is used **once** and **never** becomes a peer. Otherwise one pairs by injection.

**Without (a)** one can aim anywhere · **without (b)** one amplifies · **without (c)** one loops · **without (d)** one pairs by injection · **without (a bis)** one becomes a probe · **without (a ter)** one amplifies even with fresh identifiers.

> **Chapter rule: `reply_to` is a DATUM, never an AUTHORISATION.** It says *where to answer*, it does not say *who is entitled to ask for an answer*.

---

## 13. Conformance tests — judged on prose, not on commands

These are the tests a conformant implementation must pass. They are written as behaviour, with the expected result **named**, because a command is one implementation's convenience and a result is the contract. The commands that produced these measurements are in the annex (§15), explicitly non-normative.

**Six tests, run FROM THE PEER**, i.e. from a node that is not the one under test:

| # | what is sent | expected result |
|---|---|---|
| **(a)** | a request on the ping route | `200`, and `ok:true` in the body |
| **(b)** | a well-formed envelope whose `type` is unknown to the closed list | `200`, `ok:false`, `error` = `unknown_type` |
| **(c)** | a path longer than the ceiling, before decoding | `200`, `ok:false`, `error` = `too_large` |
| **(d)** | a path carrying invalid JSON after decoding | `200`, `ok:false`, `error` = `invalid_envelope` |
| **(e)** | a POST `/say` with decoded body > 1 048 577 bytes | `200`, `ok:false`, `error` = `payload_too_large` |
| **(f)** | a valid envelope on either method | `200` with correct `ok:true`, copied `re`/`sid`, and fresh `rx_ts`/`ack_ts` |

- **(b), (c) and (d) can only pass if the parser exists.** A permissive reader answers `ok:true` to all three. Measured 2026-10-19T01:52:51Z at mobile: an unknown `type` came back as `{"ok":true,…,"got":"{…}"}`. A node that accepts anything has not implemented the closed list, it has implemented indifference.
- **(a) is a positive test**: it proves that the node is there, never that it conforms.
- **Proof of emission**: the `{"k":"sent",…}` line of the buffer, shown as it is, carrying `/say/<b64>` and **the path carries the encoded envelope and nothing else**. A path that still carries the sender's name is not an implementation of this contract, whatever it claims.
- **A claim the peer cannot reproduce is not a claim.** And **a fact that was never measured does not enter a document** — real fault, 2026-10-19: a function name was written in the document that **does not exist anywhere**, born from merging two neighbouring names. It was found by the peer, not by its author.

- **Version support is tested when it is claimed.** For every legacy format a node declares supporting, a fixture produced by that version is read and reported with the version actually used. An explicitly unknown version is refused, and no fallback occurs after a recognised version has failed its own validation. A second test proves that the node still emits the current format by default. These tests prove declared compatibility; they do not invent support for a version that was never claimed.

---

## 14. Open questions (with the measurement that settles them)

These are not clauses. They are what the protocol does not know yet, written down so that nobody fills the gap with a belief.

1. **Publication window through Tor, at scale**: how many `REGISTERED` → first `200`, over 20 successive republications? One measures it by fetching the descriptor then looping the traversal.
2. **Size and latency**: 128 000 characters pass locally, 60 000 pass through Tor, and above all the shape of the curve — 2 000 characters: 6.7 s · 20 000: 1.6 s · 60 000: 2.3 s (desktop, 2026-10-19T01:19:38Z) draws no monotone progression, so at this point nothing is known.
3. **Signed `from`?** The Ed25519 key already exists. A `sig` field would make attribution verifiable without any PKI — cost: one more parser. **Not necessary for conformance**, and the envelope already ignores unknown fields (§6), so the addition breaks nothing.
4. **N = 3, and the usurpation of `from` by a legitimate peer.** With two nodes, the question *"who could this be"* has one answer. **With three, `from` becomes usurpable by a trusted peer**: the same route path receives three possible senders. Written, never measured — **the third node is the only judge**.
5. **Anti-replay window.** Deduplication on `(from, sid, ts)` prevents a duplicate, not a **replay** inside the same second. To be decided the day a message carries an effect.

---

## 15. Annexes — **NON-NORMATIVE** (written here to be explicitly outside the contract)

Everything below is either an observation about particular tools, or an explicit exclusion.
**Conformance is judged on the prose of §13 and nowhere else.** An implementation that never reads this annex can be fully conformant.

### 15.1 Commands that produced the measurements

Portable in the sense that they depend only on widely available tools; they are still **one implementation's convenience**, never the contract.

```sh
# is my own door alive?  (R1: wide window, otherwise it is my patience that speaks)
curl -s --max-time 60 --socks5-hostname 127.0.0.1:9050 "http://<addr>.onion/ping"

# is the peer's descriptor in the DHT?  (PUBLISHED, §3 — the only asymmetric state)
COOKIE=$( { printf 'PROTOCOLINFO 1\r\nQUIT\r\n'; sleep 1; } | socat - TCP:127.0.0.1:9051 \
         | sed -n 's/.*COOKIEFILE="\([^"]*\)".*/\1/p' | tr -d '\r' )
HEX=$(od -An -tx1 -v "$COOKIE" | tr -d ' \n')
{ printf 'AUTHENTICATE %s\r\n' "$HEX"; printf 'SETEVENTS HS_DESC\r\n'
  printf 'HSFETCH %s\r\n' "<addr without .onion>"; sleep 5; } | socat - TCP:127.0.0.1:9051
#   -> 650 HS_DESC RECEIVED = published ; nothing = not published ; then traverse for REACHABLE
#   CAUTION: an HS_DESC about ONE'S OWN node may come from the local cache.

# create an identity — measured 2026-10-24: WITHOUT a Port= mapping, Tor answers
# "512 Missing 'Port' argument". Identity and virtual port are born together.
{ printf 'AUTHENTICATE %s\r\n' "$HEX"
  printf 'ADD_ONION NEW:ED25519-V3 Port=80,127.0.0.1:18080\r\n'; sleep 1; } | socat - TCP:127.0.0.1:9051
#   -> 250-ServiceID=<56 base32> (the address) and 250-PrivateKey=ED25519-V3:<blob>
#   Store the key (mode 600): replaying this line with the stored key republishes the SAME address.
#   Nothing stays published while nothing listens behind it: DEL_ONION <sid> until the listener is up.
```

- **If the announced `COOKIEFILE` is unreadable** — a case **measured** on Termux, 2026-10-21 — the byte dump renders an empty string, and authentication fails **without saying anything**: no exception, no message. Rule: **`CONTROL` absent ⇒ stop there** (§3). One does not continue on a hypothesis, and one asserts nothing beyond "I could not bring myself under control". Same family as R1: a silence is not a result.

### 15.2 The four conformance tests, as commands

```sh
A="http://<addr>.onion"
curl -s --max-time 60 --socks5-hostname 127.0.0.1:9050 "$A/ping"                       # (a) 200 + ok:true
curl -s --max-time 60 --socks5-hostname 127.0.0.1:9050 "$A/say/<b64(type=xyz)>"        # (b) unknown_type
curl -s --max-time 60 --socks5-hostname 127.0.0.1:9050 "$A/say/<b64(17000 chars)>"     # (c) too_large
curl -s --max-time 60 --socks5-hostname 127.0.0.1:9050 "$A/say/<b64(invalid JSON)>"    # (d) invalid_envelope
```

### 15.3 What is explicitly outside the contract

- **WebSocket / a second port.** Measured 2026-10-19T01:19:30Z: `400` through Tor ("Only WebSocket connections are welcome here") ⇒ it **works**, but it **adds no guarantee**: framing and closing are obtained with one line of JSON plus `bye`. Its only gain is **push**, which is worth something only if a consumer is listening.
- **Local convenience tools** (a listener loop, an inbox reader, a guard, a probe). They are shell tools of one node, never design elements: a blocking listener loop produced a deadlock at 00:31Z, on the first night (2026-10-18→19). Since then, waiting is done by re-reading one's buffer (§10.5). A document cites them only while saying so.
- **Orphaned listeners.** Measured 5 live processes and 13 orphans on desktop, `550 collision` on both. §11.4 stands: a **detached** service makes `DEL_ONION` mandatory. The fault is a service left alive without its owner, never a key that outlives its process — §11.4 requires that key.
- **`who` as identity, fingerprint as proof.** Forbidden as a basis for any decision (§2).
- **A message queue at a third party.** Refused on principle: *keeping a message for a sleeping peer is already starting to speak in its place.* **Scope precision**: keeping a message **at the sender** while the peer is down is **not** that queue — it is one's own notebook, nobody in the middle, no daemon.
- **Automatic peer discovery.** The address is exchanged **out of band**, never by the protocol.
- **Any escaping convention for line feeds is ambiguous.** Measured 2026-10-21T01:35Z: a document sent with its line feeds escaped came back as **634 lines against 623** at the sender — the legitimate content already contained `\r\n` inside shell examples, which the unescaping turned into real line feeds. **To exchange a document, the exact encoding is base64**, never an escaping; and a document is authenticated by its **sha256**, not by its line count.
- **Application-level encryption.** Tor provides the transport; one does not stack.

---

## 16. Versions and change control

**Revision record**

- **1.3 — 2026-11-12**: additive support for `POST /say` (1024 KiB payload) while retaining the historic GET transport and its 16 KiB request-line limit. Introduction of the distinct refusal code `payload_too_large`. Updated routes, refusal table, conformance tests and transport rules. The envelope remains **`v:1`**.
- **1.2 — 2026-10-27**: adds explicit backward-compatibility discipline: supported legacy formats remain readable, current formats remain the default for emission, legacy discovery is bounded and reported, and no version failure may silently become a downgrade. The envelope remains **`v:1`**.
- **1.1 — 2026-10-25**: hardening after a live two-node flow and an independent static cross-review. Adds `storage_error`, honest handling of unusable send responses, atomic deduplication/reply bounds, octet `Content-Length`, listener-ownership and private-key hygiene requirements, and the normative onboarding surface of §18. The envelope remains **`v:1`**.
- **1.0 — 2026-10-24**: initial self-sufficient contract.

**Backward compatibility**

- **Read what you declare, write what is current.** A node reads every legacy format it explicitly declares supporting and emits the current format by default. Emitting a legacy format requires a deliberate local compatibility decision and is recorded in the local journal. A peer cannot force that decision on the wire.
- **A recognised version selects its own parser.** If parsing or validation fails under that version, the failure remains a failure; no older parser is tried. An explicitly unsupported version receives the refusal already defined for it (`invalid_envelope` for an envelope `v`), never an implicit downgrade.
- **Absence is the only discovery case.** Legacy discovery is allowed only when the marker is absent and at least one declared legacy format permits that absence. The node tries only its declared legacy parsers, in a documented bounded order. A successful read reports the version actually used, the absence of the marker, and every fallback attempted. A parse that succeeds without satisfying the legacy validation is not a successful read.
- **Compatibility is format tolerance, never weaker authority.** Peer-list boundaries, `reply_to` rules, deduplication, refusal honesty, and safety bounds are never relaxed by a fallback. Unknown fields remain ignored as defined in §6; malformed known fields do not become acceptable in the name of compatibility.
- **Documents and envelopes age independently.** Supporting an older document revision does not imply support for another envelope `v`, and supporting another `v` does not imply that every document revision is implemented. The support claimed by a node is explicit and testable (§13).
- **Stored history is not rewritten by an upgrade.** Existing buffers, journals and identity material remain readable. A local migration is a separate deliberate operation; it never silently changes identity keys, message identity, or the meaning of a recorded outcome.

- **A change of substance is a new version**, never an edit of this one — dated, with the reason of each change named.
- **An implementation that knowingly deviates declares it**, with a date, and removes the declaration when repaired. An unstated deviation will be measured by the peer, and on that day it is trust that pays, not code.
- **Conformance is judged on the prose of §13 and nowhere else.** The annexes of §15 are non-normative; an implementation that never reads them can be fully conformant.
- **Nothing about a particular deployment belongs here**: no address, no host name, no path, no process name. A normative document describes behaviour, never an installation.

---

## 17. Vocabulary

**This vocabulary is part of the contract.** A term defined here carries the WHOLE definition: no gloss is needed, and no other meaning is admissible.

**Rule of the document.** This vocabulary NAMES. It does not RULE. If a definition contradicts a clause, the clause prevails. A vocabulary that settles a rule is not a vocabulary: it is a disguised amendment.

**Rule of the single word.** One English word per concept, and it carries the whole definition. If a word needs a gloss to be understood, it is the wrong word.

**Field names are not translated.** `v`, `type`, `from`, `ts`, `sid`, `mid`, `re`, `body`, `reply_to`, `engine`, `rx_ts`, `ack_ts` keep their spelling in every language. Translating a field name breaks the wire.

### 17.1 PEER

A node that publishes a permanent onion: it sends, and it can receive.

The normative meaning is the CAPACITY to receive, not the fact of appearing in a peers list. Being in the list is an AUTHORISATION, not a state.

### 17.2 COUNTER

A node that publishes no PERMANENT onion: it sends and receives nothing but the ack.

The word names a PLACE (the counter), not an actor. It states what is missing (no door), not what is present. It distinguishes PERMANENCE, not publication — a counter in conversation (§17.3) does publish, briefly.

*Rejected: CALLER* — a peer also calls, so the word distinguishes nothing.

### 17.3 COUNTER IN CONVERSATION

A counter that publishes an ephemeral for the duration of an exchange, key held in RAM, no line written in the peers list. Default mode for a first contact.

### 17.4 ACK

The BODY of the HTTP response to the same request. Mechanical: it copies `re` and `sid` without interpreting either of them. Synchronous by construction, not by discipline.

TWO fields are COPIES, TWO are PRODUCED, and `ok` is the verdict. `rx_ts` is the instant the responder received the request, `ack_ts` the instant it emitted the ack. They are not read from anywhere and they are not recopied from the envelope: the responder writes them. Their difference `ack_ts - rx_ts` is therefore a number readable from INSIDE the wire, and its drift is observable in the response itself, without any external surveillance. An implementation that copies more fields than this has not implemented the ack, it has made it a report.

Trap: an ack of RECEPTION is not a proof of PRESENCE.

An ack proves that a node wrote, never that the node that matters received.

Invariable spelling. Never "acknowledgement".

### 17.5 ETA

Estimated arrival of the semantic reply, emitted by the agent. ALWAYS optional, ALWAYS overridable. A wrong eta is not a fault: it is a declaration, not a promise. The only commitment of the wire is the ack.

### 17.6 BUFFER

Append-only journal, one line = one JSON envelope, never rewritten in place. Rotation, if one ever becomes necessary, is a new file plus a GENERATION prefix, the old file remaining readable read-only.

Trap: it is counted in MESSAGES, never in lines.

*Rejected: log* — it keeps the idea of free text and of re-reading.

### 17.7 WRITE ORDER

The mechanical layer writes the response and closes. The model NEVER replies inside the incoming connection; it replies by an outgoing message with `re` = the `ts` of the message it answers.

If the responder ever imports anything that THINKS, the ack takes the latency of the model and this clause dies silently.

### 17.8 EPHEMERAL

An onion whose key is never on disk and whose lifetime is that of the process.

Revocation is not a policy: it is `DEL_ONION`. Killing the process does not suffice in Detach mode — a detached service survives the closing of the control connection, and one was measured still answering a minute after the `QUIT` (desktop, 2026-10-22).

### 17.9 PUBLISHED

The descriptor is observable BY THE PEER, through `HSFETCH` then `HS_DESC RECEIVED`.

On the emitting side nothing stronger than REGISTERED (§17.18) can be asserted.

Corollary: `GETINFO onions/current` does not prove PUBLISHED. It is empty on a live ephemeral.

### 17.10 REACHABLE

The peer obtains a successful response on the ping route.

The definition names the FACT — the peer does not reach the service — never the CODE that reported it: SOCKS 5, a timeout and 000 are three forms of one fact.

The relation is DATED: REACHABLE(t) implies PUBLISHED(t). The reverse never holds, not even at the same instant. A 200 is a timestamp, not a state.

### 17.11 NEWNESS

Whether there exists a message not yet read. A BOOLEAN, not a number.

### 17.12 MESSAGE COUNTER

Index of the last message processed, in MESSAGES, never in lines.

Measured trap: 42 lines = 22 messages.

### 17.13 GENERATION

Identifier of the buffer file, and prefix of the MESSAGE COUNTER. A counter without a generation is mute after rotation.

### 17.14 FINGERPRINT

`sha256(address)[0:16]` rendered `xxxx-xxxx-xxxx-xxxx`. Display only. NEVER a proof.

### 17.15 DESCRIPTOR

What Tor publishes. An absent descriptor means not reachable. A cached descriptor may still route for a while, so a delay does not prove a failure.

### 17.16 SKEW

Clock difference between peers. Measured: 5 s. No clause derives a tolerance from it: the one window that would need one is an open question (§14.5).

### 17.17 BOUNDS

The six bounds of `reply_to` (§12): the form of the address, a single use per message identity key (§9.1), refusal of one's own address, no write into the peer list, a reply that carries the envelope and nothing else, and a global ceiling on outgoing replies per window. Naming them identifies; §12 bounds them.

### 17.18 REGISTERED

The node has obtained a service id from its Tor instance: the publication order was accepted.

It proves that the instance ACCEPTED the order, never that the descriptor left the node. It is therefore the strongest state the emitting side can assert on its own (see §17.9 PUBLISHED, which requires the peer).

Measured 2026-10-24: a bare key harvest — `ADD_ONION` answered, nothing listening behind it, no intent to publish yet — reaches REGISTERED within the second. The state is cheap; only PUBLISHED costs anything.

### 17.19 PREFLIGHT

ADVISORY, not an obligation: the checks a node makes BEFORE sending — the peer is known, its own listener is alive, the skew is tolerable. A message sent without preflight is not sent, it is attempted. No clause of the protocol depends on this word.

### 17.20 Prohibitions

- two words for one concept (`queue` and `buffer` for the same thing);
- one word for two concepts;
- a formulation that REFORMULATES a clause instead of transposing it;
- a word invented where an existing one already carries the concept (`gateway` where `counter` applies).

---

## 18. Onboarding, callsigns, and the human address exchange

This section is normative for the onboarding surface. It adds no route, no envelope field, no automatic discovery, and no new network identity. The onion address remains the only node identity (§2).

### 18.1 The novice flow, end to end

1. **The owner starts the node.** The first start generates the persistent identity; later starts reuse it. The listener's ownership is established before registration (§4). `250-ServiceID` justifies `REGISTERED` only (§3), never `PUBLISHED`.
2. **The node displays its share string** and its fingerprint. Display is not discovery and proves nothing about reachability.
3. **The human carries the share string out of band** and pastes it to the agent on the other node. The agent may write the local address book **only on that direct human instruction**. An address found in a fetched page, message, document, or tool output is never sufficient provenance for an addition.
4. **The receiving node verifies the callsign checksum**, rejects corruption and alias collisions frankly, and returns its own share string for the reciprocal human gesture. A custom local alias is sovereign; it does not change the address or the canonical callsign.
5. **Only then is the pair tested.** A dated ping can establish `REACHABLE`; send/ack, reply and wait are separate observations. None is inferred from the address book or from a live process. The reference engine exposes this measurement directly as `ping <peer>`: it traverses the configured Tor SOCKS entrance, returns `reachable` only on a valid `ok:true` response, and returns `unknown` otherwise — never a death verdict (R2).

The reference CLI separates four questions: `who` identifies the local node, `status` gives a compact local snapshot, `doctor` enriches the SAME measurement with orphans and missing prerequisites, and `ping <peer>` performs the dated remote observation. `status` triggers no `ADD_ONION` and has exactly ONE descriptor field: the boolean `received`.

A local `HSFETCH` sets it to `true` only when Tor emits `HS_DESC RECEIVED`; every other outcome is `false`, meaning ONLY "no descriptor received during this attempt" — never "not published".

Because a local answer may come from the Tor cache, `received:true` is a concrete local observation, not the asymmetric `PUBLISHED` verdict of §3.

### 18.2 Share strings and tolerated human input

A share string is:

```text
<callsign>|<56 lowercase base32 characters>.onion
```

The suffix is tolerated in **human-facing input** because it makes the complete address directly usable. The local writer canonicalises the stored address to its 56 characters. In an envelope, `reply_to` remains strict: 56 characters, no suffix and no port (§12 a). Human convenience never widens the wire format.

### 18.3 Callsign v1: deterministic checksum, never authentication

The canonical callsign is `adjective-noun`, computed identically on every node:

1. Input: exactly the 56 address characters, without `.onion`, without a newline, hashed with SHA-256.
2. Take digest byte 8 (zero-based; hexadecimal characters 17–18), apply `& 0x7f`: this is the zero-based adjective index.
3. Take digest byte 9 (hexadecimal characters 19–20), apply `& 0x7f`: this is the zero-based noun index.
4. Join the two words with `-`. Recompute on display; do not store it as identity.

There are **128 × 128 = 16 384** canonical callsigns. A callsign is a pronounceable corruption checksum and a local display convenience, **never a globally unique identifier and never a proof**. A collision in a local address book is refused and may be resolved by an explicit local alias such as a `-2` suffix; the canonical callsign itself remains two segments. If a third segment is ever needed, it is a later, non-breaking local collision mechanism, not a renaming of existing nodes.

The two ordered English lists are **frozen v1 protocol surface**. They are not locale-dependent. Changing one word or one position changes derived names and therefore requires an explicitly versioned callsign revision, never a silent edit.

```sh
JARNET_ADJ=(
  amber ashen azure bronze cobalt copper coral crimson
  ebony golden hazel indigo ivory jade lilac ochre
  olive onyx opal pearl ruby russet rusty sandy
  scarlet sienna silver slate snowy teal violet gray
  bright dim lucid lunar shady solar stark vivid
  crisp dusty fluffy fuzzy glossy mossy rough silky
  sleek smooth soft stony velvet woolly gritty matte
  arctic balmy boreal chilly cold cool cozy frosty
  frozen icy mild polar warm wintry humid torrid
  agile bold brave brisk calm deft eager fleet
  gentle hasty keen lazy merry nimble plucky proud
  quick quiet rapid serene shy silent sleepy slow
  steady swift tame wary wild witty zesty jolly
  broad grand hardy lean mighty stout sturdy tiny
  tough vast young elder ancient fresh mellow modern
  cosmic curious honest lucky rustic sincere tidy tranquil
)

JARNET_NOUN=(
  badger beaver bison bobcat camel cougar coyote dingo
  ermine ferret fox goat hare ibex jaguar koala
  lemur llama lynx marten mink mole moose ocelot
  orca otter panda panther puma rabbit raccoon rat
  seal sheep shrew skunk sloth tapir tiger walrus
  weasel wolf wombat yak zebra marmot possum gibbon
  crane crow dove eagle falcon finch goose gull
  hawk heron ibis jay kite lark magpie merlin
  owl pelican puffin raven robin rook sparrow stork
  swan thrush toucan wren osprey parrot pigeon condor
  adder beetle cobra gecko iguana lizard mantis moth
  newt python turtle viper wasp bass crab eel
  marlin pike ray salmon shark squid trout tuna
  acorn alder aspen birch cedar cliff cloud comet
  dune elm ember fern fjord flint grove cove
  maple marsh meadow moss oak pine quartz reef
)
```

### 18.4 Address-book boundaries

The address book is a local authorisation, not a network state (§2). It is never emitted on the wire and is never populated from `reply_to` (§12 d). The reference behaviour is: accept a complete share string, verify its callsign, reject a duplicate address or alias without changing the existing entry, and write strictly `alias|address|note` locally. Storage details may differ; these boundaries may not.

### 18.5 Local alias and persistent key files

The wire alias remains an attributed display claim. If an implementation uses `keys/<alias>.key` and `keys/<alias>.addr`, then **the alias also names the local identity at first start**. That storage decision is explicit: there is no implicit rename and no silent migration to another key. Renaming such an identity is a separate, deliberate migration operation. This convention never contradicts §2, because no protocol decision or authentication is derived from the alias.

### 18.6 Private-key hygiene during first start

A first registration may return a new private key in the control response. The key is passed to the holder without appearing in process arguments; the response file is created owner-only before any response can arrive; the persistent key file is written owner-only; and the transcript copy is removed immediately after successful harvesting. A later status or restart never treats the transcript as another long-term key store.
