# memory_consolidation/cmd_audit.py
import hashlib
import json
import os
from collections import defaultdict
from datetime import datetime
from pathlib import Path

try:
    from .parser import list_session_files
except ImportError:
    from parser import list_session_files

CORE_INJECTED_FILES = [
    "SOUL.md",
    "AGENTS.md",
    "USER.md",
    "IDENTITY.md",
    "MEMORY.md",
]

HUMAN_EDIT_THRESHOLD_SECS = 5


def scan_tool_calls(session_dir: str) -> tuple[list[dict], dict]:
    """Scan ALL session JSONLs for tool calls targeting workspace files."""
    events = []
    last_write_contents = {}

    for f in sorted(list_session_files(session_dir)):
        pending_reads = {}
        with open(f) as fh:
            for line in fh:
                obj = json.loads(line)
                if obj.get("type") != "message":
                    continue
                msg = obj.get("message", {})
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

                    if block.get("type") == "text" and msg.get("role") == "toolResult":
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

    wizard_ts = oc["raw"].get("wizard", {}).get("lastRunAt", "")[:19]

    all_events, last_write_contents = scan_tool_calls(session_dir)

    def to_rel(path: str) -> str:
        for prefix in [str(workspace) + "/", original_ws + "/",
                       str(Path.home()) + "/.openclaw/workspace/"]:
            if prefix in path:
                return path.replace(prefix, "")
        return path

    file_stats = {}
    for name in CORE_INJECTED_FILES:
        file_stats[name] = {"read": 0, "write": 0, "edit": 0, "enoent": 0,
                            "sessions": set(), "last_write_ts": ""}

    diary_files = set()
    for ev in all_events:
        rel = to_rel(ev["path"])
        if rel.startswith("memory/") and rel.endswith(".md"):
            diary_files.add(rel)
    mem_dir = workspace / "memory"
    if mem_dir.exists():
        for f in mem_dir.glob("*.md"):
            diary_files.add(f"memory/{f.name}")
    for df in diary_files:
        if df not in file_stats:
            file_stats[df] = {"read": 0, "write": 0, "edit": 0, "enoent": 0,
                              "sessions": set(), "last_write_ts": ""}

    sessions_with_write = set()
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

    total_sessions = len(list_session_files(session_dir))

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

    timelines = defaultdict(list)

    for f in sorted(list_session_files(session_dir)):
        pending_reads = {}
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
                        if rel == path:
                            continue
                        if rel not in file_stats:
                            continue
                        if name == "read":
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

        reconstructed = None
        human_count = 0

        for ts, etype, data in events:
            if etype == "read":
                actual = data["content"]
                actual_hash = hashlib.md5(actual.encode()).hexdigest()[:8]
                if reconstructed is not None:
                    recon_hash = hashlib.md5(reconstructed.encode()).hexdigest()[:8]
                    if recon_hash != actual_hash:
                        human_count += 1
                reconstructed = actual
            elif etype == "read_enoent":
                reconstructed = None
            elif etype == "write":
                reconstructed = data["content"]
            elif etype == "edit":
                if reconstructed is not None and data["old"] in reconstructed:
                    reconstructed = reconstructed.replace(data["old"], data["new"], 1)
                else:
                    reconstructed = None

        full_path = workspace / name
        if full_path.exists() and reconstructed is not None:
            current = full_path.read_text()
            current_hash = hashlib.md5(current.encode()).hexdigest()[:8]
            recon_hash = hashlib.md5(reconstructed.encode()).hexdigest()[:8]
            if current_hash != recon_hash:
                human_count += 1
        elif full_path.exists():
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
            print("    ⚠ Agent tried to read MEMORY.md more times than it wrote — file often missing")
    print(f"  - Diary files: {diary_written}/{diary_total} written, {diary_enoent} ENOENT-only (tried but never created)")
    agents_md = file_stats.get("AGENTS.md", {})
    if agents_md:
        agents_writes = agents_md.get("write", 0) + agents_md.get("edit", 0)
        if agents_writes > 5:
            print(f"  - AGENTS.md: {agents_writes} self-modifications by agent")
    human_edit_files = sum(1 for h in human_edits.values() if h["detected"])
    if human_edit_files:
        print(f"  - {human_edit_files} file(s) with detected human edits")

    print()
    total_agent_ops = sum(fs["write"] + fs["edit"] for fs in file_stats.values())
    total_human_ops = sum(h["count"] for h in human_edits.values())
    sessions_with_read = set()
    for fs in file_stats.values():
        sessions_with_read |= fs["sessions"]
    update_rate = len(sessions_with_write) / total_sessions * 100 if total_sessions else 0
    touch_rate = len(sessions_with_read) / total_sessions * 100 if total_sessions else 0

    print("  Memory Update Rate:")
    print(f"  {'-'*80}")
    print(f"  sessions that READ  any memory file: {len(sessions_with_read):>4d}/{total_sessions}  ({touch_rate:.1f}%)")
    print(f"  sessions that WROTE any memory file: {len(sessions_with_write):>4d}/{total_sessions}  ({update_rate:.1f}%)")
    print()
    print("  Agent vs Human Operations:")
    print(f"  {'-'*80}")
    print(f"  agent write/edit ops (from JSONL):   {total_agent_ops:>4d}")
    print(f"  human edit ops (from replay gaps):   {total_human_ops:>4d}  (lower bound)")
    if total_agent_ops + total_human_ops > 0:
        agent_pct = total_agent_ops / (total_agent_ops + total_human_ops) * 100
        print(f"  agent share:                         {agent_pct:.0f}%")

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
