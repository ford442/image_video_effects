#!/bin/bash
# Show current PR queue status

cd "$(dirname "$0")/.."

echo ""
echo "╔════════════════════════════════════════════════════════════════╗"
echo "║            🎨 SHADER PR QUEUE STATUS                          ║"
echo "╚════════════════════════════════════════════════════════════════╝"
echo ""

# Current active plan
echo "📋 CURRENT (new_shader_plan.md):"
echo "────────────────────────────────────────────────────────────────"
if [ -f "new_shader_plan.md" ]; then
    HEADLINE=$(head -1 new_shader_plan.md | sed 's/# //')
    echo "   🎯 $HEADLINE"
else
    echo "   ⚠️  No new_shader_plan.md found!"
fi
echo ""

# Queue status
echo "📚 SHADER PLAN QUEUE:"
echo "────────────────────────────────────────────────────────────────"

echo "   1. ✅ Bismuth Crystal Citadel  ← COMPLETED"
echo "      Branch: feat/new-bismuth-shader-plan-17925881371107706036"
echo "      Action: WGSL + JSON generated → Pushed → Ready to merge PR"
echo ""

echo "   2. ✅ Fractured Monolith       ← IMPLEMENTED (ready to merge)"
echo "      Branch: feature/gen-fractured-monolith-17810079782175443440"
echo "      Action: Just merge the PR"
echo ""

echo "   3. ✅ Celestial Forge          ← COMPLETED"
echo "      Branch: new-shader-plan-celestial-forge-18393159539870047868"
echo "      Action: WGSL + JSON generated → Pushed → Ready to merge PR"
echo ""

echo "📎 IMAGE SUGGESTION PRs (3 total - review separately):"
echo "────────────────────────────────────────────────────────────────"
echo "   • add-5-image-suggestions-4156068978838803049"
echo "   • add-five-image-suggestions-8060953354017719946"
echo "   • add-new-image-suggestions-16258232148204982866"
echo ""

echo "🗂️  ARCHIVED PLANS:"
echo "────────────────────────────────────────────────────────────────"
ls -1 shader_queue/archive/ 2>/dev/null | sed 's/^/   • /' || echo "   (none)"
echo ""

echo "🚀 NEXT ACTIONS:"
echo "────────────────────────────────────────────────────────────────"
echo "   1. Merge PR: feat/new-bismuth-shader-plan-17925881371107706036"
echo "   2. Merge PR: feature/gen-fractured-monolith-17810079782175443440"
echo "   3. Merge PR: new-shader-plan-celestial-forge-18393159539870047868"
echo ""
echo "   🎉 All 3 shader plan PRs are ready to merge!"
echo ""

echo "💡 QUICK COMMANDS:"
echo "────────────────────────────────────────────────────────────────"
echo "   ./shader_queue/status.sh          # Show this status"
echo "   cat new_shader_plan.md            # View current plan"
echo ""
