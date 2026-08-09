# memory_consolidation/cmd_stm.py
from collections import defaultdict
from datetime import datetime, timedelta

try:
    from .cleaner import load_channel_registry
    from .formatters import (
        _update_stats,
        build_diary_section,
        build_ltm_section_from_file,
        build_user_md_header,
        build_vm_section,
        extract_existing_profile,
        format_stm_partitioned,
        write_user_md,
    )
    from .parser import load_sessions
except ImportError:
    from cleaner import load_channel_registry
    from formatters import (
        _update_stats,
        build_diary_section,
        build_ltm_section_from_file,
        build_user_md_header,
        build_vm_section,
        extract_existing_profile,
        format_stm_partitioned,
        write_user_md,
    )
    from parser import load_sessions


def cmd_stm(args):
    cutoff = datetime.now() - timedelta(days=args.days)
    channel_registry = load_channel_registry(args.session_dir)
    sessions = load_sessions(args.session_dir, cutoff, channel_registry)

    if not args.include_group:
        sessions = [s for s in sessions if "GROUP" not in s.get("channel", "")]

    sessions = [s for s in sessions if not s.get("channel", "").startswith("CRON")]

    user_tz = args.oc_config["user_timezone"]
    oc = args.oc_config

    if not sessions:
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

    by_channel = defaultdict(int)
    for s in sessions:
        by_channel[s["channel"]] += 1
    for ch in sorted(by_channel):
        print(f"  [{ch}] {by_channel[ch]} sessions")
