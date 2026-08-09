# memory_consolidation/formatters.py
import json
import os
import re
from collections import defaultdict
from datetime import datetime
from pathlib import Path

try:
    from .config import SCRIPT_DIR, _read_env_bool
    from .parser import list_session_files
except ImportError:
    from config import SCRIPT_DIR, _read_env_bool
    from parser import list_session_files

REMINDER_OPEN = "<IMPORTANT_REMINDER>"
REMINDER_CLOSE = "</IMPORTANT_REMINDER>"


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
    """Sample sessions ensuring every channel type is represented."""
    by_channel = defaultdict(list)
    for s in sessions:
        by_channel[s["channel"]].append(s)

    selected_ids = set()
    selected = []

    for ch in by_channel:
        ch_sessions = by_channel[ch]
        guaranteed = ch_sessions[-min_per_channel:]
        for s in guaranteed:
            if len(selected) >= max_sessions:
                break
            if s["session_id"] not in selected_ids:
                selected_ids.add(s["session_id"])
                selected.append(s)
        if len(selected) >= max_sessions:
            break

    remaining = max_sessions - len(selected)
    if remaining > 0:
        candidates = [s for s in sessions if s["session_id"] not in selected_ids]
        for s in reversed(candidates):
            selected.append(s)
            selected_ids.add(s["session_id"])
            remaining -= 1
            if remaining <= 0:
                break

    selected.sort(key=lambda s: s["start_time"])
    return selected


def format_stm_partitioned(sessions: list[dict], max_per_session: int, max_sessions: int, min_per_channel: int = 3, user_tz: str = "UTC", max_chars: int = 500) -> str:
    """Format sessions into STM, partitioned by channel."""
    if not sessions:
        return "_No recent conversations._"

    recent = sample_sessions_all_channels(sessions, max_sessions, min_per_channel)

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
                    ch_cut = max_chars // 2
                    text = text[:ch_cut] + "[TL;DR]" + text[-ch_cut:]
                formatted.append(text)
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
                         first_ts, last_ts, oc: dict, now: str) -> str:
    """Shared header block for USER.md (used by both stm and compact)."""
    env_path_abs = str((SCRIPT_DIR / "memory_consolidation.env").resolve())
    template_path_abs = str((SCRIPT_DIR / "memory_consolidation.template.env").resolve())
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


def write_user_md(output_path: str, reminder_block: str) -> int:
    """Append or replace <IMPORTANT_REMINDER> block in USER.md."""
    existing = ""
    try:
        with open(output_path) as f:
            existing = f.read()
    except FileNotFoundError:
        pass

    wrapped = f"{REMINDER_OPEN}\n{reminder_block}\n{REMINDER_CLOSE}\n"

    if REMINDER_OPEN in existing:
        start = existing.index(REMINDER_OPEN)
        end = existing.index(REMINDER_CLOSE) + len(REMINDER_CLOSE) if REMINDER_CLOSE in existing else len(existing)
        while end < len(existing) and existing[end] in ("\n", "\r"):
            end += 1
        output = existing[:start] + wrapped
    else:
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
