# NOTES — fork B (scanline-sorting, cyber-rain-em, data-slicer-interactive)

All renders: SRC=img minirender_img, 160/256 px, 20 frames, audio 0.5/0.3/0.2. naga clean on prelude-expanded copies.

## scanline-sorting — RESCUE + 3 ideas
- HEAD did not compile: workgroupBarrier after an early return gated on atomicLoad (non-uniform). Fixed via thread-0 copy into s_flag + workgroupUniformLoad.
- Removed dead extraBuffer[133..138] spring; removed dead plasmaBuffer[1..255] palette (always 0 → band just dimmed).
- Ideas: threshold run streak (8-tap max-luma drag along sort axis, crosses 16-px tile seams); sort-front tear (hashed row/col shift at band leading edge); sorted-rank tint (cool→warm by lane rank).
- After: meanL 0.445, no NaN; dir=1 at 256 px shows sorted columns, green streak drag, tear at band edge.
- JSON: dropped spring-cursor, palette-mapped.

## cyber-rain-em — RESCUE + 3 ideas (2nd pass)
- extraBuffer spring zeroed every frame → mouseVel≡0 → moving-charge B field + HEAD "EM wiper skew" dead. Now A texel (0,0) stores [mouse.xy, time, 0.777 sentinel]; velocity = Δmouse/Δt from C(0,0).
- Removed dead plasmaBuffer[band+1] term; clamp before ACES.
- Ideas: Lorentz glyph curl (columns bend by totalB); wiper meniscus lens (rim refracts + highlight ring); ionisation glyph density (|E|+treble lowers glyph threshold).
- Before/after meanL 0.56/0.568; meniscus ring visible. Velocity path not exercisable in minirender (static mouse) — needs real-pointer check.
- JSON: dropped spring-cursor.

## data-slicer-interactive — 3 ideas + small rescue
- sin(uv.y*res.y*PI) is 0 at every pixel centre → +0.5 offset so the per-slice scan modulation exists.
- Ideas: gravity-bent slices (slice phase pulled toward pointer, stronger held); per-slice bit-crush (hashed 3–6-bit, share grows with jitter slider); edge-row drag (boundary row smeared down below each slice edge).
- After meanL 0.575 (HEAD ~0.568), no NaN; slices bow visibly around the held pointer.
- Packing A/B unchanged. JSON untouched (tags already truthful).
