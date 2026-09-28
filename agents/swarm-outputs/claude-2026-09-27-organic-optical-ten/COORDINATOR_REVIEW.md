# COORDINATOR_REVIEW — organic-optical-ten (2026-09-27)

Checklist per `docs/SHADER_UPGRADE_BATCH.md` §9, checked against BRIEFS.md + NOTES.md +
direct git diff spot-checks on 3 of the 10 files (jellyfish-swarm, bioreactor-bloom,
chromatic-metamorphosis) plus JSON diff review on all 10.

| # | Shader | Idea Card before edit | Ideas pointable in diff | Keep-verbatim held | Diff not ≥70% boilerplate | No shared overlay w/ others | A packing matches C-read | params unchanged | Springs/ripples native-only | Naga/extraBuffer/dead-sliders | Verdict |
|---|---|---|---|---|---|---|---|---|---|---|---|
| 1 | gen-abyssal-leviathan-scales | ✅ | ✅ (dispersion, molt scar, keel ridging) | ✅ | ✅ | ✅ | ✅ (unchanged, already correct) | ✅ | ✅ (used existing spring only) | ✅ | **PASS** |
| 2 | gen-bioluminescent-aether-pulsar | ✅ | ✅ (twin jets, shear striping, shockwave flare) | ✅ | ✅ | ✅ | ✅ (unchanged) | ✅ | ✅ (used existing spring only) | ✅ | **PASS** |
| 3 | gen-bioluminescent-aether-jellyfish-swarm | ✅ | ✅ (contraction, stinger glow, startle flash — verified in diff) | ✅ | ✅ | ✅ | ✅ (fixed: exact load) | ✅ | ✅ (no spring added, per FORBID) | ✅ | **PASS** |
| 4 | gen-bioreactor-bloom | ✅ | ✅ (mitosis split, necrosis creep, reactivity bloom — verified in diff) | ✅ | ✅ | ✅ (distinct from celestial-weave's ideas) | ✅ (fixed: packing lie resolved, verified in diff) | ✅ | ✅ (no spring/ripple added, per FORBID) | ✅ | **PASS** |
| 5 | gen-celestial-weave | ✅ | ✅ (thread glint, star parallax, constellation pulse) | ✅ | ✅ | ✅ (distinct from bioreactor-bloom) | ✅ (fixed: packing lie resolved) | ✅ | ✅ (no spring/ripple added) | ✅ | **PASS** |
| 6 | gen-chromatic-metamorphosis | ✅ | ✅ (stutter-hold, afterimage, seasonal lean — verified in diff) | ✅ | ✅ (largest floor lift, but ideas are >30% of diff) | ✅ | ✅ (fixed: A now written, verified in diff) | ✅ | ✅ (no spring on catalyst, per FORBID) | ✅ | **PASS** |
| 7 | gen-aetherial-plasma-loom | ✅ | ✅ (thread-memory ghosting, weft-catch spark) | ✅ (old ideas' code + header text preserved) | ✅ | ✅ | ✅ (fixed: genuine C read now backs the JSON's prior claim) | ✅ | ✅ (mouse deliberately un-sprung, respected) | ✅ | **PASS** |
| 8 | gen-bioluminescent-reaction-diffusion | ✅ | ✅ (pointer-wake reset, quorum ignition flash) | ✅ (RD/quench/flash code untouched) | ✅ | ✅ | ✅ (unchanged, raw fields, not tone-mapped) | ✅ | ✅ (no spring added) | ✅ | **PASS** |
| 9 | gen-celestial-quantum-glass-dragonfly | ✅ | ✅ (velocity bank, vortex flutter) | ✅ (thin-film/caustic/vortex code untouched) | ✅ | ✅ | ✅ (unchanged, display RGBA) | ✅ | ✅ (used existing spring only) | ✅ | **PASS** |
| 10 | gen-chromatic-oracle-jelly | ✅ | ✅ (tentacle wake, startle contraction, optional pupil dilation) | ✅ (swim/gaze/blink code untouched) | ✅ | ✅ | ✅ (unchanged) | ✅ | ✅ (drag stays spring-free, per FORBID) | ✅ | **PASS** |

## Result: 10/10 PASS

No file received a generic spring+ripple+IQ-palette overlay. Each shader's 2-3(+) ideas
are native to its own already-declared mechanism and distinct from every other file in
the batch — no cross-file cloning observed.

## Bugs fixed as bugs, not counted as "ideas" in the closeout framing

1. **gen-bioreactor-bloom** — A/C packing lie (A wrote raw fields, C was read as color).
2. **gen-celestial-weave** — same class of A/C packing lie.
3. **gen-chromatic-metamorphosis** — `dataTextureA` was never written at all; no ACES tonemap existed anywhere in the file.
4. **gen-aetherial-plasma-loom** — `dataTextureC` binding was declared but dead (never read), while both the WGSL comment intent and the JSON `features`/`feedbackPacking` claimed a temporal-feedback loop that did not exist; JSON also had 5 duplicated top-level keys silently shadowing themselves.

## Known limitation

Real-GPU visual QA was not performed — this Cloud VM has no WebGPU adapter (`navigator.gpu.requestAdapter()` returns null). All verification above is structural (naga, precommit gate, dead-slider/extraBuffer audits, catalog integrity, Jest, production build). This should be visually spot-checked on a machine with a GPU before considering the batch fully closed out.

## Process note for future batches

This batch deliberately included 4 shaders that already had a genuine `Ideas:` line from
a prior upgrade pass (Track B) — normally §5.3 says to skip these ("floor present,
already idea-rich → skip, do not bump the Upgraded date for hygiene"). The user explicitly
asked for all 10 of the originally-pasted IDs to be touched, so Track B treated the
existing ideas as immutable and added genuinely new, distinct ideas on top rather than
re-doing or diluting what was there. Future batches should default to skipping
already-idea-rich shaders unless a user explicitly asks otherwise.
