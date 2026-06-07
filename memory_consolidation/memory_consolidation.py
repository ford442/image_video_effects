"""OpenClaw session analyzer, STM generator, and LTM compact.

Subcommands:
    stats    Print session statistics (counts, time range, channel breakdown)
    stm      Generate USER.md with Short-Term Memory (recent conversations)
    audit    Audit memory behavior on core injected files
    compact  STM → LTM compact via LLM API → write final USER.md

Message cleaning ported from OpenClaw source:
- stripEnvelope()       loader-Ds3or8QX.js L17362
- stripMessageIdHints() loader-Ds3or8QX.js L17368
- ENVELOPE_CHANNELS     loader-Ds3or8QX.js L17341
- formatAgentEnvelope() loader-Ds3or8QX.js L30733

Channel detection: sessions.json registry keys (structured) with text fallback.
  Registry key format: agent:main:{channel}:{chatType}:{peerId}
  → label: FEISHU:DM, FEISHU:GROUP, LOOPBACK, TELEGRAM:DM, ...

Usage:
    python memory_consolidation.py stats [--session-dir DIR] [--days N]
    python memory_consolidation.py stm   [--session-dir DIR] [--days N] [--output PATH] [--max-per-session N]
"""

import argparse
import hashlib
import json
import os
import re
import sys
import time as _time
import urllib.request
from collections import defaultdict
from datetime import datetime, timedelta
from pathlib import Path

# ---------------------------------------------------------------------------
# Ported from OpenClaw source: loader-Ds3or8QX.js L17340-17373
# ---------------------------------------------------------------------------

ENVELOPE_PREFIX = re.compile(r"^\[([^\]]+)\]\s*")

# loader-Ds3or8QX.js L17341-17355 + "Feishu" (plugin, not in core list)
ENVELOPE_CHANNELS = [
    "WebChat", "WhatsApp", "Telegram", "Signal", "Slack", "Discord",
    "Google Chat", "iMessage", "Teams", "Matrix", "Zalo", "Zalo Personal",
    "BlueBubbles", "Feishu",
]

MESSAGE_ID_LINE = re.compile(r"^\s*\[message_id:\s*[^\]]+\]\s*$", re.IGNORECASE)

# System event prefix injected by enqueueSystemEvent() — all channels
SYSTEM_EVENT_RE = re.compile(
    r"System:\s*\[\d{4}-\d{2}-\d{2}\s+\d{2}:\d{2}:\d{2}\s+[^\]]+\]\s*[^\n]*"
)


def looks_like_envelope_header(header: str) -> bool:
    """Port of looksLikeEnvelopeHeader() from loader-Ds3or8QX.js L17357."""
    if re.search(r"\d{4}-\d{2}-\d{2}T\d{2}:\d{2}Z", header):
        return True
    if re.search(r"\d{4}-\d{2}-\d{2} \d{2}:\d{2}\b", header):
        return True
    return any(header.startswith(f"{ch} ") for ch in ENVELOPE_CHANNELS)


def strip_envelope(text: str) -> str:
    """Port of stripEnvelope() from loader-Ds3or8QX.js L17362."""
    match = ENVELOPE_PREFIX.match(text)
    if not match:
        return text
    if not looks_like_envelope_header(match.group(1)):
        return text
    return text[match.end():]


def strip_message_id_hints(text: str) -> str:
    """Port of stripMessageIdHints() from loader-Ds3or8QX.js L17368."""
    if "[message_id:" not in text:
        return text
    lines = text.split("\n")
    filtered = [l for l in lines if not MESSAGE_ID_LINE.match(l)]
    return "\n".join(filtered) if len(filtered) != len(lines) else text


# ---------------------------------------------------------------------------
# Channel detection via sessions.json registry
# Key format: agent:main:{channel}:{chatType}:{peerId}
# Label format: FEISHU:DM, FEISHU:GROUP, LOOPBACK, TELEGRAM:DM, etc.
# ---------------------------------------------------------------------------

def load_channel_registry(session_dir: str) -> dict[str, dict]:
    """Build sessionId -> {channel, chatType, label} from sessions.json."""
    registry_path = Path(session_dir) / "sessions.json"
    try:
        with open(registry_path) as f:
            registry = json.load(f)
    except (FileNotFoundError, json.JSONDecodeError):
        return {}

    sid_map = {}
    for key, entry in registry.items():
        parts = key.split(":")  # agent:main:feishu:direct:ou_xxx
        sid = entry.get("sessionId", "")
        if not sid:
            continue
        if len(parts) >= 4:
            channel = parts[2].upper()   # FEISHU, TELEGRAM, SLACK, ...
            chat_type = parts[3].upper() # DIRECT, GROUP
            # Normalize: DIRECT → DM
            if chat_type == "DIRECT":
                chat_type = "DM"
            label = f"{channel}:{chat_type}"
        else:
            channel = "LOOPBACK"
            chat_type = "LOCAL"
            label = "LOOPBACK"
        sid_map[sid] = {"channel": channel, "chatType": chat_type, "label": label}
    return sid_map


def detect_channel_label_from_text(raw_text: str) -> str:
    """Fallback: detect channel label from raw message text.

    Tries to identify both channel (Feishu/Slack/Telegram/...) and type (DM/GROUP).
    """
    # Check each known channel
    # Kimi Claw channel (User Message From Kimi: prefix)
    if re.search(r"User Message From Kimi:", raw_text):
        return "KIMI:DM"
    for ch in ["Feishu", "Slack", "Telegram", "WhatsApp", "Signal",
               "Discord", "iMessage", "Google Chat"]:
        pattern = rf"{ch}\[[^\]]*\]\s*(DM from|message in group)"
        m = re.search(pattern, raw_text)
        if m:
            chat_type = "DM" if "DM" in m.group(1) else "GROUP"
            return f"{ch.upper()}:{chat_type}"
        # Also check without brackets (some channels)
        if re.search(rf"{ch}\s+(DM from|message in group)", raw_text):
            if "DM" in raw_text:
                return f"{ch.upper()}:DM"
            return f"{ch.upper()}:GROUP"
    return "LOOPBACK"


def resolve_channel_label(session_id: str, channel_registry: dict, fallback: str) -> str:
    """Resolve channel label for a session. Registry first, text fallback."""
    info = channel_registry.get(session_id)
    if info:
        return info["label"]
    return fallback


# ---------------------------------------------------------------------------
# Message extraction and cleaning
# ---------------------------------------------------------------------------

def extract_raw_text(msg: dict) -> str:
    """Extract raw text from user message content (before cleaning)."""
    content = msg.get("content", "")
    if isinstance(content, str):
        return content
    if isinstance(content, list):
        texts = []
        for block in content:
            if isinstance(block, dict) and block.get("type") == "text":
                texts.append(block.get("text", ""))
        return " ".join(texts)
    return ""


# Heartbeat prompt detection — read from workspace if available, fallback to known defaults
_heartbeat_signatures: list[str] = []


def load_heartbeat_signatures(workspace: str):
    """Load heartbeat prompt fragments from HEARTBEAT.md for noise detection.

    Called once at startup. Falls back to gateway default if file missing/empty.
    """
    global _heartbeat_signatures
    defaults = [
        "Read HEARTBEAT.md if it exists",
        "HEARTBEAT_OK",
        "System: heartbeat",
    ]
    hb_path = Path(workspace) / "HEARTBEAT.md"
    try:
        content = hb_path.read_text().strip()
        if content:
            # Use first non-empty lines as signatures (user's custom heartbeat)
            lines = [l.strip() for l in content.split("\n") if l.strip() and not l.startswith("#")]
            _heartbeat_signatures = lines[:5] + defaults
        else:
            _heartbeat_signatures = defaults
    except FileNotFoundError:
        _heartbeat_signatures = defaults


CURRENT_MSG_MARKER = "[Current message - respond to this]"
HISTORY_CONTEXT_MARKER = "[Chat messages since your last reply - for context]"


def extract_trigger_message(text: str) -> str:
    """In group chats, only keep the trigger user's message.

    OpenClaw injects bystander context as:
        [Chat messages since your last reply - for context]
        ...other speakers...
        [Current message - respond to this]
        {the actual trigger message}

    We discard bystander context and only keep the trigger portion.
    For Queued messages, each queued block may also contain context markers.
    """
    # Handle [Current message - respond to this] marker
    idx = text.find(CURRENT_MSG_MARKER)
    if idx != -1:
        text = text[idx + len(CURRENT_MSG_MARKER):]

    # Handle [Queued messages while agent was busy] with embedded context
    # Each "Queued #N" block might have its own context/current markers
    if "[Queued messages while agent was busy]" in text:
        blocks = re.split(r"---\s*\nQueued #\d+\s*\n?", text)
        cleaned_blocks = []
        for block in blocks:
            marker_idx = block.find(CURRENT_MSG_MARKER)
            if marker_idx != -1:
                block = block[marker_idx + len(CURRENT_MSG_MARKER):]
            # Strip history context section entirely
            hist_idx = block.find(HISTORY_CONTEXT_MARKER)
            if hist_idx != -1:
                # Everything from history marker to current marker (already handled) or end
                block = block[:hist_idx]
            cleaned_blocks.append(block)
        text = "\n".join(cleaned_blocks)

    # Also strip any remaining history context marker sections
    hist_idx = text.find(HISTORY_CONTEXT_MARKER)
    if hist_idx != -1:
        # Find next [Current message] or strip to end
        after = text[hist_idx + len(HISTORY_CONTEXT_MARKER):]
        cur_idx = after.find(CURRENT_MSG_MARKER)
        if cur_idx != -1:
            text = text[:hist_idx] + after[cur_idx + len(CURRENT_MSG_MARKER):]
        else:
            text = text[:hist_idx]

    return text


def clean_message(text: str) -> str:
    """Clean system decorations from user message text.

    Pipeline: TriggerExtract → SystemEvent → stripEnvelope → stripMessageId → noise → media → dedup
    """
    # Phase 0: Extract trigger message only (discard bystander context)
    text = extract_trigger_message(text)

    # Phase 1: System Event lines (enqueueSystemEvent)
    text = SYSTEM_EVENT_RE.sub("", text)
    text = re.sub(r"Exec\s+(completed|failed)\s+\([^)]+\).*?(?=\n|$)", "", text)
    text = re.sub(r"Gateway restart.*?(?=\n|$)", "", text)
    text = re.sub(r"FailoverError:.*?(?=\n|$)", "", text)
    # Channel inbound labels left after System: prefix removal
    text = re.sub(
        r"(Feishu\[[^\]]*\]|Slack|Telegram|WhatsApp|Signal|Discord|iMessage|Google Chat)"
        r"\s*(DM from|message in group|message in)\s+\S+:\s*",
        "", text,
    )

    # Phase 1.5: PDS/sensor lines — must run BEFORE strip_envelope so that
    # old-format messages (PDS glued to envelope on same line) expose the
    # envelope at line start for Phase 2.
    text = re.sub(
        r"\n?(apple-watch|pds|sensor-logger):.*?(?=\s*\[(?:" + "|".join(ENVELOPE_CHANNELS) + r")\s|\n|$)",
        "", text, flags=re.DOTALL,
    )

    # Phase 2: Strip envelope (ported from source)
    lines = text.split("\n")
    lines = [strip_envelope(l) for l in lines]
    text = "\n".join(lines)

    # Phase 2.5: Strip "User Message From Kimi:" gateway IM prefix
    text = re.sub(r"User Message From \S+:\s*", "", text)

    # Phase 2.6: Convert <KIMI_REF> tags to <AttachmentDisplayed:path> format
    # Kimi Claw uses <KIMI_REF type="file" path="..." name="..." /> for attachments
    text = re.sub(
        r'<KIMI_REF\s+type="file"\s+path="([^"]+)"\s+name="[^"]*"\s+(?:id="[^"]*"\s+)?/>',
        r'<AttachmentDisplayed:\1>',
        text,
    )
    # Strip all (untrusted metadata) blocks — Conversation info / Sender / etc.
    text = re.sub(
        r"(?:Conversation info|Sender)\s*\(untrusted metadata\):\s*```json\s*\{[^}]*?\}\s*```\s*"
        r"(?:Read HEARTBEAT\.md if it exists.*?(?=\n\n|\Z)|)",
        "", text, flags=re.DOTALL,
    )
    # Strip heartbeat/reminder relay instructions
    text = re.sub(
        r"A scheduled reminder has been triggered\..*?Current time:.*?(?=\n|$)",
        "", text, flags=re.DOTALL,
    )
    # Strip cron job completion summaries (system noise, not user speech)
    text = re.sub(
        r"A cron job \"[^\"]*\" just completed.*?(?=\|\|\|\||\n\n|\Z)",
        "", text, flags=re.DOTALL,
    )

    # Phase 3: Strip message_id hints (ported from source)
    text = strip_message_id_hints(text)

    # Phase 4: Channel-specific noise
    # Group chat history context from buildPendingHistoryContextFromMap()
    text = re.sub(
        r"\[Feishu\s+\S+\s+\d{4}-\d{2}-\d{2}\s+\d{2}:\d{2}\s+\w+\]\s*\S+:\s*",
        "", text,
    )
    text = re.sub(r"\[Feishu\s+\S+\]", "", text)
    text = re.sub(r"^ou_[a-f0-9]+:\s*", "", text, flags=re.MULTILINE)
    text = re.sub(r"\[System:\s*[^\]]*\]", "", text)
    text = re.sub(r'\[Replying to:\s*"[^"]*"\]', "", text)
    text = re.sub(
        r"A new session was started via /new or /reset\..*?(?=\n\n|\Z)",
        "", text, flags=re.DOTALL,
    )
    text = re.sub(r"GatewayRestart:\s*\{[^}]*\}", "", text, flags=re.DOTALL)
    text = re.sub(
        r',\s*"message":\s*null.*?"mode":\s*"gateway\.restart"\s*\}\s*\}',
        "", text, flags=re.DOTALL,
    )
    text = re.sub(r"\[Queued messages while agent was busy\]", "", text)
    # Strip compaction/memory flush system instructions
    text = re.sub(r"Pre-compaction memory flush\..*?(?=\n\n|\Z)", "", text, flags=re.DOTALL)
    text = re.sub(r"---\s*\nQueued #\d+\s*\n?", "", text)
    # [Chat messages...] and [Current message...] markers handled in Phase 0
    text = re.sub(r"To send an image back.*?(?=\n|$)", "", text, flags=re.DOTALL)

    # Phase 5: Media normalization
    text = re.sub(
        r"\[media attached:\s*(\S+)\s*\([^)]*\)\s*\|[^\]]*\]",
        r"<AttachmentDisplayed:\1>", text,
    )
    text = re.sub(r'\{"image_key":"([^"]+)"\}', r"<ImageDisplayed:\1>", text)
    text = re.sub(r'\{"file_key":"[^"]+","file_name":"([^"]+)"\}', r"<FileDisplayed:\1>", text)

    # Phase 6: Deduplicate (Feishu double: system event preview + envelope body)
    parts = text.split("\n\n")
    if len(parts) == 2 and parts[0].strip() == parts[1].strip():
        text = parts[0].strip()

    # Phase 7: Collapse whitespace
    text = re.sub(r"\n{3,}", "\n\n", text)
    return text.strip()


def is_noise(text: str) -> bool:
    """Check if message is pure noise."""
    if not text:
        return True
    # Heartbeat noise (dynamic from HEARTBEAT.md + gateway defaults)
    for sig in _heartbeat_signatures:
        if sig in text:
            return True
    if re.match(r"^(apple-watch|pds|sensor-logger):", text):
        return True
    stripped = text.strip()
    if stripped in ("/reset", "/new", "/status", "1"):
        return True
    if stripped.startswith("/reset"):
        return True
    if stripped.startswith("GatewayRestart:"):
        return True
    # HEARTBEAT_OK handled by _heartbeat_signatures above
    if len(stripped) == 0:
        return True
    return False


# ---------------------------------------------------------------------------
# Session parsing
# ---------------------------------------------------------------------------

def parse_ts(ts_str: str) -> datetime:
    return datetime.fromisoformat(ts_str[:19])


def parse_session(
    jsonl_file: Path, cutoff: datetime, channel_registry: dict
) -> dict | None:
    with open(jsonl_file) as f:
        first_line = f.readline().strip()
        if not first_line:
            return None
        header = json.loads(first_line)

    ts_str = header.get("timestamp", "")
    if not ts_str:
        return None

    start_time = parse_ts(ts_str)
    if start_time < cutoff:
        return None

    session_id = header.get("id", jsonl_file.stem)
    user_messages = []
    text_channel_fallback = "LOOPBACK"

    with open(jsonl_file) as f:
        for line in f:
            obj = json.loads(line.strip())
            if obj.get("type") != "message":
                continue
            msg = obj["message"]
            if msg.get("role") != "user":
                continue

            raw_text = extract_raw_text(msg)
            if text_channel_fallback == "LOOPBACK" and raw_text:
                text_channel_fallback = detect_channel_label_from_text(raw_text)

            text = clean_message(raw_text)
            if not text or is_noise(text):
                continue

            msg_ts = obj.get("timestamp", "")[:19]
            user_messages.append({"ts": msg_ts, "text": text})

    if not user_messages:
        return None

    channel_label = resolve_channel_label(session_id, channel_registry, text_channel_fallback)

    return {
        "session_id": session_id,
        "start_time": start_time,
        "date": ts_str[:10],
        "file": jsonl_file.name,
        "channel": channel_label,
        "user_messages": user_messages,
    }


def parse_session_full(
    jsonl_file: Path, cutoff: datetime, channel_registry: dict
) -> dict | None:
    """Parse session with BOTH user and assistant messages (for diary)."""
    with open(jsonl_file) as f:
        first_line = f.readline().strip()
        if not first_line:
            return None
        header = json.loads(first_line)

    ts_str = header.get("timestamp", "")
    if not ts_str:
        return None

    start_time = parse_ts(ts_str)
    if start_time < cutoff:
        return None

    session_id = header.get("id", jsonl_file.stem)
    messages = []  # both user and assistant
    text_channel_fallback = "LOOPBACK"

    with open(jsonl_file) as f:
        for line in f:
            obj = json.loads(line.strip())
            if obj.get("type") != "message":
                continue
            msg = obj["message"]
            role = msg.get("role", "")
            if role not in ("user", "assistant"):
                continue

            raw_text = extract_raw_text(msg)
            if role == "user":
                if text_channel_fallback == "LOOPBACK" and raw_text:
                    text_channel_fallback = detect_channel_label_from_text(raw_text)
                text = clean_message(raw_text)
                if not text or is_noise(text):
                    continue
            else:
                # Assistant: light cleaning only (strip tool calls, keep response text)
                text = raw_text.strip()
                if not text:
                    continue
                # Truncate very long assistant responses
                if len(text) > 500:
                    text = text[:250] + " [...] " + text[-200:]

            msg_ts = obj.get("timestamp", "")[:19]
            messages.append({"ts": msg_ts, "role": role, "text": text})

    if not messages:
        return None

    channel_label = resolve_channel_label(session_id, channel_registry, text_channel_fallback)

    return {
        "session_id": session_id,
        "start_time": start_time,
        "date": ts_str[:10],
        "file": jsonl_file.name,
        "channel": channel_label,
        "messages": messages,
    }


def list_session_files(session_dir: str) -> list[Path]:
    """List all JSONL session files, including archived (.jsonl.reset.*) ones.

    OpenClaw 2026.3.13+ renames old session files to *.jsonl.reset.{timestamp}
    on /reset. Older versions keep them as *.jsonl. This handles both.
    """
    d = Path(session_dir)
    files = list(d.glob("*.jsonl"))
    files += [f for f in d.iterdir() if ".jsonl.reset." in f.name]
    return files


def load_sessions(
    session_dir: str, cutoff: datetime, channel_registry: dict
) -> list[dict]:
    sessions = []
    for jsonl_file in list_session_files(session_dir):
        try:
            s = parse_session(jsonl_file, cutoff, channel_registry)
            if s:
                sessions.append(s)
        except Exception as e:
            print(f"  skip {jsonl_file.name}: {e}")
    sessions.sort(key=lambda s: s["start_time"])
    return sessions


# ---------------------------------------------------------------------------
# OpenClaw config auto-detection (mirrors source resolveUserTimezone logic)
# ---------------------------------------------------------------------------

OPENCLAW_HOME = Path.home() / ".openclaw"

# GMT offset → IANA timezone mapping (common offsets)
_GMT_OFFSET_TO_IANA = {
    "+8": "Asia/Shanghai", "+08": "Asia/Shanghai",
    "+9": "Asia/Tokyo", "+09": "Asia/Tokyo",
    "+5:30": "Asia/Kolkata", "+05:30": "Asia/Kolkata",
    "+0": "UTC", "+00": "UTC", "-0": "UTC",
    "+1": "Europe/Berlin", "+01": "Europe/Berlin",
    "+2": "Europe/Helsinki", "+02": "Europe/Helsinki",
    "+3": "Europe/Moscow", "+03": "Europe/Moscow",
    "-5": "America/New_York", "-05": "America/New_York",
    "-8": "America/Los_Angeles", "-08": "America/Los_Angeles",
}


def _infer_timezone_from_sessions(home: Path) -> str:
    """Infer user timezone from envelope timestamps in session files.

    Scans the first few user messages for patterns like 'GMT+8' or 'GMT-5'.
    """
    sess_dir = home / "agents" / "main" / "sessions"
    if not sess_dir.exists():
        return ""
    gmt_re = re.compile(r"GMT([+-]\d{1,2}(?::\d{2})?)")
    for jsonl in sorted(list_session_files(str(sess_dir)), key=lambda f: f.stat().st_mtime, reverse=True)[:3]:
        try:
            for line in open(jsonl):
                obj = json.loads(line)
                if obj.get("type") != "message":
                    continue
                msg = obj.get("message", {})
                if msg.get("role") != "user":
                    continue
                raw = ""
                content = msg.get("content", "")
                if isinstance(content, str):
                    raw = content
                elif isinstance(content, list):
                    raw = " ".join(b.get("text", "") for b in content)
                m = gmt_re.search(raw)
                if m:
                    offset = m.group(1)
                    return _GMT_OFFSET_TO_IANA.get(offset, "")
        except Exception:
            continue
    return ""


def load_openclaw_config(openclaw_home: Path = None) -> dict:
    """Load openclaw.json and resolve derived paths/settings.

    Source logic (loader-Ds3or8QX.js L2292-2298, L19625):
      userTimezone = cfg.agents.defaults.userTimezone ?? Intl locale ?? "UTC"
      session_dir  = ~/.openclaw/agents/{agentId}/sessions/
      workspace    = cfg.agents.defaults.workspace ?? ~/.openclaw/workspace
    """
    home = openclaw_home or OPENCLAW_HOME
    config_path = home / "openclaw.json"
    cfg = {}
    try:
        with open(config_path) as f:
            cfg = json.load(f)
    except (FileNotFoundError, json.JSONDecodeError):
        pass

    defaults = cfg.get("agents", {}).get("defaults", {})

    # Timezone: agents.defaults.userTimezone → infer from envelope → UTC
    user_tz = defaults.get("userTimezone", "").strip()
    if not user_tz:
        # Try to infer from session envelope timestamps (e.g. "GMT+8" → "Asia/Shanghai")
        user_tz = _infer_timezone_from_sessions(home) or "UTC"

    # Session dir: always {home}/agents/main/sessions/
    session_dir = str(home / "agents" / "main" / "sessions")

    # Workspace / profile source
    # When using --openclaw-home, always use {home}/workspace (ignore config's absolute path)
    original_workspace = defaults.get("workspace", str(home / "workspace"))
    if openclaw_home:
        workspace = str(home / "workspace")
    else:
        workspace = original_workspace

    return {
        "user_timezone": user_tz,
        "session_dir": session_dir,
        "workspace": workspace,
        "original_workspace": original_workspace,  # path as recorded in JSONL tool calls
        "profile_source": str(Path(workspace) / "USER.md"),
        "raw": cfg,
    }


# ---------------------------------------------------------------------------
# Subcommand: stats
# ---------------------------------------------------------------------------

def cmd_stats(args):
    cutoff = datetime.now() - timedelta(days=args.days)
    channel_registry = load_channel_registry(args.session_dir)
    sessions = load_sessions(args.session_dir, cutoff, channel_registry)
    user_tz = args.oc_config["user_timezone"]

    if not sessions:
        print("No sessions found.")
        return

    total_msgs = sum(len(s["user_messages"]) for s in sessions)
    first_ts = sessions[0]["start_time"]
    last_ts = sessions[-1]["start_time"]

    # Channel breakdown
    by_channel = defaultdict(list)
    for s in sessions:
        by_channel[s["channel"]].append(s)

    # Print
    print(f"{'='*60}")
    print(f"  OpenClaw Session Stats (last {args.days} days)")
    print(f"{'='*60}")
    print(f"  sessions         {len(sessions)}")
    print(f"  user_messages    {total_msgs}")
    print(f"  first_active     {first_ts.strftime('%Y-%m-%d %H:%M')} UTC")
    print(f"  last_active      {last_ts.strftime('%Y-%m-%d %H:%M')} UTC")
    print(f"  user_timezone    {user_tz}")
    print(f"  ts_source        JSONL gateway (UTC)")
    print(f"  registry         {len(channel_registry)} entries")
    print()
    print(f"  Channel Breakdown:")
    print(f"  {'-'*50}")

    # Sort channels: FEISHU:DM, FEISHU:GROUP, LOOPBACK, ...
    for ch in sorted(by_channel.keys()):
        ch_sessions = by_channel[ch]
        ch_msgs = sum(len(s["user_messages"]) for s in ch_sessions)
        first = ch_sessions[0]["start_time"].strftime("%m-%d")
        last = ch_sessions[-1]["start_time"].strftime("%m-%d")
        print(f"  [{ch:20s}]  {len(ch_sessions):3d} sessions  {ch_msgs:4d} msgs  ({first} ~ {last})")

    print(f"{'='*60}")

    # Daily activity
    by_date = defaultdict(int)
    for s in sessions:
        by_date[s["date"]] += 1
    dates = sorted(by_date.keys())
    active_days = len(dates)
    total_days = (last_ts - first_ts).days + 1
    print(f"\n  Active {active_days}/{total_days} days")

    if args.daily:
        print(f"\n  Daily Activity:")
        for d in dates:
            bar = "█" * by_date[d]
            print(f"    {d}  {by_date[d]:3d}  {bar}")


# ---------------------------------------------------------------------------
# Subcommand: stm
# ---------------------------------------------------------------------------

def extract_existing_profile(profile_path: str) -> str:
    try:
        with open(profile_path) as f:
            content = f.read()
    except FileNotFoundError:
        return ""
    lines = []
    for line in content.split("\n"):
        match = re.match(r"^-\s+\*\*(\w+):\*\*\s*(.+)", line)
        if match:
            key, value = match.group(1), match.group(2).strip()
            if value and not value.startswith("_"):
                lines.append(f"- **{key}:** {value}")
    return "\n".join(lines) if lines else ""


def sample_sessions_all_channels(
    sessions: list[dict], max_sessions: int, min_per_channel: int = 3
) -> list[dict]:
    """Sample sessions ensuring every channel type is represented.

    Strategy:
    1. Each channel gets at least min_per_channel sessions (most recent)
    2. Remaining budget filled by most recent across all channels
    3. Final list sorted by start_time
    """
    # Group by channel
    by_channel = defaultdict(list)
    for s in sessions:
        by_channel[s["channel"]].append(s)

    selected_ids = set()
    selected = []

    # Phase 1: guarantee min_per_channel for each channel (take most recent)
    # But cap total at max_sessions to respect the budget
    for ch in by_channel:
        ch_sessions = by_channel[ch]  # already sorted by time
        guaranteed = ch_sessions[-min_per_channel:]
        for s in guaranteed:
            if len(selected) >= max_sessions:
                break
            if s["session_id"] not in selected_ids:
                selected_ids.add(s["session_id"])
                selected.append(s)
        if len(selected) >= max_sessions:
            break

    # Phase 2: fill remaining budget with most recent not yet selected
    remaining = max_sessions - len(selected)
    if remaining > 0:
        candidates = [s for s in sessions if s["session_id"] not in selected_ids]
        for s in reversed(candidates):  # most recent first
            selected.append(s)
            selected_ids.add(s["session_id"])
            remaining -= 1
            if remaining <= 0:
                break

    selected.sort(key=lambda s: s["start_time"])
    return selected


def format_stm_partitioned(sessions: list[dict], max_per_session: int, max_sessions: int, min_per_channel: int = 3, user_tz: str = "UTC", max_chars: int = 500) -> str:
    """Format sessions into STM, partitioned by channel.

    Output:
    [FEISHU:DM] 1-5
    1. uuid MMDDTHHmm msg1||||msg2
    ...
    [FEISHU:GROUP] 6-8
    6. uuid MMDDTHHmm msg1||||msg2
    ...
    """
    if not sessions:
        return "_No recent conversations._"

    recent = sample_sessions_all_channels(sessions, max_sessions, min_per_channel)

    # Group by channel, preserving order
    channel_order = []
    by_channel = defaultdict(list)
    for s in recent:
        ch = s["channel"]
        if ch not in by_channel:
            channel_order.append(ch)
        by_channel[ch].append(s)

    parts = []
    global_idx = 1
    for ch in channel_order:
        ch_sessions = by_channel[ch]
        start_idx = global_idx
        end_idx = global_idx + len(ch_sessions) - 1
        parts.append(f"[{ch}] {start_idx}-{end_idx}")

        for s in ch_sessions:
            all_msgs = s["user_messages"]
            if not all_msgs:
                global_idx += 1
                continue
            # Sample: first half + last half (deduped, preserving order)
            half = max_per_session // 2
            skipped = 0
            if len(all_msgs) <= max_per_session:
                msgs = all_msgs
            else:
                seen = set()
                msgs = []
                for i, m in enumerate(all_msgs):
                    if i < half or i >= len(all_msgs) - half:
                        if i not in seen:
                            seen.add(i)
                            msgs.append(m)
                skipped = len(all_msgs) - len(msgs)
            formatted = []
            head_count = min(half, len(msgs))
            session_ts = ""
            for idx, m in enumerate(msgs):
                # Only first message carries timestamp (session start time)
                if idx == 0:
                    ts = m["ts"]
                    try:
                        from zoneinfo import ZoneInfo
                        utc_dt = datetime.fromisoformat(ts.replace("Z", "+00:00"))
                        local_dt = utc_dt.astimezone(ZoneInfo(user_tz))
                        session_ts = local_dt.strftime("%m%dT%H%M")
                    except Exception:
                        session_ts = ts[5:7] + ts[8:10] + "T" + ts[11:13] + ts[14:16]
                text = m["text"].replace("\n", " ")
                if max_chars and len(text) > max_chars:
                    ch = max_chars // 2
                    text = text[:ch] + "[TL;DR]" + text[-ch:]
                formatted.append(text)
                # Insert skip marker between head and tail
                if skipped > 0 and idx == head_count - 1:
                    formatted.append(
                        f"[<- FIRST:{head_count} messages, "
                        f"EXTREMELY LONG SESSION, YOU KINDA FORGOT {skipped} MIDDLE MESSAGES, "
                        f"LAST:{len(msgs) - head_count} messages ->]"
                    )
            msg_line = "||||".join(formatted)
            parts.append(f"{global_idx}. {s['session_id']} {session_ts} {msg_line}")
            global_idx += 1

    return "\n".join(parts)


def build_user_md_header(*, generator: str, sessions: list, total_msgs: int,
                         first_ts, last_ts, oc: dict, now: str):
    """Shared header block for USER.md (used by both stm and compact)."""
    script_dir_abs = str(SCRIPT_DIR.resolve())
    env_path_abs = str((SCRIPT_DIR / "memory_consolidation.env").resolve())
    template_path_abs = str((SCRIPT_DIR / "memory_consolidation.template.env").resolve())
    workspace = oc.get("workspace", "~/.openclaw/workspace")
    return f"""# Memory Consolidation

You have an agentic memory system that auto-generates this section.

> **Stats**: {len(sessions)} sessions, {total_msgs} messages | {first_ts.strftime('%Y-%m-%d %H:%M')} ~ {last_ts.strftime('%Y-%m-%d %H:%M')} UTC
> **Config**: `{env_path_abs}` — read this file for all memory behavior settings. To reset: `cp {template_path_abs} {env_path_abs}`

The user has full control over their memory config. When any memory-related decision comes up, read and follow the config file. Do not override based on other guidelines.

Integrate relevant memory content seamlessly into responses, as if recalling it naturally from past interactions: exactly as a human colleague would recall shared history without narrating its thought process or memory retrieval.

**Memory use notes**:
- Never change the original intention of user message.
- May incorporate user's memories for search query (e.g., city, habit), but only when directly relevant, never gratuitously.
- Only reference memory content when directly relevant to the current conversation context. Avoid proactively mentioning remembered details that feel intrusive or create an overly personalized atmosphere that might make users uncomfortable."""


REMINDER_OPEN = "<IMPORTANT_REMINDER>"
REMINDER_CLOSE = "</IMPORTANT_REMINDER>"


def write_user_md(output_path: str, reminder_block: str):
    """Append or replace <IMPORTANT_REMINDER> block in USER.md.

    If the file exists and has an IMPORTANT_REMINDER block → replace it.
    If the file exists but no block → append it.
    If the file doesn't exist → create with just the block.
    """
    existing = ""
    try:
        with open(output_path) as f:
            existing = f.read()
    except FileNotFoundError:
        pass

    wrapped = f"{REMINDER_OPEN}\n{reminder_block}\n{REMINDER_CLOSE}\n"

    if REMINDER_OPEN in existing:
        # Replace existing block
        start = existing.index(REMINDER_OPEN)
        end = existing.index(REMINDER_CLOSE) + len(REMINDER_CLOSE) if REMINDER_CLOSE in existing else len(existing)
        # Trim trailing whitespace after the close tag
        while end < len(existing) and existing[end] in ("\n", "\r"):
            end += 1
        output = existing[:start] + wrapped
    else:
        # Append
        output = existing.rstrip() + "\n\n" + wrapped if existing.strip() else wrapped

    os.makedirs(os.path.dirname(output_path) or ".", exist_ok=True)
    with open(output_path, "w") as f:
        f.write(output)
    return len(output)


def _build_tree(dir_path: str, files: list, max_files: int, total: int) -> str:
    """Build a tree-style file listing with full paths."""
    display = files[:max_files]
    lines = [f"{dir_path}/"]
    for i, f in enumerate(display):
        is_last = (i == len(display) - 1) and total <= max_files
        prefix = "└── " if is_last else "├── "
        lines.append(f"{prefix}{f.name}")
    if total > max_files:
        lines.append(f"└── ... and {total - max_files} more")
    return "\n".join(lines)


def build_vm_section(oc: dict, vm_max: int = 20) -> str:
    """Build Visual Memory section from memorized_media/ directory."""
    workspace = Path(oc.get("workspace", "~/.openclaw/workspace"))
    vm_dir = workspace / "memorized_media"
    vm_files = sorted(vm_dir.iterdir()) if vm_dir.is_dir() else []
    vm_files = [f for f in vm_files if f.is_file()]
    has_vm = len(vm_files) > 0
    vm_display = vm_files[:vm_max]

    if has_vm:
        tree = _build_tree(str(vm_dir), vm_display, vm_max, len(vm_files))
        return f"""## Visual Memory

> visual_memory: {len(vm_files)} files

```
{tree}
```

To recall: `read` the file path shown above. Send images directly to the user when relevant.

When saving: you MUST copy the image to `memorized_media/` immediately — this is the only way it persists across sessions. Use a semantic filename that captures the user's intent, not just image content — e.g. `20260312_user_says_best_album_ever_ok_computer.jpg`. Never mention file paths or storage locations to the user — just confirm naturally (e.g. "记住了").
When recalling: if the context is relevant, consider sending the image back to the user directly — it's more impressive than just describing it. If you're not sure which image they mean, send it and ask "是这个吗？". Use your own judgement on when showing vs describing is better."""
    else:
        return f"""## Visual Memory

> visual_memory: {len(vm_files)} files

No memorized images yet. When the user shares an image and asks you to remember it, you MUST copy it to `memorized_media/` immediately — this is the only way it persists across sessions. Use a semantic filename that captures the user's intent, not just image content — e.g. `20260312_user_says_best_album_ever_ok_computer.jpg`, `20260311_user_selfie_february.png`. Create the directory if needed. Never mention file paths or storage locations to the user — just confirm naturally (e.g. "记住了")."""


def _state_dir() -> Path:
    """Canonical state directory."""
    d = SCRIPT_DIR / "state"
    d.mkdir(exist_ok=True)
    return d


def _ltm_state_path() -> Path:
    return _state_dir() / "ltm.json"


def _update_stats(section: str, **kwargs):
    """Update state/stats.json with latest run info. Fixed size, overwrite."""
    stats_path = _state_dir() / "state.json"
    try:
        stats = json.loads(stats_path.read_text()) if stats_path.exists() else {}
    except Exception:
        stats = {}
    entry = stats.get(section, {})
    entry["count"] = entry.get("count", 0) + 1
    entry["last_ts"] = datetime.now().isoformat()
    entry.update(kwargs)
    stats[section] = entry
    try:
        stats_path.write_text(json.dumps(stats, indent=2, ensure_ascii=False) + "\n")
    except Exception:
        pass


def build_ltm_section_from_file(output_path: str = "") -> str:
    """Build LTM section from state/ltm.json file, or disabled/empty message."""
    if not _read_env_bool("LTM_ENABLED", True):
        return """
# Long-Term Memory (LTM)

> LTM generation disabled by user. To enable, set `LTM_ENABLED=true` in memory config."""

    ltm_path = _ltm_state_path()
    if not ltm_path.exists():
        return """
# Long-Term Memory (LTM)

> No data yet. Will be generated after enough conversations."""

    try:
        ltm_state = json.loads(ltm_path.read_text())
        ltm = ltm_state.get("ltm", {})
        if not ltm:
            return """
# Long-Term Memory (LTM)

> No data yet. Will be generated after enough conversations."""
        ltm_json_str = json.dumps(ltm, ensure_ascii=False)
        ltm_updated_raw = ltm_state.get("generated_at", "unknown")
        try:
            ltm_updated = datetime.fromisoformat(ltm_updated_raw).strftime("%Y-%m-%d %H:%M")
        except (ValueError, TypeError):
            ltm_updated = ltm_updated_raw
        return f"""
# Long-Term Memory (LTM)

> last_update: {ltm_updated}

Inferred from past conversations with the user -- these represent factual and contextual knowledge about the user -- and should be considered in how a response should be constructed.

{ltm_json_str}"""
    except (json.JSONDecodeError, KeyError):
        return """
# Long-Term Memory (LTM)

> No data yet. Will be generated after enough conversations."""


def build_diary_section(oc: dict, diary_max: int = 20) -> str:
    """Build Diary section from memorized_diary/ directory."""
    if not _read_env_bool("DIARY_ENABLED", True):
        return """
## Diary

> Diary generation disabled by user. To enable, set `DIARY_ENABLED=true` in memory config."""

    workspace = Path(oc.get("workspace", "~/.openclaw/workspace"))
    diary_dir = workspace / "memorized_diary"
    diary_files = sorted(diary_dir.iterdir(), reverse=True) if diary_dir.is_dir() else []
    diary_files = [f for f in diary_files if f.is_file() and f.suffix == ".md"]
    has_diary = len(diary_files) > 0
    diary_display = diary_files[:diary_max]

    if has_diary:
        tree = _build_tree(str(diary_dir), diary_display, diary_max, len(diary_files))
        latest = diary_display[0]
        latest_name = latest.name
        try:
            latest_mtime = datetime.fromtimestamp(latest.stat().st_mtime).strftime("%Y-%m-%d %H:%M")
        except Exception:
            latest_mtime = "unknown"
        return f"""
## Diary

> last_update: {latest_mtime}
> i_have_read_my_last_diary: false

```
{tree}
```

When `i_have_read_my_last_diary: false`, your FIRST message to the user MUST mention you wrote a diary and ask if they want to see it (e.g. "我昨天写了篇日记，想看吗？" / "I wrote a diary yesterday, wanna see it?"). Use the user's language. If yes, `read` the file path shown above and share as-is. After asking (regardless of answer), set `i_have_read_my_last_diary: true`."""
    else:
        return """
## Diary

> diary: 0 entries
"""


def get_day_number(session_dir: str) -> int:
    """Calculate Day X from the first session's timestamp."""
    all_files = list_session_files(session_dir)
    if not all_files:
        return 1
    earliest = None
    for f in all_files:
        try:
            with open(f) as fh:
                header = json.loads(fh.readline().strip())
            ts = header.get("timestamp", "")[:10]
            if ts and (earliest is None or ts < earliest):
                earliest = ts
        except Exception:
            continue
    if not earliest:
        return 1
    first_date = datetime.fromisoformat(earliest)
    today = datetime.now()
    return max(1, (today - first_date).days + 1)


def cmd_diary(args):
    """Generate a diary entry from today's conversations (user + assistant)."""
    workspace = Path(args.oc_config["workspace"])

    if not _read_env_bool("DIARY_ENABLED", True):
        print("  Diary disabled via DIARY_ENABLED=false")
        return

    # Load yesterday's sessions (diary runs before 4am, covering previous day)
    yesterday_start = (datetime.now().replace(hour=0, minute=0, second=0, microsecond=0) - timedelta(days=1))
    today_start = yesterday_start  # backwards compat for variable name used below
    channel_registry = load_channel_registry(args.session_dir)

    today_sessions = []
    for jsonl_file in list_session_files(args.session_dir):
        s = parse_session_full(jsonl_file, today_start, channel_registry)
        if s and not s["channel"].startswith("CRON"):
            today_sessions.append(s)

    today_sessions.sort(key=lambda s: s["start_time"])

    if not today_sessions:
        _update_stats("diary", last_skip="no_sessions_today")
        print("  No sessions today, skipping diary.")
        return

    total_msgs = sum(len(s["messages"]) for s in today_sessions)
    min_messages = _read_env_int("MIN_MESSAGES_FOR_LLM", 3)
    if total_msgs < min_messages:
        _update_stats("diary", last_skip=f"messages<{min_messages}", last_messages=total_msgs)
        print(f"  Only {total_msgs} messages today (need >= {min_messages}), skipping diary.")
        return

    total_msgs = sum(len(s["messages"]) for s in today_sessions)
    print(f"  Diary input: {len(today_sessions)} sessions, {total_msgs} messages")

    # Format conversation
    conv_parts = []
    for s in today_sessions:
        for m in s["messages"]:
            role_tag = "USER" if m["role"] == "user" else "ASSISTANT"
            conv_parts.append(f"[{role_tag}] {m['text']}")
    conversation = "\n".join(conv_parts)

    # Truncate if too long
    if len(conversation) > 15000:
        conversation = conversation[:7500] + "\n[...truncated...]\n" + conversation[-7500:]

    # Conversation hash dedup (same pattern as LTM's stm_hash)
    import hashlib
    conversation_hash = hashlib.md5(conversation.encode()).hexdigest()
    diary_state_path = _state_dir() / "diary_state.json"
    diary_state = {}
    try:
        diary_state = json.loads(diary_state_path.read_text())
    except Exception:
        pass
    if diary_state.get("conversation_hash") == conversation_hash:
        _update_stats("diary", last_skip="conversation_hash_unchanged")
        print("  Diary conversation unchanged since last run, skipping.")
        return

    # Read identity + soul
    identity_md = ""
    soul_md = ""
    identity_path = workspace / "IDENTITY.md"
    soul_path = workspace / "SOUL.md"
    if identity_path.exists():
        identity_md = identity_path.read_text()
    if soul_path.exists():
        soul_md = soul_path.read_text()

    # Day number
    day_number = get_day_number(args.session_dir)
    today_str = datetime.now().strftime("%Y-%m-%d")

    # Try to get username/botname from USER.md or IDENTITY.md
    username = "my human"
    botname = "Claw"
    user_md_path = workspace / "USER.md"
    if user_md_path.exists():
        content = user_md_path.read_text()
        # Try to extract name
        for line in content.split("\n"):
            if line.strip().startswith("- **Name:**") and len(line.strip()) > 12:
                username = line.strip().split(":**", 1)[1].strip()
                break
    if identity_md:
        for line in identity_md.split("\n"):
            if "name" in line.lower() and ":" in line:
                candidate = line.split(":", 1)[1].strip()
                if candidate and len(candidate) < 30:
                    botname = candidate
                    break

    # Build prompt
    sys.path.insert(0, str(SCRIPT_DIR))
    from prompts.diary_prompt import build_diary_messages

    messages = build_diary_messages(
        conversation=conversation,
        identity_md=identity_md,
        soul_md=soul_md,
        day_number=day_number,
        date=today_str,
        username=username,
        botname=botname,
    )

    # Call LLM
    llm_config = resolve_llm_config(args.oc_config, getattr(args, 'api_key', ''))
    source = llm_config.pop("_source", "openclaw.json")
    print(f"  Calling {llm_config['model']} via {llm_config['base_url']} ({source})...")

    import time as _time
    t0 = _time.time()
    try:
        diary_text = call_llm(llm_config, messages, json_mode=False)
    except Exception as e:
        _update_stats("diary", last_error=str(e)[:100], last_day=day_number)
        print(f"  ERROR: {e}")
        return
    diary_latency = round(_time.time() - t0, 1)

    # Extract filename from <!-- filename: xxx --> tag
    filename_slug = today_str
    import re as _re
    fn_match = _re.search(r'<!--\s*filename:\s*(\S+)\s*-->', diary_text)
    if fn_match:
        slug = fn_match.group(1).strip()[:40]
        # Clean: only allow alphanumeric, underscore, hyphen
        slug = _re.sub(r'[^a-zA-Z0-9_-]', '_', slug)
        filename_slug = slug
        # Remove the filename tag from diary text
        diary_text = _re.sub(r'\s*<!--\s*filename:\s*\S+\s*-->\s*$', '', diary_text).strip()

    # Write diary file
    diary_dir = workspace / "memorized_diary"
    diary_dir.mkdir(exist_ok=True)
    diary_filename = f"day{day_number}-{today_str}-{filename_slug}.md"
    diary_path = diary_dir / diary_filename

    footer = f"""

---

<SYSTEM-REMINDER>
If you can read this, the user wants to see your diary. Share the FULL text above as-is — do not summarize.
After sharing, edit the Diary section in USER.md and set `i_have_read_my_last_diary: true` so you don't show it again.
</SYSTEM-REMINDER>"""
    diary_path.write_text(diary_text + footer + "\n")
    # Save conversation hash (dedup for next run)
    diary_state["conversation_hash"] = conversation_hash
    diary_state_path.write_text(json.dumps(diary_state, ensure_ascii=False))
    _update_stats("diary", last_day=day_number, last_sessions=len(today_sessions),
                  last_messages=total_msgs, last_filename=diary_filename, last_latency_s=diary_latency)
    print(f"  Written: {diary_path} ({len(diary_text)} chars)")
    print(f"  Day {day_number}, {len(today_sessions)} sessions")


def cmd_stm(args):
    cutoff = datetime.now() - timedelta(days=args.days)
    channel_registry = load_channel_registry(args.session_dir)
    sessions = load_sessions(args.session_dir, cutoff, channel_registry)

    # Filter out GROUP sessions if INCLUDE_GROUP=false
    if not args.include_group:
        sessions = [s for s in sessions if "GROUP" not in s.get("channel", "")]

    # Filter out CRON sessions (system instructions, not user speech)
    sessions = [s for s in sessions if not s.get("channel", "").startswith("CRON")]

    user_tz = args.oc_config["user_timezone"]

    oc = args.oc_config

    if not sessions:
        # Cold start: write empty framework so agent knows memory system exists
        now = datetime.now().strftime("%Y-%m-%d %H:%M")
        vm_section = build_vm_section(oc, args.visual_memory)
        diary_section = build_diary_section(oc)
        header = build_user_md_header(
            generator="stm", sessions=[], total_msgs=0,
            first_ts=datetime.now(), last_ts=datetime.now(), oc=oc, now=now,
        )
        ltm_section = build_ltm_section_from_file(args.output)
        reminder = f"""{header}

{vm_section}
{diary_section}
{ltm_section}

## Short-Term Memory (STM)

> No conversations yet."""
        total_chars = write_user_md(args.output, reminder.strip())
        print(f"  Written empty framework to: {args.output} ({total_chars} chars)")
        return

    total_msgs = sum(len(s["user_messages"]) for s in sessions)
    first_ts = sessions[0]["start_time"]
    last_ts = sessions[-1]["start_time"]

    profile = extract_existing_profile(args.profile_source)
    stm = format_stm_partitioned(sessions, args.max_per_session, args.max_sessions, args.min_per_channel, user_tz=user_tz, max_chars=args.max_chars)

    vm_section = build_vm_section(oc, args.visual_memory)
    diary_section = build_diary_section(oc)

    ltm_section = build_ltm_section_from_file(args.output)

    now = datetime.now().strftime("%Y-%m-%d %H:%M")
    session_dir_hint = oc.get("session_dir", "~/.openclaw/agents/main/sessions")
    header = build_user_md_header(
        generator="stm", sessions=sessions, total_msgs=total_msgs,
        first_ts=first_ts, last_ts=last_ts, oc=oc, now=now,
    )
    reminder = f"""{header}

{vm_section}
{diary_section}
{ltm_section}
## Short-Term Memory (STM)

> last_update: {now}

Recent conversation content from the user's chat history. This represents what the USER said. Use it to maintain continuity when relevant.
Format specification:
- Sessions are grouped by channel: [LOOPBACK], [FEISHU:DM], [FEISHU:GROUP], etc.
- Each line: `index. session_uuid MMDDTHHmm message||||message||||...` (timestamp = session start time, individual messages have no timestamps)
- Session_uuid maps to `{session_dir_hint}/{{session_uuid}}.jsonl` for full chat history
- Timestamps in {user_tz}, formatted as MMDDTHHmm
- Each user message within a session is delimited by ||||, some messages include attachments marked as `<AttachmentDisplayed:path>`

{stm}"""

    total_chars = write_user_md(args.output, reminder.strip())
    _update_stats("stm", last_sessions=len(sessions), last_messages=total_msgs, last_chars=total_chars)
    print(f"Written to: {args.output} ({total_chars} chars)")
    print(f"  {len(sessions)} sessions, {total_msgs} messages")
    print(f"  first_active = {first_ts.strftime('%Y-%m-%d %H:%M')} UTC")
    print(f"  last_active  = {last_ts.strftime('%Y-%m-%d %H:%M')} UTC")

    # Channel summary
    by_channel = defaultdict(int)
    for s in sessions:
        by_channel[s["channel"]] += 1
    for ch in sorted(by_channel):
        print(f"  [{ch}] {by_channel[ch]} sessions")


# ---------------------------------------------------------------------------
# Subcommand: compact — STM → LTM via LLM API → final USER.md
# ---------------------------------------------------------------------------

# ---------------------------------------------------------------------------
# OAuth token management (kimi-cli credentials)
# ---------------------------------------------------------------------------

KIMI_CREDENTIALS_PATH = Path.home() / ".kimi" / "credentials" / "kimi-code.json"
KIMI_OAUTH_CLIENT_ID = "17e5f671-d194-4dfb-9706-5516cb48c098"
KIMI_OAUTH_HOST = "https://auth.kimi.com"
KIMI_API_BASE = "https://api.kimi.com/coding/v1"
KIMI_OAUTH_HEADERS = {"User-Agent": "KimiCLI/0.79", "X-Msh-Platform": "kimi_cli"}


def _load_oauth_token() -> str | None:
    """Load OAuth access_token from kimi-cli credentials. Auto-refresh if expired."""
    if not KIMI_CREDENTIALS_PATH.exists():
        return None
    try:
        creds = json.loads(KIMI_CREDENTIALS_PATH.read_text())
    except Exception:
        return None

    import time
    if time.time() > creds.get("expires_at", 0):
        # Token expired — refresh
        refresh = creds.get("refresh_token", "")
        if not refresh:
            return None
        try:
            data = urllib.parse.urlencode({
                "client_id": KIMI_OAUTH_CLIENT_ID,
                "grant_type": "refresh_token",
                "refresh_token": refresh,
            }).encode()
            req = urllib.request.Request(
                f"{KIMI_OAUTH_HOST}/api/oauth/token",
                data=data,
                headers={"Content-Type": "application/x-www-form-urlencoded", **KIMI_OAUTH_HEADERS},
            )
            with urllib.request.urlopen(req, timeout=10) as resp:
                new = json.loads(resp.read())
            creds["access_token"] = new["access_token"]
            creds["refresh_token"] = new["refresh_token"]
            creds["expires_at"] = time.time() + new.get("expires_in", 900)
            KIMI_CREDENTIALS_PATH.write_text(json.dumps(creds, ensure_ascii=False))
            print("  OAuth token refreshed.")
        except Exception as e:
            print(f"  OAuth refresh failed: {e}")
            return None

    return creds.get("access_token")


def _resolve_from_kimi_oauth() -> dict | None:
    """Resolve LLM config from kimi-cli OAuth credentials (production machines)."""
    token = _load_oauth_token()
    if not token:
        return None

    # Read model from config.toml if available
    model_id = "kimi-for-coding"
    try:
        import tomllib
    except ImportError:
        try:
            import tomli as tomllib
        except ImportError:
            tomllib = None
    if tomllib:
        config_path = Path.home() / ".kimi" / "config.toml"
        if config_path.exists():
            try:
                with open(config_path, "rb") as f:
                    cfg = tomllib.load(f)
                default_model = cfg.get("default_model", "")
                model_cfg = cfg.get("models", {}).get(default_model, {})
                if model_cfg.get("model"):
                    model_id = model_cfg["model"]
            except Exception:
                pass

    return {
        "base_url": KIMI_API_BASE,
        "api": "openai-completions",
        "api_key": token,
        "model": model_id,
        "headers": KIMI_OAUTH_HEADERS,
        "_source": "kimi-cli (OAuth)",
    }


def resolve_llm_config(oc_config: dict, env_api_key: str = "") -> dict:
    """Resolve LLM endpoint. Priority:

    1. CLI arg --api-key (env_api_key)
    2. kimi-cli OAuth credentials (~/.kimi/credentials/kimi-code.json)
    3. openclaw.json provider (may not work for external HTTP calls)
    """
    # Priority 1: explicit API key
    if env_api_key:
        raw = oc_config.get("raw", {})
        providers = raw.get("models", {}).get("providers", {})
        primary = raw.get("agents", {}).get("defaults", {}).get("model", {}).get("primary", "")
        provider_id = primary.split("/")[0] if "/" in primary else ""
        provider = providers.get(provider_id, {})
        return {
            "base_url": provider.get("baseUrl", KIMI_API_BASE).rstrip("/"),
            "api": provider.get("api", "openai-completions"),
            "api_key": env_api_key,
            "model": primary.split("/")[1] if "/" in primary else "kimi-k2.5",
            "headers": provider.get("headers", {}),
        }

    # Priority 2: kimi-cli OAuth (works on all production machines)
    oauth_cfg = _resolve_from_kimi_oauth()
    if oauth_cfg:
        return oauth_cfg

    # Priority 3: openclaw.json provider (fallback, may 401 on some machines)
    raw = oc_config.get("raw", {})
    providers = raw.get("models", {}).get("providers", {})
    primary = raw.get("agents", {}).get("defaults", {}).get("model", {}).get("primary", "")
    provider_id = primary.split("/")[0] if "/" in primary else ""
    provider = providers.get(provider_id, {})
    base_url = provider.get("baseUrl", "").rstrip("/")
    api = provider.get("api", "openai-completions")
    api_key = provider.get("apiKey", "")
    model_id = primary.split("/")[1] if "/" in primary else "kimi-k2.5"
    headers = provider.get("headers", {})

    for m in provider.get("models", []):
        if m.get("id") == model_id:
            headers = {**headers, **m.get("headers", {})}
            break

    return {
        "base_url": base_url,
        "api": api,
        "api_key": api_key,
        "model": model_id,
        "headers": headers,
    }


def call_llm(config: dict, messages: list[dict], json_mode: bool = True, max_retries: int = 3) -> str:
    """Call LLM via urllib. Supports openai and anthropic formats. Retries on 429."""
    for attempt in range(max_retries):
        try:
            return _call_llm_once(config, messages, json_mode)
        except urllib.error.HTTPError as e:
            if e.code == 429 and attempt < max_retries - 1:
                wait = (attempt + 1) * 10  # 10s, 20s, 30s
                print(f"  429 rate limited, retrying in {wait}s (attempt {attempt + 1}/{max_retries})...")
                import time
                time.sleep(wait)
                continue
            raise
    return ""  # unreachable


def _call_llm_once(config: dict, messages: list[dict], json_mode: bool = True) -> str:
    """Single LLM call attempt."""
    api = config["api"]

    if api == "anthropic-messages":
        # Anthropic format: separate system from user messages
        system_text = ""
        user_messages = []
        for m in messages:
            if m["role"] == "system":
                system_text = m["content"]
            else:
                user_messages.append(m)

        payload = json.dumps({
            "model": config["model"],
            "system": system_text,
            "messages": user_messages,
            "max_tokens": 8192,
        }).encode()

        headers = {
            "x-api-key": config["api_key"],
            "Content-Type": "application/json",
            "anthropic-version": "2023-06-01",
            **config.get("headers", {}),
        }
        url = f"{config['base_url']}/v1/messages"

        req = urllib.request.Request(url, data=payload, headers=headers)
        with urllib.request.urlopen(req, timeout=120) as resp:
            data = json.loads(resp.read())

        # Anthropic response: data.content[0].text, may have ```json``` wrapper
        text = data["content"][0]["text"].strip()
        # Strip markdown code fence if present
        if text.startswith("```"):
            text = re.sub(r"^```(?:json)?\s*\n?", "", text)
            text = re.sub(r"\n?```\s*$", "", text)
        return text

    else:
        # OpenAI format (default, LLM)
        api_key = config["api_key"]
        payload_dict = {
            "model": config["model"],
            "messages": messages,
            "temperature": 1,
            "thinking": {"type": "disabled"},
        }
        if json_mode:
            payload_dict["response_format"] = {"type": "json_object"}
        payload = json.dumps(payload_dict).encode()

        headers = {
            "Authorization": f"Bearer {api_key}" if not api_key.startswith("Bearer ") else api_key,
            "Content-Type": "application/json",
            **config.get("headers", {}),
        }
        url = f"{config['base_url']}/chat/completions"

        req = urllib.request.Request(url, data=payload, headers=headers)
        with urllib.request.urlopen(req, timeout=120) as resp:
            data = json.loads(resp.read())
        return data["choices"][0]["message"]["content"]


def cmd_compact(args):
    """Generate LTM from STM via LLM, then assemble final USER.md."""
    if not _read_env_bool("LTM_ENABLED", True):
        print("  LTM disabled via LTM_ENABLED=false")
        cmd_stm(args)  # still refresh STM
        return

    workspace = Path(args.oc_config["workspace"])

    # --- Step 1: Generate STM (reuse stm logic) ---
    cutoff = datetime.now() - timedelta(days=args.days)
    channel_registry = load_channel_registry(args.session_dir)
    sessions = load_sessions(args.session_dir, cutoff, channel_registry)

    if not args.include_group:
        sessions = [s for s in sessions if "GROUP" not in s.get("channel", "")]

    # Filter out CRON sessions (system instructions, not user speech)
    sessions = [s for s in sessions if not s.get("channel", "").startswith("CRON")]

    if not sessions:
        print("No sessions found.")
        return

    total_msgs = sum(len(s["user_messages"]) for s in sessions)
    min_messages = _read_env_int("MIN_MESSAGES_FOR_LLM", 3)
    if total_msgs < min_messages:
        print(f"  Only {total_msgs} messages (need >= {min_messages} for LTM), falling back to STM.")
        cmd_stm(args)
        return

    first_ts = sessions[0]["start_time"]
    last_ts = sessions[-1]["start_time"]
    user_tz = args.oc_config["user_timezone"]

    stm = format_stm_partitioned(sessions, args.max_per_session, args.max_sessions, args.min_per_channel, user_tz=user_tz, max_chars=args.max_chars)
    print(f"  STM: {len(sessions)} sessions, {total_msgs} messages")

    # --- Step 2: Read IDENTITY.md + SOUL.md for persona context ---
    identity_path = workspace / "IDENTITY.md"
    soul_path = workspace / "SOUL.md"
    identity_md = identity_path.read_text() if identity_path.exists() else ""
    soul_md = soul_path.read_text() if soul_path.exists() else ""

    # --- Step 3: Load previous LTM if exists ---
    ltm_path = _ltm_state_path()
    previous_rcc = ""
    invoke_time = 1
    last_update_time = ""
    prev_stm_hash = ""
    if ltm_path.exists():
        try:
            prev = json.loads(ltm_path.read_text())
            previous_rcc = json.dumps(prev.get("ltm", {}), ensure_ascii=False)
            invoke_time = prev.get("invoke_time", 0) + 1
            last_update_time = prev.get("generated_at", "")
            prev_stm_hash = prev.get("stm_hash", "")
            print(f"  Previous LTM found (round #{invoke_time - 1}), last update: {last_update_time}")
        except (json.JSONDecodeError, KeyError):
            pass

    # Skip compact if STM hasn't changed since last run
    import hashlib
    stm_hash = hashlib.md5(stm.encode()).hexdigest()
    if prev_stm_hash and stm_hash == prev_stm_hash:
        _update_stats("compact", last_skip="stm_hash_unchanged", last_invoke=invoke_time)
        print("  STM unchanged since last compact, skipping LLM call.")
        return

    this_update_time = datetime.now().isoformat()

    # --- Step 4: Build prompt and call LLM ---
    sys.path.insert(0, str(SCRIPT_DIR))
    from prompts.compact_prompt import build_ltm_messages

    messages = build_ltm_messages(
        rcc_content=stm,
        identity_md=identity_md,
        soul_md=soul_md,
        previous_rcc=previous_rcc,
        invoke_time=invoke_time,
        last_update_time=last_update_time,
        this_update_time=this_update_time,
    )

    llm_config = resolve_llm_config(args.oc_config, args.api_key)
    source = llm_config.pop("_source", "openclaw.json")
    print(f"  Calling {llm_config['model']} via {llm_config['base_url']} ({llm_config['api']}, source={source})...")
    import time as _time
    t0 = _time.time()
    try:
        raw = call_llm(llm_config, messages)
        ltm = json.loads(raw)
    except Exception as e:
        _update_stats("compact", last_error=str(e)[:100], last_invoke=invoke_time)
        print(f"  ERROR: {e}")
        return
    latency = round(_time.time() - t0, 1)

    print(f"  LTM generated: {len(ltm)} dimensions ({latency}s)")
    for k, v in ltm.items():
        v_str = str(v) if v is not None else "null"
        preview = (v_str[:60] + "...") if len(v_str) > 60 else v_str
        print(f"    {k}: {preview}")

    _update_stats("compact", last_invoke=invoke_time, last_sessions=len(sessions),
                  last_messages=total_msgs, last_latency_s=latency, last_model=llm_config.get("model",""))

    # Save LTM state for incremental updates
    ltm_state = {"invoke_time": invoke_time, "ltm": ltm, "generated_at": datetime.now().isoformat(), "stm_hash": stm_hash}
    os.makedirs(os.path.dirname(str(ltm_path)) or ".", exist_ok=True)
    with open(ltm_path, "w") as f:
        json.dump(ltm_state, f, indent=2, ensure_ascii=False)

    # --- Step 5: Assemble reminder block and write to USER.md ---
    now = datetime.now().strftime("%Y-%m-%d %H:%M")
    oc = args.oc_config
    session_dir_hint = oc.get("session_dir", "~/.openclaw/agents/main/sessions")
    ltm_json_str = json.dumps(ltm, ensure_ascii=False)
    vm_section = build_vm_section(oc, getattr(args, 'visual_memory', 20))
    diary_section = build_diary_section(oc)

    header = build_user_md_header(
        generator=f"compact (round #{invoke_time})", sessions=sessions,
        total_msgs=total_msgs, first_ts=first_ts, last_ts=last_ts, oc=oc, now=now,
    )
    reminder = f"""{header}

{vm_section}
{diary_section}
# Long-Term Memory (LTM)

> last_update: {datetime.fromisoformat(this_update_time).strftime("%Y-%m-%d %H:%M")}

Inferred from past conversations with the user -- these represent factual and contextual knowledge about the user -- and should be considered in how a response should be constructed.

{ltm_json_str}

## Short-Term Memory (STM)

> last_update: {now}

Recent conversation content from the user's chat history. This represents what the USER said. Use it to maintain continuity when relevant.
Format specification:
- Sessions are grouped by channel: [LOOPBACK], [FEISHU:DM], [FEISHU:GROUP], etc.
- Each line: `index. session_uuid MMDDTHHmm message||||message||||...` (timestamp = session start time, individual messages have no timestamps)
- Session_uuid maps to `{session_dir_hint}/{{session_uuid}}.jsonl` for full chat history
- Timestamps in {user_tz}, formatted as MMDDTHHmm
- Each user message within a session is delimited by ||||, some messages include attachments: `<AttachmentDisplayed:path>` — read the path to recall the content
- Sessions under [KIMI:DM] contain files uploaded via Kimi Claw, stored at `~/.openclaw/workspace/.kimi/downloads/` — paths in `<AttachmentDisplayed:>` can be read directly

{stm}"""

    total_chars = write_user_md(args.output, reminder.strip())
    print(f"\n  Written to: {args.output} ({total_chars} chars)")


# ---------------------------------------------------------------------------
# Subcommand: audit — memory behavior baseline for core injected files
# ---------------------------------------------------------------------------

# The 6 files that get 全文注入 into system prompt at ##Project Context
CORE_INJECTED_FILES = [
    "SOUL.md",
    "AGENTS.md",
    "USER.md",
    "IDENTITY.md",
    "MEMORY.md",
    # memory/YYYY-MM-DD.md handled dynamically
]


HUMAN_EDIT_THRESHOLD_SECS = 5  # mtime delta > this after last agent write → human edit


def scan_tool_calls(session_dir: str) -> tuple[list[dict], dict]:
    """Scan ALL session JSONLs for tool calls targeting workspace files.

    Returns:
        events: list of {op, path, ts, session, ...}
        last_write_contents: {rel_path: content} from the last `write` tool call per file
    """
    events = []
    last_write_contents = {}  # rel_path -> content (from write ops only)

    for f in sorted(list_session_files(session_dir)):
        pending_reads = {}  # tool_id -> path (for ENOENT matching)
        with open(f) as fh:
            for line in fh:
                obj = json.loads(line)
                if obj.get("type") != "message":
                    continue
                msg = obj.get("message", {})
                role = msg.get("role", "")
                content = msg.get("content", "")
                ts = obj.get("timestamp", "")[:19]
                if not isinstance(content, list):
                    continue
                for block in content:
                    if not isinstance(block, dict):
                        continue

                    if block.get("type") == "toolCall":
                        name = block.get("name", "")
                        tc_args = block.get("arguments", {})
                        tid = block.get("id", "")
                        path = tc_args.get("path", "") or tc_args.get("file_path", "")

                        if name == "read" and path:
                            pending_reads[tid] = path
                            events.append({
                                "op": "read", "path": path,
                                "ts": ts, "session": f.stem,
                            })
                        elif name == "write" and path:
                            events.append({
                                "op": "write", "path": path,
                                "ts": ts, "session": f.stem,
                                "content_size": len(tc_args.get("content", "")),
                            })
                            last_write_contents[path] = tc_args.get("content", "")
                        elif name == "edit" and path:
                            events.append({
                                "op": "edit", "path": path,
                                "ts": ts, "session": f.stem,
                            })

                    # toolResult with ENOENT
                    if block.get("type") == "text" and role == "toolResult":
                        text_val = block.get("text", "")
                        if "ENOENT" in text_val or "no such file" in text_val.lower():
                            for tid, path in pending_reads.items():
                                events.append({
                                    "op": "enoent", "path": path,
                                    "ts": ts, "session": f.stem,
                                })
                            pending_reads.clear()
    return events, last_write_contents


def cmd_audit(args):
    oc = args.oc_config
    workspace = Path(oc["workspace"])
    session_dir = oc["session_dir"]
    original_ws = oc.get("original_workspace", str(workspace))

    # Wizard bootstrap timestamp
    wizard_ts = oc["raw"].get("wizard", {}).get("lastRunAt", "")[:19]

    # Scan all tool calls
    all_events, last_write_contents = scan_tool_calls(session_dir)

    # Filter to core files only — match both local workspace and original (JSONL) workspace
    def to_rel(path: str) -> str:
        for prefix in [str(workspace) + "/", original_ws + "/",
                       str(Path.home()) + "/.openclaw/workspace/"]:
            if prefix in path:
                return path.replace(prefix, "")
        return path

    # Build per-file stats
    file_stats = {}
    for name in CORE_INJECTED_FILES:
        file_stats[name] = {"read": 0, "write": 0, "edit": 0, "enoent": 0,
                            "sessions": set(), "last_write_ts": ""}

    # Collect memory diary files dynamically
    diary_files = set()
    for ev in all_events:
        rel = to_rel(ev["path"])
        if rel.startswith("memory/") and rel.endswith(".md"):
            diary_files.add(rel)
    # Also add existing diary files from disk
    mem_dir = workspace / "memory"
    if mem_dir.exists():
        for f in mem_dir.glob("*.md"):
            diary_files.add(f"memory/{f.name}")
    for df in diary_files:
        if df not in file_stats:
            file_stats[df] = {"read": 0, "write": 0, "edit": 0, "enoent": 0,
                              "sessions": set(), "last_write_ts": ""}

    # Tally events + track which sessions have write/edit ops
    sessions_with_write = set()  # sessions that modified any memory file
    for ev in all_events:
        rel = to_rel(ev["path"])
        if rel not in file_stats:
            continue
        fs = file_stats[rel]
        op = ev["op"]
        if op == "read":
            fs["read"] += 1
        elif op == "write":
            fs["write"] += 1
            fs["last_write_ts"] = max(fs["last_write_ts"], ev["ts"])
            sessions_with_write.add(ev["session"][:8])
        elif op == "edit":
            fs["edit"] += 1
            fs["last_write_ts"] = max(fs["last_write_ts"], ev["ts"])
            sessions_with_write.add(ev["session"][:8])
        elif op == "enoent":
            fs["enoent"] += 1
        fs["sessions"].add(ev["session"][:8])

    # Count total sessions
    total_sessions = len(list_session_files(session_dir))

    # Print table
    print("=" * 90)
    print("  MEMORY BEHAVIOR AUDIT — Core Injected Files")
    print("=" * 90)
    print(f"  workspace      = {workspace}")
    print(f"  sessions       = {total_sessions}")
    print(f"  wizard_boot    = {wizard_ts or 'unknown'}")
    print()
    print(f"  {'File':30s} {'read':>5s} {'write':>5s} {'edit':>5s} {'ENOENT':>6s} {'mtime':>18s} {'size':>8s}  Attribution")
    print("-" * 90)

    for name in list(CORE_INJECTED_FILES) + sorted(diary_files):
        fs = file_stats.get(name)
        if not fs:
            continue
        full_path = workspace / name
        if full_path.exists():
            stat = full_path.stat()
            mtime = datetime.fromtimestamp(stat.st_mtime).strftime("%Y-%m-%d %H:%M")
            size = f"{stat.st_size}b"
        else:
            mtime = "NOT FOUND"
            size = "-"

        total_writes = fs["write"] + fs["edit"]

        # Attribution
        if total_writes > 0:
            attr = f"AGENT ({total_writes} writes)"
        elif mtime != "NOT FOUND" and wizard_ts and mtime <= wizard_ts[:16].replace("T", " "):
            attr = "GATEWAY (bootstrap)"
        elif fs["enoent"] > 0 and mtime == "NOT FOUND":
            attr = "NEVER CREATED"
        elif mtime != "NOT FOUND":
            attr = "USER/GATEWAY"
        else:
            attr = "NEVER CREATED"

        print(f"  {name:30s} {fs['read']:5d} {fs['write']:5d} {fs['edit']:5d} {fs['enoent']:6d} {mtime:>18s} {size:>8s}  {attr}")

    print("=" * 90)

    # --- Human edit detection via edit replay + timeline reconstruction ---
    # Build per-file timeline with full content for replay:
    #   read (full only, no offset) → content string
    #   write → content string
    #   edit → old_string, new_string
    # Then replay edits on reconstructed content, compare hash with next read.
    timelines = defaultdict(list)
    # timeline entry: (ts, type, data)
    #   type=read:  data={'content': str}
    #   type=write: data={'content': str}
    #   type=edit:  data={'old': str, 'new': str}
    #   type=read_enoent: data=None

    for f in sorted(list_session_files(session_dir)):
        pending_reads = {}  # toolCallId -> {rel, ts}
        with open(f) as fh:
            for line in fh:
                obj = json.loads(line)
                if obj.get("type") != "message":
                    continue
                msg = obj.get("message", {})
                role = msg.get("role", "")
                content = msg.get("content", "")
                ts = obj.get("timestamp", "")[:19]
                if not isinstance(content, list):
                    continue

                if role == "assistant":
                    for block in content:
                        if not isinstance(block, dict) or block.get("type") != "toolCall":
                            continue
                        name = block.get("name", "")
                        tc_args = block.get("arguments", {})
                        tid = block.get("id", "")
                        path = tc_args.get("path", "") or tc_args.get("file_path", "")
                        if not path:
                            continue
                        rel = to_rel(path)
                        if rel == path:  # to_rel didn't match any workspace prefix
                            continue
                        if rel not in file_stats:
                            continue
                        if name == "read":
                            # Only full reads (no offset/limit) — partial reads break hash comparison
                            has_offset = tc_args.get("offset") is not None or tc_args.get("limit") is not None
                            if not has_offset:
                                pending_reads[tid] = {"rel": rel, "ts": ts}
                        elif name == "write":
                            timelines[rel].append((ts, "write", {"content": tc_args.get("content", "")}))
                        elif name == "edit":
                            old = tc_args.get("old_string", tc_args.get("oldText", ""))
                            new = tc_args.get("new_string", tc_args.get("newText", ""))
                            timelines[rel].append((ts, "edit", {"old": old, "new": new}))

                elif role == "toolResult":
                    tid = msg.get("toolCallId", "")
                    if tid in pending_reads:
                        info = pending_reads.pop(tid)
                        text_val = ""
                        for block in content:
                            if isinstance(block, dict) and block.get("type") == "text":
                                text_val = block.get("text", "")
                                break
                        if "ENOENT" in text_val or "no such file" in text_val.lower():
                            timelines[info["rel"]].append((info["ts"], "read_enoent", None))
                        else:
                            timelines[info["rel"]].append((info["ts"], "read", {"content": text_val}))

    # Detect human edits via edit replay
    print()
    print("  Human Edit Detection (edit replay):")
    print(f"  {'-'*80}")
    human_edits = {}

    for name in list(CORE_INJECTED_FILES) + sorted(diary_files):
        events = sorted(timelines.get(name, []), key=lambda e: e[0])
        if not events:
            full_path = workspace / name
            if full_path.exists():
                file_mtime = datetime.fromtimestamp(full_path.stat().st_mtime)
                has_writes = file_stats.get(name, {}).get("write", 0) + file_stats.get(name, {}).get("edit", 0)
                if has_writes == 0:
                    if wizard_ts and file_mtime.isoformat()[:19] <= wizard_ts:
                        human_edits[name] = {"detected": False, "count": 0, "method": "gateway_bootstrap"}
                    else:
                        human_edits[name] = {"detected": True, "count": 1, "method": "mtime_no_agent_writes"}
                        print(f"  {name:30s} ✎ HUMAN (1x) — file exists but agent never wrote it")
                else:
                    human_edits[name] = {"detected": False, "count": 0}
            continue

        # Replay: maintain reconstructed content, compare with actual reads
        reconstructed = None  # full file content after applying agent ops
        human_count = 0

        for ts, etype, data in events:
            if etype == "read":
                actual = data["content"]
                actual_hash = hashlib.md5(actual.encode()).hexdigest()[:8]
                if reconstructed is not None:
                    recon_hash = hashlib.md5(reconstructed.encode()).hexdigest()[:8]
                    if recon_hash != actual_hash:
                        human_count += 1
                # Always update reconstructed to actual (handles human edits gracefully)
                reconstructed = actual
            elif etype == "read_enoent":
                reconstructed = None
            elif etype == "write":
                reconstructed = data["content"]
            elif etype == "edit":
                if reconstructed is not None and data["old"] in reconstructed:
                    reconstructed = reconstructed.replace(data["old"], data["new"], 1)
                else:
                    # old_string not found → file was modified externally, chain broken
                    reconstructed = None

        # Check current file vs reconstructed (detects human edit after last agent op)
        full_path = workspace / name
        if full_path.exists() and reconstructed is not None:
            current = full_path.read_text()
            current_hash = hashlib.md5(current.encode()).hexdigest()[:8]
            recon_hash = hashlib.md5(reconstructed.encode()).hexdigest()[:8]
            if current_hash != recon_hash:
                human_count += 1
        elif full_path.exists():
            # Reconstructed is None (chain broken) — fall back to mtime
            fs = file_stats.get(name, {})
            last_agent_ts = fs.get("last_write_ts", "")
            if last_agent_ts:
                file_mtime = datetime.fromtimestamp(full_path.stat().st_mtime)
                agent_dt = datetime.fromisoformat(last_agent_ts)
                if (file_mtime - agent_dt).total_seconds() > HUMAN_EDIT_THRESHOLD_SECS:
                    human_count += 1

        if human_count > 0:
            print(f"  {name:30s} ✎ HUMAN ({human_count}x)")
        elif full_path.exists():
            print(f"  {name:30s} ✓ no human edit detected")

        human_edits[name] = {"detected": human_count > 0, "count": human_count}

    # --- Summary insights ---
    print()
    print("  Key Findings:")
    mem = file_stats.get("MEMORY.md", {})
    diary_written = sum(1 for df in diary_files if file_stats[df]["write"] + file_stats[df]["edit"] > 0)
    diary_enoent = sum(1 for df in diary_files if file_stats[df]["enoent"] > 0 and not (workspace / df).exists())
    diary_total = len(diary_files)

    if mem:
        mem_writes = mem.get("write", 0) + mem.get("edit", 0)
        print(f"  - MEMORY.md: {mem_writes} writes, {mem.get('enoent', 0)} ENOENT, {mem.get('read', 0)} reads")
        if mem.get("enoent", 0) > mem_writes:
            print(f"    ⚠ Agent tried to read MEMORY.md more times than it wrote — file often missing")
    print(f"  - Diary files: {diary_written}/{diary_total} written, {diary_enoent} ENOENT-only (tried but never created)")
    agents_md = file_stats.get("AGENTS.md", {})
    if agents_md:
        agents_writes = agents_md.get("write", 0) + agents_md.get("edit", 0)
        if agents_writes > 5:
            print(f"  - AGENTS.md: {agents_writes} self-modifications by agent")
    human_edit_files = sum(1 for h in human_edits.values() if h["detected"])
    if human_edit_files:
        print(f"  - {human_edit_files} file(s) with detected human edits")

    # --- Memory update rate & agent vs human ---
    print()
    total_agent_ops = sum(fs["write"] + fs["edit"] for fs in file_stats.values())
    total_human_ops = sum(h["count"] for h in human_edits.values())
    sessions_with_read = set()
    for fs in file_stats.values():
        sessions_with_read |= fs["sessions"]
    update_rate = len(sessions_with_write) / total_sessions * 100 if total_sessions else 0
    touch_rate = len(sessions_with_read) / total_sessions * 100 if total_sessions else 0

    print(f"  Memory Update Rate:")
    print(f"  {'-'*80}")
    print(f"  sessions that READ  any memory file: {len(sessions_with_read):>4d}/{total_sessions}  ({touch_rate:.1f}%)")
    print(f"  sessions that WROTE any memory file: {len(sessions_with_write):>4d}/{total_sessions}  ({update_rate:.1f}%)")
    print()
    print(f"  Agent vs Human Operations:")
    print(f"  {'-'*80}")
    print(f"  agent write/edit ops (from JSONL):   {total_agent_ops:>4d}")
    print(f"  human edit ops (from replay gaps):   {total_human_ops:>4d}  (lower bound)")
    if total_agent_ops + total_human_ops > 0:
        agent_pct = total_agent_ops / (total_agent_ops + total_human_ops) * 100
        print(f"  agent share:                         {agent_pct:.0f}%")

    # JSON export
    if getattr(args, "json_output", ""):
        export = {
            "workspace": str(workspace),
            "wizard_bootstrap": wizard_ts,
            "total_sessions": total_sessions,
            "sessions_read_memory": len(sessions_with_read),
            "sessions_wrote_memory": len(sessions_with_write),
            "memory_update_rate": round(update_rate, 1),
            "total_agent_ops": total_agent_ops,
            "total_human_ops": total_human_ops,
            "files": {},
        }
        for name, fs in file_stats.items():
            full_path = workspace / name
            he = human_edits.get(name, {})
            export["files"][name] = {
                "read": fs["read"],
                "write": fs["write"],
                "edit": fs["edit"],
                "enoent": fs["enoent"],
                "exists": full_path.exists(),
                "size": full_path.stat().st_size if full_path.exists() else 0,
                "mtime": datetime.fromtimestamp(full_path.stat().st_mtime).isoformat() if full_path.exists() else None,
                "last_agent_write": fs["last_write_ts"] or None,
                "sessions_touched": len(fs["sessions"]),
                "human_edit": he.get("detected", False),
                "human_edit_count": he.get("count", 0),
                "human_edit_method": he.get("method"),
            }
        out_path = args.json_output
        os.makedirs(os.path.dirname(out_path) or ".", exist_ok=True)
        with open(out_path, "w") as f:
            json.dump(export, f, indent=2, ensure_ascii=False)
        print(f"\n  JSON exported to: {out_path}")


# ---------------------------------------------------------------------------
# Config loading: openclaw.json (auto) + memory_consolidation.env (overrides)
# ---------------------------------------------------------------------------

SCRIPT_DIR = Path(__file__).resolve().parent


def _read_env_bool(key: str, default: bool) -> bool:
    """Read a boolean value from memory_consolidation.env."""
    env_path = SCRIPT_DIR / "memory_consolidation.env"
    if not env_path.exists():
        return default
    for line in env_path.read_text().splitlines():
        line = line.strip()
        if line.startswith(f"{key}="):
            val = line.split("=", 1)[1].strip().strip('"').lower()
            return val not in ("false", "0", "no")
    return default


def _read_env_int(key: str, default: int) -> int:
    """Read an integer value from memory_consolidation.env."""
    env_path = SCRIPT_DIR / "memory_consolidation.env"
    if not env_path.exists():
        return default
    for line in env_path.read_text().splitlines():
        line = line.strip()
        if line.startswith(f"{key}="):
            try:
                return int(line.split("=", 1)[1].strip().strip('"'))
            except ValueError:
                return default
    return default


def load_env_config() -> dict:
    """Load memory_consolidation.env as key=value pairs.

    Priority: os.environ > env file (so inline env vars override file settings).
    """
    env_path = SCRIPT_DIR / "memory_consolidation.env"
    env = {}
    try:
        with open(env_path) as f:
            for line in f:
                line = line.strip()
                if not line or line.startswith("#"):
                    continue
                if "=" in line:
                    k, v = line.split("=", 1)
                    env[k.strip()] = v.strip()
    except FileNotFoundError:
        pass
    # os.environ overrides file values
    for key in ["ENABLED", "DAYS", "MAX_SESSIONS", "MIN_PER_CHANNEL", "MAX_PER_SESSION",
                "MAX_CHARS_PER_MESSAGE", "INCLUDE_GROUP", "GROUP_CHAT_MODE",
                "VISUAL_MEMORY", "LLM_API_KEY", "OUTPUT"]:
        if key in os.environ:
            env[key] = os.environ[key]
    return env


def resolve_config(openclaw_home: Path = None) -> dict:
    """Merge openclaw.json (auto-detected) + env file (user overrides).

    Priority: CLI args > env file > openclaw.json auto-detection
    """
    oc = load_openclaw_config(openclaw_home)
    env = load_env_config()

    # Resolve output path:
    #   "auto" or empty → {workspace}/USER.md (from openclaw.json)
    #   relative path   → relative to SCRIPT_DIR
    #   absolute path   → as-is
    output_raw = env.get("OUTPUT", "auto").strip()
    if not output_raw or output_raw.lower() == "auto":
        output_raw = oc["profile_source"]  # {workspace}/USER.md
    elif not os.path.isabs(output_raw):
        output_raw = str(SCRIPT_DIR / output_raw)

    return {
        "enabled": env.get("ENABLED", "true").lower() == "true",
        "oc_config": oc,
        "session_dir": oc["session_dir"],
        "profile_source": oc["profile_source"],
        "days": int(env.get("DAYS", "30")),
        "max_sessions": int(env.get("MAX_SESSIONS", "20")),
        "min_per_channel": int(env.get("MIN_PER_CHANNEL", "3")),
        "max_per_session": int(env.get("MAX_PER_SESSION", "10")),
        "max_chars_per_message": int(env.get("MAX_CHARS_PER_MESSAGE", "500")),
        "group_chat_mode": env.get("GROUP_CHAT_MODE", "trigger_only"),
        "include_group": env.get("INCLUDE_GROUP", "false").lower() == "true",
        "visual_memory": int(env.get("VISUAL_MEMORY", "20")),
        "api_key": env.get("LLM_API_KEY", ""),
        "output": output_raw,
    }


# ---------------------------------------------------------------------------
# CLI
# ---------------------------------------------------------------------------

def build_parser(defaults: dict):
    p = argparse.ArgumentParser(
        prog="session_stats",
        description="OpenClaw session analyzer and STM generator",
    )
    p.add_argument(
        "--session-dir", default=defaults["session_dir"],
        help="Path to session JSONL directory (auto: openclaw.json)",
    )
    p.add_argument("--days", type=int, default=defaults["days"])

    sub = p.add_subparsers(dest="command")

    # stats
    st = sub.add_parser("stats", help="Print session statistics")
    st.add_argument("--daily", action="store_true", help="Show daily activity breakdown")

    # audit
    au = sub.add_parser("audit", help="Audit memory behavior on core injected files")
    au.add_argument("--json", dest="json_output", default="",
                    help="Export results to JSON file (for cross-user aggregation)")

    # stm
    rc = sub.add_parser("stm", help="Generate USER.md with STM")
    rc.add_argument("--output", default=defaults["output"])
    rc.add_argument("--max-per-session", type=int, default=defaults["max_per_session"])
    rc.add_argument("--max-sessions", type=int, default=defaults["max_sessions"])
    rc.add_argument("--min-per-channel", type=int, default=defaults["min_per_channel"])
    rc.add_argument("--max-chars", type=int, default=defaults["max_chars_per_message"],
                    help="Max characters per message (0=unlimited)")
    rc.add_argument("--profile-source", default=defaults["profile_source"])
    rc.add_argument("--include-group", action="store_true",
                    default=defaults["include_group"],
                    help="Include group chat sessions (default: from env or false)")
    rc.add_argument("--visual-memory", type=int, default=defaults["visual_memory"],
                    help="Max memorized_media files listed in VM section")

    # compact
    cp = sub.add_parser("compact", help="STM → LTM compact via LLM → final USER.md")
    cp.add_argument("--output", default=defaults["output"])
    cp.add_argument("--max-per-session", type=int, default=defaults["max_per_session"])
    cp.add_argument("--max-sessions", type=int, default=defaults["max_sessions"])
    cp.add_argument("--min-per-channel", type=int, default=defaults["min_per_channel"])
    cp.add_argument("--max-chars", type=int, default=defaults["max_chars_per_message"],
                    help="Max characters per message (0=unlimited)")
    cp.add_argument("--profile-source", default=defaults["profile_source"])
    cp.add_argument("--include-group", action="store_true",
                    default=defaults["include_group"],
                    help="Include group chat sessions (default: from env or false)")
    cp.add_argument("--api-key", default=defaults.get("api_key", ""),
                    help="LLM API key (or set LLM_API_KEY in env file)")
    cp.add_argument("--visual-memory", type=int, default=defaults["visual_memory"],
                    help="Max memorized_media files listed in VM section")

    # diary
    di = sub.add_parser("diary", help="Generate daily diary entry from today's conversations")
    di.add_argument("--api-key", default=defaults.get("api_key", ""),
                    help="LLM API key (or set LLM_API_KEY in env file)")

    return p


def main():
    # Pre-parse --openclaw-home before full arg parsing (needed for config resolution)
    pre = argparse.ArgumentParser(add_help=False)
    pre.add_argument("--openclaw-home", default=None)
    pre_args, remaining = pre.parse_known_args()

    oc_home = Path(pre_args.openclaw_home) if pre_args.openclaw_home else None
    defaults = resolve_config(oc_home)
    load_heartbeat_signatures(defaults["oc_config"].get("workspace", ""))
    parser = build_parser(defaults)
    parser.add_argument("--openclaw-home", default=None, help="Override ~/.openclaw path")
    args = parser.parse_args(remaining)
    args.oc_config = defaults["oc_config"]
    args.session_dir = getattr(args, "session_dir", defaults["session_dir"])

    if args.command == "stats":
        cmd_stats(args)
    elif args.command == "audit":
        cmd_audit(args)
    elif not defaults["enabled"] and args.command in ("stm", "compact"):
        env_path = str((SCRIPT_DIR / "memory_consolidation.env").resolve())
        template_path = str((SCRIPT_DIR / "memory_consolidation.template.env").resolve())
        disabled_msg = f"Memory consolidation is currently disabled. To enable, set ENABLED=true in `{env_path}`. To reset config to defaults: `cp {template_path} {env_path}`"
        write_user_md(defaults["output"], disabled_msg)
        print(f"Disabled. Wrote hint to {defaults['output']}")
        return
    elif args.command == "stm":
        cmd_stm(args)
    elif args.command == "compact":
        # API key: CLI arg > .env > openclaw.json provider
        llm_check = resolve_llm_config(args.oc_config, args.api_key)
        if not llm_check["api_key"]:
            print("ERROR: no API key found. Set LLM_API_KEY in .env, or configure a provider in openclaw.json")
            return
        cmd_compact(args)
    elif args.command == "diary":
        cmd_diary(args)
    else:
        parser.print_help()


if __name__ == "__main__":
    main()
