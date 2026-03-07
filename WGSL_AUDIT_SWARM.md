# WGSL Audit Swarm

A parallel, multi-agent validation system for auditing WGSL (WebGPU Shading Language) shaders in the image_video_effects project.

## Overview

The WGSL Audit Swarm performs comprehensive validation across 586+ shader files using three specialized agent types:

| Agent | Purpose | Check Types |
|-------|---------|-------------|
| **Syntax Validator** | WGSL language compliance | textureStore args, brace balance, decorations, types |
| **UTF-8 Sanitizer** | Encoding integrity | BOM, mojibake, null bytes, line endings |
| **Portability Checker** | Cross-platform compatibility | workgroup limits, format support, barriers |

## Quick Start

```bash
# 1. Setup (run once)
chmod +x scripts/*.sh
bash scripts/setup-swarm.sh

# 2. Run audit on all shaders (parallel)
bash scripts/wgsl-audit-swarm.sh 4

# 3. Run audit on sample (10 random shaders)
bash scripts/wgsl-audit-swarm.sh 4 --sample

# 4. Run audit on specific category
bash scripts/wgsl-audit-swarm.sh 4 --category=glitch

# 5. Apply fixes
python3 scripts/apply-wgsl-fixes.py reports/20250307_033100 --create-branch
```

## Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                    WGSL Audit Swarm                         │
├─────────────────────────────────────────────────────────────┤
│  Phase 1: Discovery                                         │
│  ├── Scan public/shaders/ for .wgsl files                   │
│  ├── Build manifest with metadata                           │
│  └── Chunk into parallel batches                            │
├─────────────────────────────────────────────────────────────┤
│  Phase 2: Parallel Validation (xargs -P)                    │
│  ├── Agent A: Syntax Validator (basic pattern checks)       │
│  ├── Agent B: UTF-8 Sanitizer (encoding inspection)         │
│  └── Agent C: Portability Checker (WebGPU limits)           │
├─────────────────────────────────────────────────────────────┤
│  Phase 3: Aggregation                                       │
│  ├── Generate SUMMARY.md with stats                         │
│  ├── Generate summary.json for programmatic use             │
│  └── Individual .json reports per shader                    │
├─────────────────────────────────────────────────────────────┤
│  Phase 4: Auto-Fix (optional)                               │
│  ├── Apply UTF-8 fixes (mojibake, BOM removal)              │
│  ├── Generate PR description                                │
│  └── Create git branch with fixes                           │
└─────────────────────────────────────────────────────────────┘
```

## File Structure

```
image_video_effects/
├── scripts/
│   ├── setup-swarm.sh           # One-time setup
│   ├── wgsl-audit-swarm.sh      # Main orchestrator
│   └── apply-wgsl-fixes.py      # Auto-fix application
├── agents/
│   ├── wgsl-syntax-validator.prompt      # Agent A prompt
│   ├── wgsl-utf8-sanitizer.prompt        # Agent B prompt
│   └── wgsl-portability-checker.prompt   # Agent C prompt
├── reports/
│   └── YYYYMMDD_HHMMSS/
│       ├── SUMMARY.md           # Human-readable report
│       ├── summary.json         # Machine-readable summary
│       ├── syntax_*.json        # Per-shader syntax reports
│       ├── utf8_*.json          # Per-shader UTF-8 reports
│       └── portability_*.json   # Per-shader portability reports
└── WGSL_AUDIT_SWARM.md          # This file
```

## Command Reference

### Main Audit Script

```bash
./scripts/wgsl-audit-swarm.sh [BATCH_SIZE] [OPTIONS]
```

**Arguments:**
- `BATCH_SIZE` - Number of parallel agents (1-10, default: 4)

**Options:**
- `--sample` - Audit only 10 random shaders (for testing)
- `--category=PATTERN` - Filter shaders by name pattern
- `--use-ai-cli` - Use ai-cli.sh for enhanced validation (if available)

**Examples:**

```bash
# Full audit with 4 parallel agents
bash scripts/wgsl-audit-swarm.sh 4

# Quick test on sample
bash scripts/wgsl-audit-swarm.sh 2 --sample

# Audit only glitch effects
bash scripts/wgsl-audit-swarm.sh 4 --category=glitch

# Audit only shaders with "neon" in name
bash scripts/wgsl-audit-swarm.sh 4 --category=neon
```

### Auto-Fix Script

```bash
python3 scripts/apply-wgsl-fixes.py [REPORT_DIR] [OPTIONS]
```

**Arguments:**
- `REPORT_DIR` - Directory containing audit reports (default: reports/)

**Options:**
- `--dry-run` - Show what would be fixed without making changes
- `--create-branch` - Create a git branch with the fixes
- `--fix-type=TYPE` - Apply only specific fixes (utf8|syntax|all)

**Examples:**

```bash
# Dry run to preview changes
python3 scripts/apply-wgsl-fixes.py reports/20250307_033100 --dry-run

# Apply all fixes
python3 scripts/apply-wgsl-fixes.py reports/20250307_033100

# Apply only UTF-8 fixes
python3 scripts/apply-wgsl-fixes.py reports/20250307_033100 --fix-type=utf8

# Apply fixes and create git branch
python3 scripts/apply-wgsl-fixes.py reports/20250307_033100 --create-branch
```

## Validation Checks

### Syntax Validator

| Check | Description | Severity |
|-------|-------------|----------|
| textureStore args | Verifies correct argument order (texture, coords, value) | Critical |
| Brace balance | Counts opening/closing braces match | Critical |
| Parentheses balance | Counts opening/closing parentheses match | Critical |
| Binding decorations | Ensures @group/@binding on resources | Critical |
| Vector types | Validates vec3<f32> vs vec3f | Warning |
| Uniform alignment | Checks struct member alignment | Warning |

### UTF-8 Sanitizer

| Check | Description | Auto-Fixable |
|-------|-------------|--------------|
| BOM markers | UTF-8 BOM at file start | ✅ Yes |
| Replacement chars | U+FFFD indicating corruption | ✅ Yes |
| Null bytes | \x00 in middle of file | ✅ Yes |
| Mojibake | Smart quotes, garbled text | ✅ Yes |
| Line endings | Mixed CRLF/LF/CR | ✅ Yes |
| Truncation | File ending mid-statement | ❌ Manual |

### Portability Checker

| Check | Description | Limit |
|-------|-------------|-------|
| Workgroup size | Total threads per workgroup | <= 256 baseline |
| Early returns | Return statements in compute | Warning on some drivers |
| Storage formats | Texture storage format usage | Check device support |
| Binding limits | Resources per group | <= 16 bindings |
| Uniform alignment | Struct padding requirements | 16-byte for vec4 |

## Output Format

### Summary Report (SUMMARY.md)

```markdown
# WGSL Audit Report

**Date**: 2025-03-07T03:31:00
**Shaders Audited**: 586

## Summary Statistics

| Check | Status | Count |
|-------|--------|-------|
| Syntax | ✅ Valid | 580 |
| Syntax | ❌ Invalid | 6 |
| UTF-8 | ⚠️ Corrupted | 3 |
| Portability | 🔶 Warnings | 45 |
| Portability | 🚨 Critical | 2 |

## Detailed Results
...
```

### JSON Reports

**summary.json:**
```json
{
  "date": "2025-03-07T03:31:00",
  "repository": "ford442/image_video_effects",
  "total_shaders": 586,
  "syntax": { "valid": 580, "invalid": 6 },
  "utf8": { "clean": 583, "corrupted": 3 },
  "portability": { "pass": 539, "warnings": 45, "critical": 2 }
}
```

**Per-shader reports:**
```json
{
  "file": "public/shaders/example.wgsl",
  "status": "INVALID",
  "errors": [
    {
      "line": 42,
      "message": "textureStore missing semicolon",
      "fix": "textureStore(writeTexture, coords, value);"
    }
  ]
}
```

## Integration with ai-cli.sh

For enhanced validation using AI-powered analysis:

```bash
# Enable AI-enhanced validation (requires ai-cli.sh)
bash scripts/wgsl-audit-swarm.sh 4 --use-ai-cli
```

This will:
1. Run basic pattern-based checks (fast)
2. Submit shaders with issues to ai-cli.sh for deeper analysis (slower)
3. Combine results into comprehensive reports

## CI/CD Integration

Add to your GitHub Actions workflow:

```yaml
name: WGSL Audit
on: [push, pull_request]

jobs:
  audit:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v3
      
      - name: Run WGSL Audit
        run: |
          chmod +x scripts/wgsl-audit-swarm.sh
          bash scripts/wgsl-audit-swarm.sh 4 --sample
      
      - name: Check for Critical Issues
        run: |
          if grep -q "🚨 Critical" reports/*/SUMMARY.md; then
            echo "Critical portability issues found!"
            exit 1
          fi
      
      - name: Upload Reports
        uses: actions/upload-artifact@v3
        with:
          name: wgsl-audit-reports
          path: reports/
```

## Troubleshooting

### xargs: command not found
Install GNU parallel tools: `sudo apt-get install findutils`

### jq: command not found
The script will work without jq but with reduced JSON parsing capabilities. Install: `sudo apt-get install jq`

### Too many open files
Reduce batch size: `bash scripts/wgsl-audit-swarm.sh 2`

### Permission denied
Ensure scripts are executable: `chmod +x scripts/*.sh`

## Performance

| Shaders | Batch Size | Time (2-core) | Time (4-core) |
|---------|------------|---------------|---------------|
| 10 (sample) | 4 | ~5s | ~3s |
| 100 | 4 | ~45s | ~25s |
| 586 (full) | 4 | ~4m | ~2m |
| 586 (full) | 8 | ~3m | ~90s |

*Times are approximate and depend on file sizes and system load.*

## Contributing

To add new validation checks:

1. Edit the appropriate agent prompt in `agents/`
2. Add corresponding bash function in `wgsl-audit-swarm.sh`
3. Update this README with the new check documentation
4. Test with: `bash scripts/wgsl-audit-swarm.sh 2 --sample`

## Related Documentation

- [SHADER_AUDIT.md](./SHADER_AUDIT.md) - Manual shader audit notes
- [AGENTS.md](./AGENTS.md) - Project-level agent guide
- [SHADER_PARAMETER_AUDIT.md](./SHADER_PARAMETER_AUDIT.md) - Parameter validation

## License

Same as the parent project (image_video_effects).
