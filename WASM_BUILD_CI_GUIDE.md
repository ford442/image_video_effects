# WASM Renderer: Build & CI Documentation

## The Blessed Build Path

The canonical way to build the Pixelocity WASM renderer is:

```bash
npm run wasm:build
```

This script:
1. Sources the Emscripten SDK environment
2. Compiles the C++ renderer (`wasm_renderer/main.cpp` + `wasm_renderer/renderer.cpp`) with Emscripten + emdawnwebgpu
3. Generates JavaScript glue code (`pixelocity_wasm.js`)
4. Produces the WebAssembly binary (`pixelocity_wasm.wasm`)
5. Copies the artifacts to `public/wasm/` for inclusion in the app bundle

## Requirements

To build the WASM renderer locally, you must have the **Emscripten SDK** installed:

```bash
# See https://emscripten.org/docs/getting_started/downloads.html
# Standard setup:
git clone https://github.com/emscripten-core/emsdk.git
cd emsdk
./emsdk install latest
./emsdk activate latest
source ./emsdk_env.sh

# Then in the image_video_effects repo:
npm run wasm:build
```

## Build Failures: CI vs Local

**CI (hardened):** the dedicated `wasm` job installs emsdk, runs `npm run wasm:build`,
and fails on compilation or validation errors.

**Local caveat:** `wasm_renderer/build.sh` still **`exit 0` when `emcc` is missing**
(with a warning), so `npm run build` on a machine without Emscripten can succeed
while shipping stale committed artifacts. Run `node scripts/validate_wasm_artifacts.js`
after local builds, or install emsdk before `npm run wasm:build`.

1. **No swallowed compile errors**: `package.json` no longer wraps `wasm:build` in
   `2>/dev/null || echo` — if `emcc` is present and compilation fails, the error
   propagates.

2. **CI Validation**: The GitHub Actions CI pipeline includes a dedicated `wasm` job that:
   - Installs the Emscripten SDK
   - Builds the WASM renderer
   - Validates that artifacts are:
     - Present and have reasonable file sizes (50–200 KB for `.wasm`, 10+ KB for `.js`)
     - Not stubs or corrupted (checks for WASM magic number `\0asm`)
     - Contain expected exported functions
   - Fails the build if artifacts are missing, stubs, or out of date with source files

## Artifact Validation

The validation script (`scripts/validate_wasm_artifacts.js`) checks:

```bash
node scripts/validate_wasm_artifacts.js
```

This ensures:
- **File Existence**: All three required files exist in `public/wasm/`
  - `pixelocity_wasm.wasm` (WebAssembly binary)
  - `pixelocity_wasm.js` (Emscripten runtime glue)
  - `wasm_bridge.js` (JavaScript bridge to the C++ renderer)

- **Bridge sync** (#821): `wasm_renderer/wasm_bridge.js` must match
  `src/wasm/wasm_bridge.js` (and `.d.ts`). Skew fails validation with:
  *"Bridge skew detected — run npm run wasm:build or cp wasm_renderer/wasm_bridge.js src/wasm/"*

- **File Sizes**: Reasonable and non-empty
  - `.wasm`: 50–200 KB (should be ~96 KB)
  - `.js` files: 10+ KB minimum

- **Content Integrity**:
  - WASM magic number (`\0asm`) is present and correct
  - Not a stub or placeholder (no `Promise.resolve({})`)
  - Expected exported functions are present

- **Freshness**: Timestamps ensure artifacts are not older than source files

## What Happens During CI

The `wasm` job runs on every push to `main`/`develop` and on pull requests to `main`:

1. **Setup**: Node.js 20 + npm dependencies
2. **Emscripten**: Latest emsdk is downloaded and activated
3. **Build**: `npm run wasm:build` compiles from source
4. **Validation**: Artifacts are checked for integrity and freshness
5. **Status**: If any step fails, the CI build fails (no silent skips)

This ensures:
- WASM artifacts are **never out of sync** with source code
- Build failures are **visible and actionable**
- Commits to `main` always have valid, up-to-date WASM artifacts

## Troubleshooting

### Local build fails: "emcc not found"

Install and activate the Emscripten SDK:
```bash
git clone https://github.com/emscripten-core/emsdk.git ~/emsdk
cd ~/emsdk
./emsdk install latest
./emsdk activate latest
source ./emsdk_env.sh
```

Then try again:
```bash
npm run wasm:build
```

### CI job `wasm` is failing

Check the GitHub Actions logs for the specific error. Common causes:
- **Emscripten setup issue**: The emsdk action failed to install or activate the SDK. Check the setup step.
- **Compilation error**: A C++ change broke the build. Check the compilation output.
- **Validation failure**: Artifacts are missing, corrupted, or stubs. Check the validation output.

### Artifacts are too large / small

If file sizes are outside the expected range (50–200 KB for WASM), the build may be misconfigured:
- Check that optimization flags (`-O2`) are set in `wasm_renderer/build.sh`
- Ensure no debug symbols are included
- Verify emdawnwebgpu is being used correctly

## Current known reliability caveats (June 2026)

The C++ renderer has a **real compute + present pipeline** (`Render()` →
`PresentToSurface()` in `renderer.cpp`). The June 2026 reliability batch
([#799](https://github.com/ford442/image_video_effects/issues/799),
[roadmap comment](https://github.com/ford442/image_video_effects/issues/799#issuecomment-4678258584))
hardened init/format/limits ([#817](https://github.com/ford442/image_video_effects/issues/817)–[#822](https://github.com/ford442/image_video_effects/issues/822) ✅).

**Still open (not #817–#822):**

- `RendererManager` does not forward slot/param changes to WASM
- App never calls `setInputSource` — generative mode unreachable for WASM
- Local `build.sh` exits 0 without `emcc` (see above)
- Live-browser smoke on edge GPUs not yet formally verified

Tracking table:
[`WASM_RENDERER_GAP_ANALYSIS.md`](./WASM_RENDERER_GAP_ANALYSIS.md#c-solidification-tracking-2026-06).

## Summary

- **Build command**: `npm run wasm:build`
- **Validation**: `node scripts/validate_wasm_artifacts.js`
- **CI**: Dedicated `wasm` job with Emscripten setup, validation, and freshness checks
- **Local gap**: missing `emcc` is a warning + exit 0 — use validator or install emsdk
- **Roadmap**: See [`WASM_RENDERER_GAP_ANALYSIS.md`](./WASM_RENDERER_GAP_ANALYSIS.md) and [#799 roadmap comment](https://github.com/ford442/image_video_effects/issues/799#issuecomment-4678258584)
