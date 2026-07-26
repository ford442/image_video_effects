# Swarm Brief: liquid_crystal_birefringence

**Role:** Algorithmist
**Name:** Liquid Crystal
**Category:** generative
**Description:** Liquid crystal optical effects with birefringent double refraction, twisted nematic polarization rotation, and Schlieren texture
**Current lines:** 181
**Target lines:** 231–271 (expand by +50 to +90)

## Role Instructions

You are the Algorithmist. This LCD physics shader claims audio it does not have - make it honest, then give the spectrum a physical voice:
- FIX THE FAKE AUDIO (priority 1): `let audioPulse = u.zoom_config.w;` is mouse-DOWN, not audio - the twist 'audio' wobble only fires while the mouse is held, and plasmaBuffer is declared but never read. Rewire: bass (`plasmaBuffer[0].x`) -> cell compression around the Frederiks threshold, mids (`plasmaBuffer[0].y`) -> twist oscillation, treble (`plasmaBuffer[0].z`) -> Schlieren sparkle grain.
- Spectrum retardation bands: read per-bin `plasmaBuffer[1..8]` and add a per-bin radial Newton-ring fringe term to the phase retardation, so the interference rainbow visibly decomposes into 8 spectral bands.
- Click voltage pulses: loop ripples[] (guard `min(u32(u.config.y), 50u)`) as propagating voltage fronts that locally flip the director orientation as they pass, and spring-damper the mouse defect core (2 extraBuffer slots in [133..255]) for smooth tracking.
- Wire exactly 4 slider params via u.zoom_params.x/y/z/w using the EXISTING JSON params (same ids, names, defaults, min/max/step, and mapping order) — add them to updatedParams with index 0-3. These param ids/defaults are the saved-preset contract: do not rename or re-default them.
- Make each slider drive meaningful shader-specific constants in the WGSL. If the current mapping is generic boilerplate (e.g. a shared intensity/speed/contrast helper), rewire it so each slider visibly controls a real constant of THIS shader's algorithm.
- Preserve the shader's core algorithm and its soul — upgrade, don't rewrite.
- CAUTION: preserve the `phaseRetardation()` physical wavelength constants (650/530/460 nm x 0.001) and the `rotatePolarization` Mueller-matrix math VERBATIM - the interference colors depend on them. extraBuffer persistent state goes in [133..255] ONLY ([0..4] reserved, [5..132] = engine FFT bins).

## Required Output Format

- Return exactly one fenced WGSL block (` ```wgsl ` ... ` ``` `).
- No prose before or after the fence.
- Preserve the canonical 13-binding compute layout:
  - @binding(0) sampler, (1) readTexture, (2) writeTexture, (3) Uniforms, (4) readDepthTexture, (5) non_filtering_sampler, (6) writeDepthTexture, (7) dataTextureA, (8) dataTextureB, (9) dataTextureC, (10) extraBuffer (read_write), (11) comparison_sampler, (12) plasmaBuffer (read).
- Workgroup size must be `@workgroup_size(16, 16, 1)`.
- Write to `writeTexture`, `writeDepthTexture`, and `dataTextureA` every frame.
- Use `textureSampleLevel(..., 0.0)` for sampler reads and `textureLoad` for storage reads.
- Do not use WGSL reserved keywords as identifiers (e.g. `target`). Do not add or renumber bindings. Binding 13 (historyTexture) is optional - only declare it if the shader already uses it.
- extraBuffer (if ever used): [0..4] reserved, [5..132] = engine FFT bins - persistent shader state goes in [133..255] ONLY.

## JSON Parameters / Controls

```json
{
  "id": "liquid_crystal_birefringence",
  "name": "Liquid Crystal",
  "url": "shaders/liquid_crystal_birefringence.wgsl",
  "description": "Liquid crystal optical effects with birefringent double refraction, twisted nematic polarization rotation, and Schlieren texture",
  "tags": [
    "interactive",
    "cursor",
    "liquid-crystal",
    "birefringence",
    "polarization",
    "optics",
    "lcd"
  ],
  "features": [
    "mouse-driven",
    "rgba",
    "birefringence",
    "polarization",
    "liquid-crystal",
    "schlieren"
  ],
  "params": [
    {
      "id": "param1",
      "name": "Thickness",
      "default": 0.5,
      "min": 0,
      "max": 1,
      "step": 0.1,
      "mapping": "zoom_params.x"
    },
    {
      "id": "param2",
      "name": "Twist",
      "default": 0.5,
      "min": 0,
      "max": 1,
      "step": 0.1,
      "mapping": "zoom_params.y"
    },
    {
      "id": "param3",
      "name": "Birefringence",
      "default": 0.3,
      "min": 0,
      "max": 1,
      "step": 0.1,
      "mapping": "zoom_params.z"
    },
    {
      "id": "param4",
      "name": "Voltage",
      "default": 0.2,
      "min": 0,
      "max": 1,
      "step": 0.1,
      "mapping": "zoom_params.w"
    }
  ],
  "target_rating": 4.7,
  "updatedParams": [
    {
      "index": 0,
      "name": "Thickness",
      "default": 0.5,
      "min": 0.0,
      "max": 1.0,
      "step": 0.1
    },
    {
      "index": 1,
      "name": "Twist",
      "default": 0.5,
      "min": 0.0,
      "max": 1.0,
      "step": 0.1
    },
    {
      "index": 2,
      "name": "Birefringence",
      "default": 0.3,
      "min": 0.0,
      "max": 1.0,
      "step": 0.1
    },
    {
      "index": 3,
      "name": "Voltage",
      "default": 0.2,
      "min": 0.0,
      "max": 1.0,
      "step": 0.1
    }
  ],
  "updated": true
}
```

## Current WGSL Code

```wgsl
// ═══════════════════════════════════════════════════════════════════════════════
//  liquid_crystal_birefringence.wgsl - Liquid Crystal Optical Effects
//  
//  RGBA Focus: Alpha = polarization rotation amount
//  Techniques:
//    - Birefringent double refraction
//    - Polarization rotation through twisted nematic
//    - Color shifting based on cell thickness
//    - Electric field response (mouse-driven)
//    - Schlieren texture visualization
//  
//  Target: 4.7★ rating
// ═══════════════════════════════════════════════════════════════════════════════

@group(0) @binding(0) var u_sampler: sampler;
@group(0) @binding(1) var readTexture: texture_2d<f32>;
@group(0) @binding(2) var writeTexture: texture_storage_2d<rgba32float, write>;
@group(0) @binding(3) var<uniform> u: Uniforms;
@group(0) @binding(4) var readDepthTexture: texture_2d<f32>;
@group(0) @binding(5) var non_filtering_sampler: sampler;
@group(0) @binding(6) var writeDepthTexture: texture_storage_2d<r32float, write>;
@group(0) @binding(7) var dataTextureA: texture_storage_2d<rgba32float, write>;
@group(0) @binding(8) var dataTextureB: texture_storage_2d<rgba32float, write>;
@group(0) @binding(9) var dataTextureC: texture_2d<f32>;
@group(0) @binding(10) var<storage, read_write> extraBuffer: array<f32>;
@group(0) @binding(11) var comparison_sampler: sampler_comparison;
@group(0) @binding(12) var<storage, read> plasmaBuffer: array<vec4<f32>>;

struct Uniforms {
  config: vec4<f32>,
  zoom_config: vec4<f32>,
  zoom_params: vec4<f32>,
  ripples: array<vec4<f32>, 50>,
};

const PI: f32 = 3.14159265359;

// Schlieren texture (liquid crystal director field)
fn schlierenTexture(uv: vec2<f32>, time: f32) -> vec2<f32> {
    let scale = 8.0;
    let x = uv.x * scale;
    let y = uv.y * scale;
    
    // Twisted nematic pattern
    let twist = sin(x + time * 0.5) * cos(y + time * 0.3);
    let angle = twist * PI * 0.5;
    
    return vec2<f32>(cos(angle), sin(angle));
}

// Director field with defects
fn directorField(uv: vec2<f32>, time: f32, mouse: vec2<f32>) -> vec2<f32> {
    var dir = vec2<f32>(0.0);
    
    // Base twist
    let baseAngle = uv.x * PI * 2.0 + time * 0.2;
    dir = vec2<f32>(cos(baseAngle), sin(baseAngle));
    
    // Mouse creates defect
    let toMouse = uv - mouse;
    let dist = length(toMouse);
    let defectStrength = smoothstep(0.3, 0.0, dist);
    let defectAngle = atan2(toMouse.y, toMouse.x) * 0.5;
    let defectDir = vec2<f32>(cos(defectAngle), sin(defectAngle));
    
    dir = mix(dir, defectDir, defectStrength);
    
    // Add turbulence
    let turb = schlierenTexture(uv * 2.0, time);
    dir = normalize(dir + turb * 0.3);
    
    return dir;
}

// Birefringent phase retardation
fn phaseRetardation(thickness: f32, birefringence: f32, wavelength: f32) -> f32 {
    return 2.0 * PI * thickness * birefringence / wavelength;
}

// Apply polarization rotation
fn rotatePolarization(color: vec3<f32>, angle: f32, retardation: vec3<f32>) -> vec3<f32> {
    // Simplified Mueller matrix for twisted nematic
    let cosA = cos(angle);
    let sinA = sin(angle);
    
    // Each channel gets different retardation
    var result: vec3<f32>;
    result.r = color.r * cosA * cosA + color.g * sinA * sinA * cos(retardation.r);
    result.g = color.r * sinA * sinA + color.g * cosA * cosA * cos(retardation.g);
    result.b = color.b * cos(retardation.b);
    
    return result;
}

// Color from birefringence
fn birefringenceColor(phase: f32) -> vec3<f32> {
    // Newton's rings color sequence
    let hue = fract(phase / (2.0 * PI));
    return vec3<f32>(
        sin(hue * 6.28) * 0.5 + 0.5,
        sin(hue * 6.28 + 2.09) * 0.5 + 0.5,
        sin(hue * 6.28 + 4.19) * 0.5 + 0.5
    );
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let resolution = u.config.zw;
    let coord = vec2<i32>(global_id.xy);
    
    if (f32(coord.x) >= resolution.x || f32(coord.y) >= resolution.y) {
        return;
    }
    
    let uv = vec2<f32>(global_id.xy) / resolution;
    let time = u.config.x;
    
    // Parameters
    let cellThickness = 0.5 + u.zoom_params.x; // 0.5-1.5
    let twistAngle = u.zoom_params.y * PI * 2.0; // 0-2π twist
    let birefringence = 0.1 + u.zoom_params.z * 0.2; // 0.1-0.3
    let voltage = u.zoom_params.w; // Electric field effect
    let mousePos = u.zoom_config.yz;
    let isMouseDown = u.zoom_config.w > 0.5;
    let distToMouse = length(uv - mousePos);
    let mouseGravity = 1.0 - smoothstep(0.0, 0.3, distToMouse);
    let clickPulse = select(0.0, 1.0, isMouseDown) * exp(-distToMouse * 5.0);
    
    let audioPulse = u.zoom_config.w;
    
    // Director field
    let director = directorField(uv, time, mousePos);
    
    // Effective thickness varies with voltage (Frederiks transition)
    let effectiveVoltage = voltage + mouseGravity * 0.3 + clickPulse * 0.5;
    let effectiveThickness = cellThickness * (1.0 - effectiveVoltage * 0.7);
    
    // Phase retardation for RGB (different wavelengths)
    let wavelengthR = 650.0;
    let wavelengthG = 530.0;
    let wavelengthB = 460.0;
    
    let localBirefringence = birefringence * (1.0 + mouseGravity);
    let retardation = vec3<f32>(
        phaseRetardation(effectiveThickness, localBirefringence, wavelengthR * 0.001),
        phaseRetardation(effectiveThickness, localBirefringence, wavelengthG * 0.001),
        phaseRetardation(effectiveThickness, localBirefringence, wavelengthB * 0.001)
    );
    
    // Twist angle varies across cell
    let localTwist = twistAngle * uv.x + audioPulse * sin(time * 5.0 + uv.y * 10.0) + mouseGravity * 2.0 + clickPulse * 3.0;
    
    // Sample background
    let bg = textureSampleLevel(readTexture, u_sampler, uv, 0.0).rgb;
    
    // Apply polarization effect
    var color = rotatePolarization(bg, localTwist, retardation);
    
    // Add birefringence interference colors
    let interference = birefringenceColor(retardation.g + time * 0.5);
    color = mix(color, interference, 0.3 * (1.0 - voltage * 0.5));
    
    // Schlieren texture overlay
    let schlieren = length(schlierenTexture(uv, time));
    color += vec3<f32>(0.1, 0.15, 0.2) * schlieren * 0.5;
    
    // Alpha based on polarization rotation amount
    let rotationAmount = abs(sin(localTwist)) * (1.0 + birefringence);
    let finalAlpha = rotationAmount * 0.7 + 0.3;
    
    // Tone mapping
    color = color / (1.0 + color * 0.3);
    
    // Vignette
    let vignette = 1.0 - length(uv - 0.5) * 0.3;
    
    textureStore(writeTexture, coord, vec4<f32>(color * vignette, finalAlpha * vignette));
    textureStore(writeDepthTexture, coord, vec4<f32>(finalAlpha, 0.0, 0.0, 1.0));
    
    textureStore(dataTextureA, coord, vec4<f32>(color, finalAlpha));
}
```
