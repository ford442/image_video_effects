# BRIEFS — fork E

## gen-de-jong-attractor (second pass; earlier 6 ideas KEEP VERBATIM)
HEAD render (saved defaults 0.4,0.4,0.3,0.5, 30 frames, t 3s): idle 192 meanL .408 stdL .040 meanA .033; 576 same; held .403/.052; audio .407/.038 meanA .127.
Look: a flat saturated-blue floor (palette(density=0) painted at full strength everywhere) with the hero tube; the actual attractor lace is faint dotted specks barely above the floor.
Rescue 1 (not an idea): zero-density floor is painted the full palette colour → lace invisible. Scale the density palette by its own tone so empty plane is near-dark.
§12.1: tactic 1 (what is the subject?) the lace density; tactic 2 (what is invisible?) the density dynamic range — linear ×10 clamp crushes it; tactic 3 (what does the map know that isn't drawn?) sensitivity of the orbit to its start (Lyapunov); tactic 6 (deletion test) both ideas remove recognisable structure.
- Idea 7: Log density tone (§12.2 Density-histogram log tone) — log(1+k·acc)/log(1+k) instead of clamp(acc·10): faint lace shows, dense cores don't clip. Same noun: density.
- Idea 8: Lyapunov shadow-orbit tint (native) — a second orbit started ε away iterates alongside; the separation growth (finite-time Lyapunov exponent) of orbits passing a pixel tints chaotic filaments hot and regular arcs cold. Same noun: orbit/map. Expert test: FTLE is the standard chaos diagnostic for de Jong maps.

## gen-velocity-bloom (first pass)
HEAD render (x-meta defaults 0.3,0.7,0.5,0.85; params: [] so host shows no sliders): idle 192 meanL .794 stdL .274 meanA .926 — washed-out, whole frame blooms.
Rescue 1: velocityField compares the current source against dataTextureC.rgb, which is the previous frame's *accumulated bloom* (A.rgb), not the previous source frame → "velocity" is large everywhere even on a still image. Fix: pack previous source luma in A.a (HEAD stored hard 1.0) and compare luma; A packing becomes rgb=bloom, a=prev source luma.
Not fixed (noted): extraBuffer[133/134] click spring never persists (re-zeroed) → pulse = "while held" glow (works, picture changes); fftLow reads extraBuffer[6..8] (not a sanctioned audio source; left alone).
§12.1: tactic 1 subject = motion-driven bloom/streaks; tactic 3 what's known but undrawn = streak direction sign & trail age; tactic 6 deletion test both remove visible structure.
- Idea 1: Doppler streak fringe (native) — the motion-aligned anamorphic streak splits channels along flowDir: red leads, blue trails, gap ∝ velocity.
- Idea 2: Cooling afterglow (native) — the advected trail carried in A cools each frame (rgb·(0.9,0.96,1.06) before decay), so fresh bloom is white and old trails fade through blue, per velocityColor's own ramp.
