# Coordinator Review — Liquid Eight (2026-09-21)

Checklist: `docs/SHADER_UPGRADE_BATCH.md` §9. Column key as in the retro-glitch ten review.

| Shader | Card first | Ideas pointable | Keep holds | Not boilerplate | No shared overlay | A matches C | Params exact | No new spring/ripple | Gates | Verdict |
|---|:-:|:-:|:-:|:-:|:-:|:-:|:-:|:-:|:-:|---|
| `liquid-rainbow-prismatic` | ✅ | ✅ 2/2 | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | **PASS** |
| `luma-velocity-melt` | ✅ | ✅ 2/2 | ✅ | ✅ | ✅ | ✅ HDR | ✅ | ✅ | ✅ | **PASS** |
| `liquid` | ✅ | ✅ 2/2 | ✅ | ✅ | ✅ | ✅ raw | ✅ | ✅ precursor rides the existing loop | ✅ | **PASS** |
| `kimi_liquid_glass` | ✅ | ✅ 2/2 | ✅ | ✅ | ✅ | ✅ raw | ✅ | ✅ | ✅ | **PASS** |
| `liquid-oil` | ✅ | ✅ 2/2 | ⚠️ see below | ✅ | ✅ | ✅ raw | ✅ | ✅ | ✅ | **PASS w/ note** |
| `liquid-mirror` | ✅ | ✅ 2/2 | ✅ | ✅ | ✅ | ✅ raw | ✅ | ✅ | ✅ | **PASS** |
| `ink-marbling` | ✅ | ✅ 2/2 | ⚠️ see below | ✅ | ✅ | ✅ raw | ✅ | ✅ | ✅ | **PASS w/ note** |
| `liquid-displacement` | ✅ | ✅ 2/2 | ✅ | ✅ | ✅ | ✅ raw | ✅ | ✅ | ✅ | **PASS** |

**8 / 8 pass. 16 ideas, none shared.** The four template siblings (`liquid`, `kimi_liquid_glass`,
`liquid-oil`, `liquid-mirror`) each got physics that only makes sense for their own claim —
capillary dispersion + foam / TIR + seeds / displacement wake + streaks / glitter + rough reflection.
Swapping any pair of cards between them would be wrong on sight, which is the test.

## The two ⚠️ — deliberate replacements, declared in the cards

- **`liquid-oil`:** the pointer used to *lift* the film; it now *parts* it (trough + rim). That is the
  idea, not collateral — thick oil is displaced, not raised — but it inverts a behaviour a user may
  know. Named in the card, the WGSL comment and NOTES.
- **`ink-marbling`:** HEAD's ring-front push is removed and replaced by Jaffer's exact map. Keeping both
  would double-count the same outward motion. Named in the card, the WGSL comment and NOTES.

## GPU reviewer checklist

- **`liquid-displacement`** — vorticity confinement is a positive-feedback force. It's bounded
  (ε = turbulence·0.12, then HEAD's damping and ±1.1 clamp), but **run it at turbulence = 1 for a minute**
  and confirm it doesn't settle into a noisy boiling state. If it does, halve 0.12.
- **`liquid-mirror`** — glint density is a probability argument (~1 % of 3 px cells at rest), not a
  measurement. Check glints are sparse at rest and widen into a path when the surface is disturbed.
  If there's nothing at rest, lower the exponent from 600.
- **`kimi_liquid_glass`** — TIR fires where |gradient| exceeds about 0.26·tan(θc). Confirm it reads as
  bright lines on wave flanks, not a full-frame silver wash at high distortion.
- **`ink-marbling`** — Jaffer uses a fixed 1/60 s step. At other frame rates the drop still spreads to
  the same final radius, only at a different speed. The comb strength (0.0012/frame) is tuned by
  arithmetic, not by eye.
- **`luma-velocity-melt`** — check beads read as beads at melt-speed 0.005 (the default), and that
  ledge pooling needs real depth; it does nothing on a flat depth map, by design.
- **`liquid-rainbow-prismatic`** — at film-scale 0 the black film can cover most of the top half. That
  is correct physics for a very thin film, but check it doesn't read as "broken".

**Real-GPU visual QA outstanding for all eight.**
