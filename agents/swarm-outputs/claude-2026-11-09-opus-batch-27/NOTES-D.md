# NOTES — fork D (vortex-prism, quantum-fractal)

Renders: SwiftShader minirender_img (SRC=img), 160px. naga OK on include-expanded sources.

- vortex-prism (2nd pass): no rescue needed (HEAD meanL 0.506 → 0.508). Ideas: spiral-arm interference (log-spiral sin(6 ln r − 2θ) modulates twist in the outer band — clear two-armed spiral at twist 0.9), precessing eye (centre orbits pointer, radius·(0.04+0.04·mids)), dispersion rim (spectral ring at effect radius, gated by prism/twist; mostly off-screen at radius ≥ 0.5).
- quantum-fractal (2nd pass): RESCUE Iterations dead (u32(max(10, 0..1)) ≡ 10) → mix(10, 90); RESCUE pastel wash (×1.5 exposure into ACES shoulder, HEAD meanL 0.67 stdL 0.058 → 0.54/0.077). Ideas: nodal lines (dark seams where |ψ1|≈|ψ2|), tunnelling halo (escape-iteration via private var; late escapers glow, Edge Glow scales it — visible at high scale/iterations, faint at defaults), measurement collapse (pointer disk shows plain photo + fringed rim, only while mouse is held — zoom_config.w > 0.5; bass widens).
- Real-GPU check: maxIter now up to 90 ×2 fractals (default 50 vs HEAD 10) — check fps at 1080p.
