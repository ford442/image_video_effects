# memory_consolidation/cmd_compact.py
import hashlib
import json
import os
import sys
import time as _time
from datetime import datetime, timedelta
from pathlib import Path

try:
    from .cleaner import load_channel_registry
    from .cmd_stm import cmd_stm
    from .config import SCRIPT_DIR, _read_env_bool, _read_env_int
    from .formatters import (
        _ltm_state_path,
        _update_stats,
        build_diary_section,
        build_user_md_header,
        build_vm_section,
        format_stm_partitioned,
        write_user_md,
    )
    from .llm import call_llm, resolve_llm_config
    from .parser import load_sessions
except ImportError:
    from cleaner import load_channel_registry
    from cmd_stm import cmd_stm
    from config import SCRIPT_DIR, _read_env_bool, _read_env_int
    from formatters import (
        _ltm_state_path,
        _update_stats,
        build_diary_section,
        build_user_md_header,
        build_vm_section,
        format_stm_partitioned,
        write_user_md,
    )
    from llm import call_llm, resolve_llm_config
    from parser import load_sessions


def cmd_compact(args):
    """Generate LTM from STM via LLM, then assemble final USER.md."""
    if not _read_env_bool("LTM_ENABLED", True):
        print("  LTM disabled via LTM_ENABLED=false")
        cmd_stm(args)
        return

    workspace = Path(args.oc_config["workspace"])

    cutoff = datetime.now() - timedelta(days=args.days)
    channel_registry = load_channel_registry(args.session_dir)
    sessions = load_sessions(args.session_dir, cutoff, channel_registry)

    if not args.include_group:
        sessions = [s for s in sessions if "GROUP" not in s.get("channel", "")]

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

    identity_path = workspace / "IDENTITY.md"
    soul_path = workspace / "SOUL.md"
    identity_md = identity_path.read_text() if identity_path.exists() else ""
    soul_md = soul_path.read_text() if soul_path.exists() else ""

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

    stm_hash = hashlib.md5(stm.encode()).hexdigest()
    if prev_stm_hash and stm_hash == prev_stm_hash:
        _update_stats("compact", last_skip="stm_hash_unchanged", last_invoke=invoke_time)
        print("  STM unchanged since last compact, skipping LLM call.")
        return

    this_update_time = datetime.now().isoformat()

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
                  last_messages=total_msgs, last_latency_s=latency, last_model=llm_config.get("model", ""))

    ltm_state = {"invoke_time": invoke_time, "ltm": ltm, "generated_at": datetime.now().isoformat(), "stm_hash": stm_hash}
    os.makedirs(os.path.dirname(str(ltm_path)) or ".", exist_ok=True)
    with open(ltm_path, "w") as f:
        json.dump(ltm_state, f, indent=2, ensure_ascii=False)

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
