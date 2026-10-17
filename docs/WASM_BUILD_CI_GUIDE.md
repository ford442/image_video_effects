# WASM Renderer: Build & CI Documentation

## The Blessed Build Path

### Full production build (`npm run build`)

CRA copies `public/` into the output **during** `craco build`, so WASM artifacts must exist **before** that step. The `prebuild` hook runs this sequence **once**:

```
build.sh --if-requested → generate_shader_lists → build:manifest → craco build
```

The backend is frozen R&D (#1080), so `prebuild` uses the **committed** `public/wasm/`
artifacts by default (#1400). `build.sh --if-requested` regenerates the contract files
and the bridge copies (no emcc needed) and compiles only when `WASM_BUILD=1`:

```bash
npm run build                  # any machine, no emsdk, no env var: committed public/wasm/
WASM_BUILD=1 npm run build     # compile first (pinned emsdk required)
```

`SKIP_WASM_BUILD=1` is still honoured by `npm run wasm:build` (bridge sync only).

### Generated contract files (`npm run wasm:contracts`)

`scripts/emit-wasm-contracts.mjs` writes, from `src/contracts/*.json`:

| File | From | Used by |
|------|------|---------|
| `src/wasm/bridge/_generated.ts` | `wasm_exports.json` `exports` (returns, args, async, whileSuspended) | every bridge call into the module (no hand-written `ccall`) |
| `src/wasm/bridge/_contracts.ts` | `binding_table.json`, `workgroup_dispatch.json` | `wgslAnalysis.ts` (shared by both backends) |
| `wasm_renderer/generated/contracts.h` | `webgpu_limits.json`, `webgpu_optional_features.json`, `binding_table.json`, `slot_limits.json`, `uniforms_layout.json`, `workgroup_dispatch.json` | `device.cpp` limits/features, `pipeline.cpp` binding table, `renderer.h` slots/uniforms |

`build.sh` runs it first; `verify:wasm-bridge-sync` and `verify:device-policy` fail when a
committed copy is stale. The generator refuses limit floors below what the binding table
needs (that is how `maxSampledTexturesPerShaderStage` 3 → 4 was caught).

### Async exports

Exports marked `async` in `wasm_exports.json` can reach `wgpuInstanceWaitAny`, which
suspends under ASYNCIFY. The generated wrappers ccall them with `{ async: true }` and
return a Promise; `src/wasm/bridge/call.ts` runs them one at a time per module and applies
each sync export's `whileSuspended` policy (`call` / `queue` / `skip`) meanwhile. The release
build links with `-sASYNCIFY_ADVISE` (byte-identical output) and
`scripts/check-asyncify-exports.mjs` fails the build if the exports that can suspend are not
exactly the `async` ones.

### Debug profile (`npm run wasm:build:debug`)

`wasm_compile_flags.json` `profiles.debug`: the release flags plus `-sASSERTIONS=2 -g
-gsource-map --profiling-funcs`, written to `public/wasm/pixelocity_wasm.debug.{js,wasm,wasm.map}`
(gitignored). Load it with `?renderer=wasm&wasm_debug=1`. A suspending export called
without `{ async: true }`, or a `typeof` probe of an unexported runtime method, throws
there instead of misbehaving silently. `npm run test:wasm:debug` runs the WASM smoke spec
on SwiftShader against it and fails on any Emscripten assertion.

### WASM-only compile (`npm run wasm:build`)

The canonical way to rebuild the C++ WASM renderer alone is:

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
./emsdk install 6.0.9    # pinned — see src/contracts/wasm_compile_flags.json
./emsdk activate 6.0.9
source ./emsdk_env.sh

# Then in the image_video_effects repo:
npm run wasm:build
```

## Toolchain pin (2026-09)

The Emscripten version is **pinned**, not `latest` — a moving emsdk silently changes the
ABI of `public/wasm/pixelocity_wasm.{js,wasm}`.

- **Pin:** `emsdkVersion` in [`src/contracts/wasm_compile_flags.json`](../src/contracts/wasm_compile_flags.json) (currently **6.0.9**). The same file holds `std`, `opt`, `usePort`, `sFlags`, `jsOutputName` — `build.sh` (the only build) reads it via `scripts/format-wasm-compile-flags.js`.
- **CI:** `setup-emsdk` `version:` must equal the pin; `npm run verify:wasm-invariants` fails on drift or on `-s` flags hardcoded in `build.sh`/CMake.
- **Local gate:** `build.sh` runs `scripts/emcc-version-gate.sh`; a mismatched emcc fails the build. Emscripten 6.x glue does not embed its version, so `wasm:validate` can only check the pin exists (and would fail if a future glue embeds a mismatched version).
- **Beware stale SDKs:** `build.sh` sources the first `emsdk_env.sh` it finds (`$REPO_ROOT/emsdk`, `~/emsdk`, …), which can override an already-activated emsdk. The gate catches this.
- **Cloud VMs / Jules:** plain `npm run build` uses the committed artifacts. Do not compile with 3.1.x.
- **EM_CACHE:** `build.sh` keeps an `EM_CACHE` you set and otherwise uses emcc's default (`<emsdk>/upstream/emscripten/cache`). CI points it at `.emscripten-cache` and restores it with `actions/cache`, so the port and LTO system libraries are not rebuilt every run.
- **Bumping:** edit the JSON + `.github/workflows/wasm.yml` together, rebuild, commit artifacts in the same PR, note size deltas in `wasm_renderer/BUILD_FLAG_EXPERIMENTS.md`.

## Build Failures: CI vs Local

**CI — `wasm` job (`wasm.yml`):** installs emsdk, builds the release and debug profiles,
runs `npm run wasm:validate`, requires the fresh release `.wasm`/`.js`/`.d.ts` to equal the
committed ones byte for byte, runs `verify:wasm-bridge-sync` and the WASM Jest suites, and
uploads artifacts.

**CI — `test-wasm-e2e` job (`wasm.yml`):** downloads the `wasm` job's artifacts, runs
`npm run build` (prebuild uses them as-is), then the WASM Playwright smoke specs on
SwiftShader (`--project=swiftshader-smoke`) for the release build and again for the debug
profile (`npm run test:wasm:debug`).

**CI — `test` job (`ci.yml`, every PR):** builds against the **committed** `public/wasm/`
artifacts and runs `npm run wasm:validate` on them. It does not compile WASM.

**Local:** `npm run wasm:build` **fails (exit 1) when `emcc` is missing** (unless
`SKIP_WASM_BUILD=1`); `npm run build` never needs emcc.

### When `wasm:validate` runs

| Context | Command |
|---------|---------|
| After local C++ or bridge change | `npm run wasm:validate` |
| CI `wasm` job | immediately after `wasm:build` |
| CI `test` job | after `npm run build` (confirms artifacts survived the bundle) |
| Not run automatically | `npm start` / dev server (uses existing `public/wasm/`) |

Run `npm run wasm:validate` manually after any C++ or bridge change.

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
# or
npm run wasm:validate
```

This ensures:
- **File Existence**: All three required files exist in `public/wasm/`
  - `pixelocity_wasm.wasm` (WebAssembly binary)
  - `pixelocity_wasm.js` (Emscripten runtime glue)
  - `wasm_bridge.js` (JavaScript bridge to the C++ renderer)

- **Bridge sync**: generated `wasm_renderer/` and `public/wasm/` ESM copies must match
  each other; `wasm_bridge.d.ts` must match `src/wasm/wasm_bridge.d.ts`.
  `npm run verify:wasm-bridge-sync` fails if they drift from TypeScript emit.
  Edit `src/wasm/bridge/*.ts` only. **Never** edit `public/wasm/bridge/*.js`
  or `wasm_renderer/bridge/*.js` — those are emitted copies.

See [`wasm_renderer/ARTIFACTS.md`](../wasm_renderer/ARTIFACTS.md) for the full artifact layout.

- **File Sizes**: Reasonable and non-empty
  - `.wasm`: 50–200 KB (should be ~96 KB)
  - `.js` files: 10+ KB minimum

- **Content Integrity**:
  - WASM magic number (`\0asm`) is present and correct
  - Not a stub or placeholder (no `Promise.resolve({})`)
  - Expected exported functions are present

- **Freshness**: Timestamps ensure artifacts are not older than source files

## What Happens During CI

WASM is frozen R&D (#1080), so the `wasm` job lives in [`.github/workflows/wasm.yml`](../.github/workflows/wasm.yml) and runs only:

- on pull requests to `main` that touch the WASM tree or anything it is built from: `wasm_renderer/**`, `public/wasm/**`, `src/wasm/**`, `WASMRenderer.ts`, the contracts the generator reads (`src/contracts/wasm_*.json`, `binding_table.json`, the limits/slots/uniforms/workgroup contracts), the build scripts (`format-wasm-*`, `emit-wasm-*`, `emcc-version-gate.sh`, `check-asyncify-exports.mjs`), the WASM specs, or `wasm.yml` itself (#1400 H3);
- weekly on `main` (Monday 06:17 UTC);
- on demand (`workflow_dispatch`).

Neither WASM job is a required check. Steps:

1. **Setup**: Node.js 24 + npm dependencies
2. **Emscripten**: emsdk **6.0.9** (pinned) via `mymindstorm/setup-emsdk@v14`
3. **Build**: `npm run wasm:build` compiles from source (fails if emcc missing)
4. **Validation**: `npm run wasm:validate` — integrity, bridge sync, freshness
5. **Smoke**: Jest tests matching `WASM` (bridge API surface)
6. **Artifacts**: Uploaded for the `test-wasm-e2e` job
7. **Status**: If any step fails, CI fails (no silent skips)

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
./emsdk install 6.0.9
./emsdk activate 6.0.9
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

- App never calls `setInputSource` — generative mode unreachable for WASM *(partially addressed 2026-06-20)*
- Live-browser smoke on edge GPUs — informal only; promotion tracking in [`WASM_PROMOTION_TRACKING.md`](./WASM_PROMOTION_TRACKING.md)

Tracking table:
[`WASM_RENDERER_GAP_ANALYSIS.md`](./WASM_RENDERER_GAP_ANALYSIS.md#c-solidification-tracking-2026-06).

## Summary

- **Build command**: `npm run wasm:build` (requires emsdk; fails without it)
- **Validation**: `npm run wasm:validate`
- **CI** (`wasm.yml`, WASM-path PRs + weekly): `wasm` job builds + validates + Jest smoke; `test-wasm-e2e` runs Playwright smoke
- **App build**: `npm run build` uses committed artifacts; `WASM_BUILD=1` compiles first
- **Debug profile**: `npm run wasm:build:debug`, then `?renderer=wasm&wasm_debug=1` / `npm run test:wasm:debug`
- **Artifact layout**: [`wasm_renderer/ARTIFACTS.md`](../wasm_renderer/ARTIFACTS.md)
- **Roadmap**: See [`WASM_RENDERER_GAP_ANALYSIS.md`](./WASM_RENDERER_GAP_ANALYSIS.md) and [#799 roadmap comment](https://github.com/ford442/image_video_effects/issues/799#issuecomment-4678258584)

### Known Workarounds

#### TextDecoder and Resizable ArrayBuffers
When compiling with recent Emscripten versions and enabling WebGPU (or certain `emcc` memory flags), the WebAssembly heap may be backed by a resizable `ArrayBuffer`.
Certain browser implementations of `TextDecoder.decode()` throw a `TypeError` if provided a view into a resizable `ArrayBuffer`. This causes an initialization failure in the JS glue code (specifically within Emscripten's `UTF8ToString` or `UTF8ArrayToString`).

**Solution:**
The `wasm_renderer/build.sh` script explicitly includes `-sGROWABLE_ARRAYBUFFERS=0` while preserving `-sALLOW_MEMORY_GROWTH=1`. This prevents the memory's underlying ArrayBuffer from being marked resizable, completely bypassing the browser's `TextDecoder` exceptions without requiring runtime JS monkey-patches.
