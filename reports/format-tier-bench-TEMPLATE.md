# Format tier bench — YYYY-MM-DD

> Template. Produce the measured version with:
> `npm run build && WASM_GPU_TESTS=1 npx playwright test tests/format-tier-bench.spec.ts`
> (or Actions → **GPU_REQUIRED (manual)** → `format-tier-bench`), which writes
> `reports/format-tier-bench-<date>.md` with the tables filled in. Then complete the
> **Hardware** and **Go / no-go** sections by hand — the harness cannot know the machine.
>
> **A run with no WebGPU adapter is not evidence.** Cloud/headless VMs write a stub report
> with `GPU observed: no`; those numbers must never be quoted as tier behavior.

## Hardware

Fill in one block per machine benched. At minimum cover **discrete** and **integrated**;
add mobile Safari if a device is available.

- **Class:** discrete / integrated / mobile
- **Adapter:** _(vendor | architecture | device | description — harness records `adapter.info`)_
- **Driver / OS:**
- **Browser + version:**
- **Power state:** plugged in / on battery
- **Thermal state:** cold start / after N minutes sustained load
- **Display / canvas size:**

## Measurements

| Workload | Tier | Format | Pinned | Internal | ~MiB | FPS | GPU ms | Real timings | Slots | Passes cap |
|---|---|---|---|---|---|---|---|---|---|---|
| simple-generative | ultra | | | | | | | | | |
| simple-generative | balanced | | | | | | | | | |
| simple-generative | battery | | | | | | | | | |
| feedback-fluid | … | | | | | | | | | |
| ripple-tank-graph | … | | | | | | | | | |
| multi-slot-chain | … | | | | | | | | | |
| history-ring-temporal | … | | | | | | | | | |

`Real timings = no` means the row is wall-clock, not `timestamp-query` — treat GPU ms as
indicative only (the honesty gate is `hasRealGpuTimings`, see docs/DEVICE_FEATURES.md).

## Deltas vs ultra

| Workload | Tier | FPS ×ultra | Texture MiB ×ultra |
|---|---|---|---|

Expected shape if the tier model is right: `Texture MiB ×ultra ≈ 0.5` for FP16 tiers
(before resolution scaling), and FPS gain concentrated in the bandwidth-heavy workloads
(history-ring, multi-slot chain) rather than the ALU-bound generative baseline.

## Warnings

- Pass-cap warnings (`[GraphRunner] Pass cap …`) — expected on battery for `ripple-tank`.
- Format-rewrite misses (`… storage declaration(s) not rewritten …`) — **must be empty**.
  Any entry here is a real bug: the pipeline disagrees with allocated textures.

## Sim correctness spot-check

FP16 must not break the sims. For each FP32-required workload, confirm:

- [ ] `colorFormat` reported as `rgba32float` on **every** tier (the pin held)
- [ ] no NaN / blowup / frozen field after 60 s at balanced
- [ ] visual result matches the ultra run (screenshot diff or eyeball, note which)

## Thermal / sustained load

- [ ] 10-minute sustained run at balanced on the integrated machine
- [ ] FPS at minute 10 vs minute 1:
- [ ] Did `maxPassesPerFrame` hold (no dropped dispatches beyond the tier cap)?

## Go / no-go: balanced as iGPU default

- **Verdict:** _go / no-go_
- **Rationale:** _(bandwidth saving measured, sim correctness, thermal behavior)_
- **Follow-ups:** _(e.g. revisit `compat` rgba8unorm spike — Phase 2 in docs/FORMAT_TIERS.md)_
