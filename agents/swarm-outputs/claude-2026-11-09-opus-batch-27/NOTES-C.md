# NOTES — fork C (dimension-slicer, spatio-temporal-3d-conv)

Renders: SwiftShader minirender_img (SRC=img), 160px. Both naga-clean (prelude expanded). No rescues needed at HEAD.

- dimension-slicer (2nd pass): Ideas 4) lifted-band drop shadow (perpendicular-offset occlusion outside each band, ×0.45 darken), 5) running glint racing along each cut (bass speeds it), 6) torn cut edge (2-octave value-noise jitter of band width; rims/glow/shadow follow). HEAD meanL 0.543 → 0.530 (shadow), no NaN. Note: whole frame goes through aces(color*1.1) incl. untouched source — pre-existing contrast shift, left as is.
- spatio-temporal-3d-conv (2nd pass): one idea per mode — grain-preserving NR (¼ of removed luma residual re-injected), highlight persistence in motion blur (age-decayed max of past highlights above luma knee 0.4–0.75, bass lengthens), arrival/departure split in sharpen (+residual warm, −residual cool). minirender's history ring is 1 zero layer, so verified with a scratch variant that fakes an 8-layer ring as readTexture shifted 0.012/age: blur mode shows a bright disc streak vs HEAD's grey smear; sharpen shows warm leading / cool trailing edges.
- Real-GPU check: highlight-persistence strength on real video (knee may catch skies); torn-edge noise frequency at high res; glint visibility.
