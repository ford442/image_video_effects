## Summary

<!-- What changed and why (1–3 sentences) -->

## Checklist

- [ ] `npm test -- --watchAll=false --ci` passes locally
- [ ] If **device limits / bind group** changed: update `src/contracts/webgpu_limits.json` + `wasm_renderer/device.cpp`; run `npm run verify:device-policy`
- [ ] If **WGSL shaders** changed: `python3 scripts/wgsl_precommit_gate.py --files <paths>`
- [ ] Only if this PR touches **`wasm_renderer/**` or `public/wasm/**`** (frozen R&D, parity bugs only): `npm run wasm:build` then **`npm run wasm:validate`**, and commit the rebuilt `public/wasm/` artifacts. The `WASM (R&D)` workflow runs on these PRs; see `docs/WASM_BUILD_CI_GUIDE.md`.
