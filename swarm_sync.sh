#!/bin/bash
# swarm_sync.sh - Intermittent git sync during shader swarm
# Usage: ./swarm_sync.sh &  (run in background during swarm)

cd /root/.openclaw/workspace

echo "🐝 Swarm Sync Service started"
echo "   Pulling every 2 minutes, pushing every 5 minutes"

PUSH_COUNTER=0

while true; do
    sleep 120  # 2 minutes
    
    # Pull latest from remote
    echo "[$(date +%H:%M:%S)] 🔄 Pulling from origin..."
    git pull origin main --quiet
    
    PUSH_COUNTER=$((PUSH_COUNTER + 1))
    
    # Push every 5 minutes (every 2.5 pull cycles, round to 3)
    if [ $PUSH_COUNTER -ge 3 ]; then
        # Check if there are changes to push
        if [ -n "$(git status --short)" ]; then
            echo "[$(date +%H:%M:%S)] ⬆️ Pushing changes..."
            git add -A
            git commit -m "Swarm checkpoint: $(date +%H:%M) shader updates" --quiet
            git push origin main --quiet
            echo "[$(date +%H:%M:%S)] ✅ Sync complete"
        else
            echo "[$(date +%H:%M:%S)] ⏭️ No changes to push"
        fi
        PUSH_COUNTER=0
    fi
done
