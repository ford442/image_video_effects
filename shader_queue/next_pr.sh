#!/bin/bash
# Advance to the next PR in the queue
# Usage: ./shader_queue/next_pr.sh

cd "$(dirname "$0")/.."

ARCHIVE_DIR="shader_queue/archive"
mkdir -p "$ARCHIVE_DIR"

echo ""
echo "🚀 Advancing to next PR in queue..."
echo ""

# Archive current plan
if [ -f "new_shader_plan.md" ]; then
    CURRENT=$(head -1 new_shader_plan.md | sed 's/# //' | tr ' ' '_' | tr '/' '_')
    TIMESTAMP=$(date +%Y%m%d_%H%M%S)
    ARCHIVE_NAME="${ARCHIVE_DIR}/done_${CURRENT}_${TIMESTAMP}.md"
    cp "new_shader_plan.md" "$ARCHIVE_NAME"
    echo "✅ Archived: $ARCHIVE_NAME"
fi

# Show what's next
echo ""
echo "📋 NEXT UP: Fractured Monolith"
echo "   This PR already has the shader implemented!"
echo ""
echo "   Commands to process it:"
echo "   ───────────────────────────────────────"
echo "   git checkout feature/gen-fractured-monolith-17810079782175443440"
echo "   git pull origin main  # If needed"
echo "   # Verify shader files exist:"
echo "   ls -la src/shaders/gen-fractured-monolith.*"
echo "   # Push and create/merge PR"
echo "   git push origin HEAD"
echo ""
echo "   After merging, run this script again for Celestial Forge."
echo ""
