# Shader Entries to Add to `public/shader-lists/generative.json`

Add these entries to the generative.json list:

```json
  {"id": "gen-phoenix-fractal-flame", "name": "Phoenix Fractal Flame", "url": "shaders/gen-phoenix-fractal-flame.wgsl", "category": "generative"},
  {"id": "gen-3d-sierpinski-chaos", "name": "3D Sierpinski Chaos Game", "url": "shaders/gen-3d-sierpinski-chaos.wgsl", "category": "generative"},
  {"id": "gen-buddhabrot-aura", "name": "Buddhabrot Aura", "url": "shaders/gen-buddhabrot-aura.wgsl", "category": "generative"},
  {"id": "gen-magnetic-dipole-field", "name": "Magnetic Dipole Field Lines", "url": "shaders/gen-magnetic-dipole-field.wgsl", "category": "generative"},
  {"id": "gen-spiral-galaxy-dust", "name": "Spiral Galaxy Dust", "url": "shaders/gen-spiral-galaxy-dust.wgsl", "category": "generative"},
  {"id": "gen-turbulence-particle-flow", "name": "Turbulence Particle Flow", "url": "shaders/gen-turbulence-particle-flow.wgsl", "category": "generative"},
  {"id": "gen-coral-reef-colony", "name": "Coral Reef Colony", "url": "shaders/gen-coral-reef-colony.wgsl", "category": "generative"},
  {"id": "gen-lichen-reaction-diffusion", "name": "Lichen Reaction-Diffusion", "url": "shaders/gen-lichen-reaction-diffusion.wgsl", "category": "generative"},
  {"id": "gen-hyperbolic-tessellation", "name": "Hyperbolic Tessellation", "url": "shaders/gen-hyperbolic-tessellation.wgsl", "category": "generative"},
  {"id": "gen-islamic-star-rose", "name": "Islamic Geometric Star-Rose", "url": "shaders/gen-islamic-star-rose.wgsl", "category": "generative"}
```

# File Placement

| File Type | Source Path | Destination Path |
|-----------|-------------|-----------------|
| WGSL | `output/*.wgsl` | `public/shaders/*.wgsl` |
| JSON | `output/*.json` | `shader_definitions/generative/*.json` |
