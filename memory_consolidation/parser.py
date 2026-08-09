# memory_consolidation/parser.py
import json
from datetime import datetime
from pathlib import Path

try:
    from .cleaner import (
        clean_message,
        detect_channel_label_from_text,
        extract_raw_text,
        is_noise,
        resolve_channel_label,
    )
except ImportError:
    from cleaner import (
        clean_message,
        detect_channel_label_from_text,
        extract_raw_text,
        is_noise,
        resolve_channel_label,
    )


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
    messages = []
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
                text = raw_text.strip()
                if not text:
                    continue
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
    """List all JSONL session files, including archived (.jsonl.reset.*) ones."""
    d = Path(session_dir)
    if not d.exists():
        return []
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
