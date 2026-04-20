# Agent 6B: Mouse-Response Specialist
## Task Specification — Phase B, Agent 6 (New)

**Role:** Interactive Mouse-Driven Enhancement Engineer  
**Priority:** HIGH  
**Target:** 30–40 shaders from `phase-b-upgrade-targets.json` (`mouse_response` category)  
**Estimated Duration:** 4–5 days

---

## Mission

Add mouse-driven interactivity to image-input shaders that currently lack it. Focus on shaders in the `distortion`, `artistic`, `liquid-effects`, `visual-effects`, `lighting-effects`, `image`, and `post-processing` categories where a cursor interaction would meaningfully improve the effect.

Skip pure generative shaders that do not sample `readTexture` — mouse position is irrelevant if there is no image to distort.

---

## Mouse Input Reference

```wgsl
// Normalized mouse position (0.0–1.0)
let mousePos = u.zoom_config.yz;

// Mouse down state (>0.5 = pressed)
let isMouseDown = u.zoom_config.w > 0.5;

// Time
let time = u.config.x;

// Resolution
let res = u.config.zw;
```

---

## Mouse-Response Patterns

### Pattern 1: Cursor Gravity Well
**Use for:** Distortion, liquid, displacement shaders  
The effect strength increases as the cursor approaches a pixel.

```wgsl
let distToMouse = length(uv - mousePos);
let gravityStrength = 1.0 - smoothstep(0.0, 0.3, distToMouse);
let effectAmount = baseAmount * (1.0 + gravityStrength * 2.0);
```

### Pattern 2: Velocity-Aware Displacement
**Use for:** Slit-scan, smear, echo, trails  
Displacement direction follows the vector from previous mouse position (approximated via `zoom_config` history).

```wgsl
// Approximate velocity from parameter drift or directional bias
let mouseDir = normalize(uv - mousePos + 0.001);
let displacement = mouseDir * effectStrength * (1.0 - distToMouse);
```

### Pattern 3: Click-Triggered Ripple / Shockwave
**Use for:** Liquid, ripple, interactive shaders  
On mouse down, spawn a localized distortion that propagates outward.

```wgsl
let clickWave = sin(distToMouse * 30.0 - time * 5.0) * exp(-distToMouse * 4.0);
let clickStrength = select(0.0, 1.0, isMouseDown);
let ripple = clickWave * clickStrength;
```

### Pattern 4: Hover-State Modulation
**Use for:** Glow, reveal, focus, lens shaders  
Effect parameters shift based on cursor proximity without requiring a click.

```wgsl
let hoverFactor = 1.0 - smoothstep(0.0, 0.25, distToMouse);
let glowIntensity = baseGlow * (1.0 + hoverFactor);
let revealRadius = baseRadius * (1.0 + hoverFactor * 0.5);
```

### Pattern 5: Brush / Paint Interaction
**Use for:** Artistic, temporal, paint shaders  
Mouse acts as a brush — effect deposits or accumulates near the cursor.

```wgsl
let brushSize = 0.05 + u.zoom_params.x * 0.1;
let brushMask = 1.0 - smoothstep(0.0, brushSize, distToMouse);
let deposit = brushMask * isMouseDown * 0.1;
// Accumulate deposit into effect state
```

---

## Target Selection Rules

1. **Must sample `readTexture`** — generative-only shaders are out of scope.
2. **Must NOT already have `mouse-driven` in `features`.**
3. **Prioritize categories:** distortion > artistic > liquid-effects > visual-effects > lighting-effects > image > post-processing.
4. **Skip if** the shader is already claimed by Agent 1B-R or Agent 2B for the same shader ID.

---

## Implementation Template

```wgsl
// ═══════════════════════════════════════════════════════════════════
//  {SHADER_NAME} — Mouse-Response Upgrade
//  Category: {category}
//  Features: mouse-driven, {existing features}
//  Upgraded: 2026-04-18
//  By: Agent 6B
// ═══════════════════════════════════════════════════════════════════

// ... standard bindings ...

// ═══ MOUSE INPUT ═══
let mousePos = u.zoom_config.yz;
let isMouseDown = u.zoom_config.w > 0.5;
let distToMouse = length(uv - mousePos);

// ═══ MOUSE-DRIVEN PARAMETER ═══
let mouseInfluence = 1.0 - smoothstep(0.0, 0.3, distToMouse);
let param1 = mix(minVal, maxVal, u.zoom_params.x) * (1.0 + mouseInfluence);

// ... rest of effect ...
```

---

## JSON Update Rule

After upgrading a shader, update its JSON definition:

```json
{
  "features": ["mouse-driven", "existing-feature"],
  "tags": ["interactive", "cursor", "existing-tag"]
}
```

Add `"mouse-driven"` to the `features` array. Preserve all existing features.

---

## Deliverables

1. **30–40 upgraded WGSL files** in `public/shaders/`
2. **30–40 updated JSON definitions** in `shader_definitions/{category}/`
3. **`agent-6b-completion-summary.md`** in `swarm-outputs/`

---

## Success Criteria

- [ ] All target shaders respond to mouse position via `u.zoom_config.yz`
- [ ] Mouse effect is visually meaningful (not just decorative)
- [ ] No compilation errors introduced
- [ ] All existing functionality preserved
- [ ] JSON definitions updated with `mouse-driven` feature tag
- [ ] Randomization-safe parameters maintained
