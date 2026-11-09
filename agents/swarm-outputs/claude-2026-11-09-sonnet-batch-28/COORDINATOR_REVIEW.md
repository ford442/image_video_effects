# COORDINATOR_REVIEW — sonnet/batch-28

Checked against BRIEFS.md cards (cards written before any WGSL edit). Structural only; no real-GPU visual QA.

| id | Idea 1 | Idea 2 | Rescue | Formula rows | Verdict |
|---|---|---|---|---|---|
| generative-psy-swirls / psy-swirls | arm-wound hue | Rankine eye-wall cores | R1 glide in A(0,0) | none | pass |
| prismatic-feedback-loop | prism echo (exact bilinear C) | Cauchy-weighted taps | R1 glide, C(0,0) masked | Cauchy (F) | pass |
| interactive-origami-coupled | vorticity confinement | crease gutters | R1 prev-pointer in A(0,0) (drag/vortex/Karman were dead); R-phase; honest curl in A.z | vorticity confinement (D) | pass |
| voronoi-chaos | fracture seams (bisector distance) | impact shatter | tile samples pushed seed; R-phase; far-seed black-hole fix | Worley F2-F1 (variant) | pass |
| spec-bicubic-crystal | Beer-Lambert wedge absorption | internal-reflection twin | clamp before ACES | Beer-Lambert (F) | pass |
| murmuration | forward vision cone | sunward rim | - | none | pass (dynamics unverified on GPU) |
| gen-prismatic-mobius-helix | thin-film fringes | SDF-gradient bevel light | R-phase | thin-film phase (F), SDF lighting (E) | pass |
| prismatic-3d-compositor | afterglow from the formerly write-only trail | cursor light shafts | exact C load | none | pass (afterglow needs moving content to judge; no ACES by design, `upgraded-rgba` dropped) |
| voronoi-faceted-glass | bevel dispersion | frosted panes | - | Cauchy (F) | pass |

Row de-dup: Cauchy on 2 files (feedback-loop, faceted-glass), each with a different second idea; no row on >2 files. No spring/ripple/IQ overlay stamped across the batch.
Open for real-GPU QA: swirls eye-wall ring busyness; origami fluid is subtle on the photo; murmuration cone dynamics; crystal darkening; mobius hatching at 576 px; compositor afterglow.
