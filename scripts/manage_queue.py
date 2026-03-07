#!/usr/bin/env python3
"""Queue management for shader plans."""
import json
import sys
import os
from datetime import datetime

QUEUE_FILE = "shader_plans/queue.json"

def load_queue():
    if os.path.exists(QUEUE_FILE):
        try:
            with open(QUEUE_FILE, 'r') as f:
                data = json.load(f)
                # Ensure required keys exist
                if "pending" not in data:
                    data["pending"] = []
                if "completed" not in data:
                    data["completed"] = []
                if "in_progress" not in data:
                    data["in_progress"] = None
                return data
        except:
            pass
    return {"pending": [], "completed": [], "in_progress": None}

def save_queue(queue):
    with open(QUEUE_FILE, 'w') as f:
        json.dump(queue, f, indent=2)

def add(filename, title):
    queue = load_queue()
    queue["pending"].append({
        "filename": filename,
        "title": title,
        "added": datetime.now().isoformat()
    })
    save_queue(queue)
    print(f"✅ Added to queue: {title}")

def complete(filename):
    queue = load_queue()
    for item in queue["pending"]:
        if item["filename"] == filename:
            queue["pending"].remove(item)
            item["completed"] = datetime.now().isoformat()
            queue["completed"].append(item)
            save_queue(queue)
            print(f"✅ Completed: {item['title']}")
            return
    print(f"⚠️ Item not found in pending: {filename}")

def status():
    queue = load_queue()
    print(f"\n📋 Queue Status")
    print(f"   In Progress: {queue.get('in_progress') or 'None'}")
    print(f"   Pending: {len(queue.get('pending', []))}")
    for item in queue.get('pending', []):
        print(f"      - {item['title']}")
    print(f"   Completed: {len(queue.get('completed', []))}")

if __name__ == "__main__":
    if len(sys.argv) < 2:
        print("Usage: manage_queue.py [add|complete|status] [args...]")
        sys.exit(1)
    
    cmd = sys.argv[1]
    if cmd == "add" and len(sys.argv) >= 4:
        add(sys.argv[2], sys.argv[3])
    elif cmd == "complete" and len(sys.argv) >= 3:
        complete(sys.argv[2])
    elif cmd == "status":
        status()
    else:
        print("Usage: manage_queue.py [add|complete|status] [args...]")
