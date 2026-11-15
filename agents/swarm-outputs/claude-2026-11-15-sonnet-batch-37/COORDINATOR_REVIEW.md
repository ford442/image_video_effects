# COORDINATOR REVIEW — sonnet/batch-37

Base origin/main 7f6ce638 + 8577b989 (prelude migration of rainbow-cloud + gen-solar-wind-ribbons, header-only). Cards: `BRIEFS.md` (committed 663d468c, before any WGSL). Method: 4 forks implemented → coordinator spot-checks (HEAD-vs-new renders, diff read) → 2 fresh unanchored reviewers re-rendered HEAD vs new at the **saved** slider defaults (the harness defaults to 1,1,1,1) → 14 findings routed back to the owning forks, reproduced, fixed → coordinator re-gated and re-timed on an idle machine.

## Verdict per file (against its Idea Card)
| File | Card ideas findable + visible | KEEP VERBATIM held | Verdict |
|---|---|---|---|
| gen-ethereal-cyber-aurora-mantis-shrine (1st) | 3/3 (curtain sky 33.6 %, chrome reflection 4.4 % = whole mantis, heartbeat ring 1–6 % by beat phase); AO skipped (optional) | geometry/params/camera/ripple warp yes; composition **flipped upright** (rescue R3, confirmed upside-down at HEAD) | PASS |
| rainbow-cloud (1st) | 3/3 (HG 35 %, Beer–Powder 77 %, corona 70 % > 0.02 after the reviewer fix) | 4 params + A pack yes; **density ramp retuned** — card said keep 0.35, but HEAD drew no cloud (alpha floor 0.03 at every slider; coordinator re-rendered HEAD at density 0.5/1.0 and confirmed) | PASS with deviation (owner to eyeball) |
| gen-emergent-calligraphic-weave | 2/2 (wet-edge ring 24 % dish after fix, fibre wicking 32 %) | earlier ideas 1–4, palette, history, 4 params yes; hard weave seams removed | PASS |
| kaleido-scope-grokcf1 | 2/2 (bounce 78 %, barrel 42 %, field stop 8.7 % of px) | A-texel (0,0) spring state untouched (idle spring settles identically at frame 300/900) | PASS (default ≈ −5 % luma, cooler) |
| liquid-chrome-ripple | 2/2 (capillary 42 % at idle, horizon env 99 %) | metal=0 reproduces HEAD env; all-off bit-identical | PASS |
| gen-solar-wind-ribbons | 2/2 (striations 32.6 %, flare 3.4 %) | ribbonCentre/KH/palette/4 params yes; **unrequested rescue**: nearest-*segment* instead of nearest-sample (thin ribbons were beads) | PASS (default +10 % luma) |
| hybrid-cyber-organic | 2/2 (wavefront 6.4 %, vias 9.4 %) | hex trick, earlier ideas, 4 params, A raw occupancy yes; **true hex-centre id** rescue changes 51 % of px | PASS (default look differs; growth bounded, ~30 % cells stay unlit) |
| gen-chromatic-oracle-jelly | 2/2 (canals 3.6 %, oral arms 4.1 %) | all 7 earlier ideas, masks, history, ACES yes | PASS |
| gen-liquid-cathedral-dream | 2/2 (bubbles 5.4 %, cord 22 %, motes ~7 %) | cames/drips/shafts/dichroic, history yes | PASS |
| molten-glass | 2/2 (incandescence 50 % of heat region after the reviewer fix, craquelure 27 %) | whole heat solver byte-for-byte; all-off bit-identical | PASS |

## Reviewer round (14 findings, all reproduced or explained)
Fixed: molten hot core flattened to a white disc (INCAND_GAIN 2.2 → 0.5); kaleido bounce attenuation twice the card (cap 4, field stop to corners); rainbow-cloud bass re-randomised the cloud (pivot about screen centre) and corona read as speckle not rings (periodic ring phase); hybrid top-edge stripes (±0.5 px border tolerance), unbounded via radius (cap 0.14, bit-identical at saved defaults), hard gate pop (crossfade); calligraphy wet-edge ring unreadable (hollow 0.30→0.60); solar striation seam (fade over 2.5 widths) and flare washing 14 ribbons white ((8/n)²); cathedral bubbles clipped at lattice lines, tier-index growth, reamy cord as mottling; jelly canal pulse wrap pop; molten crack ticks on bare photo; chrome shimmer (CAP_AMP 0.25).
Not reproduced / left: cathedral `tierId` precision (arithmetic reproduced, no visible effect, wrapped anyway); hybrid outline pops at HEAD's own `occupy > 0.5` rule.

## Cost vs HEAD (idle machine, min of drained frames, interleaved, median of 5 rounds)
hybrid 1.26 · solar-wind 1.27 · calligraphy 1.26 · cathedral 1.23 · liquid-chrome 1.11 · molten 1.11 · jelly 1.09 · aurora 1.08 (was 1.82 before the fog-crawl trim) · rainbow-cloud 1.08 · kaleido 1.05. All ≤ the 1.3× cap. Fork C's 1.5× for hybrid was measured under load average 15–28.

## §12.4 row budget
Rows used once each: Henyey–Greenstein (rainbow-cloud), Brown–Conrady (kaleido), deep-water dispersion (liquid-chrome-ripple), blackbody (molten-glass), paper granulation + wet-edge (calligraphy). Step-count AO not used. No row appears on two files. Everything else is native; no spring/ripple/IQ overlay was added to any file.

## Checklist (§9 / §12.7)
- [x] Cards written and committed before the WGSL diff (663d468c before 6aec9f9b)
- [x] Each numbered idea pointable via a `// ── Idea n` comment
- [x] KEEP VERBATIM holds (deviations listed above, each owner-visible)
- [x] Diff is not ≥ 70 % boilerplate (changes are idea code; the only plumbing is aurora's A/ACES/alpha, which the card required)
- [x] No generic overlay shared across files
- [x] A packing truthful and unchanged where HEAD was consistent; aurora newly A = ACES display RGBA
- [x] Saved params unchanged (JSON `params` untouched; aurora gained `features` + `x-meta.upgrade.params` only)
- [x] No springs/ripples added (existing ones kept)
- [x] naga-wasm 10/10, precommit 10/10, extraBuffer clean
- [x] No `fwidth`/`dpdx`; ACES inputs clamped ≥ 0

## Open for the owner
1. `lotus-complexity` (aurora shrine) is a **dead slider at HEAD** — layers ≥ 1 add nothing; left because fixing restructures the loop the card said to keep.
2. Large default-look changes: rainbow-cloud, aurora shrine, hybrid-cyber-organic, calligraphy (+19 % luma), solar-wind (+10 %), kaleido (−5 %).
3. Real-GPU visual QA and thumbnails (Shader Scanner → "Changed since last thumbnail"). Everything here is SwiftShader on a synthetic photo; click/ripple paths were reasoned from code or exercised in scratch renders only.
4. `audit:dead-sliders` scans 0 definitions for some JSONs (known blind spot); slider liveness was instead proven by 0→1 sweeps in every NOTES file.
