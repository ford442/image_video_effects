# BRIEFS — fork F (sonnet/batch-48): conv-guided-video-filter

Written BEFORE any WGSL edit. Baseline = worktree file at fork start (header-only identical to origin/main 2e876e2e), snapshotted to the scratch dir as `conv-guided-video-filter_head.wgsl`.

## HEAD diagnosis (measured on SwiftShader, `agents/mr.mjs` + a scratch variant that seeds C with a posterized/blurred/channel-shifted "processed" image and can hold C fixed like a prior chain slot)

| Case | Result at HEAD |
|---|---|
| Standalone / slot 1 / first frame (C = 0) | **pure black, forever** (meanL 0, stdL 0). P = 0 → a = b = 0 → q = 0 → written to A → C stays 0. |
| C = uniform grey seed, self-feed, 6 frames | meanL 0.725, stdL 0 — ACES fixed point (0.728). |
| Empty-C fallback only (scratch), self-feed 40 frames | meanL 0.728, stdL 0.002 → **flat grey**: ACES'd colour is stored in A and re-read as P next frame; ACES contracts it to its attractor (slope 0.37) at ~0.46/frame. |
| Same + un-ACES'd state in A (scratch), self-feed 40 frames | stable: meanL 0.444, stdL 0.145 — structure survives. |
| Chain case (C = processed image, fixed) | works, but **dark/bright overshoot rims around strong edges** (linear model `q = a·G + b` extrapolates past P's range — gradient reversal / halo). |
| Also | `result.rgb` (`a·G+b`) can be negative and goes straight into ACES (catalog ACES maps negatives bright). |

## Rescues (loud — they change the default look in the empty-C case only; chain look changes only through the two ideas)

- **R1 empty-C fallback.** Decided once per pixel: `useSrc = max(C.rgba at the pixel) <= 1e-5`; window taps then use `select(C.rgb, gRGB, useSrc)` (`gRGB` is already fetched, no new load) and the final blend uses the same test. Empty previous pass ⇒ the filter becomes the classic self-guided edge-preserving smoother of the source instead of black. A real prior pass (any non-zero C at the pixel) is untouched. (First written per tap; moved to per pixel after timing — pixel-identical output, ~0.1× cheaper.)
- **R2 clamp before ACES.** `max(q·(1+mids·0.15), 0)`.
- **R3 A packing.** A now carries the **pre-ACES** guided state (+ confidence α); `writeTexture` keeps HEAD's exact display formula (`mix(P, ACES(q), guideStr)`). Fixes the ACES-in-feedback contraction. Display in the chain case is formula-identical to HEAD; only what a *later* slot reads from C is un-tone-mapped (it was double-tone-mapped before).

## Idea Card

```
SHADER: conv-guided-video-filter
IDENTITY (one sentence): the previous pass's output (dataTextureC) re-fitted to the crisp source
  frame as an edge-preserving guided filter (He et al.) with a depth-augmented guide and a
  mouse "focus magnifier" — a colourist reads it as "restore the edges, kill the halos".
KEEP VERBATIM: single-window box local linear model q = a·G + b over the (2r+1)² window, per-channel
  a/b on P = dataTextureC (exact integer loads); guide G = mix(luma, depth, 0.35) [existing idea];
  params rad→radius 1..8 (1+i32(x·7)), eps→ε mix(0.0002,0.08,y), guide strength→mix(P,guided,z),
  mouse strength→exp(−d²·10) focus (radius→1, ε→0.05ε); bass→ε·(1−0.2·bass), mids→exposure
  1+0.15·mids; ACES on display; confidence α = |a|·2 → 0.75·conf + 0.25·src.a; depth pass-through;
  dataTextureB untouched; no spring / ripple / palette.
ADD (2 native ideas):
  1. Edge-aware ε weighting (weighted guided filter, Li et al. 2015 — §12.2A guided-filter row):
     Γ = (σ₃·σ_R + λ)/(χ_ref + λ) from the 3×3 sub-window of the *same* taps already looped and the
     window variance already computed; ε_eff = ε/Γ, Γ clamped [½, 4] with χ_ref = 0.0012 (first
     drafted as [¼, 4] / 0.004; recalibrated after measuring Γ's distribution — 96% of pixels sat on
     the floor, i.e. "ε×4 everywhere"). Flat regions get a larger ε (smoother, ≤ε×2), true edges a
     smaller one (≥ε/4, a→1, crisp) — the `eps` slider keeps its role as the base regulariser. Native: it is the regulariser of this exact estimator, promoted from a
     constant to a per-pixel quantity (tactics 3+4).
  2. Guide-gated anti-halo envelope (§12.2A anti-halo row, joint-range variant): track per-channel
     min/max of P over the window taps whose guide value is within τ = clamp(2·√ε, 0.06, 0.30) of the
     centre guide (same side of the edge); clamp q to [min−allow, max+allow], allow = 0.01 + 0.5·ε.
     The linear model can no longer extrapolate past P's own range on the pixel's side of an edge,
     which is exactly the overshoot ring seen in the HEAD render. (tactic 2: the first-order side
     effect of a guided filter is gradient-reversal halos; the header already promises "eliminating the
     halo artifacts".)
FORBID on this file: springs / click fronts / IQ palette / holographic scan / glow; any new param;
  changing the guide mix, window shape, mouse falloff or audio roles; promoting B; iterating the filter.
A PACKING: A = pre-ACES guided colour (display-range) + confidence α (R3); writeTexture = ACES display
  RGBA, semantic α unchanged.
```

## §12.1 mechanism interrogation

- **Tactic 1 (deepen the kernel).** The kernel is the centre-window variant of the guided filter; the next-better approximation is the mean-of-coefficients form, but that needs a/b at every neighbouring window (O(r⁴) or two passes) — rejected on cost. Within the single window, the better regulariser is ε/Γ (idea 1) and the better output bound is the range envelope (idea 2).
- **Tactic 2 (physics one step further).** Edge-preserving filters built on a *linear* model share one failure: the model extrapolates where guide contrast ≠ input contrast ⇒ overshoot rings. The real remedies are range clamping to the local input extrema and an edge-adaptive ε. Both are named in the literature of this exact filter.
- **Tactic 3 (promote an intermediate).** `varG` is computed and only used as a denominator; the 3×3 sub-window of the already-fetched taps gives the second scale for Γ. `count`/taps already hold P — min/max are two more reductions over the same values.
- **Tactic 6 (history the file owns).** C is read as colour P (display-range). The one continuity gained: do not feed the tone-mapped value back (R3) — a packing fix, not an idea.
- Tactics 4/5/7/8: ε becomes per-pixel (idea 1 is also tactic 4); direction/orientation was considered (edge-tangent guide smoothing via the 3×3 Sobel) and **dropped**: the guide is a smooth video frame, so along-edge smoothing is visually ≈ 0 for +4 loads/pixel — a third idea that fails the "visible diff" bar.

## §12.4 formula admission

| Idea | Row (§12.2A) | Family match | Consumes what exists | Deletion test (both ways) |
|---|---|---|---|---|
| 1 ε/Γ | Guided-filter base/detail (regulariser; WGIF) | it *is* the guided filter | g taps, varG, centre P-model | delete → HEAD's constant ε (still this effect); delete mechanism, keep Γ → nothing |
| 2 envelope | Anti-halo envelope (joint-range) | sharpen/local-contrast family; the file's own header promises anti-halo | P taps already loaded, guide centre value | delete → HEAD with halos; delete mechanism, keep envelope → a clamp, not a filter |

Row claims honoured: no Wallis / H&D / grain / halation (fork A), no Cauchy / BC / CFA (B), no CRT rows (C), no fold/orbit (E). Structure-tensor orientation (also claimed by this fork) was evaluated and deliberately not used.
