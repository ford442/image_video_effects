#!/bin/bash
# ═══════════════════════════════════════════════════════════════════════════════
#  Shader Repair Swarm Launcher
#  Repairs 24 WGSL shaders using Naga validation and subagents
# ═══════════════════════════════════════════════════════════════════════════════

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
SHADERS_DIR="$PROJECT_ROOT/public/shaders"
WORKSPACE="/tmp/shader-repair-swarm-$$"

# List of shaders to repair
SHADERS=(
  "audio_geometric_pulse.wgsl"
  "data-stream-corruption.wgsl"
  "energy-shield.wgsl"
  "fabric-zipper.wgsl"
  "gen-art-deco-sky.wgsl"
  "gen-biomechanical-hive.wgsl"
  "gen-celestial-prism-orchid.wgsl"
  "gen-chromatic-metamorphosis.wgsl"
  "gen-chronos-labyrinth.wgsl"
  "gen-crystal-caverns.wgsl"
  "gen-ethereal-anemone-bloom.wgsl"
  "gen-fractal-clockwork.wgsl"
  "gen-fractured-monolith.wgsl"
  "gen-magnetic-ferrofluid.wgsl"
  "gen-magnetic-field-lines.wgsl"
  "gen-prismatic-bismuth-lattice.wgsl"
  "gen-quantum-mycelium.wgsl"
  "gen-raptor-mini.wgsl"
  "gen-supernova-remnant.wgsl"
  "gen-xeno-botanical-synth-flora.wgsl"
  "gen_grok4_life.wgsl"
  "gen_mandelbulb_3d.wgsl"
  "gen_quantum_foam.wgsl"
  "glitch-pixel-sort.wgsl"
)

echo "═══════════════════════════════════════════════════════════════════════════════"
echo "  🔧 SHADER REPAIR SWARM"
echo "═══════════════════════════════════════════════════════════════════════════════"
echo ""
echo "Target: ${#SHADERS[@]} shaders to repair"
echo "Shaders dir: $SHADERS_DIR"
echo "Workspace: $WORKSPACE"
echo ""

# Check dependencies
if ! command -v node &> /dev/null; then
    echo "❌ Node.js not found"
    exit 1
fi

# Create workspace
mkdir -p "$WORKSPACE"
mkdir -p "$WORKSPACE/backup"
mkdir -p "$WORKSPACE/fixed"
mkdir -p "$WORKSPACE/reports"

# Backup shaders
echo "📦 Backing up shaders..."
for shader in "${SHADERS[@]}"; do
    if [ -f "$SHADERS_DIR/$shader" ]; then
        cp "$SHADERS_DIR/$shader" "$WORKSPACE/backup/"
    else
        echo "⚠️  Warning: $shader not found"
    fi
done

echo "✅ Backup complete"
echo ""

# Create subagent script
cat > "$WORKSPACE/subagent.js" << 'SUBAGENT_EOF'
const fs = require('fs');
const path = require('path');
const { execSync } = require('child_process');

const SHADER_PATH = process.argv[2];
const WORKSPACE = process.argv[3];

if (!SHADER_PATH || !WORKSPACE) {
    console.error('Usage: node subagent.js <shader-path> <workspace>');
    process.exit(1);
}

const shaderName = path.basename(SHADER_PATH);
const reportPath = path.join(WORKSPACE, 'reports', `${shaderName}.json`);

function validateWithNaga(filePath) {
    try {
        execSync(`naga "${filePath}"`, { stdio: 'pipe' });
        return { valid: true, errors: [] };
    } catch (error) {
        const stderr = error.stderr?.toString() || error.message || '';
        const errors = [];
        for (const line of stderr.split('\n').filter(l => l.trim())) {
            const match = line.match(/error:\s*(.+?)(?:\s+at\s+line\s+(\d+))?/i);
            if (match) {
                errors.push({ message: match[1], line: match[2] ? parseInt(match[2]) : null });
            }
        }
        return { valid: false, errors };
    }
}

function attemptFix(content, error) {
    let fixed = content;
    const fixes = [];
    
    // Fix 1: textureSample -> textureSampleLevel in compute shaders
    if (error.includes('stage') && error.includes('forbidden') && content.includes('textureSample(')) {
        const before = fixed;
        fixed = fixed.replace(
            /textureSample\s*\(\s*(\w+)\s*,\s*(\w+)\s*,\s*([^,)]+)\s*\)/g,
            'textureSampleLevel($1, $2, $3, 0.0)'
        );
        if (fixed !== before) fixes.push('textureSample->textureSampleLevel');
    }
    
    // Fix 2: arrayLength comparison type mismatch
    if (error.includes('Sint') && error.includes('Uint')) {
        const before = fixed;
        fixed = fixed.replace(/if\s*\(\s*(\w+)\s*<\s*arrayLength\(/g, 'if (u32($1) < arrayLength(');
        fixed = fixed.replace(/if\s*\(\s*(\w+)\s*<=\s*arrayLength\(/g, 'if (u32($1) <= arrayLength(');
        if (fixed !== before) fixes.push('i32-u32 cast for arrayLength');
    }
    
    // Fix 3: floor() on integer vectors
    if (error.includes('floor') && (error.includes('u32') || error.includes('i32'))) {
        const before = fixed;
        fixed = fixed.replace(/floor\s*\(\s*global_id\.xy\s*\/\s*(\w+)/g, 'floor(vec2<f32>(global_id.xy) / $1');
        if (fixed !== before) fixes.push('floor() integer cast');
    }
    
    // Fix 4: Reserved keywords (let -> const for immutable)
    if (error.includes('let') || error.includes('immutable')) {
        const before = fixed;
        // Replace 'let' with 'const' for bindings that shouldn't change
        fixed = fixed.replace(/@binding\(\d+\)\s*let\s+([a-zA-Z_][a-zA-Z0-9_]*)/g, '@binding($1) const $2');
        if (fixed !== before) fixes.push('let->const for bindings');
    }
    
    return { fixed, fixes };
}

console.log(`[SUBAGENT] Processing: ${shaderName}`);

let content = fs.readFileSync(SHADER_PATH, 'utf8');
const initialValidation = validateWithNaga(SHADER_PATH);

if (initialValidation.valid) {
    console.log(`[SUBAGENT] ✅ ${shaderName} already valid`);
    fs.writeFileSync(reportPath, JSON.stringify({
        shader: shaderName,
        status: 'already_valid',
        fixes: [],
        attempts: 0
    }, null, 2));
    process.exit(0);
}

console.log(`[SUBAGENT] ❌ ${shaderName} has ${initialValidation.errors.length} errors`);

// Attempt fixes
let currentContent = content;
let allFixes = [];
let attempt = 0;
const maxAttempts = 5;

while (attempt < maxAttempts) {
    attempt++;
    const errorMsg = initialValidation.errors.map(e => e.message).join(' ');
    const { fixed, fixes } = attemptFix(currentContent, errorMsg);
    
    if (fixes.length === 0) {
        console.log(`[SUBAGENT] ⚠️ No more fixes available at attempt ${attempt}`);
        break;
    }
    
    allFixes.push(...fixes);
    currentContent = fixed;
    
    // Write temp file and validate
    const tempPath = path.join(WORKSPACE, 'fixed', shaderName);
    fs.writeFileSync(tempPath, currentContent, 'utf8');
    
    const validation = validateWithNaga(tempPath);
    if (validation.valid) {
        console.log(`[SUBAGENT] ✅ Fixed ${shaderName} after ${attempt} attempts`);
        fs.writeFileSync(reportPath, JSON.stringify({
            shader: shaderName,
            status: 'fixed',
            fixes: allFixes,
            attempts: attempt
        }, null, 2));
        process.exit(0);
    }
}

console.log(`[SUBAGENT] ❌ Could not fix ${shaderName} after ${attempt} attempts`);
fs.writeFileSync(reportPath, JSON.stringify({
    shader: shaderName,
    status: 'failed',
    fixes: allFixes,
    attempts: attempt,
    remaining_errors: initialValidation.errors
}, null, 2));
process.exit(1);
SUBAGENT_EOF

# Launch subagents in parallel
echo "🚀 Launching repair subagents..."
echo ""

PIDS=()
for shader in "${SHADERS[@]}"; do
    SHADER_PATH="$SHADERS_DIR/$shader"
    if [ -f "$SHADER_PATH" ]; then
        echo "  → Spawning agent for $shader"
        node "$WORKSPACE/subagent.js" "$SHADER_PATH" "$WORKSPACE" &
        PIDS+=($!)
    fi
done

echo ""
echo "⏳ Waiting for ${#PIDS[@]} subagents to complete..."
echo ""

# Wait for all agents
FAILED=0
for pid in "${PIDS[@]}"; do
    if ! wait $pid; then
        ((FAILED++))
    fi
done

# Collect results
echo ""
echo "═══════════════════════════════════════════════════════════════════════════════"
echo "  📊 REPAIR REPORT"
echo "═══════════════════════════════════════════════════════════════════════════════"
echo ""

FIXED=0
ALREADY_VALID=0
FAILED_COUNT=0

for report in "$WORKSPACE/reports"/*.json; do
    if [ -f "$report" ]; then
        STATUS=$(node -e "console.log(JSON.parse(require('fs').readFileSync('$report', 'utf8')).status)")
        SHADER=$(node -e "console.log(JSON.parse(require('fs').readFileSync('$report', 'utf8')).shader)")
        
        case "$STATUS" in
            "fixed")
                echo "✅ $SHADER - Fixed"
                ((FIXED++))
                ;;
            "already_valid")
                echo "✓  $SHADER - Already valid"
                ((ALREADY_VALID++))
                ;;
            "failed")
                echo "❌ $SHADER - Failed"
                ((FAILED_COUNT++))
                ;;
        esac
    fi
done

echo ""
echo "═══════════════════════════════════════════════════════════════════════════════"
echo "  SUMMARY"
echo "═══════════════════════════════════════════════════════════════════════════════"
echo "  Fixed:        $FIXED"
echo "  Already Valid: $ALREADY_VALID"
echo "  Failed:       $FAILED_COUNT"
echo "═══════════════════════════════════════════════════════════════════════════════"

# Copy fixed shaders back
if [ $FIXED -gt 0 ]; then
    echo ""
    echo "📦 Copying fixed shaders back to project..."
    for shader in "$WORKSPACE/fixed"/*.wgsl; do
        if [ -f "$shader" ]; then
            cp "$shader" "$SHADERS_DIR/"
            echo "  → Updated: $(basename $shader)"
        fi
    done
    echo "✅ Done!"
fi

# Cleanup
rm -rf "$WORKSPACE"

echo ""
echo "🎉 Swarm repair complete!"
echo ""

exit 0
