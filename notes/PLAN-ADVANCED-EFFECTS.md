# PLAN: Advanced Physics, Geometry, and Visual Effects

This plan collects concrete implementation steps for a set of advanced shader effects and simulation systems. Each section gives architectural notes, implementation steps, suggestions for shader-level parameters (these map to `u.zoom_params` or `extraBuffer`), performance guidance, and testing checkpoints.

IMPORTANT: Follow the immutable shader contract described in `AGENTS.md`. Use `u.ripples` and `u.zoom_config` for mouse and zoom/position control, and write shaders under `public/shaders/*.wgsl`. Keep changes to Renderer.ts minimal and only use existing bind groups and buffers.

---

I. Advanced Physics & Material Simulation

1) "Fabric of Reality" — Mass-Spring Cloth
  - Architecture:
    - Particles/grid stored in a texture (dataTextureA), or packed into a storage buffer for large grids.
    - Use position and previous_position fields for Verlet integration.
    - Constraints: store neighbor indices or compute neighbor coordinates on the fly for regular grids.
    - Broken springs: mark in a third texture (dataTextureC) or encode break flags into alpha channel.
    - Visual: write main color to `writeTexture`; write wireframe/tear highlights to `dataTextureB` as overlay.
  - Shader tasks:
    - Add a compute shader: `fabric-step.wgsl` (integration + constraints solver loop).
    - Add compute shader: `fabric-render.wgsl` (draw mesh/wireframe to `writeTexture`).
    - Add routines for tearing: when strain > threshold, mark broken and spawn debris into a particle buffer.
  - Mouse/Interaction:
    - Use `u.ripples` and `u.zoom_config.yz` for repulsive force application.
    - Add UI: `Stiffness`, `TearThreshold`, `Gravity`, `Damping` (map to `u.zoom_params`/extraBuffer).
  - Psychedelic features: Material Memory, Temporal Weaving, Gravity Wells, Self-Healing (as small compute passes).
  - Performance: Use 1/2 or 1/4 resolution particle grid for 4K; 8x8 workgroups for constraint solving; run 3-5 constraint iterations per frame.

2) Photonic Caustics Accumulator
  - Architecture:
    - Photon trace as compute shader(s): emit photons from mouse light (u.zoom_config center).
    - Use a buffer for photons and an accumulation storage (texture_storage with atomicAdd support if available); if not, use reduce passes to avoid atomic stamps.
    - Heightmap-derived IOR, normals from blurred luminance of the source texture.
  - Shader tasks:
    - Add `caustic-emitter.wgsl` (emit photons with direction/wavelength).
    - Add `photon-trace.wgsl` (bounce simulation with Snell/Fresnel and chromatic dispersion).
    - Accumulate to `causticBuffer` (dataTexture) and render to `writeTexture`.
  - Implementation details:
    - Use Schlick's approximation for Fresnel; apply chromatic dispersion via slightly different IORs for R/G/B.
    - Use a Perlin noise normal map (time-animated) for micro-surface shimmer.
  - UI: Photon count slider, IOR range, Light size, Bounce count.
  - Performance: Run 500k-2M photon traces across frames; limit steps per photon; use early exit if intensity falls below threshold.

3) 2D Wave Equation (Ripple Tank)
  - Architecture:
    - 3-buffer ping-pong: previous/current/next (textures or storage buffers).
    - Discrete Laplacian with configurable kernel (5x5 recommended).
  - Shader tasks:
    - `wave-step.wgsl`: compute next frame from previous/current.
    - `wave-inject.wgsl`: apply drivers from red channel or `u.ripples`.
    - `wave-render.wgsl`: to display displacement, normal, or color mapping.
  - Features: wave phase mapping from hue for driver frequency, phase-based particle spawn on collisions.
  - UI: Wave speed, Damping, Source strength, Boundary reflectivity.
  - Performance: Use 512/1024 grids; run 2-4 passes per frame for stability; use workgroup tile caches for Laplacian.

4) Chromatographic Separation (Fluid Viscosity)
  - Architecture:
    - Create three separate velocity fields (textures): velocityR, velocityG, velocityB.
    - Each channel advects its dye field and interacts with others via drag/cohesion terms.
    - Wind global vector (per frame or animated) stored in a uniform buffer or extraBuffer.
  - Shader tasks:
    - `advect-layer.wgsl` per layer with individual viscosity, diffusion settings.
    - `interact-layers.wgsl` mixing and drag forces between layers.
    - `phase-change.wgsl` for evaporation/condensation mechanics based on temperature field.
  - UI: Viscosities (R/G/B), Wind strength, Temperature control.
  - Performance: Run half-resolution for each layer and upsample for display; separate compute pipelines per layer for optimization.

---

II. Geometry & Math

5) Hyperbolic Tiling (Poincaré Disk)
  - Architecture:
    - Function to map uv to Poincaré disk coordinates in the shader; compose Möbius transforms as separate functions.
    - Multi-layer tiling: sample source and transform at multiple radii.
  - Shader tasks:
    - `poincare-tile.wgsl` for tile generation and Möbius transformations.
  - UI: Curvature, Symmetry, Animation speed.

6) Log-Polar Vortex (Droste)
  - Architecture: log-polar coordinate mapping and recursive sampling of scaled source; handle recursion levels with loop or layered pass.
  - Shader tasks: `log-polar-droste.wgsl`.
  - UI: Zoom speed, Spiral factor, Recursion depth.

7) Anisotropic Kuwahara (Van Gogh flow)
  - Architecture: structure tensor, eigenvector estimation and rotation of smoothing windows.
  - Shader tasks: `anisotropic-kuwahara.wgsl` with multi-scale passes.
  - UI: Window size, Anisotropy, Temporal smoothing.

---

III. Biological & Growth Algorithms

8) Diffusion-Limited Aggregation (DLA) Crystals
  - Architecture:
    - Spawn walkers in a buffer, store frozen pixels in a texture.
    - Use continuous positions for walkers and snap on freeze.
  - Shader tasks: `dla-walkers.wgsl` and `dla-freeze.wgsl`.
  - UI: Walker count, Attraction strength, Stickiness.

9) Multiscale Turing Patterns
  - Architecture: run multiple reaction-diffusion systems seeded from DoG bands and combine.
  - Shader tasks: `multi-turing.wgsl` with separate buffers for each scale.
  - UI: Feed/Kill per scale, coupling strength.

10) Predator-Prey Pixel Ecology
  - Architecture: CA using a packed RGBA integer grid or storage buffer; apply rules using neighbor scan.
  - Shader tasks: `predator-prey.wgsl` and optional `ecology-render.wgsl`.
  - UI: Eat probability, Death rate, Mutation rate.

---

IV. Glitch, Time, & Data

11) Bitwise "Byte-Mosh"
  - Architecture: bitwise ops on u32 representations per pixel (via bit reinterpretation in WGSL).
  - Shader tasks: `byte-mosh.wgsl` (XOR/AND/shift/rotate) with a noise texture to modulate operations.
  - UI: Operation mix, bit shift, error rate.

12) Time-Lag Map
  - Architecture: 3D texture ring buffer; per-pixel lag control.
  - Shader tasks: `time-lag-step.wgsl` (push/rotate) and `time-lag-read.wgsl` (spatially varying read).
  - UI: Buffer length, mapping function, feedback mix.

13) Streamline Pixel Sorting
  - Architecture: compute vector field from luminance gradient, swap pixels downstream.
  - Shader tasks: `flow-field.wgsl` and `sort-downstream.wgsl`.
  - UI: Flow strength, sorting passes, strand persistence.

14) Magnetic Dipole Alignment
  - Architecture: Compute field via hierarchical clustering or downsample for approximations; rotate sprites or render metaballs.
  - Shader tasks: `magnetic-field.wgsl` and `dipole-render.wgsl`.
  - UI: Charge strength, alignment inertia, sprite size.

15) Voronoi Dynamics (Bubbles)
  - Architecture: Use centroid physics in a buffer; spatial hash for neighbor checks; declarative Voronoi sampler for final render.
  - Shader tasks: `voronoi-physics.wgsl`, `voronoi-render.wgsl`.
  - UI: Centroid count, repulsion, attraction.

---

E. Process + Integration
  - Phase 1: Prototyping
    - Pick 2–3 effects to prototype (recommend: Fabric of Reality, Photonic Caustics, and the Wave Tank). Create skeleton WGSL compute files under `public/shaders/` using the standard immutable header.
    - Provide parameter controls in `Controls.tsx` and map to `u.zoom_params`/`extraBuffer` or `u.zoom_config`
  - Phase 2: Integration and UI
    - Add params to `public/shader-list.json` for each implemented shader.
    - Add optional toggle in `Controls.tsx` for running heavy simulations on low-res vs full-res.
  - Phase 3: Optimization and Testing
    - Use `npm run build` and the dev server to test performance.
    - Add instrumentation in `Renderer.ts` to throttle heavy passes and add a 'simulate' switch.

F. Implementation Checkpoints
  - Add initial skeleton WGSL for chosen prototypes and update `shader-list.json`.
  - Map required uniforms and ensure shaders follow `AGENTS.md` header.
  - Add UI controls for the basic param space.
  - Measure performance on 1080p and 4K; adjust default resolution/downsampling.

G. Priorities and Roadmap (suggested):
  - Phase A: Fabric of Reality, Wave Tank, Photonic Caustics (largest visual impact; proof-of-concept).
  - Phase B: Chromatographic Separation, Multiscale Turing Patterns, DLA Crystals.
  - Phase C: Hyperbolic Tiling, Log-polar Droste, Kuwahara flow.
  - Phase D: Byte-Mosh, Time-Lag Map, Streamline Sorting, Magnetic Dipoles, Voronoi Dynamics (apply more creative glitches and time-based effects).

H. Notes & Constraints
  - Do not add new bind groups (follow `AGENTS.md` constraints). Reuse `dataTextureA/B/C`, `extraBuffer`, and `u.zoom_params` for extra parameters.
  - For heavy CPU/GPU tasks (e.g., photon traces), consider multi-frame accumulation and progressive refinement.
  - Avoid atomicAdd where not supported; use hierarchical reduction or fragment-based accumulation where possible.

---

If you want, I can now: a) create skeleton WGSL files and `shader-list.json` entries for the Phase A prototypes, or b) implement one full feature (e.g., Fabric of Reality). Which do you prefer? 
