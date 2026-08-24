# Format-tier evidence — 2026-08-23

> Honest Cloud-VM record for #1124. **This machine has no WebGPU adapter.**
> Numbers below are **not** discrete/iGPU FPS evidence. Fill the hardware blocks
> on a workstation with `npm run bench:format-tiers` (or Actions → GPU_REQUIRED).

## What this change proved in-tree (no GPU required)

- `probeFormatCapabilities` creates 1×1 `rgba16float` + `rgba32float` storage
  textures on the **same** boot-probe `GPUDevice`. It no longer hardcodes
  `supportsRgba32FloatStorage: true`. Jest: `formatPolicy.test.ts`,
  `webgpuBootProbe.test.ts`.
- WASM `wgpuQueueWriteTexture` `bytesPerRow` follows `colorFormat_`
  (`wasm_renderer/format_pack.h` + `resources.cpp`). rgba16float = 8 B/px,
  rgba32float = 16 B/px. Zero-init of `dataC` / `readTexture` uses that row
  pitch. Depth (`audio_depth.cpp`) stays `r32float`.
- Pin honesty: category `simulation` and tags `physics` / `fluid` /
  `reaction-diffusion` do **not** pin. JSON `requiresRgba32Float` and the
  state-shader allowlist still pin `ripple-tank`, `fabric-of-reality`,
  `chromatographic-fluid`, `gray-scott-tank` (plus `wave-tank`,
  `optical-flow-dream`, `photonic-caustics-graph`, `sim-fluid-feedback-coupled`).
- `Float16Array` missing ⇒ fail-soft `rgba32float` + console breadcrumb;
  CPU packer still has a software binary16 path so uploads do not throw.
- Device-init policy, B→C then A→C feedback, and gpu-chores “adopt renderer
  device” are unchanged.

## Cloud VM adapter

- **GPU observed:** no (`navigator.gpu.requestAdapter()` is null here)
- **Adapter:** n/a
- **`getFormatRewriteWarnings()`:** n/a (no pipeline compile on this host)
- **Pin fired:** unit-tested only

Run the stub-safe harness anyway — it must write `GPU observed: no` and skip:

```bash
npm run bench:format-tiers
```

## Workstation checklist (required for go/no-go)

On **≥1 discrete** and **≥1 iGPU**, with a GPU-capable browser:

```bash
npm run build
WASM_GPU_TESTS=1 npm run bench:format-tiers
```

Then complete both hardware blocks (copy from
`reports/format-tier-bench-TEMPLATE.md` / `reports/format-tier-bench-<date>.md`):

### Discrete

- **Adapter:** _(vendor | architecture | device | description)_
- **Driver / OS / browser:**
- **simple-generative balanced:** format `rgba16float`, pin `false`, FPS ____, ~MiB ____
- **simple-generative ultra:** format `rgba32float`, pin `false`, FPS ____, ~MiB ____
- **ripple-tank / gray-scott / fabric / chromatographic** on balanced: `colorFormat=rgba32float`, `fp32Pinned=true`
- **Rewrite warnings:** empty

### Integrated

- **Adapter:**
- **simple-generative balanced:** format `rgba16float`, pin `false`, FPS ____ (claim: hold 30/60 without silent FP32 pin)
- **battery:** format `rgba16float` unless Float16Array/storage probe failed
- **10-minute thermal:** FPS minute 1 vs minute 10:

## Go / no-go: balanced as iGPU default

- **Verdict:** _pending real-GPU run_
- **Rationale:** Cloud VM cannot observe an adapter. Host rewrite + packing +
  probe are in tree; FPS/MiB evidence must come from the workstation sweep.
