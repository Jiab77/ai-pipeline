#!/usr/bin/env bash
# shellcheck shell=bash
# ==============================================================================
# plugins/jarnet.sh — Mechanical engine for the JARNET protocol
# ==============================================================================
# Implements the protocol listener, envelope handling, identity and peer
# onboarding, journaling, and Tor hidden-service lifecycle.
#
# Author: Jiab77
# Collaborator: Jarvis
# Version: 1.3.1
#
# Contract: jarnet.md 1.3; wire envelope v:1
# Conformance oracle: tests/jarnet-selftest.sh
# ==============================================================================
#
# Implemented (contract sections v1.3):
#   §4  HTTP/1.0, one process per request, loopback only. Supports both
#       GET /say/<b64url> (raw request line ≤ 16384) and POST /say
#       (decoded JSON body ≤ 1 MiB).
#   §5  Routes: /ping, / (alias), /say (GET + POST). Two distinct limits
#       and refusal codes: too_large (GET) and payload_too_large (POST).
#       Order of checks is normative.
#   §6  Envelope v1, base64url (no padding emitted, padding accepted),
#       unknown fields ignored.
#   §7  Ack format unchanged.
#   §8  Closed refusal table now includes payload_too_large.
#   §9–§12, §17–§18 unchanged (dedup, reply_to bounds, callsign, etc.)
#
# This version is fully conformant to JARNET 1.3 (2026-11-12).
# Backward compatible with 1.1 and 1.2 nodes via GET path.
# ============================================================================
#
# Implemented (contract sections):
#   §4  HTTP/1.0, one process per request, request line only, listener bound
#       to LOOPBACK ONLY (TCP-LISTEN bind=127.0.0.1), one port, two routes,
#       raw request-line length journaled before any decoding
#   §5  /ping, / (served, never counted), /say/<b64url(envelope)>, 404 else;
#       `engine` = protocol version; ceiling 16 384 measured on the RAW path;
#       order of controls normative (too_large before any decoding)
#   §6  envelope v/type/from/ts/sid/[mid]/re/body/[reply_to]; base64url
#       emitted WITHOUT padding, accepted WITH; unknown fields ignored;
#       body required (and a string) for msg AND eta; sid required for
#       msg and bye; re required for eta; ts and from required, non-empty
#   §7  ack = body of the response: re+sid copied, rx_ts+ack_ts produced,
#       ok = verdict — NOTHING else; refusal = same shape + error, re/sid
#       empty when the envelope was unreadable
#   §8  closed refusal table; 408 <=> read rc != 0, empty body, no buffer
#       entry; send outcomes ok / refused / unknown (resend only on unknown:
#       3 attempts 30 s apart, identical envelope); journal written AFTER
#   §9  identity key (from,sid,mid) or (from,sid,ts); duplicate answers the
#       recorded content (same re/sid) with FRESH timestamps, writes nothing,
#       never re-emits an outgoing reply; buffer append-only, one line = one
#       event, offset = MESSAGE counter, no automatic rotation
#   §10 wait returns {ok, reason, waited_s}, reason in the closed set
#       {timeout, transport_error, nothing_new}; read window 15 s; a status
#       confesses orphans (§10.6)
#   §12 the six bounds of reply_to: form (56 base32, no port) at entry,
#       single use per identity key, own-address loop refused, peers.txt
#       never written by a reply, outgoing reply = envelope only, global
#       ceiling per window; `re` is a `ts`, never a `sid`
#   §11  up publishes via ADD_ONION (holder-kept, §11.4 by construction);
#        the key is generated at the first up, stored 600, reused forever
#
# Publication (§11): `up` PUBLISHES — ADD_ONION with the node's key
#   (NEW:ED25519-V3 at the first up; the PrivateKey is stored chmod 600 in
#   keys/<alias>.key and reused forever: same key => same address, measured).
#   The onion is tied to the holder's control connection (§11.4 by
#   construction): `down` kills the holder, the onion dies with it — no
#   Detach, no DEL_ONION ceremony. `up --offline` starts the loopback
#   listener WITHOUT touching the ControlPort (harness, dev). The human
#   gesture (§11.2) remains: a human types `up`. doctor probes the
#   ControlPort (§3), never the holder's pid alone.
#   (Divergence D1, declared 2026-10-24, repaired 2026-10-25.)
#
# Identity (§2): the onion address IS the identity. On the wire, `who` and
# `from` remain claims, never proofs. Locally this implementation names its
# key file keys/<alias>.key: the alias therefore names the local identity at
# the first up and is NOT implicitly renamed (§18.5). That storage convention
# never makes the wire alias authenticated, and it never travels in the URL.
#
# Onboarding (2026-10-24, normative in §18 since 1.1):
#   callsign — a deterministic adjective-noun name of the address; a pure
#              function of it, recomputed everywhere, stored nowhere (§17.14:
#              display only, proves nothing — a checksum for the HUMAN channel)
#   peer add — the agent WRITES peers.txt on direct human instruction (§11.2);
#              the gesture stays human, the plumbing stays mechanical
#   up / who — report the callsign, the fingerprint, and the ready-to-share
#              string "<callsign>|<onion>.onion>"
# ============================================================================

set -u

JARNET_ROOT="${JARNET_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
JARNET_DIR="${JARNET_DIR:-${JARNET_ROOT}/data/jarnet}"
JARNET_SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
JARNET_SCRIPT_FILE="${BASH_SOURCE[0]##*/}"
CONFIG_DIR="${JARNET_ROOT}/config"
TOR_CONFIG="${CONFIG_DIR}/torrc"
LIB_DIR="${AIDE_LIB_DIR:-${JARNET_ROOT}/lib}"
LIB_DEPS=("base64" "timeout" "sha256")
export JARNET_ROOT JARNET_DIR          # inherited by socat EXEC children

# Log and exit helper
die() {
  echo -e "\nError: $*\n" >&2
  exit 255
}

# Tor helper
load_tor_config() {
  # Check Tor config
  [[ ! -r $TOR_CONFIG ]] && die "Missing Tor config file."

  # Parse and set Tor config
  TOR_HOST="127.0.0.1"
  TOR_PORT=$(grep -v "#" "$TOR_CONFIG" | grep -m1 "SOCKSPort" | cut -d' ' -f2)
  CTRL_PORT=$(grep -m1 "ControlPort" "$TOR_CONFIG" | cut -d' ' -f2)

  # TOR_PROXY="socks5h://${TOR_HOST}:${TOR_PORT}"
  # TOR_PROXY_MOBILE="socks4a://${TOR_HOST}:${TOR_PORT}"
  # SOCKS_PROXY="socks5://${TOR_HOST}:${TOR_PORT}"
  # TOR_LOG="/tmp/tor.log"

  CTRL="${JR_CTRL:-${TOR_HOST}:${CTRL_PORT}}"       # Tor ControlPort (§3 vocabulary)
  SOCKS="${JR_SOCKS:-${TOR_HOST}:${TOR_PORT}}"     # Tor SOCKS (traversal for send)
}

# Load required libraries
load_libs() {
  local total_libs=0
  local found_libs=0
  local missing_libs=0
  local missing_libs_str=""
  total_libs="${#LIB_DEPS[@]}"
  for d in "${LIB_DEPS[@]}"; do
    if [[ -r "${LIB_DIR}/${d}.sh" && -s "${LIB_DIR}/${d}.sh" ]]; then
      # shellcheck source=/dev/null
      source "${LIB_DIR}/${d}.sh" || die "Failed to load '$d' library."
      ((found_libs++))
    else
      [[ $missing_libs -ne 0 ]] && missing_libs_str+=", "
      missing_libs_str+="$d"
      ((missing_libs++))
    fi
  done
  if [[ $found_libs -ne $total_libs ]]; then
    die "Missing libraries: $missing_libs_str"
  fi
}

# -----------------------------------------------------------------------------
# Init Tor
# -----------------------------------------------------------------------------
load_tor_config

# -----------------------------------------------------------------------------
# Portability helpers (stock macOS / BSD differences)
# -----------------------------------------------------------------------------
load_libs

# Init
mkdir -p "$JARNET_DIR" 2>/dev/null || true

# -- one convention per file, all owned by THIS engine ----------------------
J_ALIAS="${JARNET_DIR}/.alias"          # one line: this node's display name
J_PEERS="${JARNET_DIR}/peers.txt"       # alias|onion|note  (operator-written)
J_INBOX="${JARNET_DIR}/inbox.jsonl"     # k:"received" — one line = one event
J_SENT="${JARNET_DIR}/sent.jsonl"       # k:"sent"
J_OFFSET="${JARNET_DIR}/.inbox.offset"  # MESSAGE counter, never a line number
J_PID="${JARNET_DIR}/.listener.pid"
J_LINKS="${JARNET_DIR}/.links"          # consent, dies with the process
J_DIAG="${JARNET_DIR}/jarnet.diag.log"  # raw request-line lengths, refusals
J_REPLIES="${JARNET_DIR}/.replies"      # bounds (b) and (a ter) of §12
J_SIDF="${JARNET_DIR}/.sid"             # session id, stable while the file lives
J_KEYS="${JARNET_DIR}/keys"             # keys/<alias>.addr = derived cache; .key = identity
J_HOLDER="${JARNET_DIR}/.holder.pid"    # the control connection, kept open
J_HRESP="${JARNET_DIR}/.holder.resp"    # this up's control answers (rewritten per up)

LPORT="${JR_LPORT:-18080}"              # loopback port behind the virtual port 80
READ_TMO="${JR_READ_TMO:-15}"           # §10.5: the read window is 15 s
SEND_TMO="${JR_SEND_TMO:-45}"           # §10.5: the send window is 45 s
HSFETCH_TMO="${JR_HSFETCH_TMO:-5}"      # status: bounded local HSFETCH observation
MAX_PATH="${JR_MAX_PATH:-16384}"        # §5: chosen ceiling, measured on the raw path
MAX_BODY="${JR_MAX_BODY:-1048576}"      # v1.3 : 1 MiB for POST /say
RETRY_N="${JR_RETRY:-3}"                # §8.4
RETRY_S="${JR_RETRY_S:-30}"             # §8.4
REPLY_WINDOW="${JR_REPLY_WINDOW:-60}"   # §12 (a ter)
REPLY_MAX="${JR_REPLY_MAX:-20}"         # §12 (a ter)
JARNET_PROTO="${JR_PROTO:-1.3}"         # §5: `engine` — protocol version, not a commit

# -- identity (§2) ----------------------------------------------------------
jarn_alias() {
  if [[ -n ${JR_ALIAS:-} ]]; then printf '%s' "$JR_ALIAS"; return 0; fi
  if [[ -r $J_ALIAS ]]; then head -n1 "$J_ALIAS" | tr -d ' \r\n'; return 0; fi
  printf 'peer'                          # generic: no decision depends on it
}

# keys/<alias>.addr — written by jarn_publish from the MEASURED ServiceID
# (the KEY is the identity; the address is derived, never chosen by hand).
# One line, with or without .onion. A malformed v3 name is not an address.
jarn_onion() {
  local f a=""
  f="${J_KEYS}/$(jarn_alias).addr"
  [[ -r $f ]] || return 1
  [[ -r $f ]] || return 1
  a=$(head -n1 "$f" | tr -d ' \r\n' | sed 's/\.onion$//')
  [[ $a =~ ^[a-z2-7]{56}$ ]] || return 1
  printf '%s' "$a"
}

# §17.14 — display only, proves nothing.
jarn_fingerprint() {
  local a; a=$(jarn_onion) || return 1
  printf '%s' "$(printf '%s' "$a" | _sha256sum | cut -c1-16 \
    | sed 's/\(....\)\(....\)\(....\)\(....\)/\1-\2-\3-\4/')"
}

# -- callsign (onboarding): a deterministic, pronounceable node name -------
# A pure function of the address — same input as the fingerprint (the 56
# base32 chars, no .onion): bytes 8 and 9 of the sha256 (hex chars 17..20)
# index the two lists. Zero state: recomputed everywhere, stored nowhere.
# THE LISTS ARE PROTOCOL SURFACE, FROZEN v1 (validated 2026-10-25): versioned
# like the magic number (§8.1) — changing one word renames every node and the
# human checksum ("mine says golden-otter") dies. 128 x 128 = 16 384 names.
# Scaling path, IF ever needed: a deterministic 3rd segment (hash byte 10) as
# a collision suffix in the LOCAL address book only — the canonical callsign
# stays 2 segments forever, nobody is renamed.
# Criteria: 1-2 syllables, sayable on a phone, no near-homophones inside a
# list, no word present in both lists, nothing loaded.
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

jarn_callsign() {  # <onion-56> -> "adjective-noun"; deterministic, display only
  local a="${1:-}" h=""
  [[ $a =~ ^[a-z2-7]{56}$ ]] || return 1
  h=$(printf '%s' "$a" | _sha256sum)
  printf '%s-%s' "${JARNET_ADJ[$(( 0x${h:16:2} & 0x7f ))]}" \
                 "${JARNET_NOUN[$(( 0x${h:18:2} & 0x7f ))]}"
}

jarn_sid() {
  if [[ -r $J_SIDF ]]; then tr -dc 'a-f0-9' < "$J_SIDF"; return 0; fi
  local s; s=$(printf '%s-%s' "$$" "$(date +%s)" | _sha256sum | cut -c1-6)
  printf '%s' "$s" > "$J_SIDF" 2>/dev/null || true
  printf '%s' "$s"
}

jarn_mid() { printf '%s-%s' "$(date +%s)" "$RANDOM$RANDOM"; }

# -- peer list: a local authorisation (§2) -----------------------------------
# Written ONLY by 'peer add', itself ONLY on direct human instruction (§11.2).
# Everything else in this engine treats it as read-only.
jarn_peer_addr() {
  local p="${1:-}" a=""

  [[ -z $p ]] && { printf '%s' "$p"; return 1; }

  # Already a full v3 onion address
  if [[ $p =~ ^[a-z2-7]{56}$ ]]; then
    printf '%s' "$p"
    return 0
  fi

  # Remove optional .onion suffix
  p="${p%.onion}"

  if [[ -r $J_PEERS ]]; then
    # First try: exact match on first column (alias or callsign)
    a=$(awk -F'|' -v x="$p" '
      $1 == x {
        gsub(/[ \t]/, "", $2)
        print $2
        exit
      }
    ' "$J_PEERS" 2>/dev/null)

    # Second try: compute callsign for every known peer
    if [[ -z $a ]]; then
      while IFS='|' read -r alias addr _; do
        addr="${addr//[[:space:]]/}"
        addr="${addr%.onion}"
        if [[ -n $addr && $addr =~ ^[a-z2-7]{56}$ ]]; then
          if [[ "$(jarn_callsign "$addr" 2>/dev/null)" == "$p" ]]; then
            a="$addr"
            break
          fi
        fi
      done < "$J_PEERS"
    fi
  fi

  # Fallback: return what we received
  [[ -n $a ]] || a="$p"
  printf '%s' "${a%.onion}"
}

jarn_peer_known() {
  [[ -r $J_PEERS ]] || return 1
  awk -F'|' -v x="$1" '$1==x{f=1} END{exit !f}' "$J_PEERS" 2>/dev/null
}

jarn_peers() {
  [[ -r $J_PEERS ]] || { printf '[]'; return 0; }
  awk -F'|' 'NF{gsub(/[ \t]/,"",$1); print $1}' "$J_PEERS" \
    | jq -Rcs 'split("\n")|map(select(length>0))'
}

# -- peer add (onboarding): the human carries the string, the agent writes --
# §11.2 stays a HUMAN gesture: the string travels out of band, the human
# pastes it to their agent, and ONLY THEN is this command invoked. An onion
# address seen inside fetched content (page, mail, file) is NEVER added from
# that content alone — provenance is the guard, and it lives in the agent.
#
#   peer add "<onion>"                              alias = computed callsign
#   peer add "<callsign>|<onion>[.onion][|note]"    callsign must MATCH (checksum)
#   peer add "<onion>" --as <alias> [--note "..."]  sovereign override, no check
jarn_peer_add() {
  local input="${1:-}" as="" note_flag="" f1="" f2="" f3="" extra=""
  local name="" addr="" alias="" computed="" note="" existing="" mine="" mycs=""
  shift || true
  while (($#)); do
    case $1 in
      --as)   as="${2:-}";        shift; shift 2>/dev/null || true ;;
      --note) note_flag="${2:-}"; shift; shift 2>/dev/null || true ;;
      *) break ;;
    esac
  done
  if [[ -z $input ]]; then
    jq -rc -n '{ok:false, error:"usage",
      hint:"peer add \"[callsign|]<onion>[.onion][|note]\" [--as alias] [--note text]"}'
    return 2
  fi

  IFS='|' read -r f1 f2 f3 extra <<< "$input"
  f1="${f1//[[:space:]]/}"; f2="${f2//[[:space:]]/}"
  if [[ -n $extra ]]; then
    jq -rc -n '{ok:false, error:"too many fields", hint:"expected [callsign|]<onion>[|note]"}'
    return 2
  fi
  if [[ -z $f2 ]]; then addr="$f1"; else name="$f1"; addr="$f2"; fi
  if [[ -n $f3 ]]; then note="$f3"; else note="$note_flag"; fi
  addr="${addr%.onion}"

  if [[ ! $addr =~ ^[a-z2-7]{56}$ ]]; then
    jq -rc -n --arg a "$addr" '{ok:false, error:"invalid address (56 base32 expected)",
      got:$a, hint:"v3 onion names are 56 lowercase base32 characters — re-copy the string"}'
    return 3
  fi
  computed=$(jarn_callsign "$addr")

  if [[ -n $as ]]; then
    alias="$as"
  elif [[ -n $name ]]; then
    if [[ $name != "$computed" ]]; then
      jq -rc -n --arg g "$name" --arg c "$computed"         '{ok:false, error:"callsign_mismatch", given:$g, computed:$c,
          hint:"the string was corrupted somewhere — ask the peer to resend; to add it under a custom alias anyway: peer add \"<onion>\" --as <alias>"}'
      return 4
    fi
    alias="$name"
  else
    alias="$computed"
  fi

  # A clean alias: lowercase, dashes, 2-32 chars — and never an address.
  if [[ ! $alias =~ ^[a-z0-9]([a-z0-9-]{0,30}[a-z0-9])?$ ]] || [[ $alias =~ ^[a-z2-7]{56}$ ]]; then
    jq -rc -n --arg a "$alias" '{ok:false, error:"invalid alias", alias:$a,
      hint:"lowercase letters, digits, dashes; 2-32 chars; never an address"}'
    return 5
  fi
  if jarn_peer_known "$alias"; then
    jq -rc -n --arg a "$alias" --arg s "${computed}-2"       '{ok:false, error:"alias already in peers.txt", alias:$a,
        hint:"a second node with the same callsign? retry with --as " + $s}'
    return 6
  fi
  existing=""
  if [[ -r $J_PEERS ]]; then
    existing=$(awk -F'|' -v x="$addr"       '{gsub(/[ \t]/,"",$2); sub(/\.onion$/,"",$2)} $2==x{print $1; exit}' "$J_PEERS" 2>/dev/null)
  fi
  if [[ -n $existing ]]; then
    jq -rc -n --arg a "$addr" --arg e "$existing"       '{ok:false, error:"address already known", address:$a, known_as:$e,
        hint:"this peer is already in your book — nothing to add"}'
    return 7
  fi

  mkdir -p "$(dirname "$J_PEERS")" 2>/dev/null
  printf '%s|%s|%s\n' "$alias" "$addr" "$note" >> "$J_PEERS"

  mine=$(jarn_onion 2>/dev/null) || mine=""
  [[ -n $mine ]] && mycs=$(jarn_callsign "$mine") || mycs=""
  jq -rc -n --arg alias "$alias" --arg addr "$addr" --arg cs "$computed"      --arg note "$note" --arg mine "$mine" --arg mycs "$mycs" --arg f "$J_PEERS"     '{ok:true, result:"peer_added", alias:$alias, address:$addr, callsign:$cs,
      verified:(if $alias==$cs then true else null end), note:$note, file:$f,
      share_back:(if $mine=="" then null else ($mycs + "|" + $mine + ".onion") end),
      hint:"peer written — your address book, your sovereign choice (§11.2)"}'
}

# -- buffer (§9.4): append-only, one line = one event ----------------------
jarn_append() { mkdir -p "$(dirname "$1")" 2>/dev/null; printf '%s\n' "$2" >> "$1"; }
jarn_count()  { [[ -r $1 ]] || { printf '0'; return 0; }; awk 'NF{n++} END{print n+0}' "$1"; }
jarn_offset_get() { [[ -r $J_OFFSET ]] && awk 'NF{print $1; exit}' "$J_OFFSET" || printf '0'; }
jarn_offset_set() {
  local new="${1:?}" source="${2:-unknown}" previous
  previous=$(jarn_offset_get)
  printf '%s\n' "$new" > "$J_OFFSET" 2>/dev/null || return 1
  # Diagnosis for the 2026-10-25 live flow: an offset had advanced before the
  # visible check. Record WHO advanced it, never any message content.
  jarn_append "$J_DIAG" "$(date -u +%Y-%m-%dT%H:%M:%SZ) offset ${previous}->${new} source=${source} pid=$$ ppid=$PPID"
}

# -- small, portable critical sections (socat fork AND concurrent CLI) -----
# mkdir is the atomic primitive, so no new flock dependency is imposed on
# Termux. An owner that dies is reclaimed; a live owner is never disturbed.
J_LOCK=""
jarn_lock_acquire() {  # <inbox|reply> -> J_LOCK, rc 0; timeout after ~10 s
  local name="${1:?}" dir owner="" tries=0 current=""
  dir="${JARNET_DIR}/.lock-${name}"
  J_LOCK=""
  mkdir -p "$JARNET_DIR" 2>/dev/null || return 1
  while ! mkdir "$dir" 2>/dev/null; do
    owner=""
    [[ -r $dir/pid ]] && owner=$(tr -dc '0-9' < "$dir/pid" 2>/dev/null)
    if [[ -n $owner ]] && ! kill -0 "$owner" 2>/dev/null; then
      current=""
      [[ -r $dir/pid ]] && current=$(tr -dc '0-9' < "$dir/pid" 2>/dev/null)
      [[ $current == "$owner" ]] || continue
      rm -f "$dir/pid" 2>/dev/null
      rmdir "$dir" 2>/dev/null || true
    elif (( tries == 40 )) && [[ -z $owner ]]; then
      # The owner died between mkdir and writing its pid. rmdir is safe: it
      # succeeds only while the directory is still empty.
      rm -f "$dir/pid" 2>/dev/null
      rmdir "$dir" 2>/dev/null || true
    fi
    (( tries >= 200 )) && return 1
    tries=$((tries+1))
    sleep 0.05
  done
  J_LOCK="$dir"
  if ! printf '%s\n' "$$" > "$dir/pid" 2>/dev/null; then
    rm -f "$dir/pid" 2>/dev/null
    rmdir "$dir" 2>/dev/null || true
    J_LOCK=""
    return 1
  fi
  return 0
}

jarn_lock_release() {
  local dir="${J_LOCK:-}"
  [[ -n $dir ]] || return 0
  J_LOCK=""
  rm -f "$dir/pid" 2>/dev/null
  rmdir "$dir" 2>/dev/null || true
}

# -- identity carried on the wire: callsign (derived from the address),
#    alias only as fallback when no .addr exists yet.
jarn_from() {
  local a
  a=$(jarn_onion) && jarn_callsign "$a" && return 0
  jarn_alias
}

jarn_envelope() {  # <type> <body> [re] [reply_to] [sid]
  jq -rc -n \
    --arg type "$1" --arg from "$(jarn_from)" --arg body "$2" \
    --arg re "${3:-}" --arg sid "${5:-$(jarn_sid)}" --arg mid "$(jarn_mid)" \
    --arg reply_to "${4:-}" \
    --arg ts "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
    '{v:1, type:$type, from:$from, ts:$ts, sid:$sid, mid:$mid, re:$re, body:$body}
     + (if $reply_to == "" then {} else {reply_to:$reply_to} end)'
}

jarn_key_of() {  # stdin = envelope -> identity key (§9.1)
  jq -r '(.from // "") + "|" + (.sid // "") + "|" +
         (if (.mid // "") == "" then (.ts // "") else .mid end)'
}

jarn_b64encode() { b64e | tr -d '=' | tr '/+' '_-'; }
jarn_b64decode() {  # accepts WITH or WITHOUT padding (§6)
  local s="${1:-}"
  case $(( ${#s} % 4 )) in 2) s="${s}==" ;; 3) s="${s}=" ;; esac
  printf '%s' "$s" | tr '_-' '/+' | b64d 2>/dev/null
}

# A refusal needs an actual JSON verdict. Invalid/truncated JSON, or a HTTP
# 200 without a boolean ok, is UNKNOWN: it must never masquerade as a refusal.
jarn_response_issue() {  # <response-body> -> ok | refused | unknown
  local resp="${1:-}"
  if jq -e 'type=="object" and .ok == true' <<< "${resp:-{\}}" >/dev/null 2>&1; then
    printf 'ok'
  elif jq -e 'type=="object" and .ok == false and ((.error // "") | type=="string" and length>0)' \
      <<< "${resp:-{\}}" >/dev/null 2>&1; then
    printf 'refused'
  else
    printf 'unknown'
  fi
}

# -- ping (§3, §5): one DATED measurement, never a death certificate -------
jarn_ping() {  # <peer|onion> [timeout_s=45]
  local peer="${1:?peer}" tmo="${2:-45}" addr url out resp
  local rc=0 http t0 t1 dur
  addr=$(jarn_peer_addr "$peer")
  if [[ ! $addr =~ ^[a-z2-7]{56}$ ]]; then
    jq -rc -n --arg p "$peer" '{ok:false, issue:"refused", error:"invalid address (56 expected)", peer:$p}'
    return 3
  fi
  [[ $tmo =~ ^[1-9][0-9]*$ ]] || {
    jq -rc -n '{ok:false, issue:"refused", error:"timeout must be a positive integer"}'; return 2; }
  (( tmo > 120 )) && tmo=120
  url="http://${addr}.onion/ping"
  t0=$(date +%s)
  out=$(curl -sS --max-time "$tmo" -w '\n%{http_code}' --proxy "socks5h://${SOCKS}" "$url" 2>&1) || rc=$?
  t1=$(date +%s); dur=$((t1-t0))
  http=$(printf '%s' "${out##*$'\n'}" | tr -dc '0-9')
  resp=$(printf '%s' "${out%$'\n'*}" | head -c 2000)

  if [[ $rc -eq 0 && $http == "200" ]] \
     && jq -e 'type=="object" and .ok==true' <<< "${resp:-{\}}" >/dev/null 2>&1; then
    jq -rc -n --arg peer "$peer" --argjson response "$resp" --argjson rc "$rc" \
       --argjson http "$((10#${http:-0}))" --argjson dur "$dur" \
      '{ok:true, result:"reachable", peer:$peer, who:($response.who//null),
        ts:($response.ts//null), engine:($response.engine//null),
        http:$http, rc:$rc, dur_s:$dur}'
    return 0
  fi

  jq -rc -n --arg peer "$peer" --arg resp "$resp" --argjson rc "$rc" \
     --argjson http "$((10#${http:-0}))" --argjson dur "$dur" \
    '{ok:false, issue:"unknown", peer:$peer, http:$http, rc:$rc, dur_s:$dur,
      detail:(if $resp=="" then null else $resp[0:160] end),
      hint:"no REACHABLE verdict — timeout, transport or invalid response is NOT a dead peer (R2)"}'
  return 1
}

# -- send (§8) -------------------------------------------------------------
# Success = rc=0 AND http=200 AND ok:true. Traversal is always through the
# SOCKS entrance: the transport IS Tor. The journal is written AFTER.
jarn_send() {  # <peer|onion> <body> [type] [re] [reply_to] [sid] -> JSON on stdout
  local peer="${1:?peer}" body="${2:-}" type="${3:-msg}" re="${4:-}" rto="${5:-}" sid="${6:-}"
  local addr env b64 json url method attempt=1 rc http resp out
  local issue="unknown" t0 t1 dur

  addr=$(jarn_peer_addr "$peer")
  if [[ ! $addr =~ ^[a-z2-7]{56}$ ]]; then
    jq -rc -n --arg p "$peer" --argjson n "${#addr}" \
      '{ok:false, issue:"refused", error:"invalid address (56 expected)", peer:$p, len:$n}'
    return 3
  fi

  env=$(jarn_envelope "$type" "$body" "$re" "$rto" "$sid") \
    || { printf '{"ok":false,"issue":"refused","error":"envelope not built"}\n'; return 4; }

  json=$(printf '%s' "$env" | jq -c .)
  b64=$(printf '%s' "$env" | jarn_b64encode)

  # v1.3: choose GET or POST depending on the size
  if (( ${#b64} + 6 > MAX_PATH )); then
    method="POST"
    url="http://${addr}.onion/say"
  else
    method="GET"
    url="http://${addr}.onion/say/${b64}"
  fi

  # Test aid: return the envelope and the exact path that would travel,
  # byte for byte, without touching the network.
  if [[ ${JR_DRY:-0} == 1 ]]; then
    jq -rc -n --argjson env "$env" --arg path "/say/${b64}" \
      '{ok:true, issue:"dry", path:$path, envelope:$env}'
    return 0
  fi

  # v1.3 — two distinct limits and refusal codes
  if [[ $method == "GET" ]]; then
    if (( ${#b64} + 6 > MAX_PATH )); then
      jq -rc -n --argjson n "$(( ${#b64} + 6 ))" --argjson max "$MAX_PATH" \
        '{ok:false, issue:"refused", error:"too_large", path_len:$n, max:$max}'
      jarn_append "$J_SENT" "$(jq -rc -n --argjson env "$env" --arg peer "$peer" \
          '{k:"sent", tx_ts:(now|todate), to:$peer, issue:"refused",
            http:null, error:"too_large", envelope:$env}')"
      return 5
    fi
  else
    # POST : on mesure la taille du JSON décodé
    if (( ${#json} > MAX_BODY )); then
      jq -rc -n --argjson n "${#json}" --argjson max "$MAX_BODY" \
        '{ok:false, issue:"refused", error:"payload_too_large", body_len:$n, max:$max}'
      jarn_append "$J_SENT" "$(jq -rc -n --argjson env "$env" --arg peer "$peer" \
          '{k:"sent", tx_ts:(now|todate), to:$peer, issue:"refused",
            http:null, error:"payload_too_large", envelope:$env}')"
      return 5
    fi
  fi

  t0=$(date +%s)
  while :; do
    rc=0

    # v1.3 — two distinct sending methods
    if [[ $method == "POST" ]]; then
      out=$(curl -sS --max-time "$SEND_TMO" -w '\n%{http_code}' \
            -H "Content-Type: application/json" \
            -d "$json" \
            --proxy "socks5h://${SOCKS}" "$url" 2>&1) || rc=$?
    else
      out=$(curl -sS --max-time "$SEND_TMO" -w '\n%{http_code}' \
            --proxy "socks5h://${SOCKS}" "$url" 2>&1) || rc=$?
    fi

    http=$(printf '%s' "${out##*$'\n'}" | tr -dc '0-9')
    resp=$(printf '%s' "${out%$'\n'*}" | head -c 2000)

    if [[ $rc -eq 0 && $http == "200" ]]; then
      issue=$(jarn_response_issue "$resp")
      case $issue in
        ok|refused) break ;;
        *)       issue="unknown" ;;
      esac
    else
      issue="unknown"
    fi

    (( attempt >= RETRY_N )) && break
    attempt=$((attempt+1))
    sleep "$RETRY_S"
  done
  t1=$(date +%s); dur=$((t1-t0))

  # Logging v1.3: store which method has been used
  local log_tmp ; log_tmp=$(mktemp)

  jq -rc -n \
    --argjson env "$(printf '%s' "$env" | jq -c .)" \
    --arg peer "$peer" --argjson rc "$rc" \
    --argjson http "$((10#${http:-0}))" --arg issue "$issue" \
    --argjson attempts "$attempt" --argjson dur "$dur" \
    --arg resp "${resp:-}" --arg method "$method" \
    --arg txts "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
    '{k:"sent", tx_ts:$txts, to:$peer, method:$method, issue:$issue, http:$http,
      rc:$rc, attempts:$attempts, dur_s:$dur, response:$resp, envelope:$env}' > "$log_tmp"

  jarn_append "$J_SENT" "$(cat "$log_tmp")"
  rm -f "$log_tmp"

  # Restore the output contract (v1.3 regression): callers (jarn_reply §9,
  # tools layer) parse .issue from stdout to exercise the single-use claim.
  # A silent success made every claim silently skipped.
  jq -rc -n \
    --argjson env "$(printf '%s' "$env" | jq -c .)" \
    --arg peer "$peer" --arg issue "$issue" --arg method "$method" \
    --argjson http "$((10#${http:-0}))" --argjson attempts "$attempt" \
    --argjson dur "$dur" \
    '{ok:($issue=="ok"), issue:$issue, to:$peer, method:$method,
      http:$http, attempts:$attempts, dur_s:$dur}'

  [[ $issue == "ok" ]]
}

# -- responder (§4 to §9) --------------------------------------------------
jarn_byte_length() { local LC_ALL=C; printf '%s' "${#1}"; }

# v1.3 — refusal table updated: too_large (GET) + payload_too_large (POST)
jarn_refuse() {  # <code> [rx] [ack_ts] [cause] -> 200 + ok:false (an ack too, §8.2)
  local jre="" jsid="" b blen
  if [[ -n ${J_ENV:-} ]]; then
    jre=$(jq -r '.ts // ""' <<< "$J_ENV" 2>/dev/null)
    jsid=$(jq -r '.sid // ""' <<< "$J_ENV" 2>/dev/null)
  fi
  jarn_append "$J_DIAG" "$(date -u +%Y-%m-%dT%H:%M:%SZ) refuse $1${4:+ cause=$4}"
  b=$(jq -rc -n --arg e "$1" --arg rx "${2:-}" --arg ack "${3:-}" \
        --arg re "$jre" --arg sid "$jsid" \
    '{ok:false, error:$e, rx_ts:$rx, ack_ts:$ack, re:$re, sid:$sid}')
  blen=$(jarn_byte_length "$b")
  printf 'HTTP/1.0 200 OK\r\nContent-Type: application/json\r\nContent-Length: %s\r\nConnection: close\r\n\r\n%s' "$blen" "$b"
}

jarn_respond() {  # <body-json>
  local b="$1" blen
  blen=$(jarn_byte_length "$b")
  printf 'HTTP/1.0 200 OK\r\nContent-Type: application/json\r\nContent-Length: %s\r\nConnection: close\r\n\r\n%s' \
    "$blen" "$b"
}

jarn_serve() {
  local line="" method="" path="" payload="" body="" clen=0 rc=0 rx ack env key found
  J_ENV=""        # last decoded envelope, read by jarn_refuse

  # §4 + §5 v1.3: read first line to detect if method is GET or POST
  IFS= read -r -t "$READ_TMO" line; rc=$?
  rx=$(date -u +%Y-%m-%dT%H:%M:%SZ)

  if (( rc != 0 )); then
    # §8.3: the one answer with no ack — nothing was read, nothing to copy,
    # nothing to acknowledge, nothing to journal into the buffer.
    jarn_append "$J_DIAG" "$(printf '%s 408 read_rc=%s' "$rx" "$rc")"
    printf 'HTTP/1.0 408 Request Timeout\r\nContent-Length: 0\r\nConnection: close\r\n\r\n'
    return 0
  fi

  line="${line%$'\r'}"
  method="${line%% *}"
  path="${line#* }"; path="${path%% *}"

  # Log raw request before handling (v1.3)
  jarn_append "$J_DIAG" "$(printf '%s req method=%s path_len=%s' "$rx" "$method" "${#path}")"

  case $path in
    /ping|/)                                    # §5: / is an alias of /ping
      jarn_respond "$(jq -rc -n --arg who "$(jarn_alias)" --arg ts "$rx" \
        --arg engine "$JARNET_PROTO" \
        '{ok:true, who:$who, ts:$ts, engine:$engine}')"
      return 0 ;;
    /say)
      [[ $method == "POST" ]] || { printf 'HTTP/1.0 405 Method Not Allowed\r\n\r\n'; return 0; }
      ;;
    /say/*)
      [[ $method == "GET" ]] || { printf 'HTTP/1.0 405 Method Not Allowed\r\n\r\n'; return 0; }
      payload="${path#/say/}"
      ;;
    *)                                          # §5: 404 is reserved for this
      printf 'HTTP/1.0 404 Not Found\r\nContent-Type: text/plain\r\nConnection: close\r\n\r\nnot found'
      return 0 ;;
  esac

  # === POST handling (v1.3) ===
  if [[ $method == "POST" ]]; then
    # Read headers to get 'Content-Length'
    while IFS= read -r -t 2 header; do
      header="${header%$'\r'}"
      [[ -z $header ]] && break
      if [[ $header == Content-Length:* ]]; then
        clen="${header#Content-Length: }"
        clen="${clen// /}"
      fi
    done

    if (( clen > MAX_BODY )); then
      jarn_refuse "payload_too_large" "$rx" "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "body"
      return 0
    fi

    # Read the body
    if (( clen > 0 )); then
      body=$(dd bs=1 count="$clen" 2>/dev/null)
    fi

    # Envelope
    env="$body"
  else
    # GET legacy
    if (( ${#path} > MAX_PATH )); then
      jarn_refuse "too_large" "$rx" "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "path"; return 0
    fi

    # §6: base64url alphabet; '=' tolerated at the end only. An EMPTY payload
    # passes here and decodes to nothing — §8.3 gives it its own code below.
    if [[ ! $payload =~ ^[A-Za-z0-9_-]*={0,2}$ ]]; then
      jarn_refuse "invalid_envelope" "$rx" "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "alphabet"; return 0
    fi

    # Envelope
    env=$(jarn_b64decode "$payload")
    if [[ -z $env ]]; then
      jarn_refuse "unreadable_payload" "$rx" "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "base64"; return 0
    fi
  fi

  J_ENV="$env"   # from here, refusals carry re and sid (§8.2)

  # §8.3 — closed table, in order.
  jq -e 'type=="object"' <<< "$env" >/dev/null 2>&1 \
    || { jarn_refuse "invalid_envelope" "$rx" "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "json"; return 0; }
  [[ $(jq -r '.v // ""' <<< "$env") == "1" ]] \
    || { jarn_refuse "invalid_envelope" "$rx" "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "v"; return 0; }

  local jtype; jtype=$(jq -r '.type // ""' <<< "$env")
  case $jtype in
    msg|eta|bye) ;;
    *) jarn_refuse "unknown_type" "$rx" "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "type"; return 0 ;;
  esac

  # required fields: from and ts (all types), sid (msg, bye), re (eta),
  # body present and a string (msg, eta); body, when present, is a string.
  [[ -n $(jq -r '.from // ""' <<< "$env") ]] \
    || { jarn_refuse "invalid_envelope" "$rx" "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "from"; return 0; }
  [[ -n $(jq -r '.ts // ""' <<< "$env") ]] \
    || { jarn_refuse "invalid_envelope" "$rx" "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "ts"; return 0; }
  # §6: sid is required for EVERY type — it carries the session (§10.1), and
  # the identity key (§9.1) is meaningless without it.
  if [[ -z $(jq -r '.sid // ""' <<< "$env") ]]; then
    jarn_refuse "invalid_envelope" "$rx" "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "sid"; return 0
  fi
  if [[ $jtype == "eta" ]] && [[ -z $(jq -r '.re // ""' <<< "$env") ]]; then
    jarn_refuse "invalid_envelope" "$rx" "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "re"; return 0
  fi
  if [[ $jtype == "msg" || $jtype == "eta" ]] && [[ $(jq -r 'has("body")' <<< "$env") != "true" ]]; then
    jarn_refuse "invalid_envelope" "$rx" "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "body_absent"; return 0
  fi
  if [[ $(jq -r 'if has("body") then (.body|type) else "string" end' <<< "$env") != "string" ]]; then
    jarn_refuse "invalid_envelope" "$rx" "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "body_type"; return 0
  fi

  # §12 (a): the WIRE form is strict — 56 base32 characters, no suffix. The
  # human CLI may tolerate .onion; the envelope never does (§18).
  local rto; rto=$(jq -r '.reply_to // ""' <<< "$env")
  if [[ -n $rto ]] && [[ ! $rto =~ ^[a-z2-7]{56}$ ]]; then
    jarn_refuse "invalid_envelope" "$rx" "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "reply_to_form"; return 0
  fi
  # §12 (c): reply_to pointing at my OWN address is a loop — refused like (a),
  # at entry, before any use. A node without an address cannot loop: skipped.
  if [[ -n $rto ]]; then
    local mine=""; mine=$(jarn_onion 2>/dev/null) || mine=""
    if [[ -n $mine && $rto == "$mine" ]]; then
      jarn_refuse "invalid_envelope" "$rx" "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "reply_to_loop"; return 0
    fi
  fi

  # §9.1: a duplicate answers the recorded content — same re, same sid — with
  # FRESH timestamps, writes nothing, and never re-emits an outgoing reply.
  # The lookup + append is ONE critical section under socat fork.
  if ! jarn_lock_acquire "inbox"; then
    jarn_refuse "storage_error" "$rx" "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "inbox_lock"; return 0
  fi

  key=$(jarn_key_of <<< "$env")
  found=""
  if [[ -r $J_INBOX ]]; then
    found=$(jq -c --arg k "$key" \
      'select(.k=="received") | select((((.envelope.from // "") + "|" + (.envelope.sid // "") + "|" + (if (.envelope.mid // "")=="" then (.envelope.ts // "") else .envelope.mid end)) == $k)) | .ack // empty' \
      "$J_INBOX" 2>/dev/null | head -n1)
  fi

  if [[ -n $found ]]; then
    local ack2
    jarn_lock_release
    ack2=$(jq -rc -n --arg rx "$rx" --arg at "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
      --arg re "$(jq -r '.ts // ""' <<< "$env")" --arg sid "$(jq -r '.sid // ""' <<< "$env")" \
      '{ok:true, rx_ts:$rx, ack_ts:$at, re:$re, sid:$sid}')
    jarn_append "$J_DIAG" "$(printf '%s duplicate key=%s content=recorded timestamps=fresh' "$rx" "$key")"
    jarn_respond "$ack2"
    return 0
  fi

  # §7.4: the mechanical layer writes, closes, and that is all. No model,
  # no memory file, no mailbox read — ack_ts - rx_ts must measure reception.
  ack=$(jq -cn --arg rx "$rx" --arg at "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
        --arg re "$(jq -r '.ts // ""' <<< "$env")" --arg sid "$(jq -r '.sid // ""' <<< "$env")" \
        '{ok:true, rx_ts:$rx, ack_ts:$at, re:$re, sid:$sid}')

  local inbox_tmp ; inbox_tmp=$(mktemp)

  jq -rc -n \
    --argjson e "$(printf '%s' "$env" | jq -c .)" \
    --arg rx "$rx" \
    --argjson ack "$ack" \
    '{k:"received", rx_ts:$rx, ack:$ack, envelope:$e}' > "$inbox_tmp"

  if ! jarn_append "$J_INBOX" "$(cat "$inbox_tmp")"; then
    rm -f "$inbox_tmp"
    jarn_lock_release
    jarn_refuse "storage_error" "$rx" "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "inbox_append"
    return 0
  fi

  rm -f "$inbox_tmp"

  jarn_lock_release
  jarn_respond "$ack"
}

# -- read (§9.4): MESSAGES, never lines ------------------------------------
jarn_check() {  # [after_n] [source] -> JSON; consumes (advances the offset)
  local n total previous source="${2:-check}" asked stored tmpfile
  total=$(jarn_count "$J_INBOX")
  previous=$(jarn_offset_get)
  [[ $previous =~ ^[0-9]+$ ]] || previous=0
  asked="${1:-$previous}"
  [[ $asked =~ ^[0-9]+$ ]] || asked=0
  # §9.4: the offset is a MESSAGE COUNTER and the STORED one is the source of
  # truth. A caller-supplied after_n may NEVER move the cursor past unread
  # messages: a stale after_n (behind) costs at most a re-delivery, while a
  # cursor running ahead skips messages FOREVER, silently — that is exactly
  # the 2026-10-25/26 "message already read" anomaly (new:0 with total grown,
  # .inbox.offset left untouched). At-least-once, never at-most-once.
  n=$asked
  (( n > previous )) && n=$previous

  if (( total <= n )); then
    # Nothing to deliver: report the STORED counter, never the argument —
    # an offset that was never written must never be announced.
    jq -rc -n --argjson total "$total" --argjson off "$previous" \
      '{ok:true, new:0, total:$total, offset:$off, messages:[]}'
    return 0
  fi

  tmpfile=$(mktemp)
  awk -v skip="$n" 'NF{c++; if(c>skip) print}' "$J_INBOX" > "$tmpfile"

  # Report what was ACTUALLY written, never a presumed $total.
  stored=$(jarn_offset_set "$total" "$source" && jarn_offset_get)
  [[ $stored =~ ^[0-9]+$ ]] || stored=$previous

  if (( n != asked )); then
    jarn_append "$J_DIAG" "$(date -u +%Y-%m-%dT%H:%M:%SZ) offset_clamped asked=${asked} stored=${previous} used=${n} pid=$$"
  fi

  jq -rc -n \
    --argjson total "$total" \
    --argjson off "$stored" \
    --slurpfile msgs "$tmpfile" \
    '{ ok: true,
       new: ($msgs | length),
       total: $total,
       offset: $off,
       messages: ($msgs // []) }'

  rm -f "$tmpfile"
}

# -- wait (§10.5): never emptiness, reason in a closed set -----------------
jarn_wait_shape() {  # <check-json> <waited_s>
  jq -rc -n --argjson o "$1" --argjson w "${2:-0}" '
    {ok:(($o.new // 0) > 0),
     reason:(if (($o.new // 0) > 0) then null else "nothing_new" end),
     waited_s:$w}
    + (if (($o.new // 0) > 0)
       then {new:$o.new, total:$o.total, offset:$o.offset, messages:$o.messages}
       else {offset:($o.offset // $o.total)} end)'
}

jarn_wait() {  # [timeout_s=45] [after_n]
  local tmo="${1:-45}" n start elapsed out
  n="${2:-$(jarn_offset_get)}"
  [[ $tmo =~ ^[0-9]+$ ]] || tmo=45
  if (( tmo == 0 )); then
    out=$(jarn_check "$n" "wait")
    (( $(printf '%s' "$out" | jq -r '.new') > 0 )) && { jarn_wait_shape "$out" 0; return 0; }
    jq -rc -n --argjson off "$n" '{ok:false, reason:"nothing_new", waited_s:0, offset:$off}'
    return 1
  fi
  (( tmo > 120 )) && tmo=120
  start=$(date +%s)
  while :; do
    out=$(jarn_check "$n" "wait")
    if (( $(printf '%s' "$out" | jq -r '.new') > 0 )); then
      jarn_wait_shape "$out" "$(( $(date +%s) - start ))"
      return 0
    fi
    elapsed=$(( $(date +%s) - start ))
    if (( elapsed >= tmo )); then
      jq -rc -n --argjson w "$elapsed" --argjson off "$n" \
        '{ok:false, reason:"timeout", waited_s:$w, offset:$off,
          hint:"measured silence over the whole duration (R2) -- not a dead peer"}'
      return 1
    fi
    sleep 1
  done
}

# -- outgoing reply (§12): six bounds --------------------------------------
jarn_reply() {  # <sid> <reply_to> <body> [ts-of-the-message]
  local sid="${1:?sid}" target="${2:?target}" body="${3:-}" now cnt
  target="${target%.onion}"          # human CLI tolerance, never carried (§12 a)
  target=$(jarn_peer_addr "$target") # alias|callsign -> onion (§2), passthrough if already onion

  # (a) form, before any use: onion v3, 56 base32 characters, no port
  if [[ ! $target =~ ^[a-z2-7]{56}$ ]]; then
    jq -rc -n --arg t "$target" '{ok:false, issue:"refused", error:"invalid reply_to (56 base32 expected)", target:$t}'
    return 3
  fi
  # (c) loop: never answer my own address
  if [[ $target == "$(jarn_onion)" ]]; then
    printf '{"ok":false,"issue":"refused","error":"reply_to points at myself (loop)"}\n'
    return 4
  fi

  mkdir -p "$JARNET_DIR"
  if ! jarn_lock_acquire "reply"; then
    printf '{"ok":false,"issue":"refused","error":"reply state unavailable"}\n'
    return 8
  fi
  now=$(date +%s)

  # (a ter) global ceiling per window, independent of (b)
  cnt=$(awk -v n="$now" -v w="$REPLY_WINDOW" '$1>=n-w{c++} END{print c+0}' "$J_REPLIES" 2>/dev/null || printf '0')
  if (( cnt >= REPLY_MAX )); then
    jarn_lock_release
    jq -rc -n --argjson c "$cnt" --argjson m "$REPLY_MAX" \
      '{ok:false, issue:"refused", error:"outgoing reply ceiling reached", count:$c, max:$m}'
    return 5
  fi

  # The message being answered: pinned by its ts when given (4th argument),
  # otherwise the last one of the session. `re` is its `ts` (§7.4) — never a sid.
  local mts="${4:-}" msgj="" re_ts="" mkey=""
  [[ -r $J_INBOX ]] && msgj=$(jq -c --arg s "$sid" --arg t "$mts" \
    'select(.k=="received") | select((.envelope.sid // "") == $s)
     | select($t == "" or (.envelope.ts // "") == $t) | .envelope' \
    "$J_INBOX" 2>/dev/null | tail -n1)
  [[ -n $msgj ]] && re_ts=$(jq -r '.ts // ""' <<< "$msgj")
  if [[ -z $re_ts ]]; then
    jarn_lock_release
    jq -rc -n --arg s "$sid" '{ok:false, issue:"refused",
      error:"message not in the buffer: re requires the ts of the message answered", sid:$s}'
    return 7
  fi

  # (b) single use per MESSAGE (§9.1 identity key) — never per sender, never
  # per session: a conversation answers many messages of the same sid.
  mkey=$(jarn_key_of <<< "$msgj")
  if [[ -r $J_REPLIES ]] && awk -v k="$target|$mkey" '$2==k{f=1} END{exit !f}' "$J_REPLIES" 2>/dev/null; then
    jarn_lock_release
    jq -rc -n --arg s "$sid" --arg ts "$re_ts" '{ok:false, issue:"refused",
      error:"already answered this message", sid:$s, re:$ts}'
    return 6
  fi

  # (a bis) the reply carries ONLY the envelope; (d) peers.txt is never written.
  #
  # ORDER MATTERS (fixed 2026-10-28): the single-use claim is written AFTER the
  # send, never before. Written before, a send interrupted between the claim and
  # the delivery (tool timeout, kill, hung Tor path) left the message "already
  # answered" without a single byte having left the node: the message became
  # unanswerable forever and every retry was refused. A claim must record what
  # HAPPENED, never what was merely attempted.
  #
  # The lock is held across the send on purpose: check (b) and claim stay ONE
  # critical section, so two concurrent replies to the same message cannot both
  # pass (b). Cost: a send that has to wait out Tor (~RETRY_N x (45 s +
  # RETRY_S)) keeps .lock-reply held, and a concurrent reply then waits ~10 s
  # before being refused with "reply state unavailable" — a refusal, never a
  # silent duplicate. A killed sender leaves a stale pid in .lock-reply, which
  # jarn_lock_acquire already reclaims.
  local out rc issue claim_ts
  out=$(jarn_send "$target" "$body" "msg" "$re_ts" "" "$sid"); rc=$?
  issue=$(printf '%s' "$out" | jq -r '.issue // "unknown"' 2>/dev/null)
  issue=${issue:-unknown}

  # ok      -> the peer accepted it: the message IS answered.
  # refused -> the peer reached a verdict (§8): never answer it twice.
  # dry     -> the local test aid simulated an accepted send; the single-use
  #            claim must still be exercised, or the harness cannot measure
  #            bound (b) without touching the network.
  # unknown -> nothing was proved (timeout, invalid ack): NO claim, so the
  #            message stays answerable and the identical resend allowed by
  #            §8.4 remains the caller's decision.
  case $issue in
    ok|refused|dry)
      claim_ts=$(date +%s)   # not $now: a slow send must not age the claim
      if ! printf '%s %s|%s\n' "$claim_ts" "$target" "$mkey" >> "$J_REPLIES"; then
        jarn_lock_release
        printf '%s\n' "$out"
        printf 'jarnet: WARNING — answer sent (%s) but the reply claim could not be written; a retry would answer this message twice\n' "$issue" >&2
        return 8
      fi ;;
  esac
  jarn_lock_release
  printf '%s\n' "$out"
  return "$rc"
}

# -- who am I (§2: display convenience) ------------------------------------
jarn_who() {
  local onion="" pid peers fp="" cs="" hp=0
  onion=$(jarn_onion) || onion=""
  [[ -n $onion ]] && fp=$(jarn_fingerprint)
  [[ -n $onion ]] && cs=$(jarn_callsign "$onion") || cs=""
  pid=$(jarn_listener_pid) || pid=0
  hp=$(jarn_holder_pid) || hp=0
  peers=$(jarn_peers)
  jq -rc -n --arg alias "$(jarn_alias)" --arg onion "$onion" --arg sid "$(jarn_sid)" \
     --arg fp "$fp" --arg cs "$cs" \
     --argjson total "$(jarn_count "$J_INBOX")" --argjson off "$(jarn_offset_get)" \
     --argjson sent "$(jarn_count "$J_SENT")" --argjson pid "$pid" \
     --argjson peers "${peers:-[]}" --arg socks "$SOCKS" --arg proto "$JARNET_PROTO" --argjson holder "$hp" \
    '{ok:true, alias:$alias, proto:$proto, onion:(if $onion=="" then null else $onion end),
      callsign:(if $cs=="" then null else $cs end),
      fingerprint:(if $fp=="" then null else $fp end), sid:$sid,
      share:(if $cs=="" then null else ($cs + "|" + $onion + ".onion") end),
      inbox_total:$total, inbox_offset:$off, sent_total:$sent,
      listener_pid:(if $pid==0 then null else $pid end), peers:$peers, socks:$socks,
      holder_pid:(if $holder==0 then null else $holder end), holder_alive:($holder != 0)}'
}

# Portable process-environment reader. Linux: /proc newline-separated.
# macOS/BSD: `ps eww` appends the env after the command, space-separated.
# Both forms are grep-able with a fixed-string match.
# shellcheck disable=SC2009
jarn_proc_env() {
  local p="${1:-}"
  [[ -n $p ]] || return 1
  if [[ -r /proc/$p/environ ]]; then
    tr '\0' '\n' < "/proc/$p/environ" 2>/dev/null
  else
    ps eww "$p" 2>/dev/null
  fi
}

# Portable process-cmdline reader (Linux: /proc NUL-separated;
# macOS/BSD: `ps -ww -o command=` single line). Both grep-able.
jarn_proc_cmdline() {
  local p="${1:-}"
  [[ -n $p ]] || return 1
  if [[ -r /proc/$p/cmdline ]]; then
    tr '\0' ' ' < "/proc/$p/cmdline" 2>/dev/null
  else
    ps -ww -p "$p" -o command= 2>/dev/null
  fi
}

# Ownership is proven by the ENVIRONMENT tag the holder was launched with —
# a live pid is not a live control connection (measured, step 3 note).
jarn_holder_is_ours() {
  jarn_proc_env "${1:-}" | grep -qF "JARNET_HOLDER=${JARNET_DIR}"
}

jarn_holder_pid() {
  local pid=""
  [[ -r $J_HOLDER ]] && pid=$(tr -dc '0-9' < "$J_HOLDER" 2>/dev/null)
  [[ -n $pid ]] || { printf '0'; return 1; }
  kill -0 "$pid" 2>/dev/null || { printf '0'; return 1; }   # stale
  jarn_holder_is_ours "$pid" || { printf '0'; return 2; }  # not ours: hands off
  printf '%s' "$pid"; return 0
}

# -- listener (§4, §11.1): the listener belongs to the NODE ----------------
# A pidfile may point at a process that is not ours (another engine serving
# the same port). Killing it would break a live service => ownership check
# BEFORE any kill.
jarn_pid_is_ours() {
  jarn_proc_cmdline "${1:-}" | grep -qF "${JARNET_SCRIPT_DIR##*/}/${JARNET_SCRIPT_FILE}"
}

jarn_listener_env_is_ours() {
  jarn_proc_env "${1:-}" | grep -qF "JARNET_LISTENER=${JARNET_DIR}"
}

jarn_listener_ping_ok() {  # exact identity expected from OUR local backend
  local resp="${1:-}"
  jq -e --arg who "$(jarn_alias)" --arg engine "$JARNET_PROTO" \
    'type=="object" and .ok==true and .who==$who and .engine==$engine' \
    <<< "$resp" >/dev/null 2>&1
}

jarn_listener_pid() {
  local pid=""
  [[ -r $J_PID ]] && pid=$(tr -dc '0-9' < "$J_PID" 2>/dev/null)
  [[ -n $pid ]] || { printf '0'; return 1; }
  kill -0 "$pid" 2>/dev/null || { printf '0'; return 1; }   # stale
  jarn_pid_is_ours "$pid" || { printf '0'; return 2; }      # not ours: hands off
  printf '%s' "$pid"; return 0
}

jarn_listener_start() {
  local pid="" probe="" adopted="" c p0=""
  mkdir -p "$JARNET_DIR"

  # A listener recorded in OUR pidfile may be adopted (including the legacy
  # listener that predates environment tags), but its answer must still match.
  if pid=$(jarn_listener_pid) && [[ $pid != 0 ]]; then
    probe=$(curl -s --max-time 2 "http://127.0.0.1:${LPORT}/ping" 2>/dev/null)
    if jarn_listener_ping_ok "$probe"; then printf '%s' "$pid"; return 0; fi
    printf '0'; return 4
  fi

  command -v socat >/dev/null 2>&1 || { printf '0'; return 2; }

  # Anything already answering on the port is foreign unless its PROCESS
  # carries the tag of THIS data directory. A JSON "who" is not ownership.
  probe=$(curl -s --max-time 2 "http://127.0.0.1:${LPORT}/ping" 2>/dev/null)
  if [[ -n $probe ]]; then
    for c in $(pgrep -f "TCP-LISTEN:${LPORT}" 2>/dev/null); do
      if jarn_listener_env_is_ours "$c"; then adopted="$c"; break; fi
    done
    if [[ -n $adopted ]] && jarn_listener_ping_ok "$probe"; then
      printf '%s\n' "$adopted" > "$J_PID"
      printf '%s' "$adopted"; return 0
    fi
    printf '0'; return 4
  fi

  # §4: the listener binds LOOPBACK ONLY — a socket reachable from a shared
  # interface is non-conformant, whatever the peer list believes.
  JARNET_LISTENER="$JARNET_DIR" socat "TCP-LISTEN:${LPORT},bind=127.0.0.1,reuseaddr,fork" \
        "EXEC:bash ${JARNET_ROOT}/plugins/jarnet.sh serve" >/dev/null 2>&1 &
  printf '%s\n' "$!" > "$J_PID"
  sleep 0.4

  # Never let a foreign process validate our startup. The process must be
  # alive AND ours AND the response must carry our exact alias/protocol.
  if ! pid=$(jarn_listener_pid) || [[ ! $pid =~ ^[1-9][0-9]*$ ]]; then
    [[ -r $J_PID ]] && p0=$(tr -dc '0-9' < "$J_PID" 2>/dev/null)
    [[ -n $p0 ]] && kill "$p0" 2>/dev/null
    rm -f "$J_PID"
    printf '0'; return 3
  fi
  probe=$(curl -s --max-time 2 "http://127.0.0.1:${LPORT}/ping" 2>/dev/null)
  if ! jarn_listener_ping_ok "$probe"; then
    kill "$pid" 2>/dev/null
    rm -f "$J_PID"
    printf '0'; return 3
  fi
  printf '%s' "$pid"
}

jarn_listener_stop() {
  local pid; pid=$(jarn_listener_pid)
  case $? in
    0) ;;
    2) printf 'foreign'; return 2 ;;   # another engine's pidfile: hands off
    *) rm -f "$J_PID"; printf '0'; return 0 ;;
  esac
  kill "$pid" 2>/dev/null
  rm -f "$J_PID" "$J_LINKS"
  printf '%s' "$pid"; return 0
}

# -- publication (§11): ADD_ONION — the key is the identity -----------------
jarn_ctrl_alive() {
  ( printf 'PROTOCOLINFO 1\r\nQUIT\r\n'; sleep 0.3 ) \
    | _timeout 3 socat - "TCP:${CTRL}" 2>/dev/null | grep -q PROTOCOLINFO
}

jarn_ctrl_cookie_hex() {  # -> cookie as hex on stdout (measured flow, step 3)
  local cf
  cf=$( { printf 'PROTOCOLINFO 1\r\nQUIT\r\n'; sleep 0.5; } \
        | _timeout 3 socat - "TCP:${CTRL}" 2>/dev/null \
        | sed -n 's/.*COOKIEFILE="\([^"]*\)".*/\1/p' | tr -d '\r' )
  [[ -n $cf && -r $cf ]] || return 1
  od -An -tx1 -v "$cf" | tr -d ' \n'
}

# status: observe the local descriptor through Tor, without ADD_ONION.
# received:true is ONLY the local HSFETCH result (cache included), never the
# asymmetric PUBLISHED verdict of §3. false means "not received this attempt".
jarn_hsfetch() {
  local onion hex resp
  onion=$(jarn_onion) || { printf 'false'; return 0; }
  hex=$(jarn_ctrl_cookie_hex) || { printf 'false'; return 0; }
  [[ $HSFETCH_TMO =~ ^[1-9][0-9]*$ ]] || HSFETCH_TMO=5
  (( HSFETCH_TMO > 30 )) && HSFETCH_TMO=30
  resp=""
  resp=$( { printf 'AUTHENTICATE %s\r\n' "$hex"
            printf 'SETEVENTS HS_DESC\r\n'
            printf 'HSFETCH %s\r\n' "$onion"
            sleep "$HSFETCH_TMO"
          } | _timeout "$HSFETCH_TMO" socat - "TCP:${CTRL}" 2>/dev/null ) || true
  if grep -q '650 HS_DESC RECEIVED' <<< "$resp"; then
    printf 'true'
  else
    printf 'false'
  fi
}

# ADD_ONION with the stored key — NEW:ED25519-V3 at the first up, then the
# same key forever (same key => same address, measured twice). The holder
# keeps the control connection OPEN: the onion lives exactly as long as the
# holder (§11.4 by construction — no Detach, no DEL_ONION, frank death).
jarn_publish_cleanup() {
  local hp="${1:?}"
  kill -- -"$hp" 2>/dev/null
  rm -f "$J_HOLDER" "$J_HRESP"
}

jarn_publish() {  # -> ServiceID (56 base32) on stdout
  local alias key hex sid priv existing waited hp hrc diag
  # Idempotent only for a live holder of OURS. A foreign holder is hands off.
  hp=$(jarn_holder_pid); hrc=$?
  if (( hrc == 0 )) && [[ $hp != 0 ]]; then jarn_onion; return $?; fi
  (( hrc == 2 )) && return 7

  alias=$(jarn_alias)
  key=""
  [[ -r ${J_KEYS}/${alias}.key ]] && key=$(head -n1 "${J_KEYS}/${alias}.key" | tr -d ' \r\n')
  hex=$(jarn_ctrl_cookie_hex) || return 2

  # The response can contain PrivateKey on the first up. Recreate it with mode
  # 600 BEFORE Tor can write anything, and never leave an old permissive mode.
  rm -f "$J_HRESP"
  if ! (umask 077; : > "$J_HRESP") || ! chmod 600 "$J_HRESP" 2>/dev/null; then
    rm -f "$J_HRESP"
    return 2
  fi

  # Secrets travel on fd 3/4, never in argv. The single-quoted holder program
  # is intentional: only its positional, non-secret parameters are expanded.
  local wrapper
  if command -v setsid >/dev/null 2>&1; then
    wrapper="setsid"    # Linux
  else
    wrapper="nohup"     # macOS/BSD
  fi
  # shellcheck disable=SC2016
  JARNET_HOLDER="$JARNET_DIR" "$wrapper" bash -c '
    umask 077
    {
      IFS= read -r hex <&3
      IFS= read -r key <&4 || true
      printf "AUTHENTICATE %s\r\n" "$hex"
      if [[ -n $key ]]; then
        printf "ADD_ONION %s Port=80,127.0.0.1:%s\r\n" "$key" "$3"
      else
        printf "ADD_ONION NEW:ED25519-V3 Port=80,127.0.0.1:%s\r\n" "$3"
      fi
      unset hex key
      while :; do sleep 3600; done    # remplace sleep infinity -- better for macOS/BSD
    } | socat - "TCP:$1" > "$2" 2>&1
  ' _ "$CTRL" "$J_HRESP" "$LPORT" 3<<<"$hex" 4<<<"$key" </dev/null >/dev/null 2>&1 &
  hp=$!
  printf '%s\n' "$hp" > "$J_HOLDER"

  # The control answers on its own clock: poll the response file, die frankly
  # on an explicit Tor error code, time out without lying.
  sid=""; waited=0
  while (( waited < 30 )); do
    if [[ -r $J_HRESP ]]; then
      if grep -q '250-ServiceID=' "$J_HRESP" 2>/dev/null; then
        sid=$(sed -n 's/.*250-ServiceID=\([a-z2-7]\{56\}\).*/\1/p' "$J_HRESP" | head -n1)
        break
      fi
      if grep -Eq '^(515|512|550|551|553) ' "$J_HRESP" 2>/dev/null; then
        diag=$(head -n1 "$J_HRESP" | tr -d '\r')
        jarn_publish_cleanup "$hp"
        jarn_append "$J_DIAG" "$(date -u +%Y-%m-%dT%H:%M:%SZ) publish refused: $diag"
        return 3
      fi
    fi
    sleep 0.5; waited=$((waited+1))
  done
  if [[ -z $sid ]]; then
    jarn_publish_cleanup "$hp"
    return 4
  fi

  # First up: harvest the PrivateKey Tor just made — mode 600, never shown.
  if [[ -z $key ]]; then
    priv=$(sed -n 's/.*250-PrivateKey=\(ED25519-V3:[A-Za-z0-9+/=]*\).*/\1/p' "$J_HRESP" | head -n1 | tr -d '\r')
    if [[ -z $priv ]]; then
      jarn_publish_cleanup "$hp"
      return 5
    fi
    mkdir -p "$J_KEYS" 2>/dev/null
    if ! (umask 077; printf '%s\n' "$priv" > "${J_KEYS}/${alias}.key"); then
      jarn_publish_cleanup "$hp"
      return 5
    fi
    if ! chmod 600 "${J_KEYS}/${alias}.key" 2>/dev/null; then
      rm -f "${J_KEYS}/${alias}.key"
      jarn_publish_cleanup "$hp"
      return 5
    fi
    priv=""
    # Do not leave a SECOND copy of the private key in the control transcript.
    rm -f "$J_HRESP"
  fi

  # A pre-existing .addr that disagrees with the measured ServiceID is a
  # contradiction: die frankly, overwrite nothing silently.
  existing=""
  [[ -r ${J_KEYS}/${alias}.addr ]] && existing=$(head -n1 "${J_KEYS}/${alias}.addr" | tr -d ' \r\n' | sed 's/\.onion$//')
  if [[ -n $existing && $existing != "$sid" ]]; then
    jarn_publish_cleanup "$hp"
    return 6
  fi
  mkdir -p "$J_KEYS" 2>/dev/null
  if ! printf '%s.onion\n' "$sid" > "${J_KEYS}/${alias}.addr"; then
    jarn_publish_cleanup "$hp"
    return 7
  fi
  printf '%s' "$sid"
}

# down's other half: the onion dies with its holder — kill the whole process
# group (setsid), never a bare pid whose children would keep the pipe open.
jarn_unpublish() {
  local pid; pid=$(jarn_holder_pid)
  case $? in
    0) kill -- -"$pid" 2>/dev/null; rm -f "$J_HOLDER"; printf '%s' "$pid" ;;
    2) printf 'foreign'; return 2 ;;   # another node's holder: hands off
    *) rm -f "$J_HOLDER"; printf '0' ;;
  esac
  rm -f "$J_HRESP"
}

# §10.6: a status confesses orphans, it does not hide them.
jarn_orphans() {
  local out="" tracked p
  tracked=$(jarn_listener_pid 2>/dev/null || printf '0')
  for p in $(pgrep -f "TCP-LISTEN:${LPORT}" 2>/dev/null); do
    [[ $p == "$tracked" ]] && continue
    jarn_pid_is_ours "$p" || continue
    out="$out $p"
  done
  printf '%s' "${out# }"
}

# -- up [link <peer>] [--offline] (§11.2: a human gesture) ------------------
# Order matters: the LISTENER first (nothing to publish without a backend),
# then CONTROL, then ADD_ONION. --offline: loopback only, Tor never touched.
jarn_up() {
  local peer="" offline=0
  [[ ${1:-} == "link" ]] && peer="${2:-}"
  case " $* " in *" --offline "*) offline=1 ;; esac
  if [[ -n $peer ]] && ! jarn_peer_known "$peer"; then
    jq -rc -n --arg p "$peer" '{ok:false, error:"unknown link -- this peer is not in peers.txt", peer:$p}'
    return 3
  fi

  local pid; pid=$(jarn_listener_start) \
    || { jq -rc -n '{ok:false, error:"listener did not come up (socat missing, port busy/foreign, or engine not runnable)"}'; return 5; }
  [[ $pid =~ ^[1-9][0-9]*$ ]] \
    || { jq -rc -n '{ok:false, error:"listener ownership could not be established — nothing registered"}'; return 5; }

  local onion="" registered=false holder=0 perr="" prc=0
  if (( offline == 0 )); then
    if ! jarn_ctrl_alive; then
      perr="control unreachable -- listener is UP, nothing registered (§3: stop here, never continue on a hypothesis)"
    else
      onion=$(jarn_publish) && prc=0 || prc=$?
      case $prc in
        0) registered=true; holder=$(jarn_holder_pid 2>/dev/null || printf '0') ;;
        *) perr="registration failed (rc=$prc) -- listener stays UP, nothing registered: $(head -n2 "$J_HRESP" 2>/dev/null | tr '\r\n' '  ')" ;;
      esac
    fi
  fi
  [[ -z $onion ]] && { onion=$(jarn_onion) || onion=""; }

  local links
  if [[ -n $peer ]]; then links="$peer"; else links=$(jarn_peers | jq -r 'join(",")' 2>/dev/null); fi
  printf '%s\n' "$links" > "$J_LINKS" 2>/dev/null || true

  local ann='{}'
  if [[ -n $peer && $registered == true ]]; then
    ann=$(JR_RETRY=1 jarn_send "$peer" "up" "msg" "" 2>/dev/null)
    [[ -n $ann ]] || ann='{}'
  fi

  local cs="" fp=""
  [[ -n $onion ]] && cs=$(jarn_callsign "$onion" 2>/dev/null) || cs=""
  [[ -n $onion ]] && fp=$(jarn_fingerprint 2>/dev/null) || fp=""

  jq -rc -n --arg onion "$onion" --arg links "$links" --argjson pid "${pid:-0}" \
     --argjson port "$LPORT" --argjson ann "$ann" --arg cs "$cs" --arg fp "$fp" \
     --argjson registered "$registered" --argjson holder "${holder:-0}" \
     --argjson offline "$offline" --arg perr "$perr" \
    '{ok:true, state:"UP", onion:(if $onion=="" then null else $onion end),
      callsign:(if $cs=="" then null else $cs end),
      fingerprint:(if $fp=="" then null else $fp end),
      share:(if $cs=="" then null else ($cs + "|" + $onion + ".onion") end),
      registered:$registered, holder_alive:($holder != 0), offline:($offline==1),
      listener_pid:(if $pid==0 then null else $pid end),
      holder_pid:(if $holder==0 then null else $holder end), port:$port,
      links:($links|split(",")|map(select(length>0))),
      announce:$ann,
      banner:("UP -- links: " + $links + " -- stop it with: down")}
     + (if $perr=="" then {} else {warning:$perr} end)
     + (if $offline==1 then {hint:"offline: loopback listener only -- Tor was never touched"} else {} end)'
}

# -- measured state (§3: CONTROL is a prerequisite, not one more state) ----
jarn_state() {
  local onion="" ctrl=false e=false
  onion=$(jarn_onion) || onion=""
  ( printf 'PROTOCOLINFO 1\r\nQUIT\r\n'; sleep 0.3 ) \
    | _timeout 3 socat - "TCP:${CTRL}" 2>/dev/null | grep -q PROTOCOLINFO && ctrl=true
  curl -s --max-time 2 "http://127.0.0.1:${LPORT}/ping" 2>/dev/null | grep -q '"who"' && e=true
  if [[ $ctrl != true ]]; then printf 'CONTROL_ABSENT'
  elif [[ -z $onion ]]; then printf 'NO_ADDRESS'
  elif [[ $e != true ]]; then printf 'ADDRESSED_NOT_LISTENING'
  else printf 'LISTENING'; fi
}

# One measurement, two views: status is the compact snapshot, doctor the
# diagnostic view. Neither revalidates ADD_ONION or infers a network state.
jarn_measure() {
  local onion="" pid state orph hp=0
  onion=$(jarn_onion) || onion=""
  pid=$(jarn_listener_pid) || pid=0
  hp=$(jarn_holder_pid) || hp=0
  state=$(jarn_state)
  orph=$(jarn_orphans)
  jq -rc -n --arg alias "$(jarn_alias)" --arg onion "$onion" --arg state "$state" \
     --argjson pid "$pid" --argjson holder "$hp" --argjson port "$LPORT" --arg orphans "$orph" \
     --argjson inbox "$(jarn_count "$J_INBOX")" --argjson sent "$(jarn_count "$J_SENT")" \
     --argjson off "$(jarn_offset_get)" --arg diag "${J_DIAG}" \
    '{alias:$alias, state:$state, onion:(if $onion=="" then null else $onion end),
      listener_pid:(if $pid==0 then null else $pid end), port:$port,
      holder_pid:(if $holder==0 then null else $holder end), holder_alive:($holder != 0),
      orphans:($orphans|split(" ")|map(select(length>0)|tonumber)),
      inbox_messages:$inbox, inbox_offset:$off, sent_messages:$sent, diag_file:$diag}'
}

jarn_status() {
  local m received
  m=$(jarn_measure)
  received=$(jarn_hsfetch)
  jq -rc -n --argjson d "$m" --argjson received "$received" '{
    ok:($d.state=="LISTENING"), alias:$d.alias, state:$d.state, onion:$d.onion,
    control:($d.state!="CONTROL_ABSENT"),
    listener_alive:($d.listener_pid!=null), listener_pid:$d.listener_pid, port:$d.port,
    holder_alive:$d.holder_alive, holder_pid:$d.holder_pid,
    received:$received
  }'
}

jarn_doctor() {
  local m; m=$(jarn_measure)
  jq -rc -n --argjson d "$m" '
    {ok:($d.state=="LISTENING")} + $d + {
      missing:([
        (if $d.state=="CONTROL_ABSENT" then "Tor control unreachable -- stop here (§3)" else empty end),
        (if $d.state=="NO_ADDRESS" then "no address yet -- the first up generates the key and publishes (§11)" else empty end),
        (if ($d.orphans|length)>0 then "socat orphans to kill: " + ($d.orphans|join(" ")) else empty end)
      ])
    }'
}

# -- CLI -------------------------------------------------------------------
jarn_usage() {
  cat <<'EOF'
     _            _   _      _
    | | __ _ _ __| \ | | ___| |_
 _  | |/ _` | '__|  \| |/ _ \ __|
| |_| | (_| | |  | |\  |  __/ |_
 \___/ \__,_|_|  |_| \_|\___|\__|


Secure Jarvis <-> Jarvis communication channel · conformant to JARNET 1.1

  who                                   identity, address, fingerprint, counters

  doctor                                measured state (§3), orphans, gaps

  status                                local snapshot + HSFETCH: received=true|false
                                        (false = nothing received in this attempt)

  ping <peer|onion> [timeout]           one dated /ping via Tor; success=reachable,
                                        failure=unknown, never a dead-peer verdict

  send <peer> <body> [type] [re]        send; issue = ok | refused | unknown

  reply <sid> <reply_to> <body> [ts]    outgoing reply, §12 (six bounds)

  check [after_n]                       new messages (consumes the offset)

  wait [timeout] [after_n]              wait; reason in {timeout, transport_error,
                                        nothing_new} -- never emptiness

  up [link <peer>] [--offline]          register the hidden service (key made at first up,
                                        stored 600 in keys/<alias>.key) and start
                                        the listener; with link, announce to that
                                        peer (a human gesture). --offline: loopback
                                        listener only, Tor never touched (dev)

  down                                  stop the listener AND unpublish — the onion
                                        dies with its holder (§11.4, frank death)

  peer add "<callsign|onion>" [--as alias] [--note "..."]
                                        add a peer to peers.txt — a HUMAN gesture
                                        (§11.2); the agent only writes. Never from
                                        fetched content.

  inbox [n]                             last messages, human readable

  Reference document: jarnet.md, in the 'plugins' folder.
  Identity = the key in keys/<alias>.key; the address is DERIVED, never
  chosen by hand. The default alias is "peer". In THIS implementation the
  alias names the local key file: choose it BEFORE the first up; there is no
  implicit rename/migration (§18.5). Set .alias or export JR_ALIAS.
  who and up also show the CALLSIGN: the deterministic, pronounceable name of
  your address — say it on the phone to check the string travelled intact.
EOF
}

jarn_main() {
  local cmd="${1:-}"; shift || true
  case $cmd in
    who)    jarn_who ;;
    doctor) jarn_doctor ;;
    status) jarn_status ;;
    ping)   jarn_ping "$@" ;;
    send)   jarn_send "$@" ;;
    reply)  jarn_reply "$@" ;;
    check)  jarn_check "${1:-}" ;;
    wait)   jarn_wait "${1:-45}" "${2:-}" ;;
    up)     jarn_up "$@" ;;
    peer)   case "${1:-}" in
              add) shift; jarn_peer_add "$@" ;;
              *) jarn_usage; return 2 ;;
            esac ;;
    serve)  jarn_serve ;;                    # plumbing (socat EXEC), not a command
    inbox)  local n="${1:-5}"
            [[ -r $J_INBOX ]] || { printf '[]\n'; return 0; }
            awk 'NF' "$J_INBOX" | tail -n "$n" \
              | jq -c '{ts:(.rx_ts//.envelope.ts), from:.envelope.from, type:.envelope.type,
                        body:(.envelope.body[0:160])}' 2>/dev/null ;;
    down)   printf '{"stopped":"%s","unpublished":"%s"}\n' \
              "$(jarn_listener_stop || printf '0')" "$(jarn_unpublish || printf '0')" ;;
    ""|-h|--help|help) jarn_usage ;;
    *) jarn_usage; return 2 ;;
  esac
}

if [[ ${BASH_SOURCE[0]} == "$0" ]]; then jarn_main "$@"; fi
