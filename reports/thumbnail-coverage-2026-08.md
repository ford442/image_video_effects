# Thumbnail coverage — August 2026

Snapshot: 2026-08-01 (Europe/Berlin)

## Coverage

- Catalog: **1,306** unique list IDs.
- Eligibility skip list: **1** (`deep-workgroup-multi-effect-blend`), leaving **1,305** eligible.
- Nominal manifest + PNG coverage: **349/1,306 (26.7%)**.
- Nominal eligible coverage: **349/1,305 (26.7%)**.
- Corrected integrity audit: **77 black frames**, **0 magenta/error frames**.
- Integrity-adjusted healthy eligible coverage: **272/1,305 (20.8%)**.
- 80% eligible target: **1,044** healthy thumbnails; **772** healthy thumbnails remain.

The nominal remaining count is 695, but it treats the 77 invalid existing PNGs as
complete. The healthy remaining count is the honest production target.

## Integrity correction

The prior checked-in audit reported 89 flags. Its PNG reader skipped the per-row
PNG filter byte without reconstructing Sub/Up/Average/Paeth filters, which produced
false dark/magenta measurements for valid images. The corrected standard-library
decoder reports 77 genuinely near-black files:

- `generative`: 56
- `visual-effects`: 21

`run-thumbnail-waves.sh` now force-retries integrity failures before processing
missing thumbnails. These 77 shaders remain eligible and must not be moved to the
coverage skip list merely to improve the percentage.

## Current execution ceiling

This Cloud VM cannot provide trustworthy thumbnail output. A production-app probe
reached the WebGPU backend but captured a zero-energy frame for
`gen-abyssal-quantum-leviathan-skeleton`:

```text
success=0 failed=1 black_frame=1
meanLuminance=0.0000 activePixelRatio=0.0000
```

Therefore no PNG generated on this host was accepted. Run the waves on a discrete
GPU workstation or a verified GPU VPS/self-hosted runner:

```bash
SKIP_WASM_BUILD=1 npm run build
bash scripts/run-thumbnail-waves.sh --wave=W1  # generative
bash scripts/run-thumbnail-waves.sh --wave=W2  # simulation + interactive-mouse
bash scripts/run-thumbnail-waves.sh --wave=W3  # remaining categories
python3 scripts/audit_thumbnail_integrity.py
npm run thumbs:status
```

## Skip-list justification

`deep-workgroup-multi-effect-blend` is excluded because its `16x16x4` workgroup
requires 1,024 invocations. Keep it excluded until the capture adapter reports
`maxComputeInvocationsPerWorkgroup >= 1024`; the reason is recorded alongside the
ID in `reports/thumbnail_skip_allowlist.json`.

## Product and CI verification

- `App.tsx` supplies the manifest-backed `hasThumbnail` predicate to both roulette
  and attract mode.
- Both paths use `pickWeightedShader`; only manifest entries receive the 3x preview
  weight. Missing entries retain weight 1 rather than being hidden from the catalog.
- Gallery components use the same manifest and fall back when no entry exists.
- The scheduled coverage workflow remains reporting-only. Coverage percentage is
  not a PR failure gate before the healthy baseline reaches 50%.

## Acceptance state

- [ ] At least 80% healthy eligible coverage — requires discrete-GPU waves.
- [ ] All 77 near-black frames regenerated — queued automatically by the wave runner.
- [x] Existing skip entry has an explicit hardware justification.
- [x] Attract/roulette manifest-backed weighting verified in code and unit tests.
- [x] Monthly coverage report checked in.
