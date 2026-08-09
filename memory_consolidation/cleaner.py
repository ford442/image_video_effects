# memory_consolidation/cleaner.py
import json
import re
from pathlib import Path

# Ported from OpenClaw source: loader-Ds3or8QX.js L17340-17373
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
    if re.search(r"User Message From Kimi:", raw_text):
        return "KIMI:DM"
    for ch in ["Feishu", "Slack", "Telegram", "WhatsApp", "Signal",
               "Discord", "iMessage", "Google Chat"]:
        pattern = rf"{ch}\[[^\]]*\]\s*(DM from|message in group)"
        m = re.search(pattern, raw_text)
        if m:
            chat_type = "DM" if "DM" in m.group(1) else "GROUP"
            return f"{ch.upper()}:{chat_type}"
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
    idx = text.find(CURRENT_MSG_MARKER)
    if idx != -1:
        text = text[idx + len(CURRENT_MSG_MARKER):]

    if "[Queued messages while agent was busy]" in text:
        blocks = re.split(r"---\s*\nQueued #\d+\s*\n?", text)
        cleaned_blocks = []
        for block in blocks:
            marker_idx = block.find(CURRENT_MSG_MARKER)
            if marker_idx != -1:
                block = block[marker_idx + len(CURRENT_MSG_MARKER):]
            hist_idx = block.find(HISTORY_CONTEXT_MARKER)
            if hist_idx != -1:
                block = block[:hist_idx]
            cleaned_blocks.append(block)
        text = "\n".join(cleaned_blocks)

    hist_idx = text.find(HISTORY_CONTEXT_MARKER)
    if hist_idx != -1:
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
    text = extract_trigger_message(text)

    text = SYSTEM_EVENT_RE.sub("", text)
    text = re.sub(r"Exec\s+(completed|failed)\s+\([^)]+\).*?(?=\n|$)", "", text)
    text = re.sub(r"Gateway restart.*?(?=\n|$)", "", text)
    text = re.sub(r"FailoverError:.*?(?=\n|$)", "", text)
    text = re.sub(
        r"(Feishu\[[^\]]*\]|Slack|Telegram|WhatsApp|Signal|Discord|iMessage|Google Chat)"
        r"\s*(DM from|message in group|message in)\s+\S+:\s*",
        "", text,
    )

    text = re.sub(
        r"\n?(apple-watch|pds|sensor-logger):.*?(?=\s*\[(?:" + "|".join(ENVELOPE_CHANNELS) + r")\s|\n|$)",
        "", text, flags=re.DOTALL,
    )

    lines = text.split("\n")
    lines = [strip_envelope(l) for l in lines]
    text = "\n".join(lines)

    text = re.sub(r"User Message From \S+:\s*", "", text)

    text = re.sub(
        r'<KIMI_REF\s+type="file"\s+path="([^"]+)"\s+name="[^"]*"\s+(?:id="[^"]*"\s+)?/>',
        r'<AttachmentDisplayed:\1>',
        text,
    )
    text = re.sub(
        r"(?:Conversation info|Sender)\s*\(untrusted metadata\):\s*```json\s*\{[^}]*?\}\s*```\s*"
        r"(?:Read HEARTBEAT\.md if it exists.*?(?=\n\n|\Z)|)",
        "", text, flags=re.DOTALL,
    )
    text = re.sub(
        r"A scheduled reminder has been triggered\..*?Current time:.*?(?=\n|$)",
        "", text, flags=re.DOTALL,
    )
    text = re.sub(
        r"A cron job \"[^\"]*\" just completed.*?(?=\|\|\|\||\n\n|\Z)",
        "", text, flags=re.DOTALL,
    )

    text = strip_message_id_hints(text)

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
    text = re.sub(r"Pre-compaction memory flush\..*?(?=\n\n|\Z)", "", text, flags=re.DOTALL)
    text = re.sub(r"---\s*\nQueued #\d+\s*\n?", "", text)
    text = re.sub(r"To send an image back.*?(?=\n|$)", "", text, flags=re.DOTALL)

    text = re.sub(
        r"\[media attached:\s*(\S+)\s*\([^)]*\)\s*\|[^\]]*\]",
        r"<AttachmentDisplayed:\1>", text,
    )
    text = re.sub(r'\{"image_key":"([^"]+)"\}', r"<ImageDisplayed:\1>", text)
    text = re.sub(r'\{"file_key":"[^"]+","file_name":"([^"]+)"\}', r"<FileDisplayed:\1>", text)

    parts = text.split("\n\n")
    if len(parts) == 2 and parts[0].strip() == parts[1].strip():
        text = parts[0].strip()

    text = re.sub(r"\n{3,}", "\n\n", text)
    return text.strip()


def is_noise(text: str) -> bool:
    """Check if message is pure noise."""
    if not text:
        return True
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
    if len(stripped) == 0:
        return True
    return False
