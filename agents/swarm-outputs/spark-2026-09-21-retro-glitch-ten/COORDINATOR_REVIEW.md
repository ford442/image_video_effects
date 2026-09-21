# Coordinator Review — Retro-Glitch Ten (2026-09-21)

Checklist from `docs/SHADER_UPGRADE_BATCH.md` §9, applied per file.
`C` = card exists and predates the diff · `P` = each numbered idea is pointable in the WGSL ·
`K` = KEEP VERBATIM holds · `B` = diff is **not** ≥70 % header/ACES/spring/ripple boilerplate ·
`O` = no overlay shared with another file in the batch · `A` = A packing matches how C is read ·
`S` = saved `params` unchanged · `R` = springs/ripples only if native · `G` = gates green on this file.

| Shader | C | P | K | B | O | A | S | R | G | Verdict |
|---|:-:|:-:|:-:|:-:|:-:|:-:|:-:|:-:|:-:|---|
| `crt-phosphor-decay` | ✅ | ✅ 3/3 | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ none added | ✅ | **PASS** |
| `crt-magnet` | ✅ | ✅ 3/3 | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ none added | ✅ | **PASS** |
| `vhs-tracking` | ✅ | ✅ 3/3 | ✅ | ✅ | ✅ | ✅ raw sim | ✅ | ✅ none added | ✅ | **PASS** |
| `signal-noise` | ✅ | ✅ 3/3 | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ none added | ✅ | **PASS** |
| `byte-mosh` | ✅ | ✅ 3/3 | ✅ | ✅ | ✅ | ✅ raw state | ✅ | ✅ none added | ✅ | **PASS** |
| `xerox-degrade` | ✅ | ✅ 3/3 | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ none added | ✅ | **PASS** |
| `ascii-flow` | ✅ | ✅ 3/3 | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ stayed spring-free | ✅ | **PASS** |
| `pixelation-drift` | ✅ | ✅ 3/3 | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ none added | ✅ | **PASS** |
| `spectrum-bleed` | ✅ | ✅ 3/3 | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ none added | ✅ | **PASS** |
| `vinyl-scratch` | ✅ | ✅ 3/3 | ✅ | ✅ | ✅ | ⚠️ documented | ✅ | ✅ click made native | ✅ | **PASS w/ note** |

**10 / 10 pass. 30 distinct ideas, no idea repeated across files.**

## Anti-pattern sweep (§4)

1. *Hygiene as upgrade* — no. The floor was already present on all ten before this batch; that is
   precisely why they qualified as a second pass. Nothing in the diff is a binding, a workgroup
   size, an ACES helper, a `updatedParams` alignment or an `upgraded-rgba` stamp, with one
   exception: `spectrum-bleed`'s missing `upgraded-rgba` tag, added only because ideas landed.
2. *Reimagining* — no. Every file's modes, kernel family and param roles survive. Each shader still
   opens on the same picture.
3. *Generic overlay* — no. **Zero springs added, zero ripple loops added, zero IQ palettes added,
   zero conveyors added.** Three files (`crt-magnet` degauss, `vinyl-scratch` click,
   `xerox-degrade` C history) instead gave an already-present-but-inert mechanism a job.
4. *Param theft* — no. `git diff shader_definitions/` is one line: a feature tag. Every preset loads.
5. *Packing lies* — none introduced. Two raw-state files (`vhs-tracking`, `byte-mosh`) kept raw
   state and were not "promoted" to display RGBA. One pre-existing looseness was documented rather
   than silently changed (see note below).
6. *Line-count theater* — +484 / −77 across ten files, ~48 added lines each, roughly a third of
   which is the comment explaining which idea a block is. No file was padded to a target.

## Things a GPU reviewer must check (this VM has no adapter)

These are the places where the code is right structurally but the *picture* is unverified:

- **`crt-phosphor-decay`** — HEAD's triad mask was dead (`fract(uv.x * resX)` ≡ 0.5, a flat tint).
  It is now a real 3-pixel grille, so this file will look visibly different at high
  Scanline Intensity. That is the fix working, but it is the largest visual delta in the batch and
  should be eyeballed first. Also confirm the two-rate knee does not smear motion into mush at
  Decay Rate = 1.0 (`tailRate` is capped at 0.994, so it must not, but confirm).
- **`pixelation-drift`** — the block average costs 12 bilinear taps per pixel where HEAD took 3.
  Correctness win; check the frame cost at large block sizes on a low-end adapter.
- **`ascii-flow`** — the typed-cell wake latches differentially against a post-ACES history read,
  so its strength varies with scene exposure. Self-limiting by construction; confirm it fades
  rather than accumulating on a bright source.
- **`vinyl-scratch`** — (a) the eccentric centre also feeds `radialChromatic()`, so the CA centre now
  orbits with the record. Intentional and physically consistent, but it is a coupled change.
  (b) The scratch marks reconstruct the platter angle at click time as `age * rotationSpeed`, which
  ignores the mouse `scratchOffset` and the held jitter. Marks will therefore creep slightly while
  the user is dragging the record. Acceptable: recording it here rather than adding ripple state.
- **`crt-magnet`** — the warped grille can alias against the display at some resolutions. That is
  the point (it is moiré), but verify it does not shimmer when the pointer is at rest.

## Honest limitation

`⚠️` on `vinyl-scratch` A packing: HEAD stores display RGBA in A and reads `C.a` back as a
sparkle-coherence value — i.e. the semantic alpha doing double duty. That is looser than §8 wants
but it is not a lie that breaks the next frame, and rewiring it would change the look for reasons
unrelated to any Idea Card. It is now stated in the file header and in NOTES. Flagged for a future
pass, not fixed silently here.

**Real-GPU visual QA remains outstanding for all ten.**
