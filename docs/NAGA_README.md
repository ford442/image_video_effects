# Naga WGSL Validator Integration

This directory contains scripts for validating WGSL shaders using [naga](https://github.com/gfx-rs/wgpu/tree/trunk/naga) - the official Rust shader compiler used by wgpu.

## Installation

```bash
# Install Rust if you don't have it
curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh

# Install naga CLI
cargo install naga-cli
```

## Scripts

### validate-naga.js

Validates all WGSL shaders using naga (proper parsing, not just regex).

```bash
# Validate all shaders
node scripts/validate-naga.js

# Validate specific directory
node scripts/validate-naga.js ./public/shaders/custom

# Generate JSON report
node scripts/validate-naga.js --json
```

### fix-naga.js

Attempts to automatically fix common WGSL errors detected by naga.

```bash
# Dry run (see what would be fixed)
node scripts/fix-naga.js --dry-run

# Apply fixes
node scripts/fix-naga.js

# Show all errors even if no auto-fix available
node scripts/fix-naga.js --fix-all
```

**Fixed issues:**
- `textureSample` -> `textureSampleLevel` in compute shaders
- Signed/unsigned int comparison with `arrayLength()`
- `floor()` on integer vectors (adds cast to f32)

### fix-compute-shaders.js

Specifically fixes compute shader compatibility issues.

```bash
# Dry run
node scripts/fix-compute-shaders.js --dry-run

# Apply fixes
node scripts/fix-compute-shaders.js
```

## Why Naga?

The existing `validate_shaders_v2.js` uses regex/pattern matching which can miss:
- Type mismatches (e.g., comparing i32 with u32)
- Invalid operations for shader stages
- Actual WGSL syntax errors

Naga is the reference parser/validator used by wgpu, Chrome, and Firefox.

## Integration with npm

Add to package.json:

```json
{
  "scripts": {
    "validate:naga": "node scripts/validate-naga.js",
    "fix:naga": "node scripts/fix-naga.js"
  }
}
```

## CI Integration

```yaml
- name: Validate WGSL
  run: |
    cargo install naga-cli
    node scripts/validate-naga.js
```

## Current Status

Run validation to see current shader health:

```bash
node scripts/validate-naga.js
```

Typical output:
```
📊 Summary:
   Total shaders: 691
   ✅ Valid: 600
   ❌ Invalid: 91
```

## Collaboration Workflow

When collaborating across workspaces:

1. Run validation before committing:
   ```bash
   node scripts/validate-naga.js
   ```

2. Try auto-fixing common issues:
   ```bash
   node scripts/fix-naga.js
   ```

3. Review remaining errors manually

4. Commit with validation report:
   ```bash
   git add naga-validation-report.json
   git commit -m "Update shaders + validation report"
   ```
