# pp-sharpen — Idea Card (2026-11-09)
Family: post-process (§12.2A). Keep: bilateral USM, 3 modes, anti-halo + luma-only.
Ideas: 1) clarity band — 4x-radius ring, midtone-weighted local contrast added as luma (modes 0/1). 2) tonal protection — sharpening delta faded in deep shadows (<0.12) and clipped highlights (>0.9).
Rescues: full ACES fit re-graded every photo (whites 0.80, mids lifted, desaturated) → SDR-identity shoulder above 0.8; centre lens was always on (idle cursor parks at 0.5) → gated on hold; extraBuffer[133..138] spring never persisted → removed (cursor direct).
