# Task: Molten Gold Optimization Pass (Flagship Upgrade)

## Objective
Elevate the existing `molten-gold` shader to become one of the strongest flagships in the showcase lineup, applying lessons learned from Ethereal Silk and Fractal Ember.

## Background
- `molten-gold` is already delivered as a flagship shader with solid foundation
- Ethereal Silk (A+) and Fractal Ember (A+) demonstrated: better idle flow, claim feedback, audio mapping
- This pass avoids creating yet another Nebula variant by upgrading an existing high-quality asset

## Current State (File Exists)
- `public/shaders/molten-gold.wgsl` — 130+ lines, has noise/fbm/gold color logic
- `shader_definitions/generative/molten-gold.json` — 4 params (flowSpeed/turbulence, glow, specular, highlightFreq)
- Features: audio-reactive, mouse-driven, generative, temporal, showcase

## Key Upgrade Areas

### 1. Idle Optimization
- Make molten gold flow feel more natural and organic (reference: silk-like movement in Ethereal Silk)
- Enhance slow evolution of internal details to avoid repetitive look during prolonged viewing
- Add subtle heat shimmer / convection currents

### 2. Enhanced Mouse Claim Feedback
- Current mouse interaction is too subtle — needs stronger visual feedback
- Liquid gold should be drawn in, accelerated flow, changes in surface tension, intensified highlights
- Add physical sense of "pulling" or "gathering"
- Reference: Fractal Ember's satisfying click → gather → release cycle

### 3. Improved Audio Reactivity
- Refine `zoomParam1-4` mapping to bass/mid/treble frequencies:
  - **Bass**: Overall flow speed + boiling effect
  - **Mid**: Surface ripples / folds
  - **Treble**: Highlight flickering / sparks
- Use `bass_env` (smoothed) not raw bass for fluid motion (avoid strobing)

### 4. Visual Quality Enhancement
- Improve gold texture: premium specular + subsurface scattering feel
- Add edge glow and heat effects (refer to neonGlow approach)
- More unified and sophisticated color palette (deeper gold, richer shadows)
- Consider chromatic aberration on highlights (subtle, not distracting)

### 5. Technical Cleanup
- Implement latest branchless coding practices and performance optimization
- Ensure proper `dataTexture` usage (temporal feedback, state accumulation)
- Update JSON parameter descriptions
- Add `upgraded-rgba` stack: ACES + chromatic + temporal + dataA + semantic alpha

## Reference Materials
- `agents/design-ethereal-silk.md` — Idle/Claim/Audio patterns (A+ reference)
- `agents/design-fractal-ember.md` — State machine + click feedback (A+ reference)
- `agents/showcase-checklist-v1.md` — Quality checklist
- `agents/WGSL_BUILTINS_GENERATIVE.md` — Latest coding standards
- `public/shaders/molten-gold.wgsl` — Current file to upgrade
- `public/shaders/gen-ethereal-silk-veil.wgsl` — Gold reference for organic flow
- `public/shaders/gen-fractal-ember-lattice.wgsl` — Gold reference for claim feedback

## Output Requirements
1. **Updated `molten-gold.wgsl`** — Complete upgrade with summary comment at top
2. **Updated JSON** — Parameter descriptions match new behavior
3. **Notes file** — `agents/swarm-outputs/kimi-notes/molten-gold-upgrade.notes.md` documenting changes

## Deliverable Checklist
- [ ] Idle flow is organic and non-repetitive (12s+ rotation ready)
- [ ] Mouse claim has strong visual feedback (pull, gather, accelerate)
- [ ] Audio mapping: bass→flow/boil, mid→ripples, treble→sparks
- [ ] Gold texture feels premium (specular + subsurface + heat glow)
- [ ] Full `upgraded-rgba` stack (ACES, chromatic, temporal, dataA, semantic alpha)
- [ ] `bass_env` used for fluid motion (not raw bass)
- [ ] Naga validation passes
- [ ] JSON/header feature parity
- [ ] Performance-friendly (60fps stable)

## Output
- `public/shaders/molten-gold.wgsl` (overwrite with upgrade)
- `shader_definitions/generative/molten-gold.json` (update)
- `agents/swarm-outputs/kimi-notes/molten-gold-upgrade.notes.md` (new)

## Important
- **Upgrade existing file** — do not create new shader name
- Preserve all existing features while enhancing them
- If upgrade adds >30 lines, that's expected for a flagship pass
- One shader only — focus all quality on this single upgrade
