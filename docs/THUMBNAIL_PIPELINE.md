# Thumbnail Pipeline

Automated batch rendering of shader preview thumbnails for the gallery / mega-menu UX.

## Hardware requirements

Thumbnail generation needs a **WebGPU adapter**. The script drives Chromium via Playwright and renders through the production WebGPU renderer.

| Environment | Works? |
|-------------|--------|
| Linux/macOS/Windows with Vulkan, D3D12, or Metal | Yes (`capture_host: gpu`) |
| Chrome / Chromium 121+ | Yes |
| GPU-less host (Cloud VM) with Playwright's Chromium + `--adapter=swiftshader` | Yes, slowly (`capture_host: swiftshader`) |
| GitHub `ubuntu-latest` | Not used: never register it as the `gpu` runner |
| `xvfb-run` alone | No — provides a display, not a GPU |

`xvfb-run` can help on headless Linux **when a GPU is present** but no display server is running.

### SwiftShader captures (since 2026-10-05)

`--adapter=swiftshader` launches Chromium with `SWIFTSHADER_WEBGPU_ARGS`
(`scripts/lib/swiftshaderArgs.js`, shared with `playwright.config.ts`). That is a real,
conformant WebGPU device in software (Vulkan SwiftShader), not a fallback: the production
renderer runs the same WGSL, and the PNG is read back from the GPU texture. It is slow
(about 2 fps at 512², 30-70 s per shader), so it renders at scale 0.25 (512²) on a 512 px page
on the main thread. Pages narrower than about 512 px never start the renderer.

Rules:

- A SwiftShader PNG is coverage when it passes the same health checks as any other capture
  (black, magenta, flat). It is tagged `capture_host: "swiftshader"` in `manifest.json`.
- A GPU host should recapture them when one exists: `npm run thumbs:generate -- --recapture-host=swiftshader`.
- Never commit an unreviewed wave: build a contact sheet of the new PNGs and look at it first.
- Shaders that need features SwiftShader lacks (1024-invocation workgroups) stay in
  `reports/thumbnail_skip_allowlist.json` with that reason.

## Prerequisites

```bash
npm ci
npm run build
npx playwright install chromium
```

The `app` engine (default) serves the production build from `build/` and supports the
full catalog, including multipass shaders. Thumbnail PNGs use gpu-chores `downsample_2d`
when the adopted WebGPU device is live (`captureThumbnailPng` in the test harness);
otherwise the canvas 2D scale fallback. The `minimal` engine skips the build and
uses a fast inline WebGPU path for **generative shaders only**; it rejects other
categories rather than producing misleading captures.

## Commands

```bash
# Generate missing thumbnails, attract / Physics Lab first
npm run thumbs:generate -- --priority=attract --missing

# Check coverage vs catalog (healthy eligible, not PNG-only)
npm run thumbs:status

# Category batch
npm run thumbs:generate -- --missing --category=generative

# Limit smoke run
npm run thumbs:generate -- --limit=5 --category=generative

# Parallel shards across machines
npm run thumbs:generate -- --missing --shard=0/4
npm run thumbs:generate -- --missing --shard=1/4
# ...

# Force regenerate existing
npm run thumbs:generate -- --force --ids=plasma-storm,cyber-ripples

# Fast inline engine (no production build; generative only)
npm run thumbs:generate:minimal -- --limit=20
```

## CLI flags

| Flag | Default | Description |
|------|---------|-------------|
| `--engine=app\|minimal` | `app` | Production full-catalog renderer vs generative-only inline WebGPU |
| `--missing` | off | Skip shaders that already have PNG + manifest entry |
| `--force` | off | Regenerate even when thumbnail exists |
| `--category=NAME` | `all-catalog` | Shader list category or `all-catalog` |
| `--priority=attract` | off | Process attract + Physics Lab ids first, then 4-param generative, then long tail |
| `--limit=N` | none | Max shaders to process |
| `--shard=I/N` | none | Process every Nth shader where `index % N === I` |
| `--frames=60` | `60` | Animation frames to wait before capture (`app` engine) |
| `--size=256` | `256` | Output PNG dimension (square) |
| `--quality=battery` | `battery` | Render quality preset (OOM guard) |
| `--time=1.5` | `1.5` | Shader time uniform at capture |
| `--report=PATH` | `reports/thumbnail-failures.json` | Failure report output |
| `--adapter=default\|swiftshader` | `default` (env `THUMBS_ADAPTER`) | `swiftshader`: software WebGPU on GPU-less hosts; PNGs tagged `capture_host: swiftshader` |
| `--viewport=N` | none (`512` with swiftshader) | Page size in px; the renderer does not start below ~512 |
| `--render-scale=S` | none (`0.25` with swiftshader) | Pin the internal render scale (0.25 = 512²) |
| `--port=N` | `3459` | Static server port, so several shards can run on one host |
| `--recapture-host=HOST` | none | Only shaders whose manifest `capture_host` is HOST (e.g. redo `swiftshader` on a GPU) |

## Output

- PNG files: `public/thumbnails/<shader-id>.png`
- Manifest: `public/thumbnails/manifest.json` (consumed by `ShaderGallery` and `CommunityGallery`)
- Failures: `reports/thumbnail-failures.json`

### Failure report schema

```json
{
  "generated_at": "2026-07-19T12:00:00.000Z",
  "engine": "app",
  "summary": {
    "success": 120,
    "failed": 3,
    "skipped": 1,
    "black_frame": 2,
    "magenta_frame": 0,
    "error_frame": 0,
    "compile": 1
  },
  "failures": [
    {
      "id": "some-shader",
      "reason": "black_frame",
      "detail": "meanLuminance=0.0020 activePixelRatio=0.0010 magentaPixelRatio=0.0000",
      "stats": {
        "meanLuminance": 0.002,
        "activePixelRatio": 0.001,
        "magentaPixelRatio": 0,
        "width": 1024,
        "height": 1024
      }
    }
  ]
}
```

Failure reasons: `black_frame`, `magenta_frame`, `error_frame`, `flat_frame`, `compile`, `pipeline`, `no_wgsl`, `gpu_unavailable`, `load_failed`, `capture_failed`.

Health is measured on the PNG that will be committed (decoded with `sharp`), with the same
thresholds in `scripts/lib/thumbnailFrameAnalysis.js`, `src/services/thumbnailBatch/frameCheck.ts`
and `scripts/audit_thumbnail_integrity.py`: black = active pixels < 2% or mean luminance < 0.01;
magenta = ≥ 75% magenta pixels; **flat** = largest R/G/B standard deviation < 0.01 (a solid fill or
invisible noise, added 2026-10-05; it flagged 11 PNGs that had counted as healthy, including the
attract ids `stellar-plasma` and `bio_lenia_continuous`).

Capture conditions (both the CLI and the in-app scanner):

- Every category except `generative` renders over the input image
  `public/fixtures/thumbnail-scene.png` (512², procedural, `scripts/make-thumbnail-fixture.py`), as
  in the app. List entries without a `category` take their list's name; before 2026-10-05 most of
  them were captured over a cleared input and came out black.
- The shader is loaded from its list `url` (graph steps and renamed files used to be skipped as `no_wgsl`).
- Feedback textures are reallocated before each shader, so a capture starts from zero state
  rather than the previous shader's.
- The CLI page blocks every non-localhost request: the app otherwise fetches a random remote
  image at boot that can land mid-capture.
- Warm-up counts frames the renderer actually rendered, not page animation frames.

Skipped shaders (intentional): listed in `reports/thumbnail_skip_allowlist.json` — excluded from generation queue and eligible coverage denominator.

## Weekly refresh: only changed shaders (in-app or CLI)

Every shader has a **source hash** covering its WGSL, its `#include`d `_*.wgsl`
libraries, later multipass passes, and the `params` block of its definition
JSON (`scripts/lib/shaderSourceHash.js`). Each thumbnail manifest entry stores
the `source_hash` it was captured from, so a thumbnail is:

| State | Meaning |
|-------|---------|
| `fresh` | Captured from the current source |
| `stale` | Shader changed since capture (e.g. an upgrade batch) |
| `missing` | No thumbnail |
| `unknown` | Captured before hashing existed — run the backfill once |

`npm start` / `npm run build` regenerate `public/thumbnails/source-hashes.json`
(gitignored) via `npm run build:source-hashes`.

### One-time setup

```bash
npm run thumbs:backfill-hashes        # needs full git history (not a --depth 1 clone)
npm run upgrades:record               # first run creates the baseline ledger
```

The backfill stamps an existing thumbnail only when git shows no change to its
source files after the thumbnail's `generated_at`, and never stamps ids in
`public/thumbnails/unhealthy.json` (black/error PNGs). The 2026-10-04 run stamped
2, left 281 changed-since-capture and 77 unhealthy unstamped (queued for recapture).
Skip-allowlist ids are copied into `source-hashes.json` (`skip`) so the in-app
scanner leaves them out of *Changed since last thumbnail* like the CLI does.

### After each upgrade batch

```bash
npm run upgrades:record -- --note="2026-10-03 weekly batch (opus) — upgrade_batches/…"
```

This appends an entry to `reports/shader-upgrade-ledger.json` for every shader
whose hash changed (`--event=fixed` or `--event=hygiene` for non-upgrade edits).
Then refresh just those thumbnails, either:

- **In the app (Chrome/Edge, real GPU):** open **Shader Scanner** → scope
  *Changed since last thumbnail* → *Render + save thumbnails* → **Choose repo
  folder** (the checkout root) → **Start Scan**. It compile-checks, renders each
  passing shader through the live Tier A renderer, flags black/magenta frames,
  writes `public/thumbnails/<id>.png`, merges `manifest.json` (every 10 captures),
  and writes failures to `reports/thumbnail-failures-inapp.json`. Your slot
  stack, params and input are restored afterwards.
- **CLI:** `npm run thumbs:stale` (same as `thumbs:generate` with `--stale`).

Both paths stamp `source_hash`, so the next run skips everything already current.

## Coverage strategy (campaign target ≥50% healthy; 80% later)

Prefer a discrete-GPU workstation. A GPU-less host (the Cloud VM) can capture with
`--adapter=swiftshader` (see Hardware requirements); never commit black PNGs as coverage.

```bash
npm run build
npm run thumbs:generate -- --priority=attract --missing
npm run thumbs:status
python3 scripts/audit_thumbnail_integrity.py
bash scripts/run-thumbnail-waves.sh --wave=attract
```

The wave runner audits first and force-retries every currently flagged PNG before
processing missing entries. This prevents `--missing` from treating an existing
black/error PNG as complete. The final audit is the authoritative healthy count.

Priority order: `ATTRACT_SHOWCASE_IDS` + `ATTRACT_PHYSICS_LAB_IDS`, then remaining generative with four live `zoom_params` mappings, then long tail.

| Wave | Categories | Notes |
|------|------------|-------|
| attract | `--priority=attract` | Curated pool first |
| W1 | `generative` | Remaining generative |
| W2 | `simulation`, `interactive-mouse` | Multipass flagships + user-facing interaction |
| W3 | `visual-effects`, `distortion`, `liquid-effects`, `image`, remainder | Non-generative shaders use `public/fixtures/thumbnail-scene.png` |

### Campaign plan — 50% checkpoint (baseline 2026-09-13)

Baseline from a fresh integrity audit (`python3 scripts/audit_thumbnail_integrity.py`, then
`node scripts/check-thumbnail-coverage.js`), against the current catalog:

| | Count |
|---|---|
| Catalog (unique list ids) | 1,365 |
| Eligible (minus skip allowlist) | 1,364 |
| PNG + manifest | 360 |
| Integrity-flagged (`black_frame`) | 77 — generative 56, visual-effects 21 |
| **Healthy** | **283 (20.7%)** |
| **50% checkpoint** | **682 healthy — +399** |

The older "360 / 26.6%" figure counted the 77 black PNGs as healthy, because that report
ran against a stale audit. Always audit before quoting a percentage.

Remaining non-healthy shaders by category (eligible − healthy): interactive-mouse 239,
generative 224 (incl. 56 black), advanced-hybrid 166, artistic 96, image 91, distortion 61,
simulation 44, retro-glitch 33, liquid-effects 29, post-processing 28, visual-effects 22
(incl. 21 black), hybrid 18, geometric 16, lighting-effects 15.

| Step | Scope | Healthy after | Command |
|------|-------|---------------|---------|
| C0 repair | 77 flagged PNGs, the attract gap (`gen-ethereal-cyber-chrono-nebula-phoenix`), and the 12 ids with no thumb and no deferral (below) | ~373 (27%) | `bash scripts/run-thumbnail-waves.sh --wave=attract` |
| C1 | rest of `generative` + `visual-effects` | ~529 (39%) | `--missing --category=generative`, then `visual-effects` |
| C2 | `simulation` + small families: `lighting-effects`, `geometric`, `hybrid`, `liquid-effects`, `post-processing` | ~679 (49.8%) | one `--category=` run per family |
| **C3 — 50% checkpoint** | first `interactive-mouse` shard to cross 682 | **≥682 (50%)** | `--missing --category=interactive-mouse --limit=20` |

C2 deliberately covers the small families before content work (upgrade batches for
lighting/geometric/hybrid). The picker should show them with real pictures first.

At the checkpoint: re-run the audit, refresh `reports/thumbnail_coverage.md`, drop
`continue-on-error` from the regression job (see CI below), and write the monthly snapshot.
Then continue with `interactive-mouse`, `advanced-hybrid`, `artistic`, `image`, `distortion`,
and `retro-glitch` toward 80% (1,092).

Ids with no healthy thumbnail and no deferral as of the baseline (gen-* unless noted):
`gen-aetherial-plasma-loom`, `gen-bioluminescent-neural-lattice`,
`gen-chronomorphic-glass-tesseract`, `gen-hyperdimensional-bismuth-lattice`,
`gen-hyperdimensional-plasma-loom`, `gen-liquid-metal-cymatic-resonator`,
`gen-liquid-neon-topography`, `gen-luminescent-nebula-silk-weaver`,
`gen-neutron-star-magnetic-spindle`, `gen-sentient-bismuth-hypercrystal`,
`gen-sentient-void-silk-nebula`, `gen-symbiotic-cyber-mycelium`.

**Deferral expiry is a scheduled gate, not a push gate (since 2026-10-18).** Expiry used to fail
`verify:thumbs-deferrals` on every push and PR, so a calendar date turned unrelated PRs red with
no code change; that cliff was defused by hand twice (2026-09-26 for the 09-29 wave, 2026-10-18 for
the 10-26 wave of 39). The gate now has two modes (`checkDeferrals({ expiryMode })` in
`scripts/lib/thumbnailDeferrals.js`):

| | Push mode (default) | `--expiry` |
|---|---|---|
| Where | `verify:toolchain-foundation` (`test` job, every push/PR), `thumbs:check-regression` (PR job, capture farm) | `thumbnail-coverage-status.yml`, Mondays 09:17 UTC |
| Schema, reasons, 30-day span, renewals, ratchet | error | error |
| Row past `expires` | one warning: `N deferral(s) expired — the scheduled expiry job owns this` | error |
| Past-dated row that is new or re-dated vs the base ref | error (introduced-expired) | — |
| Within 7 days | — | warning |
| Next expiry date | — | printed (`next expiry YYYY-MM-DD`) |

```bash
node scripts/verify-thumbs-deferrals.js [--expiry] [--base-ref=<gitref>]
THUMBS_DEFERRALS_NOW=YYYY-MM-DD      # override today (tests, previewing a cliff)
THUMBS_DEFERRALS_BASE_REF=<gitref>   # same as --base-ref; the flag wins. CI sets this in the test job
```

The introduced-expired rule needs a base list: same id with the same past date is grandfathered,
so rows that merely aged never fail a PR, but nobody can commit a pre-expired entry. Without a base
ref (local runs, a new branch) it is skipped. An unresolvable base ref exits 1.

The scheduled run goes red on an expired row and upserts one comment on issue #921 whose first
line is `<!-- thumbnail-deferral-expiry-sticky -->` (verifier output, expired/expiring ids with
reason, renewals and `failure_note`, and the disposition commands); it is refreshed on green runs
too. GitHub cron is best-effort, so the push-mode warning line is the backstop in every CI log.

Disposition is removal or capture, not bulk renewal: expired ids simply become "Missing", which is
the honest meaning of expiry. **Next expiry: 2026-11-10** (`gen-liquid-metal-chrono-flora`;
4 entries remain, see the 2026-10-18 disposition below).

In the picker, authors can use the dev-only **Needs thumb** filter in `ShaderGallery` to list
shaders without a healthy thumbnail (manifest + `public/thumbnails/unhealthy.json`).

Example W1:

```bash
npm run build
npm run thumbs:generate -- --missing --category=generative
npm run thumbs:status
git add public/thumbnails/
```

`thumbs:status` reports both nominal manifest/file coverage and integrity-adjusted
healthy coverage when the checked-in audit fingerprint matches the current PNG set.
Use `npm run thumbs:status -- --require-priority` after a GPU wave to make the
curated attract and Physics Lab pool requirement blocking; the default status
command remains reporting-only for Cloud VM checks.

Check one monthly snapshot into `reports/thumbnail-coverage-YYYY-MM.md`; include
catalog/eligible/healthy counts, integrity reasons, skip justifications, and the
GPU host or execution ceiling used for that month.

Commit PNGs + `manifest.json` in category-sized PRs to keep diffs reviewable.

### PNG vs healthy reconciliation (2026-09-26)

`public/thumbnails/` holds **360** PNGs (not ~362), and the report's 283 healthy is correct: the
difference is exactly the 77 integrity-flagged PNGs. Produced with
`python3 scripts/audit_thumbnail_integrity.py` and `node scripts/thumbnail-coverage-status.js`
(the audit's PNG fingerprint matches the committed `reports/thumbnail_integrity_audit.json`; a
re-run changed only `generated_at`, so that file was not re-committed). Report only, no PNG was deleted.

| | Count |
|---|---|
| Catalog ids (`public/shader-lists`) / eligible | 1,373 / 1,372 (1 skip-allowlisted) |
| PNG files on disk | 360 |
| Manifest entries (`public/thumbnails/manifest.json`) | 360 |
| Flagged `black_frame` | **77** (generative 56, visual-effects 21) |
| Flagged magenta | 0 |
| PNG without a manifest entry | 0 |
| Manifest entry without a PNG / not in the catalog | 0 / 0 |
| Orphan PNG (id not in any list) | 0 |
| **Healthy** (PNG + manifest + not flagged) | **283 = 360 − 77 (20.6% of 1,372 eligible)** |

All 77 black PNGs belong to ids that are still `gpu-capture-pending` (they are part of the 234
renewed entries), so they are counted as deferred, not as coverage. The 234 pending split into
77 with a black PNG and 157 with no PNG at all; none of them is healthy.
Not-healthy eligible = 1,089 = 234 deferred + 855 "Missing" (no healthy PNG, no deferral).

### 2026-10-05 SwiftShader capture station log

Host: the Cloud VM (8 cores, no GPU), Playwright Chromium + SwiftShader (`--adapter=swiftshader`),
3 parallel shards plus retry passes, 30 warm-up frames (120 for simulation/multipass ids),
render scale 0.25 (512²), every non-generative shader over `fixtures/thumbnail-scene.png`.
Throughput was about 1.8 captures/min across the 3 shards (30-70 s per shader per browser).

| | Before (main, 2026-10-05) | After |
|---|---|---|
| Healthy eligible | 277 / 1,378 (20.1%, after the `flat_frame` rule) | **1,265 / 1,379 (91.7%)** |
| Integrity-flagged PNGs | 85 (74 black, 11 flat) | 22 (17 black, 5 flat) |
| `gpu-capture-pending` deferrals / ratchet | 234 / 234 | **40 / 40** (target 200) |
| PNGs tagged `capture_host: swiftshader` | 0 | 994 |

Every new PNG was reviewed on contact sheets before commit. Not healthy (114 eligible ids):

- **black_frame (55)** and **flat_frame (29)** at default params on SwiftShader. 13 of the 55 black
  ones were also black when captured on a real GPU in 2026-06; the other 42 had never been captured.
  Black or flat on SwiftShader is strong evidence of a shader problem at default params but not
  proof: a GPU recapture should confirm before anything is filed as a content bug. black: `aerogel-smoke-hdr`, `alpha-fire-temperature`, `audio-reactive-rgb-dispersion`, `boids`, `bubble-chamber`, `cellular-automata-rgba`, `charcoal-rub-diffusion`, `chromatic-manifold-2`, `conv-guided-video-filter`, `double-exposure-hdr`, `elastic-chromatic-explosion`, `emergent-calligraphic-weave`, `fire-smoke-volumetric-fog`, `flow-sort`, `fractal-boids-field`, `gen-cellular-automata-tapestry`, `gen-dragon-curve`, `gen-fireworks-crackle-palm`, `gen-grok41-plasma`, `gen-hyper-geometric-void-glass-seraph`, `gen-hyperdimensional-bismuth-lattice`, `gen-lenia-2`, `gen-lichen-reaction-diffusion`, `gen-live-studio-tab`, `gen-neural-dust`, `gen-prismatic-aether-loom`, `gen-prismatic-quantum-glass-chrysalis-engine`, `gen-psychedelic-time-warp-kaleidoscope`, `gen-rainbow-icosahedron-cascade`, `gen-velocity-bloom`, `ink-bleed`, `interactive-film-burn`, `interactive-magnetic-ripple-em`, `liquid-optimized-pass1`, `liquid-rainbow`, `liquid-smear`, `long-exposure`, `magnetic-flux-garden`, `molten-gold`, `mouse-time-crystal`, `nano-repair`, `nebula-gyroid`, `neon-cursor-trace`, `particle-disperse`, `pixel-depth-sort`, `plastic-bricks`, `pp-sharpen`, `quantum-foam-pass1`, `quantum-smear`, `retro_phosphor_dream`, `spatio-temporal-3d-conv`, `spec-spherical-harmonics-light`, `temporal-frequency-decomposition`, `tile-twist`, `velocity-field-paint`.
  flat: `alpha-multi-state-ecosystem`, `chromatic-folds-gemini`, `gamma-ray-burst-blackbody`, `gen-crystal-caverns`, `gen-cyclic-automaton`, `gen-fractal-flame-classic`, `gen-julia-set`, `gen-neon-plasma-chrono-bloom`, `gen-quantum-neural-lace`, `gen-reaction-diffusion`, `gen-sentient-cyber-chrono-void-serpent`, `gen-symbiotic-cyber-fungal-core-reactor`, `gen-symbiotic-cyber-mycelium`, `gen-temporal-motion-smear`, `gen-thermal-rainbow-topography`, `gen-xeno-mycelial-resonance-web`, `glitch-ripple-drag`, `hybrid-spectral-decomposed`, `ink-bleed-fluid`, `kimi-fractal-dreams`, `liquid`, `liquid-viscous`, `luma-melt-interactive`, `neon-quantum-lattice`, `optical-feedback`, `quad-mirror`, `recursive-ancestral-terrains`, `stellar-plasma-blackbody`, `symbiotic-light-propagation-networks`.
- **timeout / load failure (30)**: heavy kernels (non-local means, Gabor, frequency-domain notch,
  Lenia variants, slime moulds) exceed the 5-minute per-shader budget on SwiftShader, or wedge the
  device. A GPU host should capture these: `anisotropic-kuwahara-nlm`, `artistic_painterly_oil`, `bio_lenia_continuous`, `bitonic-sort`, `conv-difference-of-gaussians-cascade`, `conv-fractal-kernel`, `conv-frequency-domain-notch`, `conv-gabor-texture-analyzer`, `conv-non-local-means`, `cyber-scan-gabor`, `divine-light-gpt52`, `fractal-noise-dissolve-nlm`, `gen-cybernetic-ferro-coral`, `gen-cymatic-quantum-silk-loom`, `gen-image-pyro`, `gen-luminescent-aether-plasma-nebula-koi`, `gen-luminescent-nebula-silk-weaver`, `gen-orb`, `gen-quantum-singularity-forge`, `gen-resonant-crystal-canyons`, `gen-resonant-quantum-plasma-dragon-eye`, `gen-symbiotic-plasma-reef-matrix`, `gen-trails`, `hybrid-particle-fluid`, `kimi-flock-symphony-em`, `kimi-nebula-depth`, `lenia-on-video`, `painterly-oil-bilateral`, `sim-slime-mold-growth`, `sim-slime-mold-growth-em`.

Low-information captures that pass the checks (washed-out near-white fields, dense noise, a lone
sprite on black). They count as healthy but are worth a content look: `chromatic-folds-bilateral`, `gen-bismuth-citadel-crystal`, `gen-fractal-chrono-dendrite-forge`, `mirror-dimension`, `melting-oil-blackbody`, `alpha-em-field-simulation`, `gen-image-pixel-detonation`, `alpha-erosion-terrain`, `gen-singularity-forge-blackbody`, `gen-grok4-life`, `gen-grok4-perlin`, `chromatic-folds-2`, `gen-liquid-metal-cymatic-resonator`, `engraving-stipple-blue-noise`, `gen-hyper-dimensional-bismuth-matrix`, `rgb-fluid`, `photonic-caustics-iridescence`, `gen-fluffy-raincloud`, `cellular-automata-3d`, `gen-eldritch-tesseract-hive-mind`, `pp-vignette`, `sim-decay-system-rgba`, `gen-flame-fractal-attractor`, `gen-sentient-ferro-silicate-swarm`, `chromatic-folds`, `gen-radiant-cyber-chrono-void-stag`, `gen-fireworks-dahlia-burst`, `dimension-slicer-guided`, `bio-lenia-rgba`, `gen-crystalline-nebula-weaver-forge`.

Deferrals: the 194 deferred ids that now have healthy thumbnails were removed with
`scripts/thumbs-farm-finalize.js`; the remaining 40 are ids above that failed and still expire on
2026-10-26 (renew only with a `capture_failure` note, or let them lapse to "Missing"). 39 of them
were removed on 2026-10-18 (see the 2026-10-18 disposition below).
`kimi-fractal-dreams` (flat white at default params) left the attract pool.

Harness fixes found while doing this (all in `scripts/generate-shader-thumbnails.js`,
`scripts/lib/thumbnailHarness.mjs`): health measured on the committed PNG instead of a blank
compositor canvas; non-generative effects get an input image (most list entries have no
`category`); list `url` used for the WGSL; feedback textures reset per shader; remote requests
blocked; warm-up counts rendered frames; the app reloads (or a new page opens) after a wedged
shader; the manifest is flushed per capture so shards can run in parallel and survive interruption.
`check-thumbnail-coverage.js` read base-ref shader lists through a 1 MB pipe buffer, so large lists
silently vanished and hundreds of old shaders looked "newly eligible"; fixed (256 MB buffer, lists
first).

## CI

Manual workflow: **Actions → Generate Thumbnails → Run workflow**

The default GitHub runner has no GPU; the job runs a `--limit=5` smoke capture and uploads artifacts. For full batch runs, use a self-hosted runner with the `webgpu` label (see `.github/workflows/generate-thumbnails.yml`).

Pull requests that add shader definitions run `npm run thumbs:check-regression`.
The check compares the PR with the base branch and **fails only** when a newly eligible
id has no healthy PNG (PNG + manifest + not integrity-flagged) and no unexpired deferral,
or when a previously healthy PNG is deleted. Global coverage **percentage and count are not gates**.

Healthy eligible coverage passed 50% on 2026-10-05 (91.7%), so the PR job is **blocking**
(`continue-on-error` dropped, `set -o pipefail` so the `tee` cannot hide the exit status).
The sticky comment step stays non-blocking. The weekly coverage workflow's status report is
reporting-only, but its deferral `--expiry` step fails the run on an expired deferral (see above).

### Deferral Mechanism

When a PR adds a shader definition but cannot provide a healthy thumbnail (e.g., pending GPU capture), add a deferral entry to `reports/thumbnail_deferrals.json`:

```json
{
  "entries": [
    {
      "id": "gen-shader-name",
      "added_by": "author",
      "deferred_at": "2026-09-21",
      "expires": "2026-10-21",
      "reason": "gpu-capture-pending"
    }
  ]
}
```

- `reason` is one of `gpu-capture-pending | known-magenta | other` here. `audio-only` / `interactive-no-still` are permanent → `thumbnail_skip_allowlist.json`, and the gate rejects them in this file
- `expires` (or `until`) must be ≤ 30 days from `deferred_at`; the entry is valid through that day. Expired entries fail `verify-thumbs-deferrals.js --expiry` (the scheduled job) and only warn in push mode (`verify:toolchain-foundation`, `thumbs:check-regression`); committing an entry that is already past fails push mode against the base ref. Do not bulk-bump dates
- Renewing: `renewals` increments and `renewed_at` is set; a second renewal requires a `failure_note` describing the captured failure. Never hand-edit this file — use the writer below
- `reports/thumbnail_deferral_ratchet.json` caps the `gpu-capture-pending` count (`maxGpuCapturePending`, target 200). Lower it after each wave, never raise it (`defer-thumbnail.js ratchet` refuses to). It is currently **2** (2026-10-18). `target` is printed, never compared
- Deferrals never count as coverage. Attract pool and gallery CLIP ranking use healthy thumbnails only
- Each deferral should correspond to an eligible shader without a healthy thumbnail
- Deferrals are distinct from skip allowlist: skip IDs are permanent (unrenderable), deferrals are temporary (pending thumbnail)
- Capture farm: `.github/workflows/thumbs-capture-farm.yml` (self-hosted `gpu` runner only, ≤80 shaders/run, integrity-gated PR)
- After a GPU capture wave, remove deferrals for ids that now have healthy PNGs
- `--expiry` warns (exit 0) when any entry expires within 7 days, printing the count and earliest date, and always prints the next expiry. `THUMBS_DEFERRALS_NOW=YYYY-MM-DD` overrides "today" for reproductions and tests (including the "unexpired" count in `check-thumbnail-coverage.js`); CI never sets it

### Deferral writer

[`scripts/defer-thumbnail.js`](../scripts/defer-thumbnail.js) is the only sanctioned writer for
`reports/thumbnail_deferrals.json`. It sorts by id, writes 2-space JSON with a trailing newline,
and takes `--dry-run` on every subcommand (prints the diff summary, writes nothing).

```bash
node scripts/defer-thumbnail.js add <id> --reason=gpu-capture-pending|known-magenta|other [--days=N<=30]
node scripts/defer-thumbnail.js renew <id...> | --category=<name> | --ids-file=<path>  --note="<failure_note>"
node scripts/defer-thumbnail.js remove <id...> | --expired | --category=<name>
node scripts/defer-thumbnail.js reclassify <id> --reason=audio-only|interactive-no-still --why="<evidence>"
node scripts/defer-thumbnail.js ratchet [--to=N]     # lower maxGpuCapturePending; default = current pending count
```

- `--category=<name>` reads `public/shader-lists/<name>.json`; `--category=attract` reuses the
  generator's `--priority=attract` source (`loadAttractPriorityIds` → `src/app/constants/attractShowcasePool.ts`).
  A category only selects ids that are actually deferred.
- `renew` sets `deferred_at` = `renewed_at` = today and `expires` = today + 30, increments
  `renewals`, and is refused without `--note` when an id's renewals would exceed 1.
- `reclassify` moves the id out of the deferrals into `reports/thumbnail_skip_allowlist.json`
  (`ids` + `reasons`); `--why` must be headless evidence (e.g. the shader outputs black without audio).
- `add` refuses permanent reasons, unknown ids, duplicates, and anything that would push
  `gpu-capture-pending` above the ratchet. `ratchet` can only lower the cap, and not below the current pending count.
- Tests: `scripts/defer-thumbnail.test.js` and `scripts/verify-thumbs-deferrals.test.js` (part of
  `npm run thumbs:test`, a step of the CI `test` job; temp files only).

### 2026-09-29 deferral disposition (run 2026-09-26)

Issue #1312 track A. No self-hosted GPU runner exists, so nothing here captured a thumbnail.

| Bucket | Count | Notes |
|---|---|---|
| Reclassified → skip allowlist | **0** | No id could be evidenced headlessly as audio-only / interactive-no-still (see below) |
| Renewed once (→ 2026-10-26) | **234** | generative 212 + visual-effects 22; attract 0 (no attract id is deferred, and a Jest test asserts that) |
| Removed (now "Missing") | **835** | every other entry; all were `gpu-capture-pending` |
| **Remaining pending** | **234** | ratchet lowered 1069 → **234** (target 200) |

Reclassify evidence: the capture harness passes mouse (0.5, 0.5), no click, and a zeroed plasma
buffer. A static sweep of all 1,069 deferred WGSL files found none that read audio without also
using time or the input image, and none that write black unless the mouse is down. The audio-named
candidates (`audio-*`, `gen-audio-spirograph*`, `gen-fireworks-audio-symphony`) all draw a
visible base at zero audio (stars/idle shells, spirograph rings, image pass-through), so their
black PNGs are capture failures, not audio-only shaders. For the interactive `mouse-*`/`*-drag`
family the sweep found no early-out that writes black unless the mouse is down; they were not
individually inspected beyond that, so per the owner's rule they were left as is.

Commands, in order (all through the writer; `--note` is
`no self-hosted gpu runner registered (gpu-required.yml / thumbs-capture-farm.yml); next capture wave`):

```bash
N="no self-hosted gpu runner registered (gpu-required.yml / thumbs-capture-farm.yml); next capture wave"
node scripts/defer-thumbnail.js renew --category=attract --note="$N"          # 0 ids deferred
node scripts/defer-thumbnail.js renew --category=generative --note="$N"       # 212
node scripts/defer-thumbnail.js renew --category=visual-effects --note="$N"   # 22
THUMBS_DEFERRALS_NOW=2026-09-30 node scripts/defer-thumbnail.js remove --expired   # 835
node scripts/defer-thumbnail.js ratchet                                        # 1069 -> 234
```

The removal ran with `THUMBS_DEFERRALS_NOW=2026-09-30` because the un-renewed entries were not
yet expired on 2026-09-26 (they expire 09-29); a plain `remove --expired` would have removed
nothing and left the cliff in place. This removed them three days early.

Afterwards `node scripts/check-thumbnail-coverage.js` reports 283 healthy / 234 unexpired
deferrals / 855 missing (1,372 eligible). Reproduce the cliff with
`THUMBS_DEFERRALS_NOW=2026-09-30 node scripts/verify-thumbs-deferrals.js` (exit 0).

### 2026-10-26 deferral disposition (run 2026-10-18)

39 of the 41 `gpu-capture-pending` entries (the SwiftShader-wave failures, all `renewals: 1` with a
`failure_note`) expired 2026-10-26, which would have turned every push, PR and farm run red from
2026-10-27. They were **removed, not renewed**; they now count as Missing. A GPU re-capture pass
(one-off GPU runner + `thumbs-farm-finalize.js`, so clean PNGs un-Missing themselves) is a
separate follow-up, not a precondition.

```bash
THUMBS_DEFERRALS_NOW=2026-10-27 node scripts/defer-thumbnail.js remove --expired --dry-run   # 39 ids
THUMBS_DEFERRALS_NOW=2026-10-27 node scripts/defer-thumbnail.js remove --expired
node scripts/defer-thumbnail.js ratchet                                                      # 41 -> 2
node scripts/check-thumbnail-coverage.js --base-ref origin/main
THUMBS_DEFERRALS_NOW=2026-10-27 node scripts/verify-thumbs-deferrals.js --expiry             # next expiry 2026-11-10
```

Remaining (4): `gen-liquid-metal-chrono-flora` (pending, 2026-11-10), `gen-acoustic-obsidian-resonator`
(`other`, 2026-11-11), `gen-aetheric-tachyon-lattice` (`other`, 2026-11-14), `gen-synaptic-void-weaver`
(pending, 2026-11-15). The two `other` rows ("Needs WebGPU to render") are valid and kept.
`reports/thumbnail_coverage.md` on that tree: 4 unexpired deferrals, 96 missing, 1,291 / 1,391
healthy; the committed integrity audit was stale for the current PNG set, so integrity flags were
not applied to those counts.

Removed ids: `emergent-calligraphic-weave`, `gen-cellular-automata-tapestry`, `gen-cybernetic-ferro-coral`, `gen-cyclic-automaton`, `gen-cymatic-quantum-silk-loom`, `gen-dragon-curve`, `gen-fireworks-crackle-palm`, `gen-fractal-flame-classic`, `gen-grok41-plasma`, `gen-image-pyro`, `gen-julia-set`, `gen-lenia-2`, `gen-lichen-reaction-diffusion`, `gen-live-studio-tab`, `gen-luminescent-aether-plasma-nebula-koi`, `gen-neural-dust`, `gen-orb`, `gen-prismatic-aether-loom`, `gen-prismatic-quantum-glass-chrysalis-engine`, `gen-psychedelic-time-warp-kaleidoscope`, `gen-quantum-singularity-forge`, `gen-rainbow-icosahedron-cascade`, `gen-reaction-diffusion`, `gen-resonant-crystal-canyons`, `gen-resonant-quantum-plasma-dragon-eye`, `gen-sentient-cyber-chrono-void-serpent`, `gen-symbiotic-cyber-fungal-core-reactor`, `gen-symbiotic-plasma-reef-matrix`, `gen-temporal-motion-smear`, `gen-thermal-rainbow-topography`, `gen-trails`, `gen-velocity-bloom`, `kimi-fractal-dreams`, `kimi-nebula-depth`, `magnetic-flux-garden`, `molten-gold`, `nebula-gyroid`, `retro_phosphor_dream`, `symbiotic-light-propagation-networks`.

## Related

- Generator: [`scripts/generate-shader-thumbnails.js`](../scripts/generate-shader-thumbnails.js)
- Harness: [`scripts/lib/thumbnailHarness.mjs`](../scripts/lib/thumbnailHarness.mjs)
- Test API: [`src/hooks/useTestHarness.ts`](../src/hooks/useTestHarness.ts)
- Parent issue: #1076
