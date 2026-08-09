# memory_consolidation/config.py
import json
import os
import re
from pathlib import Path

OPENCLAW_HOME = Path.home() / ".openclaw"
SCRIPT_DIR = Path(__file__).resolve().parent

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
    try:
        from .parser import list_session_files
    except ImportError:
        from parser import list_session_files

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
    """Load openclaw.json and resolve derived paths/settings."""
    home = openclaw_home or OPENCLAW_HOME
    config_path = home / "openclaw.json"
    cfg = {}
    try:
        with open(config_path) as f:
            cfg = json.load(f)
    except (FileNotFoundError, json.JSONDecodeError):
        pass

    defaults = cfg.get("agents", {}).get("defaults", {})

    user_tz = defaults.get("userTimezone", "").strip()
    if not user_tz:
        user_tz = _infer_timezone_from_sessions(home) or "UTC"

    session_dir = str(home / "agents" / "main" / "sessions")

    original_workspace = defaults.get("workspace", str(home / "workspace"))
    if openclaw_home:
        workspace = str(home / "workspace")
    else:
        workspace = original_workspace

    return {
        "user_timezone": user_tz,
        "session_dir": session_dir,
        "workspace": workspace,
        "original_workspace": original_workspace,
        "profile_source": str(Path(workspace) / "USER.md"),
        "raw": cfg,
    }


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
    """Load memory_consolidation.env as key=value pairs."""
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
    for key in ["ENABLED", "DAYS", "MAX_SESSIONS", "MIN_PER_CHANNEL", "MAX_PER_SESSION",
                "MAX_CHARS_PER_MESSAGE", "INCLUDE_GROUP", "GROUP_CHAT_MODE",
                "VISUAL_MEMORY", "LLM_API_KEY", "OUTPUT"]:
        if key in os.environ:
            env[key] = os.environ[key]
    return env


def resolve_config(openclaw_home: Path = None) -> dict:
    """Merge openclaw.json (auto-detected) + env file (user overrides)."""
    oc = load_openclaw_config(openclaw_home)
    env = load_env_config()

    output_raw = env.get("OUTPUT", "auto").strip()
    if not output_raw or output_raw.lower() == "auto":
        output_raw = oc["profile_source"]
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
