# Notes — temporal echo twelve (2026-10-30)

Floor on every file: `#include "_prelude.wgsl"`, 16×16, exact `dataTextureC` loads where C is history, saved `params` unchanged, ACES on display RGB. Six files had pasted bindings; `migrate_to_prelude.py` ran first (no upgrade by itself). Phantom-lag persistent state moved from engine-owned `extraBuffer[0..3]` to `[133..137]`.

Real-GPU visual QA: not run (no GPU adapter on this VM).

| Shader | Kept | A packing | Ideas in the diff |
|---|---|---|---|
| temporal-echo | accumulative alpha, depth-layered alpha, temporalOffset lag, bass pin, ripple pin | linear accumulation in A; ACES on writeTexture | history-axis smear; shadow-first stick |
| temporal_echo | tangent orbit, chromatic exact-C taps, HSV walk, ripple fronts, raw HDR in A | raw HDR + alpha; ACES on writeTexture | orbital arc smear; afterimage bleach |
| phantom-lag | PHI tap stack, Echo X/Y roles, hue cycle, cursor stretch | ACES display RGBA | lag fan + filament; catch-up collapse |
| long-exposure | threshold gate, reciprocity fade, highlight plate, eraser, ripple flashes, 4-tap glow | raw exposure RGB; A.a = exposure density | light-trail tangent; reciprocity color |
| temporal-rgb-ghost | per-channel ages, fractional G, motion-gated displace, blue comet, vignette | display RGBA | leading red; disagreement fringe |
| temporal-layered-time-stamps | spiral, hue tint, exponential weights, onion outlines | display RGBA | peg-bar shift; inter-stamp smear |
| temporal-decay-multiresolution | decay kernels, click time-inversion, mouse lens | display RGB, A = ultra-slow luma | cross-scale cascade; stationary mute |
| temporal-feedback-zoom-tracer | zoom/rotation/persistence/blend, jitter, chroma, bezels, hue drift | display RGBA | field lag; feedback-camera cos⁴ falloff |
| infinite-video-feedback | 5-pass zoom-rotate, sprung center, click spin, color shift, accumulative alpha | linear feedback in A; ACES on writeTexture | generation softness; frame-edge fold |
| neon-echo | per-channel tau, P7 tail, exact-C persistence, blackbody, halation | raw persistence; ACES on writeTexture | ignition flash; phosphor slot mask (display only) |
| luma-echo-warp | terrace quantize, contour decay, curl warp, pre-tint feedback | linear echo RGB 0..1.2 + alpha | bright-lead trail; terrace riser shade (display only) |
| temporal-rift | arrival delay, velocity shear, sprung pointer, click rift | nextHist RGBA | rift lip; rift-widened chroma |

Formula names: none of the §12.2 rows are shared by more than one file. cos⁴ falloff is only on temporal-feedback-zoom-tracer, and only on the warped history.
