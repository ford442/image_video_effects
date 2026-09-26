# Thumbnail Pipeline

Automated batch rendering of shader preview thumbnails for the gallery / mega-menu UX.

## Hardware requirements

Thumbnail generation **requires a real WebGPU GPU**. The script drives Chromium via Playwright and renders through the production WebGPU renderer.

| Environment | Works? |
|-------------|--------|
| Linux/macOS/Windows with Vulkan, D3D12, or Metal | Yes |
| Chrome / Chromium 121+ | Yes |
| GitHub `ubuntu-latest` (no GPU adapter) | No — smoke-only |
| Cursor Cloud VM (headless, no ICD) | No |
| `xvfb-run` alone | No — provides a display, not a GPU |

`xvfb-run` can help on headless Linux **when a GPU is present** but no display server is running.

## Prerequisites

```bash
npm ci
SKIP_WASM_BUILD=1 npm run build
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

Failure reasons: `black_frame`, `magenta_frame`, `error_frame`, `compile`, `pipeline`, `no_wgsl`, `gpu_unavailable`, `load_failed`, `capture_failed`.

Skipped shaders (intentional): listed in `reports/thumbnail_skip_allowlist.json` — excluded from generation queue and eligible coverage denominator.

## Coverage strategy (campaign target ≥50% healthy; 80% later)

**Do not capture on the Cloud VM** (no GPU adapter; black PNGs are not coverage). Run on a discrete-GPU workstation:

```bash
SKIP_WASM_BUILD=1 npm run build
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
| W3 | `visual-effects`, `distortion`, `liquid-effects`, `image`, remainder | Image shaders use `public/fixtures/thumbnail-sample.png` |

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

**Deferral cliff (defused 2026-09-26):** expiry *is* a hard gate. `verify:thumbs-deferrals`
fails when any entry has `expires < today`, and it runs in `verify:toolchain-foundation` on every
push and PR, so an un-actioned expiry turns CI red on every run with no code change. All 1,069
original deferrals were due to expire 2026-09-29. They were dispositioned once (below) rather than
bulk-extended. Expired ids that are not renewed simply become "Missing" in the report-only
coverage job, which is the honest meaning of expiry. **Next expiry: 2026-10-26** (all 234
remaining entries); the gate starts warning 7 days earlier (2026-10-19) and fails on 2026-10-27.
Renew only the categories in the next scheduled capture wave, 30 days at most, via the writer.

In the picker, authors can use the dev-only **Needs thumb** filter in `ShaderGallery` to list
shaders without a healthy thumbnail (manifest + `public/thumbnails/unhealthy.json`).

Example W1:

```bash
SKIP_WASM_BUILD=1 npm run build
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

## CI

Manual workflow: **Actions → Generate Thumbnails → Run workflow**

The default GitHub runner has no GPU; the job runs a `--limit=5` smoke capture and uploads artifacts. For full batch runs, use a self-hosted runner with the `webgpu` label (see `.github/workflows/generate-thumbnails.yml`).

Pull requests that add shader definitions run `npm run thumbs:check-regression`.
The check compares the PR with the base branch and **fails only** when a newly eligible
id has no healthy PNG (PNG + manifest + not integrity-flagged) and no unexpired deferral,
or when a previously healthy PNG is deleted. Global coverage **percentage and count are not gates**.

The CI job stays `continue-on-error` (reporting-only with a sticky PR comment) until
healthy eligible coverage is ≥ 50%; then drop `continue-on-error` so new-definition
failures block the PR. The weekly coverage workflow remains reporting-only until that flip.

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
- `expires` (or `until`) must be ≤ 30 days from `deferred_at`; expired entries fail `npm run verify:thumbs-deferrals` (also in `verify:toolchain-foundation` and `thumbs:check-regression`). Do not bulk-bump dates
- Renewing: `renewals` increments and `renewed_at` is set; a second renewal requires a `failure_note` describing the captured failure. Never hand-edit this file — use the writer below
- `reports/thumbnail_deferral_ratchet.json` caps the `gpu-capture-pending` count (`maxGpuCapturePending`, target 200). Lower it after each wave, never raise it (`defer-thumbnail.js ratchet` refuses to). It is currently 234
- Deferrals never count as coverage. Attract pool and gallery CLIP ranking use healthy thumbnails only
- Each deferral should correspond to an eligible shader without a healthy thumbnail
- Deferrals are distinct from skip allowlist: skip IDs are permanent (unrenderable), deferrals are temporary (pending thumbnail)
- Capture farm: `.github/workflows/thumbs-capture-farm.yml` (self-hosted `gpu` runner only, ≤80 shaders/run, integrity-gated PR)
- After a GPU capture wave, remove deferrals for ids that now have healthy PNGs
- The gate warns (exit 0) when any entry expires within 7 days, printing the count and earliest date. `THUMBS_DEFERRALS_NOW=YYYY-MM-DD` overrides "today" for reproductions and tests; CI never sets it

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
- Tests: `scripts/defer-thumbnail.test.js` (part of `npm run thumbs:test`, temp files only).

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
black PNGs are capture failures, not audio-only shaders. Interactive `mouse-*`/`*-drag` shaders
are image processors that still show the input at the harness's default mouse. Left as is.

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

## Related

- Generator: [`scripts/generate-shader-thumbnails.js`](../scripts/generate-shader-thumbnails.js)
- Harness: [`scripts/lib/thumbnailHarness.mjs`](../scripts/lib/thumbnailHarness.mjs)
- Test API: [`src/hooks/useTestHarness.ts`](../src/hooks/useTestHarness.ts)
- Parent issue: #1076
