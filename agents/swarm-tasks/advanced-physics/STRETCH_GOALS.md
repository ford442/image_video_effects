# Stretch Goals — Advanced Physics Epic

Ship only after priority queue (#1–#3) acceptance criteria are met.

---

## 4. Chromatographic Separation (fluid viscosity)

Three velocity/dye layers (R/G/B) with distinct viscosity, wind vector in `extraBuffer[0..1]`, inter-layer drag.

**Passes:** `advect-layer` ×3 (or one pass with channel split) → `interact-layers` → `phase-change` → render  
**Ref:** `docs/plans/PLAN-ADVANCED-EFFECTS.md` §4  
**Tier:** C for 3 independent advection fields at full res

---

## 5. Hyperbolic Tiling (Poincaré disk)

Möbius transforms on UV in Poincaré disk; multi-layer sampling.

**Shader:** `poincare-tile.wgsl` (single-pass OK)  
**Params:** curvature, symmetry order, animation speed, kaleidoscope depth  
**Ref:** PLAN §5

---

## 6. Log-Polar Vortex (Droste)

Log-polar remap + recursive scale sampling.

**Shader:** `log-polar-droste.wgsl`  
**Params:** zoom speed, spiral factor, recursion depth, center drift  
**Ref:** PLAN §6

---

## 7. Anisotropic Kuwahara (Van Gogh flow)

Structure tensor + multi-scale Kuwahara — natural multipass (tensor pass → blur passes).

**Shader:** `anisotropic-kuwahara.wgsl`  
**Ref:** PLAN §7, phase-c Perona-Malik agent for PDE neighbor pattern

---

## Agent assignment

Each stretch goal gets a one-page prompt when promoted from backlog. Use same preamble as `README.md`.
