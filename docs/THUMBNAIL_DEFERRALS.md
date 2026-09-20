# Thumbnail deferrals

`reports/thumbnail_deferrals.json` records shaders that are **eligible for a thumbnail but do not have a
healthy one yet**. This page is the policy; the machine-readable form is
[`src/contracts/thumbnail_deferrals.json`](../src/contracts/thumbnail_deferrals.json), enforced by
`npm run verify:thumbs-deferrals` (part of `verify:toolchain-foundation` and a **blocking** step of the
`thumbnail-coverage` CI job).

## What a deferral does and does not do

- It exempts a *newly eligible* shader from `thumbs:check-regression` while a GPU capture is pending.
- It does **not** count toward coverage. `reports/thumbnail_coverage.md` reports healthy PNGs only.
- The 2026-09-29 expiry of the original 1,069 entries was never a CI cliff: `check-thumbnail-coverage.js` only
  exits non-zero for newly-eligible shaders lacking a thumbnail/deferral and for deleted healthy PNGs, and the
  CI step is `continue-on-error: true`. What it *was* is the date the file silently stopped meaning anything.
  The gate below is what makes the dates mean something.

## Schema

| field | required | notes |
|-------|----------|-------|
| `id` | yes | catalog id; unique in the file |
| `reason` | yes | `gpu-capture-pending` \| `audio-only` \| `interactive-no-still` \| `known-magenta` \| `other` |
| `added_by` | yes | who/what created it |
| `deferred_at` | yes | `YYYY-MM-DD`, date of the latest write; may not be in the future |
| `expires` | yes | `YYYY-MM-DD`; must be after `deferred_at` and not before today |
| `first_deferred_at` | no | date of the original deferral, preserved across renewals |
| `renewals` | no (default 0) | how many times this entry was renewed |
| `capture_failure` | conditional | required for renewals beyond the allowance |
| `note` | conditional | required for every reason except `gpu-capture-pending` |

Keys are written in the order above and entries are sorted by `id`, so diffs stay readable.

The legacy reason string was `"gpu-capture pending"` (with a space). The enum is hyphenated. The gate rejects
the spaced form (and says what to use); `defer-thumbnail.js` normalizes it.

### `gpu-capture-pending` rules

1. `expires - deferred_at` is 1 to **30 days**.
2. An entry past `expires` **fails the gate**.
3. `renewals` up to **1** needs no evidence. Every renewal beyond that needs a `capture_failure` string
   (≥ 20 chars) containing a run URL or an ISO date of a real capture attempt. The gate checks the *shape*; a
   reviewer must check the attempt was real.

### Permanent skips are not deferrals

Shaders that can never produce a meaningful still belong in `reports/thumbnail_skip_allowlist.json`
(`{ ids, reasons }`, with a specific per-id reason). An id in the allowlist may not also be deferred.

## The ratchet

`pendingRatchet` in the contract is the maximum number of `gpu-capture-pending` entries. The gate fails if the
count exceeds it, and (in CI, via `--base-ref`) if the ratchet is *higher* than on the base branch. It only goes
down. Consequence: a new shader cannot be deferred once the file is at the ratchet: land its thumbnail, or free
a slot by landing another one. Renewing an existing entry does not change the count.

## Adding, renewing, removing

Never hand-edit the file. Use the writer (`npm run thumbs:defer --` is an alias):

```bash
# add (new id) or renew (existing id: renewals+1, fresh 30-day window from today)
node scripts/defer-thumbnail.js --id my-shader
node scripts/defer-thumbnail.js --ids-file ids.txt
# a renewal beyond the allowance needs evidence
node scripts/defer-thumbnail.js --id my-shader --capture-failure "run https://github.com/<org>/<repo>/actions/runs/<n>: no GPU adapter"
# other reasons need a note
node scripts/defer-thumbnail.js --id my-shader --reason interactive-no-still --note "why"
# after real thumbnails land
node scripts/defer-thumbnail.js --remove my-shader
node scripts/defer-thumbnail.js --lower-ratchet     # sets pendingRatchet to the current pending count
```

The writer refuses (exit 1, nothing written) anything `verify:thumbs-deferrals` would reject, including
exceeding the ratchet, unknown catalog ids for new entries, and skip-allowlisted ids. `--dry-run` previews.

## State recorded when this landed (2026-09-19)

- 1,069 entries migrated through the writer: `gpu-capture-pending`, `renewals: 1`, one fresh window
  (`2026-09-19` → `2026-10-19`), `first_deferred_at: 2026-08-30`. `pendingRatchet: 1069`.
- **Nothing was reclassified to the skip allowlist.** The catalog tags that look like candidates do not
  distinguish shaders that cannot produce a still: `mouse-driven` is on 896 of the 1,069 deferred shaders but
  also on 172 of the 281 (at measurement time) healthy ones; `audio-reactive` is on 207 healthy shaders; 12
  healthy shaders are multipass; the capture harness is multipass-safe. Only 1 catalog entry is a
  non-first pass of a chain (`tone-histogram-apply`), which the harness can capture as part of its chain.
  Without evidence, under-claiming is correct.
- **No deferred id has a healthy PNG**, so reconciliation removed nothing from the file.
- The 360 PNGs → 283 healthy gap is **77 `black_frame` PNGs** (recomputed independently with
  `audit_thumbnail_integrity.py`'s own analysis: 283 clean, 77 black, 0 magenta, identical to the committed
  audit). All 360 have a manifest entry and a catalog id; there were no manifest gaps or id/filename
  mismatches to fix. The 77 need a real recapture. They are all also in the deferral list. None were marked
  healthy.
- 16 eligible shaders have neither a healthy PNG nor a deferral (`Missing` in `thumbnail_coverage.md`). They are
  not added here: doing so would raise the ratchet above the current count.
- `thumbs:check-regression` exits 1 on `origin/main` itself: its base snapshot
  `public/shader-manifest-unified.json` holds 895 shaders, so everything added since reads as "newly eligible".
  Pre-existing, reporting-only in CI, and untouched here.

## Track B (GPU capture farm) is blocked

Landing real thumbnails needs a GPU. `.github/workflows/gpu-required.yml` is `workflow_dispatch` only with
`runs-on: ${{ inputs.runner_label || 'ubuntu-latest' }}`, and **no self-hosted `gpu` runner is registered**, so
dispatching it runs on `ubuntu-latest`, which has no GPU adapter. Until a GPU runner exists (or a human
captures locally per `docs/THUMBNAIL_PIPELINE.md`), the deferral count cannot fall, and every entry will hit
its second renewal with nothing but "no GPU" to cite. Track A (this gate) makes that visible; it does not fix it.

`docs/THUMBNAIL_PIPELINE.md` still shows the old hand-edited deferral example and the "expiry doesn't block" note;
this page supersedes them.
