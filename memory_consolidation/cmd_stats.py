# memory_consolidation/cmd_stats.py
from collections import defaultdict
from datetime import datetime, timedelta

try:
    from .cleaner import load_channel_registry
    from .parser import load_sessions
except ImportError:
    from cleaner import load_channel_registry
    from parser import load_sessions


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

    by_channel = defaultdict(list)
    for s in sessions:
        by_channel[s["channel"]].append(s)

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
    print("  Channel Breakdown:")
    print(f"  {'-'*50}")

    for ch in sorted(by_channel.keys()):
        ch_sessions = by_channel[ch]
        ch_msgs = sum(len(s["user_messages"]) for s in ch_sessions)
        first = ch_sessions[0]["start_time"].strftime("%m-%d")
        last = ch_sessions[-1]["start_time"].strftime("%m-%d")
        print(f"  [{ch:20s}]  {len(ch_sessions):3d} sessions  {ch_msgs:4d} msgs  ({first} ~ {last})")

    print(f"{'='*60}")

    by_date = defaultdict(int)
    for s in sessions:
        by_date[s["date"]] += 1
    dates = sorted(by_date.keys())
    active_days = len(dates)
    total_days = (last_ts - first_ts).days + 1
    print(f"\n  Active {active_days}/{total_days} days")

    if args.daily:
        print("\n  Daily Activity:")
        for d in dates:
            bar = "█" * by_date[d]
            print(f"    {d}  {by_date[d]:3d}  {bar}")
