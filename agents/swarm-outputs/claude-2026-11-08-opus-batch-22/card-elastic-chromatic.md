SHADER: elastic-chromatic (2nd pass)
IDENTITY: per-channel temporal EMA lag (red trails, blue snaps) around a springy cursor + Lissajous source, blackbody split-tone grade
KEEP VERBATIM: wavelength-dependent EMA lag, Rayleigh residual tint, Lissajous source, shock rings, blackbody grade
ADD:
  3. Velocity-aligned tension split — near the spring head / Lissajous source R and B are pulled apart ALONG the motion vector (analytic Lissajous velocity, so it shows at idle)
  4. Elastic overshoot rebound — on spring whip / shock ring / bass, blue (and a bit of green) extrapolates PAST the live frame away from history, then the trail catches up
RESCUES:
  - writeTexture was ACES'd twice (second pass on premultiplied sRGB) → near-black frame.
  - Graded colour fed back into C → blackbody tint compounded every frame (green/black drift). A now holds ungraded EMA history.
  - Spring lived in extraBuffer[133..137] (host re-uploads → dead spring). Moved to A texels (0,0)/(1,0).
  - JSON params[] (elasticity, chromatic_scale, lissajous_ratio, damping) vs code (Elasticity, Damping, Shockwave, Palette): 3 of 4 sliders mis-wired. Code rewired to params[]; shock/palette pinned at old defaults; x-meta synced.
Stats (256px, 20f, t=3, defaults): before meanL .069 (black) → after .346; audio .101 → .344. No NaN.
Open: harness mouse is static, so tension/rebound from the spring itself are unverified visually.
