# Catalog count SoT: assert the derivable invariant, alias legacy IDs, split the extraBuffer baseline

> Expanded 2026-08-29 from the #1184 B-track draft, using three model reviews (Gemini Pro, Kimi K2, Grok) **plus a verification pass against the tree at `a27a627`**. The verification overturned part of the original premise — see "Corrections" below. Numbers here are measured, not carried.

## Context / motivation

Pixelocity's shader catalog reports four different totals depending on which artifact you read. Agents regenerate catalogs and cite whichever number they saw last; that ambiguity is the mechanism by which duplicate IDs and dead sliders enter the tree unnoticed. It is a prerequisite for authoring new WGSL compute shaders at volume and for multi-slot stacking, which resolves shaders by string ID.

**Measured on `a27a627`:**

| Signal | Count |
|---|---:|
| `shader_definitions/**/*.json` | **1,362** |
| Unique IDs across those definitions | **1,362** |
| Duplicate IDs | **0** |
| Multipass secondary definitions (`multipass.pass > 1`) | **13** |
| `public/shader-lists/*.json` entries | **1,349** |
| List IDs with no backing definition (orphans) | **0** |
| README advertised total | **1,291** (stale; 4 occurrences) |
| Underscore *IDs* | **22** |
| Underscore *filenames* carrying a hyphenated ID | **31** |
| ID ≠ filename mismatches (total) | **33** |
| Definitions carrying `multipass.graph` | **7** |

## Corrections to the original premise

Three claims in the parent issue do not survive contact with the tree. They are corrected here because two of them would have produced no-op work.

1. **"13 ID-vs-filename mismatches — most are legitimate graph parents" is wrong.** There are **33** mismatches and **zero** are graph parents; all 7 `multipass.graph` definitions have `id == filename`. 31 of the 33 are the cosmetic inverse case (underscore *filename*, hyphenated *ID* — e.g. `gen_wave_equation.json` containing `id: "gen-wave-equation"`). The remaining 2 are genuinely odd and need eyes: `gen-bioluminescent-abyss` in `bioluminescent-abyss.json`, and `galaxy-sim` in `galaxy.json`.
   **Consequence: the proposed "whitelist `multipass.graph` entries" step is a no-op and is dropped from this issue.** It would suppress nothing.

2. **The 13-count gap is real, but it is not graph parents — it is multipass *secondaries*.** The gap between definitions (1,362) and list entries (1,349) is exactly the 13 definitions with `multipass.pass > 1`: `vortex-pass2`, `quantum-foam-pass2`, `quantum-foam-pass3`, `rd-on-video-pass2`, `rd-on-video-pass3`, `liquid-pass2`, `liquid-optimized-pass2`, `aurora-rift-pass2`, `aurora-rift-2-pass2`, `digital-glitch-pass2`, `pyramid-bandprocess-pass2`, `pyramid-composite-pass3`, `spectrogram-displace-pass2`. These are secondary passes correctly excluded from the user-facing catalog — you pick `vortex`, not `vortex-pass2`.

3. **The catalog is structurally healthy; the *reporting* is what is broken.** Zero duplicate IDs, zero orphans, and the exclusion is already implemented and logged — `scripts/generate_shader_lists.js` tracks `skippedMultipassSecondaries` (line ~176) and `skippedDuplicates` (line ~183) and prints both. It simply never asserts them or exports them as data. That makes this a much smaller fix than the parent issue assumed.

**Also corrected:** the auditors are **Python**, not Node. They are `scripts/audit_extrabuffer.py` and `scripts/audit_dead_sliders.py`. There is no `audit-extrabuffer.mjs`.

## The invariant

The whole issue reduces to one assertion, verified true today:

```
definitions − multipass_secondaries − duplicates == shader_list_entries == manifest _meta.total_count
1362        − 13                    − 0          == 1349                == 1349
```

The pipeline is a three-hop chain and the parent issue compared hop 1 against hop 4, attributing the difference to the wrong cause:

```
shader_definitions/**  →  generate_shader_lists.js  →  public/shader-lists/*.json  →  build-unified-manifest.ts  →  shader-manifest-unified.json
       1362                  (drops 13 secondaries)            1349                     (reads CANONICAL_LIST_FILES)          1349
```

Note `build-unified-manifest.ts` reads `public/shader-lists/` via a hardcoded `CANONICAL_LIST_FILES` array of 14 category files — it does **not** walk `shader_definitions/`. It warns and silently continues on a missing list file (line ~87), which is a real silent-failure path worth closing.

## Proposed approach

### A — Assert the invariant (the core work)

1. Export the counts `generate_shader_lists.js` already computes. Emit a small machine-readable summary (definitions scanned, secondaries skipped, duplicates skipped, entries written per category).
2. Add `npm run verify:catalog-counts` asserting the equation above across all three hops. On failure it must print *which* hop lost entries and *which* IDs — the failure message is the deliverable, since the whole problem is that nobody could tell where the numbers diverged.
3. Make a missing entry in `CANONICAL_LIST_FILES` a hard failure rather than a warning, or assert that the 14 canonical categories exactly match the `shader_definitions/` subdirectories (they do today).
4. Wire it into CI **after** `build:manifest`.

### B — README total, without the churn

The README's four `1,291` occurrences are advertising, not inventory. Two changes:

1. Replace the precise number with a rounded floor (`1,300+`) in prose. It stays true for months and never conflicts.
2. If an exact number is wanted, put it behind a single generated marker (`<!-- catalog-count:start -->…<!-- catalog-count:end -->`) refreshed by a **post-merge job on `main`**, not a PR gate.

**Explicitly rejected: `git diff --exit-code README.md` as a PR gate.** This repo merges generative-shader PRs almost daily; a committed-artifact gate would red-build every one of them until the author rebuilds and pushes, and would conflict on the README on every content PR. The invariant in (A) needs no committed artifact — it is derived at build time from files the PR already changed — so it is conflict-free by construction. That is the whole reason to assert the invariant rather than the advertised number.

### C — Legacy ID aliases (build-side only here)

Generate `alias_map.json` for the 22 underscore IDs and embed it in the unified manifest's `_meta.aliases`. Alias only — **no file renames**, which would break VPS storage keys and CDN caching.

**A documentation-only alias map is not acceptable and is not what this issue ships.** All three reviews independently reached that conclusion: if nothing reads the map, old share URLs keep 404ing, which is the bug. But runtime resolution touches `src/`, which this issue is scoped away from. So this issue ships the *generated map*, and a follow-up issue ships the *resolver*. See "Follow-up" below. Do not close this issue believing legacy URLs are fixed — they are not, until the follow-up lands.

Separately, the 31 underscore *filenames* carrying hyphenated IDs are cosmetic and orthogonal to the 22 underscore IDs. Renaming those files changes nothing user-visible and is **out of scope** — call it out in the report, do not act on it.

### D — extraBuffer baseline split + dynamic-index triage

1. Restructure `reports/extrabuffer_write_audit_baseline.json` from its current flat `{generated, reason, entries}` shape into sectioned groups — `engine_owned`, `shader_bug`, `triaged_dynamic` — each with a `reason` field. Update `scripts/audit_extrabuffer.py` (Python) to parse the sectioned shape.
2. Do **not** blind-rewrite the 93 known FFT-zone owners; many are engine-documented audio behavior. The split is what makes the baseline safe to shrink later.
3. Triage the 32 dynamic-index writes into `triaged_dynamic` as **machine-readable JSON the auditor consumes**, each with the bound that makes it safe (`[133..255]`) or a note that it needs a bounded-slot rewrite. A markdown-only verdict would become a fifth disagreeing artifact. The rewrites themselves are out of scope.

### E — Optional stretch, needs Noah's call

Add JSON Schema validation of `shader_definitions/**/*.json` via `ajv` — required fields, param shape, and an ID pattern `^[a-z0-9]+(?:-[a-z0-9]+)*$` that stops the next underscore ID at authoring time rather than auditing it afterward. This is the one piece worth buying rather than writing.

**This requires a new devDependency (`ajv` / `ajv-cli`), which the Copilot brief otherwise forbids.** Only take it if Noah approves the dep. Schema validation alone would not have caught the count drift, so it is additive, not a substitute for (A).

## Acceptance criteria

- [ ] `npm run verify:catalog-counts` exists, asserts `definitions − secondaries − duplicates == list entries == manifest _meta.total_count`, and passes on the current tree (1362 − 13 − 0 == 1349).
- [ ] On failure it names the hop and the specific IDs lost, not just a mismatched integer.
- [ ] A missing `CANONICAL_LIST_FILES` entry fails the build instead of warning.
- [ ] The check runs in CI after `build:manifest`, and needs **no committed generated artifact** — no content PR is red-built by it.
- [ ] README no longer advertises a stale precise total.
- [ ] `alias_map.json` covers all 22 underscore IDs and is embedded at `_meta.aliases`; no shader file or storage key is renamed.
- [ ] `reports/extrabuffer_write_audit_baseline.json` is sectioned into `engine_owned` / `shader_bug` / `triaged_dynamic`, each entry carrying a reason; `audit_extrabuffer.py` parses it and still exits 0 (currently 0 new / 93 known).
- [ ] All 32 dynamic-index writes carry a machine-readable triage verdict.
- [ ] `audit:dead-sliders` still exits 0 (currently 0 new / 28 known).
- [ ] The 2 genuine ID/filename oddities (`gen-bioluminescent-abyss`, `galaxy-sim`) are resolved or documented.
- [ ] No changes to `src/`, `wasm_renderer/`, `public/shaders/`, `shader_definitions/**` content, device init, feedback order, or the WASM default.

## Out of scope

- Runtime alias resolution (follow-up — touches `src/`).
- Renaming the 31 underscore filenames.
- Migrating the remaining 8×8 workgroups — that is #1180.
- Rewriting the 32 dynamic-index writes (triage only).
- Any bundler migration. CRA/CRACO is deprecated upstream and is a real medium-term risk, but it is not this issue's problem and mixing the two would bury the audit.

## Follow-up issue to open alongside this one

**"Resolve legacy shader ID aliases at runtime"** — consumes `_meta.aliases` at the lookup boundary so old share URLs and saved presets resolve. Blast radius to work through, surfaced by the reviews:

- **Share/deep links** — `?shader=aurora_borealis` must resolve rather than 404.
- **localStorage** — saved VJ stacks and preset packs referencing underscore IDs need migration at hydration.
- **FastAPI backend** — if `storage_manager` validates incoming IDs against the manifest, the frontend must normalize before sending, or the backend must load the alias map too.
- **WASM renderer** — confirm nothing resolves shader identity by exact string on the C++ side.

Treat a missing alias as a CI failure once the map is declared complete.

## Open questions for Noah

1. **Rounded README total, or a generated exact marker?** I lean rounded — it is advertising copy, and a precise integer there is the thing that rots.
2. **The 2 odd ID/filename pairs**: is `galaxy-sim` in `galaxy.json` intentional, or a rename that never finished?
3. **Ajv dep (E)**: approve the devDependency, or defer schema validation entirely?
4. **Should the follow-up resolver land before or after #1180?** They touch disjoint `src/` paths (`ShaderCompilation.ts` / contracts vs. the shader-resolution path), so either order is safe — but sequencing them avoids two agents in `src/` at once.
