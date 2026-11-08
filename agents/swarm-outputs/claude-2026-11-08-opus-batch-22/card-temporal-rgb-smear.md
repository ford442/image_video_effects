SHADER: temporal-rgb-smear (1st idea pass)
IDENTITY: directional curl-flow RGB smear with temporal feedback trails
KEEP VERBATIM: curl/domain-warp flow, Halton jitter, per-channel decay, sparkle grain, layered alpha
ADD:
  1. Highlight-led comet streaks — smear length ×0.65..1.6 by source luma (long-exposure light trails)
  2. Curved streamline taps — 2 extra taps march along the re-evaluated curl field, so streaks bend with Turbulence
  3. Bass ghost-hold — kicks surge feedback toward ~0.99 so the frame leaves a held ghost that bleeds out
RESCUES:
  - Code read y/z/w as MouseSpring/Sparkle/FeedbackClamp but JSON params[] is smear_decay/chromatic_split/turbulence: turbulence (0.3) clamped to clampMax=1 → dead; split and decay hard-coded. Rewired to params[]; defaults reproduce old constants; x-meta synced.
  - dt read u.config.y (ripple count) → spring dt 0; spring state in extraBuffer[0..6] written by every thread and re-uploaded by host → dead + racy. Moved to A texels (0,0)/(1,0) with a time clock.
Stats (256px, 20f, t=3, defaults): before meanL .574 → after .571; audio .610 → .594. No NaN.
