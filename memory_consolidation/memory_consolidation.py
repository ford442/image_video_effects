"""OpenClaw session analyzer, STM generator, and LTM compact.

Subcommands:
    stats    Print session statistics (counts, time range, channel breakdown)
    stm      Generate USER.md with Short-Term Memory (recent conversations)
    audit    Audit memory behavior on core injected files
    compact  STM → LTM compact via LLM API → write final USER.md
    diary    Generate daily diary entry from today's conversations

Usage:
    python memory_consolidation.py stats [--session-dir DIR] [--days N]
    python memory_consolidation.py stm   [--session-dir DIR] [--days N] [--output PATH] [--max-per-session N]
"""

import argparse
import sys
from pathlib import Path

_SCRIPT_DIR = Path(__file__).resolve().parent
if str(_SCRIPT_DIR) not in sys.path:
    sys.path.insert(0, str(_SCRIPT_DIR))

try:
    from .cleaner import (
        CURRENT_MSG_MARKER,
        ENVELOPE_CHANNELS,
        ENVELOPE_PREFIX,
        HISTORY_CONTEXT_MARKER,
        MESSAGE_ID_LINE,
        SYSTEM_EVENT_RE,
        clean_message,
        detect_channel_label_from_text,
        extract_raw_text,
        extract_trigger_message,
        is_noise,
        load_channel_registry,
        load_heartbeat_signatures,
        looks_like_envelope_header,
        resolve_channel_label,
        strip_envelope,
        strip_message_id_hints,
    )
    from .cmd_audit import CORE_INJECTED_FILES, HUMAN_EDIT_THRESHOLD_SECS, cmd_audit, scan_tool_calls
    from .cmd_compact import cmd_compact
    from .cmd_diary import cmd_diary
    from .cmd_stats import cmd_stats
    from .cmd_stm import cmd_stm
    from .config import (
        OPENCLAW_HOME,
        SCRIPT_DIR,
        _GMT_OFFSET_TO_IANA,
        _infer_timezone_from_sessions,
        _read_env_bool,
        _read_env_int,
        load_env_config,
        load_openclaw_config,
        resolve_config,
    )
    from .formatters import (
        REMINDER_CLOSE,
        REMINDER_OPEN,
        _build_tree,
        _ltm_state_path,
        _state_dir,
        _update_stats,
        build_diary_section,
        build_ltm_section_from_file,
        build_user_md_header,
        build_vm_section,
        extract_existing_profile,
        format_stm_partitioned,
        get_day_number,
        sample_sessions_all_channels,
        write_user_md,
    )
    from .llm import (
        KIMI_API_BASE,
        KIMI_CREDENTIALS_PATH,
        KIMI_OAUTH_CLIENT_ID,
        KIMI_OAUTH_HEADERS,
        KIMI_OAUTH_HOST,
        _call_llm_once,
        _load_oauth_token,
        _resolve_from_kimi_oauth,
        call_llm,
        resolve_llm_config,
    )
    from .parser import (
        list_session_files,
        load_sessions,
        parse_session,
        parse_session_full,
        parse_ts,
    )
except ImportError:
    from cleaner import (
        CURRENT_MSG_MARKER,
        ENVELOPE_CHANNELS,
        ENVELOPE_PREFIX,
        HISTORY_CONTEXT_MARKER,
        MESSAGE_ID_LINE,
        SYSTEM_EVENT_RE,
        clean_message,
        detect_channel_label_from_text,
        extract_raw_text,
        extract_trigger_message,
        is_noise,
        load_channel_registry,
        load_heartbeat_signatures,
        looks_like_envelope_header,
        resolve_channel_label,
        strip_envelope,
        strip_message_id_hints,
    )
    from cmd_audit import CORE_INJECTED_FILES, HUMAN_EDIT_THRESHOLD_SECS, cmd_audit, scan_tool_calls
    from cmd_compact import cmd_compact
    from cmd_diary import cmd_diary
    from cmd_stats import cmd_stats
    from cmd_stm import cmd_stm
    from config import (
        OPENCLAW_HOME,
        SCRIPT_DIR,
        _GMT_OFFSET_TO_IANA,
        _infer_timezone_from_sessions,
        _read_env_bool,
        _read_env_int,
        load_env_config,
        load_openclaw_config,
        resolve_config,
    )
    from formatters import (
        REMINDER_CLOSE,
        REMINDER_OPEN,
        _build_tree,
        _ltm_state_path,
        _state_dir,
        _update_stats,
        build_diary_section,
        build_ltm_section_from_file,
        build_user_md_header,
        build_vm_section,
        extract_existing_profile,
        format_stm_partitioned,
        get_day_number,
        sample_sessions_all_channels,
        write_user_md,
    )
    from llm import (
        KIMI_API_BASE,
        KIMI_CREDENTIALS_PATH,
        KIMI_OAUTH_CLIENT_ID,
        KIMI_OAUTH_HEADERS,
        KIMI_OAUTH_HOST,
        _call_llm_once,
        _load_oauth_token,
        _resolve_from_kimi_oauth,
        call_llm,
        resolve_llm_config,
    )
    from parser import (
        list_session_files,
        load_sessions,
        parse_session,
        parse_session_full,
        parse_ts,
    )


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
