## Summary

<!-- What changed and why (1–3 sentences) -->

## Checklist

- [ ] `npm test -- --watchAll=false --ci` passes locally
- [ ] If **C++ or `wasm_renderer/bridge/`** changed: `npm run wasm:build` then **`npm run wasm:validate`**
- [ ] If **device limits / bind group** changed: update `contracts/webgpu_limits.json` + `wasm_renderer/device.cpp`; run `npm run verify:device-policy`
- [ ] If **WGSL shaders** changed: `python3 scripts/wgsl_precommit_gate.py --files <paths>`

## WASM / build notes

CI builds WASM via **`wasm_renderer/build.sh` only** (not CMake). Committed artifacts under `public/wasm/` must stay in sync when touching the renderer.

See `wasm_renderer/README.md` and `WASM_BUILD_CI_GUIDE.md`.
