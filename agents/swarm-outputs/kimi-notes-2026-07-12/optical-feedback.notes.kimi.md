# optical-feedback — Interactivist upgrade notes

- **What changed:** Replaced static feedback with audio-envelope zoom pumping, domain-warped UV drift driven by treble, HSV hue shifting, depth-aware alpha fade, and ACES tone mapping. The JSON preserves params but renames `decay` to `accumulation` for clarity and adds `upgraded-rgba`, `audio-reactive`, and `depth-aware` features.
- **Why:** The original feedback loop was already temporal but linear; adding audio and warp injects emergent, self-organizing patterns while depth-aware fade keeps the effect compositable in chained slots.
- **Performance concern:** The domain warp evaluates `fbm(..., 3)` twice and the feedback sample reads `dataTextureC`; at high zoom/rotation values the feedback can diverge, so the accumulation rate clamps help prevent blow-out.
