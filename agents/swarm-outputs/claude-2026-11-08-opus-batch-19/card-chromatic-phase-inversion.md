SHADER: chromatic-phase-inversion (2nd pass)
IDENTITY: R/G/B inverted by detuned temporal phase oscillators, channel ghosts drift with the phase
KEEP VERBATIM: detuned phase oscillators, ghost offsets, Mackie lines, pointer phase-lock, depth parallax, params, A packing
ADD: 4. solarization fold (HEAD rescue) — v→1−v crossfade replaced by Sabattier fold |v−w|/max(w,1−w); same endpoints, V-curve mid-cycle instead of flat grey
     5. depth-sweep inversion front — thin shell sweeps near→far through depth (~8 s/pass, bass speeds it), flipping phase inside
     6. phase-front isolines — hairline contours where each channel's phase crosses 0.5, drifting with the spatial noise field
FORBID: ripple rings, palettes, spring cursor
A PACKING: unchanged (phR, phG, phB, lockW)
HEAD BUG: linear crossfade at weight 0.5 is constant 0.5; green capped at 0.5 → frame washed to grey (stdL 0.024 baseline → 0.10 after). Default look is now darker/more contrasty (solarized) — intentional rescue.
Renders: before-cpi.png, after-cpi-t3.png, after-cpi-t6.png
