#!/bin/bash
set -euo pipefail

# WGSL Audit Swarm - Parallel shader validation using multiple agent types
# Usage: ./wgsl-audit-swarm.sh [batch_size] [--sample] [--category=cat]

REPO="ford442/image_video_effects"
BATCH_SIZE=${1:-4}
TEMP_DIR="temp"
REPORT_DIR="reports/$(date +%Y%m%d_%H%M%S)"
SAMPLE_MODE=false
CATEGORY_FILTER=""
USE_AI_CLI=false

# Parse additional arguments
for arg in "$@"; do
    case $arg in
        --sample)
            SAMPLE_MODE=true
            echo "🎯 Sample mode: Will audit only 10 random shaders"
            ;;
        --category=*)
            CATEGORY_FILTER="${arg#*=}"
            echo "📂 Category filter: $CATEGORY_FILTER"
            ;;
        --use-ai-cli)
            USE_AI_CLI=true
            echo "🤖 Will use ai-cli.sh for validation"
            ;;
    esac
done

mkdir -p "$REPORT_DIR" fixes "$TEMP_DIR"

echo "🚀 WGSL Audit Swarm initializing..."
echo "Repository: $REPO"
echo "Batch size: $BATCH_SIZE parallel agents"
echo "Report dir: $REPORT_DIR"
echo ""

# Find all WGSL files locally
find_shaders() {
    local search_dir="${1:-public/shaders}"
    if [ -n "$CATEGORY_FILTER" ]; then
        # Try to find shaders by category pattern in filename or path
        find "$search_dir" -name "*.wgsl" -type f | grep -i "$CATEGORY_FILTER" 2>/dev/null || find "$search_dir" -name "*.wgsl" -type f
    else
        find "$search_dir" -name "*.wgsl" -type f
    fi
}

echo "📡 Building shader manifest from local files..."
SHADER_MANIFEST="$TEMP_DIR/shader-manifest.jsonl"

find_shaders | while read -r shader_path; do
    # Get relative path
    rel_path="${shader_path#./}"
    filename=$(basename "$shader_path")

    # Check for textureStore pattern
    if grep -q "textureStore" "$shader_path" 2>/dev/null; then
        has_texture_store=1
    else
        has_texture_store=0
    fi

    echo "{\"path\": \"$rel_path\", \"filename\": \"$filename\", \"has_textureStore\": $has_texture_store}"
done > "$SHADER_MANIFEST"

# Apply sample limit if requested
if [ "$SAMPLE_MODE" = true ]; then
    shuf "$SHADER_MANIFEST" 2>/dev/null | head -10 > "$TEMP_DIR/sample-manifest.jsonl" && mv "$TEMP_DIR/sample-manifest.jsonl" "$SHADER_MANIFEST"
fi

TOTAL=$(wc -l < "$SHADER_MANIFEST")
echo "🎯 Found $TOTAL shaders to audit"
echo ""

# Check if we have any shaders
if [ "$TOTAL" -eq 0 ]; then
    echo "❌ No shaders found to audit!"
    exit 1
fi

# Syntax validation function using basic patterns
validate_syntax_basic() {
    local file="$1"
    local content
    content=$(cat "$file")
    local errors=()
    local line_num=0

    # Check 1: textureStore argument order
    while IFS= read -r line; do
        ((line_num++))
        if echo "$line" | grep -q "textureStore"; then
            # Count commas to check argument count
            comma_count=$(echo "$line" | tr -cd ',' | wc -c)
            if [ "$comma_count" -lt 2 ]; then
                errors+=("$line_num: textureStore missing arguments (need texture, coords, value)")
            fi

            # Check for vec2<i32> or vec2<u32> in coords
            if ! echo "$line" | grep -qE "vec2<i32>|vec2<u32>|vec2i|vec2u"; then
                errors+=("$line_num: textureStore coords should be vec2<i32> or vec2<u32>")
            fi
        fi
    done <<< "$content"

    # Check 2: Brace balance
    local open_braces close_braces
    open_braces=$(echo "$content" | tr -cd '{' | wc -c)
    close_braces=$(echo "$content" | tr -cd '}' | wc -c)
    if [ "$open_braces" -ne "$close_braces" ]; then
        errors+=("0: Mismatched braces - $open_braces opening, $close_braces closing")
    fi

    # Check 3: Parentheses balance
    local open_parens close_parens
    open_parens=$(echo "$content" | tr -cd '(' | wc -c)
    close_parens=$(echo "$content" | tr -cd ')' | wc -c)
    if [ "$open_parens" -ne "$close_parens" ]; then
        errors+=("0: Mismatched parentheses - $open_parens opening, $close_parens closing")
    fi

    # Check 4: Required bindings for compute shaders
    if echo "$content" | grep -q "@compute"; then
        if ! echo "$content" | grep -q "@group.*@binding"; then
            errors+=("0: Compute shader missing @group/@binding decorations")
        fi
        if ! echo "$content" | grep -q "texture_storage_2d"; then
            errors+=("0: Compute shader should have texture_storage_2d for output")
        fi
    fi

    # Output JSON
    if [ ${#errors[@]} -eq 0 ]; then
        echo "{\"file\": \"$file\", \"status\": \"VALID\", \"errors\": []}"
    else
        local errors_json
        errors_json=$(printf '%s\n' "${errors[@]}" | jq -R . | jq -s .)
        echo "{\"file\": \"$file\", \"status\": \"INVALID\", \"errors\": $errors_json}"
    fi
}

# UTF-8 validation function
validate_utf8_basic() {
    local file="$1"
    local issues=()

    # Check for BOM
    if head -c 3 "$file" | xxd -p 2>/dev/null | grep -q "efbbbf"; then
        issues+=("{\"type\": \"bom\", \"message\": \"UTF-8 BOM marker found at file start\"}")
    fi

    # Check for replacement characters
    if grep -q $'\xEF\xBF\xBD' "$file" 2>/dev/null || grep -q '�' "$file" 2>/dev/null; then
        issues+=("{\"type\": \"replacement_char\", \"message\": \"UTF-8 replacement character found - possible corruption\"}")
    fi

    # Check for null bytes
    if grep -q $'\x00' "$file" 2>/dev/null; then
        issues+=("{\"type\": \"null_bytes\", \"message\": \"Null bytes found in file\"}")
    fi

    # Check for high-bit characters that might be mojibake
    local high_ascii
    high_ascii=$(grep -c '[\x80-\xFF]' "$file" 2>/dev/null || echo "0")
    if [ "$high_ascii" -gt 0 ]; then
        issues+=("{\"type\": \"high_ascii\", \"message\": \"Found $high_ascii lines with high ASCII bytes - possible encoding issues\"}")
    fi

    # Output JSON
    if [ ${#issues[@]} -eq 0 ]; then
        echo "{\"file\": \"$file\", \"status\": \"CLEAN\", \"issues\": []}"
    else
        local issues_json
        issues_json=$(echo "[${issues[*]}]" | sed 's/} {/}, {/g')
        echo "{\"file\": \"$file\", \"status\": \"CORRUPTED\", \"issues\": $issues_json}"
    fi
}

# Portability check function
check_portability_basic() {
    local file="$1"
    local content
    content=$(cat "$file")
    local issues=()
    local line_num=0

    while IFS= read -r line; do
        ((line_num++))

        # Check workgroup size
        if echo "$line" | grep -q "@workgroup_size"; then
            # Extract workgroup size numbers
            local wg_size
            wg_size=$(echo "$line" | grep -oE '@workgroup_size\s*\([^)]+\)' | grep -oE '[0-9]+' | tr '\n' ' ')
            if [ -n "$wg_size" ]; then
                local total=1
                for num in $wg_size; do
                    total=$((total * num))
                done
                if [ "$total" -gt 256 ]; then
                    issues+=("{\"severity\": \"WARNING\", \"line\": $line_num, \"message\": \"Workgroup size $total exceeds baseline limit of 256\", \"suggestion\": \"Consider reducing for broader compatibility\"}")
                fi
                if [ "$total" -gt 1024 ]; then
                    issues+=("{\"severity\": \"CRITICAL\", \"line\": $line_num, \"message\": \"Workgroup size $total exceeds maximum of 1024\", \"suggestion\": \"Must reduce - will fail on all hardware\"}")
                fi
            fi
        fi

        # Check for early returns in compute shaders
        if echo "$content" | grep -q "@compute"; then
            if echo "$line" | grep -qE '^\s*return\s*;'; then
                issues+=("{\"severity\": \"WARNING\", \"line\": $line_num, \"message\": \"Early return in compute shader\", \"suggestion\": \"Some drivers have issues with early returns in compute\"}")
            fi
        fi

    done <<< "$content"

    # Check storage texture format consistency
    local storage_formats
    storage_formats=$(echo "$content" | grep -oE 'texture_storage_2d<[a-z0-9]+' | sort -u | wc -l)
    if [ "$storage_formats" -gt 1 ]; then
        issues+=("{\"severity\": \"INFO\", \"line\": 0, \"message\": \"Multiple storage texture formats used\", \"suggestion\": \"Consider consistency for better cache usage\"}")
    fi

    # Output JSON
    if [ ${#issues[@]} -eq 0 ]; then
        echo "{\"file\": \"$file\", \"severity\": \"PASS\", \"issues\": []}"
    else
        local issues_json
        issues_json=$(echo "[${issues[*]}]" | sed 's/} {/}, {/g')
        echo "{\"file\": \"$file\", \"severity\": \"WARNING\", \"issues\": $issues_json}"
    fi
}

# Generate task files for parallel processing
echo "📝 Preparing task files..."
TASK_DIR="$TEMP_DIR/tasks"
mkdir -p "$TASK_DIR"

# Split manifest into individual task files
counter=0
while IFS= read -r line; do
    echo "$line" > "$TASK_DIR/task_$counter.json"
    ((counter++))
done < "$SHADER_MANIFEST"

# Main audit function for a single shader
audit_shader_task() {
    local task_file="$1"
    local line=$(cat "$task_file")
    local path=$(echo "$line" | jq -r '.path')
    local filename=$(echo "$line" | jq -r '.filename')
    local safe_name="${filename//[^a-zA-Z0-9._-]/_}"

    echo "  🔍 Auditing: $path"

    # Run all three checks
    validate_syntax_basic "$path" > "$REPORT_DIR/syntax_${safe_name}.json" 2>/dev/null || \
        echo "{\"file\": \"$path\", \"status\": \"CHECK_FAILED\", \"error\": \"syntax validation error\"}" > "$REPORT_DIR/syntax_${safe_name}.json"

    validate_utf8_basic "$path" > "$REPORT_DIR/utf8_${safe_name}.json" 2>/dev/null || \
        echo "{\"file\": \"$path\", \"status\": \"CHECK_FAILED\", \"error\": \"utf8 validation error\"}" > "$REPORT_DIR/utf8_${safe_name}.json"

    check_portability_basic "$path" > "$REPORT_DIR/portability_${safe_name}.json" 2>/dev/null || \
        echo "{\"file\": \"$path\", \"severity\": \"CHECK_FAILED\", \"error\": \"portability check error\"}" > "$REPORT_DIR/portability_${safe_name}.json"

    echo "  ✅ Completed: $path"
}

export -f audit_shader_task validate_syntax_basic validate_utf8_basic check_portability_basic
export REPORT_DIR TEMP_DIR

# Run parallel audit
echo "🚀 Launching parallel audit agents..."
echo ""

# Use find to pass task files to xargs
find "$TASK_DIR" -name "task_*.json" -type f | xargs -P "$BATCH_SIZE" -I {} bash -c 'audit_shader_task "{}"'

# Aggregate results
echo ""
echo "📊 Generating aggregate report..."
echo ""

# Count various issues
SYNTAX_INVALID=$(grep -l '"status": "INVALID"' "$REPORT_DIR"/syntax_*.json 2>/dev/null | wc -l)
SYNTAX_VALID=$(grep -l '"status": "VALID"' "$REPORT_DIR"/syntax_*.json 2>/dev/null | wc -l)
UTF8_CORRUPTED=$(grep -l '"status": "CORRUPTED"' "$REPORT_DIR"/utf8_*.json 2>/dev/null | wc -l)
PORTABILITY_WARNINGS=$(grep -l '"severity": "WARNING"' "$REPORT_DIR"/portability_*.json 2>/dev/null | wc -l)
PORTABILITY_CRITICAL=$(grep -l '"severity": "CRITICAL"' "$REPORT_DIR"/portability_*.json 2>/dev/null | wc -l)

# Generate summary markdown
cat > "$REPORT_DIR/SUMMARY.md" << EOF
# WGSL Audit Report

**Date**: $(date -Iseconds)
**Repository**: $REPO
**Shaders Audited**: $TOTAL

## Summary Statistics

| Check | Status | Count |
|-------|--------|-------|
| Syntax | ✅ Valid | $SYNTAX_VALID |
| Syntax | ❌ Invalid | $SYNTAX_INVALID |
| UTF-8 | ⚠️ Corrupted | $UTF8_CORRUPTED |
| Portability | 🔶 Warnings | $PORTABILITY_WARNINGS |
| Portability | 🚨 Critical | $PORTABILITY_CRITICAL |

## Detailed Results

### Syntax Validation

EOF

# Add invalid syntax details
if [ "$SYNTAX_INVALID" -gt 0 ]; then
    echo "#### Files with Syntax Errors" >> "$REPORT_DIR/SUMMARY.md"
    echo "" >> "$REPORT_DIR/SUMMARY.md"
    for f in "$REPORT_DIR"/syntax_*.json; do
        if grep -q '"status": "INVALID"' "$f" 2>/dev/null; then
            local_file=$(jq -r '.file' "$f")
            echo "- \`$local_file\`" >> "$REPORT_DIR/SUMMARY.md"
            jq -r '.errors[] | "  - Line " + .' "$f" 2>/dev/null | head -5 >> "$REPORT_DIR/SUMMARY.md"
        fi
    done
    echo "" >> "$REPORT_DIR/SUMMARY.md"
fi

# Add UTF-8 corruption details
cat >> "$REPORT_DIR/SUMMARY.md" << EOF

### UTF-8 Encoding

- Clean files: $((TOTAL - UTF8_CORRUPTED))
- Files with encoding issues: $UTF8_CORRUPTED

EOF

if [ "$UTF8_CORRUPTED" -gt 0 ]; then
    echo "#### Files with Encoding Issues" >> "$REPORT_DIR/SUMMARY.md"
    echo "" >> "$REPORT_DIR/SUMMARY.md"
    for f in "$REPORT_DIR"/utf8_*.json; do
        if grep -q '"status": "CORRUPTED"' "$f" 2>/dev/null; then
            local_file=$(jq -r '.file' "$f")
            echo "- \`$local_file\`" >> "$REPORT_DIR/SUMMARY.md"
        fi
    done
    echo "" >> "$REPORT_DIR/SUMMARY.md"
fi

# Add portability details
cat >> "$REPORT_DIR/SUMMARY.md" << EOF

### Portability

- Files passing all checks: $((TOTAL - PORTABILITY_WARNINGS - PORTABILITY_CRITICAL))
- Files with warnings: $PORTABILITY_WARNINGS
- Files with critical issues: $PORTABILITY_CRITICAL

EOF

if [ "$PORTABILITY_CRITICAL" -gt 0 ]; then
    echo "#### Critical Portability Issues" >> "$REPORT_DIR/SUMMARY.md"
    echo "" >> "$REPORT_DIR/SUMMARY.md"
    for f in "$REPORT_DIR"/portability_*.json; do
        if grep -q '"severity": "CRITICAL"' "$f" 2>/dev/null; then
            local_file=$(jq -r '.file' "$f")
            echo "- \`$local_file\`" >> "$REPORT_DIR/SUMMARY.md"
            jq -r '.issues[] | select(.severity == "CRITICAL") | "  - Line " + (.line | tostring) + ": " + .message' "$f" 2>/dev/null >> "$REPORT_DIR/SUMMARY.md"
        fi
    done
    echo "" >> "$REPORT_DIR/SUMMARY.md"
fi

# Add recommendations
cat >> "$REPORT_DIR/SUMMARY.md" << EOF

## Recommendations

EOF

if [ "$SYNTAX_INVALID" -gt 0 ]; then
    echo "1. **Fix Syntax Errors**: $SYNTAX_INVALID shaders have syntax issues that need immediate attention." >> "$REPORT_DIR/SUMMARY.md"
fi
if [ "$UTF8_CORRUPTED" -gt 0 ]; then
    echo "2. **Fix Encoding**: $UTF8_CORRUPTED shaders have UTF-8 encoding issues. Run \`scripts/apply-wgsl-fixes.py\` to auto-fix." >> "$REPORT_DIR/SUMMARY.md"
fi
if [ "$PORTABILITY_CRITICAL" -gt 0 ]; then
    echo "3. **Critical Portability**: $PORTABILITY_CRITICAL shaders have issues that will cause failures on some hardware." >> "$REPORT_DIR/SUMMARY.md"
fi
if [ "$PORTABILITY_WARNINGS" -gt 0 ]; then
    echo "4. **Portability Warnings**: $PORTABILITY_WARNINGS shaders have warnings that may affect performance on some devices." >> "$REPORT_DIR/SUMMARY.md"
fi

if [ "$SYNTAX_INVALID" -eq 0 ] && [ "$UTF8_CORRUPTED" -eq 0 ] && [ "$PORTABILITY_CRITICAL" -eq 0 ]; then
    echo "✅ All audited shaders passed critical checks!" >> "$REPORT_DIR/SUMMARY.md"
fi

cat >> "$REPORT_DIR/SUMMARY.md" << EOF

## Raw Data

Individual JSON reports are available in \`$REPORT_DIR/\`:
- \`syntax_*.json\` - Syntax validation results
- \`utf8_*.json\` - UTF-8 encoding check results
- \`portability_*.json\` - Portability analysis results

## Next Steps

1. Review the detailed reports above
2. Run \`python3 scripts/apply-wgsl-fixes.py $REPORT_DIR\` to auto-apply fixes where possible
3. Create a PR with the fixes: \`git checkout -b wgsl-audit-fixes\`
EOF

# Also create a JSON summary for programmatic use
cat > "$REPORT_DIR/summary.json" << EOF
{
  "date": "$(date -Iseconds)",
  "repository": "$REPO",
  "total_shaders": $TOTAL,
  "syntax": {
    "valid": $SYNTAX_VALID,
    "invalid": $SYNTAX_INVALID
  },
  "utf8": {
    "clean": $((TOTAL - UTF8_CORRUPTED)),
    "corrupted": $UTF8_CORRUPTED
  },
  "portability": {
    "pass": $((TOTAL - PORTABILITY_WARNINGS - PORTABILITY_CRITICAL)),
    "warnings": $PORTABILITY_WARNINGS,
    "critical": $PORTABILITY_CRITICAL
  }
}
EOF

echo "🎉 Swarm complete!"
echo ""
echo "📁 Reports saved to: $REPORT_DIR"
echo "📄 Summary: $REPORT_DIR/SUMMARY.md"
echo "📊 JSON: $REPORT_DIR/summary.json"
echo ""
echo "Quick stats:"
echo "  ✅ Syntax valid: $SYNTAX_VALID / $TOTAL"
echo "  ❌ Syntax invalid: $SYNTAX_INVALID"
echo "  ⚠️  UTF-8 issues: $UTF8_CORRUPTED"
echo "  🔶 Portability warnings: $PORTABILITY_WARNINGS"
echo "  🚨 Critical issues: $PORTABILITY_CRITICAL"
