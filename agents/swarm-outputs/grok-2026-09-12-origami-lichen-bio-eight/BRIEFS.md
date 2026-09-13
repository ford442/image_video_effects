# Paper-fold / lichen / bioluminescent leftover eight — Idea Cards

Written **before** any WGSL edit, per `docs/SHADER_UPGRADE_BATCH.md` §2.

Family: leftover paper-fold + lichen/bio/moss/nano shaders named as the next
clean leftover after kaleido/drag eights (already shipped 09-11) and
origami/crease/ascii (already 09-11 Idea Cards). Two native ideas each.
Identities kept. No spring+ripple+IQ stamp.

Skipped: interactive-origami / digital-crease / ascii-glyph / neon-quantum-lattice
(already Idea Cards); kaleido/voronoi eight and drag-glitch eight (shipped);
paper-cutout / paper-burn (already idea-bearing); tesseract-fold /
gen-quantum-aether-origami (overlay-rich); physarum extraBuffer[0..] agents;
creature-scale seahorse/owl/jellyfish/abyss; mycelium-network (already tropism/
heartbeat); digital-moss shade-taxis clone.

---

```
SHADER: origami-fold
IDENTITY: mouse-centered mountain/valley paper fold that reflects the photo across a crease
KEEP VERBATIM: Fold Speed / Shadow Strength / Fold Angle / Paper Opacity; mountain vs valley from click parity; Kawasaki angle helper; paper fiber; crease specular; existing ACES
ADD (2 native ideas):
  1. Kawasaki buckle — kAngle already computed but only fed alpha; when the vertex is not flat-foldable the crease wrinkles along the tangent instead of staying a clean dihedral
  2. Sheet print-through — the unfolded half sees a faint reflected sample at the crease (paperOpacity as translucency), so both faces of the sheet read
FORBID on this file: extraBuffer springs; cloning interactive-origami wet-fold shadow; IQ palette
A PACKING: ACES display RGBA (C unused as history — keep it that way)
```

```
SHADER: interactive-origami-coupled
IDENTITY: three crease waves around the pointer plus viscous fluid that drags the folded photo
KEEP VERBATIM: Fold Scale / Fold Depth / Viscosity / Vortex Strength; three fixed crease normals; viscosity damping; mouse force + perpendicular vortex; click-ripple density; A = (vel.xy, vorticity, dens)
ADD (2 native ideas):
  1. Capillary pooling — fluid density settles into crease valleys (low fold height), native to wet paper
  2. Kármán street along a crease — stored vorticity drives an alternating lateral kick when the pointer moves fast, the vortex street the header already promised
FORBID: new springs; replacing the three-crease origami with a different fold; IQ overlay
A PACKING: raw (vx, vy, vorticity, density) — ACES display only. Prev mouse leaves the (0,0) A cell and lives in extraBuffer[133..134] stash (not a spring).
```

```
SHADER: gen-lichen-reaction-diffusion
IDENTITY: crustose lichen look from multi-octave noise "feed/kill" regimes, mouse deposit, rock grain, spore motes
KEEP VERBATIM: Pattern Density / Growth Rate / Zoom / Color Shift; evalLichen noise regimes (do NOT rewrite as Gray-Scott); lichen_color ramp; mouse/ripple deposits; persistence from C
ADD (2 native ideas):
  1. Thallus growth rings — concentric age bands around the pointer deposit and click rings
  2. Apothecia cups — disk fruiting bodies on high-density patches (crustose lichen, not moss rhizoids)
FORBID: cloning this morning's digital-moss shade taxis / rhizoids; real Gray-Scott rewrite; springs
A PACKING: display RGB + pattern_density in A.a (matches prev.rgb persistence)
```

```
SHADER: gen-bioluminescent-reaction-diffusion
IDENTITY: actual Gray-Scott A/B field with cyan A-species and violet B-species glow
KEEP VERBATIM: Intensity / Simulation Speed / Spatial Scale / Mouse Influence; bounded 8-tap Laplacian; luma-mutated feed/kill; mouse B seed; raw A/B in A.xy
ADD (2 native ideas):
  1. Luciferin quench — glow saturates then dims where B has stayed high (age in A.z, previously unused 0)
  2. Excitation front — extra flash where B is advancing vs its neighbors (the traveling bioluminescent wave)
FORBID: cloning this morning's RD aniso-Laplacian / mitosis / nutrient taxis; IQ palette as the look
A PACKING: raw (A, B, luciferin-age, 1) — ACES display only
```

```
SHADER: nano-repair
IDENTITY: mouse-radius nanobots raise a health field; damage shows as block glitch + scanlines; repair glows
KEEP VERBATIM: Repair Radius / Decay Speed / Glitch Strength / Scanlines; health in A.r; block glitch; scanlines; red→green emission
ADD (2 native ideas):
  1. Healing front — emission concentrates on |∇health| (the moving repair boundary, not a disk fill)
  2. Weld flash — a brief cyan-white seam where health rose this frame (C vs new health)
FORBID: new springs; replacing health with a different sim; IQ overlay
A PACKING: raw (health, 0, 0, 1) — ACES display only. Exact C load (was a sample).
```

```
SHADER: digital-moss-rgba
IDENTITY: dual Gray-Scott pairs (A/B and C/D) tinting a luma-gated moss overlay on the photo
KEEP VERBATIM: Moss Density / Growth Rate / Color Shift / Moisture as feed/kill/cross-inhibit/growSpeed; extraBuffer[133..138] spring; held plant / click clean; A packing (A,B,C,D)
ADD (2 native ideas):
  1. Dual-species territorial ridge — bright seam where B ≈ D (the two moss chemistries meet)
  2. Capsule stalks — high-B pixels sample a short screen-up offset as sporophyte height
FORBID: cloning digital-moss shade taxis / rhizoids; new spring; replacing the 4-channel RD
A PACKING: raw (A, B, C, D) chemistry — ACES display only
```

```
SHADER: bioluminescent
IDENTITY: click-planted spores spread as glowing tissue with veins and subsurface scatter on the photo
KEEP VERBATIM: Spread Speed / Branch Density / Glow Intensity / Spore Count; growth in A.r; click spore planting; vein noise; SSS; four named palettes
ADD (2 native ideas):
  1. Spore tropism — growth bias toward the nearest live click spore (fungus reaching the inoculum)
  2. Quorum flash — glow pulses where local growth exceeds the neighbor average (excitation, not a clock overlay)
FORBID: extraBuffer springs; IQ cosine stamp; stealing zoom_config as GrowthRate/ColorMode (engine mouse/time)
A PACKING: raw (growth, 0, 0, 1) — ACES display only
```

```
SHADER: bioluminescent-blackbody
IDENTITY: same spore-growth field, but glow is blackbody temperature from growth energy
KEEP VERBATIM: Spread / Density / Glow / Spores; blackbodyColor Kelvin mapping; growth in A.r; click spores
ADD (2 native ideas):
  1. Leading-edge heat — temperature spikes on the advancing front (growth > neighbors)
  2. Cooling lag — stored heat in A.g trails growth so abandoned tissue cools instead of snapping off
FORBID: keeping or restamping the leftover clock-ring / IQ spectral overlay at the end of HEAD; cloning artistic tropism
A PACKING: raw (growth, heat, 0, 1) — ACES display only
```
