#!/bin/bash
# Process Next PR in Queue
# Usage: ./shader_queue/process_next_pr.sh

set -e

cd "$(dirname "$0")/.."

QUEUE_FILE="shader_queue/pr_queue.json"
ARCHIVE_DIR="shader_queue/archive"

mkdir -p "$ARCHIVE_DIR"

echo "=== Shader PR Queue Manager ==="
echo ""

# Show current queue status
echo "📋 Current Queue Status:"
echo "------------------------"

# Find next pending shader plan
NEXT_PR=$(grep -A5 '"status": "pending"' "$QUEUE_FILE" | grep -E '"name"|"branch"' | head -4)

if [ -z "$NEXT_PR" ]; then
    echo "✅ No pending shader PRs in queue!"
    exit 0
fi

echo "Next up: $NEXT_PR"
echo ""

# Check if there's a current new_shader_plan.md that needs archiving
if [ -f "new_shader_plan.md" ]; then
    # Extract shader name from the plan
    SHADER_NAME=$(head -1 new_shader_plan.md | sed 's/# //' | tr ' ' '_' | tr '/' '_')
    TIMESTAMP=$(date +%Y%m%d_%H%M%S)
    ARCHIVE_NAME="${ARCHIVE_DIR}/${SHADER_NAME}_${TIMESTAMP}.md"
    
    echo "💾 Archiving current new_shader_plan.md..."
    echo "   → $ARCHIVE_NAME"
    cp "new_shader_plan.md" "$ARCHIVE_NAME"
    echo ""
fi

# Show next steps
echo "🎯 Next Steps:"
echo "--------------"
echo "1. Checkout the next PR branch:"
echo "   git checkout feat/new-bismuth-shader-plan-17925881371107706036"
echo ""
echo "2. Copy the plan to new_shader_plan.md:"
echo "   git show HEAD:new_shader_plan.md > new_shader_plan.md"
echo ""
echo "3. Generate the shader (run your generation command)"
echo ""
echo "4. Commit and push:"
echo "   git add ."
echo "   git commit -m 'Add <shader-name> generative shader'"
echo "   git push origin HEAD"
echo ""
echo "5. Return to main and update queue:"
echo "   git checkout main"
echo "   # Mark as done in pr_queue.json"
echo ""
