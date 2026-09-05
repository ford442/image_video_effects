# Coordinator Review

## Contract review

- Bind group: exact declarations for bindings 0–12 in all ten shaders.
- Dispatch: explicit `@workgroup_size(16, 16, 1)` plus bounds guards.
- Feedback: exact unfiltered `textureLoad(dataTextureC, ...)` only; A is the
  sole temporal writer and contains raw HDR RGBA history.
- Output: ACES tone mapping is display-only; alpha encodes geometric, crystal,
  optical, fractal, or vortex coverage; every effect writes generated depth.
- Audio: bass, mids, and treble come from `plasmaBuffer[0].x/.y/.z` and each
  drives effect-specific behavior.
- Controls: aligned four-entry `params` and `updatedParams` arrays; focused
  liveness audit reports zero dead sliders.
- Interaction: normalized pointer coordinates, held response, and bounded
  age-guarded click fronts are retained or added according to each design.
- Compatibility: Hyper Warp retains `gen_hyper_warp.wgsl`,
  `gen_hyper_warp.json`, the `gen-hyper-warp` ID, and its catalog URL.

## Validation

- Actual Naga CLI 30.0.1: 10 passed, 0 failed.
- Focused precommit structure: 10 passed; no binding, workgroup, or
  extraBuffer violations.
- Dead-slider audit: 10 definitions, 0 new dead sliders, 0 definition errors.
- Strict extraBuffer audit: 10 shaders, 0 violations or unresolved writes.
- Static ownership/metadata/catalog audit: 10/10; no B/C stores or filtered C
  reads; all parameter arrays and relative URLs align.
- Catalogs: 453 generative effects and 1,345 effects in the unified manifest;
  all ten exact IDs are present.
- Uniform-layout, shader-URL policy, and TypeScript checks: passed.
- Jest: 81/81 suites passed; 545 tests passed and 1 skipped.
- Production build: compiled successfully with `SKIP_WASM_BUILD=1` and the
  committed WASM artifacts.

The Cloud VM has no WebGPU adapter, so final browser review must cover visual
balance, click/held feel, HDR stability, and 1080p performance on a real GPU.
