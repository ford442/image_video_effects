# Broadcast-Signal Twelve — Coordinator Review (2026-09-28)

Checklist per `docs/SHADER_UPGRADE_BATCH.md` §9. Structural checks were run by the coordinator on every file
(params byte-exact vs HEAD via python; `^//  Ideas:` and `^//  A packing:` present; zero `extraBuffer[...] =` writes;
no `plasmaBuffer[n>0]` reads outside comments; no `pow(x, 2.0)`; no sampler on dataTextureC; precommit gate 12/12;
`audit_extrabuffer` PASS; `audit_dead_sliders --files <12>` PASS, 0 new dead sliders). Idea line ranges below come from the
implementer notes (`notes-<id>.md`) and were spot-read.

| # | id | card written first | ideas pointable | KEEP VERBATIM holds | diff ≥70% boilerplate? | overlay shared w/ prev file? | A packing = C read | params exact | springs/ripples native | gates | verdict |
|---|---|---|---|---|---|---|---|---|---|---|---|
| 1 | vhs-chroma-bleed | yes | 3/3 (L217-238, 240-248, 250-260) | yes | no (+91/-22, ideas dominate) | no | display RGBA, no C read | yes | none (pointer push kept) | pass | **PASS** |
| 2 | vhs-jog | yes | 3/3 (L131-142+169-171, 179-194, 156-163) | yes | no (+80/-16) | no | pre-ACES linear + alpha; C as colour | yes | ripples = HEAD's slip bands | pass | **PASS** |
| 3 | vhs-tracking-mouse | yes | 3/3 (L123-147, 86-98, 149-155) | yes | no (+73/-57; spring removal is part of the delta) | no | display RGBA, no C read | yes | ripples = HEAD's click tears; held lock uses newest ripple timestamp as the press clock (flagged) | pass | **PASS** |
| 4 | signal-tuner | yes | 3/3 (L141-148, 127-136, 106-113+138-139) | yes | no (+79/-63) | no | pre-ACES linear + alpha; C as colour | yes | ripples = HEAD's retune rings | pass | **PASS** |
| 5 | crt-scanline-damage | yes | 3/3 (L84-123+130-132+145, 167-173, 126-133) | yes (no pointer added) | no (+79/-21) | no | pre-ACES linear + alpha; C as colour | yes | ripples = HEAD's degauss | pass | **PASS** (JSON drops `mouse-driven`) |
| 6 | scan-distort | yes | 3/3 (L208-221, 184-199, 152-182) | yes | no (+97/-60) | no | pre-ACES linear + display alpha; C as colour (HEAD's A.a bass env dropped, was dead) | yes | ripples = HEAD | pass | **PASS** |
| 7 | waveform-glitch | yes | 3/3 (L146-165, 42-63+140-143, 110-118) | yes | no (+87/-51) | no | pre-ACES linear + alpha; C as colour | yes | ripples = HEAD | pass | **PASS** |
| 8 | holographic-projection-failure | yes | 3/3 (L85-95+158+184-188+197, 151-154, 126-141) | yes | no (+67/-21) | no | pre-ACES linear + alpha; C as colour | yes (updatedParams defaults realigned to params) | none | pass | **PASS** — base-look change: fringes now concentric on emitter (card idea 1) |
| 9 | holographic-glitch | yes | 3/3 (L199-206, 166-181, 74-77+187-194) | yes | no (+76/-17) | no | pre-ACES linear + alpha; C 3 taps as colour | yes | none | pass | **PASS** (5 false feature tags removed) |
| 10 | phosphor-decay | yes | 3/3 (L210-217+283, 138-158+245-259, 231-238) | yes | no (+114/-58) | no | linear HDR phosphor RGB + burn-in in A.a; C read as that | yes | ripples = HEAD's click bloom | pass | **PASS** — HEAD was near-black; look changes by construction |
| 11 | cyber-terminal-ascii | yes | 3/3 (L67-93+154-157, 162-173, 136-146+182-183+198) | yes | no (+89/-49) | no | pre-ACES linear + coverage alpha; C as colour | yes | ripples = HEAD's burst | pass | **PASS** (default lens radius = HEAD's 0.155) |
| 12 | strip-scan-glitch | yes | 3/3 (L116-138, 164-178, 150-161) | yes | no (+113/-69) | no | pre-ACES linear + alpha; C as colour (HEAD had no C read; added for ideas 2-3) | yes | pointer already owned | pass | **PASS** — "brake" is a C freeze mix, not a speed ramp (documented) |

No file in the batch received a spring, an IQ palette, or a generic ripple shockwave. Every dead spring was removed.

## Deviations accepted
- vhs-chroma-bleed: small resting chroma-dropout rate added (HEAD's dropout rows only existed under bass).
- vhs-tracking-mouse: hold ramp keyed on the newest ripple timestamp; if the host only pushes ripples on click, lock engages instantly instead of ramping (visual still correct).
- signal-tuner: detune beat uses a fixed 48 rad/uv virtual raster (Frequency maxes at 100, never reaches res.y).
- strip-scan-glitch: held brake freezes via C rather than ramping speed (no persistent phase state exists).
- cyber-terminal-ascii: default lens radius reproduces HEAD's effective 0.155 (the brief's 0.1275 figure was a coordinator arithmetic slip).

## Not verified here
Real-GPU look. Every calibration constant flagged in `notes-<id>.md` under "GPU risks" is an analytic guess.
