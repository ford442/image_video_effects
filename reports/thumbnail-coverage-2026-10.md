# Thumbnail coverage — October 2026

Snapshot: 2026-10-05 (after the SwiftShader capture waves)

## Coverage

- Catalog: **1,379** unique list ids; skip list **1** (`deep-workgroup-multi-effect-blend`), **1,378** eligible.
- PNG + manifest: **1,286**.
- Integrity flags: **22** (17 `black_frame`, 5 `flat_frame`; `flat_frame` = largest RGB std < 0.01, new this month).
- **Healthy eligible: 1,264 / 1,378 (91.7%)**, past the 50% checkpoint and the 80% target (1,103).
- Deferrals: **40** `gpu-capture-pending` (ratchet 40, target 200), expiring 2026-10-26.
- Missing (no healthy PNG, no deferral): **74**.

## Execution host

Cloud VM, no GPU. Playwright Chromium with SwiftShader (`--adapter=swiftshader`), a conformant
software WebGPU device; render scale 0.25 (512²), 30 warm-up frames (120 for simulation and
multipass ids), 3 shards. 993 PNGs carry `capture_host: "swiftshader"` in `manifest.json`; a
GPU host should recapture them with `npm run thumbs:generate -- --recapture-host=swiftshader`.

## Not healthy (114 eligible ids)

| Reason | Count | Next step |
|---|---:|---|
| black at default params | 55 | GPU recapture to confirm, then content fix (13 were also black on a GPU in 2026-06) |
| flat at default params | 29 | same |
| timeout / load failure on SwiftShader | 30 | GPU capture (heavy kernels: NLM, Gabor, frequency-domain, Lenia variants) |

Id lists and the low-information review candidates are in `docs/THUMBNAIL_PIPELINE.md`
(“2026-10-05 SwiftShader capture station log”).
