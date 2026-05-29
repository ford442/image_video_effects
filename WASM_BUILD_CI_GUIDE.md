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

## Build Failures Are No Longer Silent

**As of May 2026**, the build process has been hardened:

1. **No More Silent Skips**: The `package.json` `prebuild` and `build` scripts **no longer** suppress WASM build errors with `2>/dev/null || echo`.
   - If `emcc` is not available, `npm run wasm:build` will **fail the build** with a clear error message.
   - If compilation fails, the error is propagated up, not hidden.

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

## Summary

- **Build command**: `npm run wasm:build`
- **Validation**: `node scripts/validate_wasm_artifacts.js`
- **CI**: Dedicated `wasm` job with Emscripten setup, validation, and freshness checks
- **Failures are now visible**: No silent skips, no swallowed errors
- **Next steps**: See `WASM_RENDERER_GAP_ANALYSIS.md` for the roadmap to full WASM viability
