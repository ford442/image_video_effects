# GPU CI runner

How to give the repo a self-hosted runner with a real GPU, and what runs on it (#1512 Part C).

GitHub-hosted runners have no GPU adapter, and the Cloud VM only has SwiftShader (AGENTS.md), so everything that needs hardware evidence goes through the manual workflow **GPU_REQUIRED** ([`.github/workflows/gpu-required.yml`](../.github/workflows/gpu-required.yml)). It runs on a runner labelled `gpu`. The thumbnail capture farm (`thumbs-capture-farm.yml`) uses the same label.

## What runs on it

| Suite (`suite` input) | Command | Covers |
|---|---|---|
| `engine2` | `npm run test:engine2:gpu` | Every `tests/*.swiftshader.spec.ts` suite on the hardware device: engine2, device loss, isolation, validation scopes, Display P3, cue crossfade, Graph Lab, sim hash, the WASM measurement specs, plus the three below |
| `compositor-golden` | `npm run test:golden:gpu`, then the golden spec again with `PX_RENDER_THREAD=main` | Layer-compositor golden frames, HDR and storage present, the compat rung |
| `compositor-golden-swiftshader` | `npm run test:golden` (+ `PX_RENDER_THREAD=main`) | The same fixtures on SwiftShader. Always runs on `ubuntu-latest` (the job ignores `runner_label` for this suite), so no hardware is needed |
| `format-tier-bench`, `wasm-benchmark`, `renderer-parity`, `wasm-encode-parity` | (unchanged) | The #1357 benches |

The Playwright project `gpu` (`playwright.config.ts`) runs the `*.swiftshader.spec.ts` files with the hardware launch flags from `src/utils/gpuLaunchArgs.ts` (`--use-webgpu-adapter=default`, and Vulkan + ANGLE on Linux) and the full Chromium build (`channel: 'chromium'`; headless-shell disables GPU compositing). Specs that call `annotateBootAdapter` (`tests/helpers/rendererHarness.ts`) do two things:

- They record the adapter as an `adapter` annotation in the report.
- They **fail** a test that booted on a software adapter under the `gpu` project. A green `gpu` run is therefore hardware evidence and never a silent SwiftShader pass.

### Golden frames

`tests/compositor-golden.swiftshader.spec.ts` covers:

- Every blend mode (normal, add, screen, multiply, overlay, soft-light, difference, luma-key, depth-key) × {rgba16float, rgba32float}.
- The acceptance case: two parallel slots, screen at 50 % opacity.
- Masks: own luma, another slot's alpha (inverted), a mask slot's matte, depth, and feather.
- A `// @requires f16` shader against its f32 twin within ΔE < 1.

Each frame is read back through `__pixelocity__.captureThumbnailPng` at 32×32 and compared with the CPU reference of `composite.wgsl` (`src/renderer/webgpu/compositeReference.ts`). The comparison uses `diffFrames`, the helper the WASM parity suite uses, in linear light: max |Δ| ≤ 5/255 and mean ≤ 2/255. The expectation is built from the two layers *as this device rendered them*, so the check is the blend math and not a driver's gradients, and there are no committed PNGs to drift. Failing frames are written to `test-results/compositor-golden/` and uploaded.

Run it locally the same way:

```bash
SKIP_WASM_BUILD=1 npm run build
npm run gpu:adapter-check          # what adapter headless Chromium gets here
npm run test:golden:gpu            # hardware (needs a GPU)
npm run test:golden                # SwiftShader
```

## Adapter check

`npm run gpu:adapter-check` (`scripts/gpu-adapter-check.ts`) is the first step of every suite. It does the following:

- Launches Chromium with the `gpu` project's flags.
- Asks for a core and a compatibility adapter and prints vendor and architecture, the tier 2 features, the limits that pick a limits tier, and the preferred canvas format.
- Writes `test-results/gpu-adapter.json` and a table in the job summary.

With `strict` (the default) a missing or software adapter (SwiftShader, llvmpipe, lavapipe, WARP) **fails the job** before anything else runs. Use its output to fill the hardware tables in [DEVICE_FEATURES.md](./DEVICE_FEATURES.md#hdr-hardware-validation).

## Provisioning a runner

Any Linux box with a Vulkan-capable GPU works. Two options:

- **A dedicated box.** A spare desktop or a rented GPU server (Contabo and similar hosts offer them) with an NVIDIA or AMD card. This is the cheapest option if it stays registered.
- **A cloud GPU spot instance.** For example an AWS `g4dn.xlarge` (T4) or a GCP `g2-standard-4` (L4), started when needed. Use an ephemeral runner (`--ephemeral`) so each job gets a clean machine.

Steps (Ubuntu 22.04 / 24.04):

1. **Driver and Vulkan.** Install the vendor driver (`nvidia-driver-550` or newer, or Mesa RADV for AMD) and `vulkan-tools`. `vulkaninfo --summary` must list the GPU and not only `llvmpipe`.
2. **Device access.** The launch flags use Vulkan without a window surface (`--disable-vulkan-surface`), so no display server is needed. The runner user must be able to open the GPU device nodes: add it to the `video` and `render` groups (`/dev/dri/*`, or `/dev/nvidia*` on NVIDIA).
3. **Node and browsers.** Node 24, then `npx playwright install --with-deps chromium` once as the runner user (the workflow repeats it without `--with-deps`).
4. **Register the runner.** Repository → Settings → Actions → Runners → *New self-hosted runner*. Follow the `config.sh` steps with `--labels gpu` (add `--ephemeral` for spot machines), then install it as a service (`sudo ./svc.sh install && sudo ./svc.sh start`).
5. **Check it.** Actions → **GPU_REQUIRED (manual)** → Run workflow, with suite `compositor-golden`, runner label `gpu` and strict on. The *Check WebGPU adapter* step must show the real GPU.

Security: the workflow is `workflow_dispatch` only, so code from a fork's pull request never runs on the box. Keep it that way. Do not add `pull_request` triggers to workflows that target the `gpu` label.

## Recording results

After a run, add a row per machine to:

- the HDR table in [DEVICE_FEATURES.md](./DEVICE_FEATURES.md#hdr-hardware-validation), with the adapter from the job summary and whether highlights above SDR white were visible on an HDR display (that needs a person at the screen);
- `reports/format-tier-bench-*.md`, for the `format-tier-bench` suite ([FORMAT_TIERS.md](./FORMAT_TIERS.md)).
