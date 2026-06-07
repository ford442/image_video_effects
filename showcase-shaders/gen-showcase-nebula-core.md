# Showcase-Optimized Generative Shader: `gen-showcase-nebula-core`

## Design Goals
- **Idle:** Hypnotic, slow-moving nebula with organic pulsation — captivating even without interaction
- **Mouse Claim:** Mouse becomes a gravity well that pulls the nebula's plasma, dramatically warping the field
- **Audio Reactivity:** Bass → nebula density/intensity, Mid → rotation speed, Treble → chromatic sparkles, Overall → zoom pulse
- **Performance:** Single-pass, no heavy loops, uses smooth fBM and domain warping

## Visual Description
A deep-space nebula core with layered plasma clouds. Colors shift slowly across the spectrum (gold → magenta → cyan). When mouse is claimed, the core "breathes" toward the cursor. Bass hits create bright shockwave rings. Treble adds fine star-like particles.

## WGSL Header
```wgsl
// gen-showcase-nebula-core.wgsl
// Showcase shader optimized for: idle animation + mouse claim + audio reactivity

// 13-binding universal layout (must match all shaders)
@group(0) @binding(0) var nearestSampler: sampler;
@group(0) @binding(1) var readTexture: texture_2d<f32>;
@group(0) @binding(2) var writeTexture: texture_storage_2d<rgba32float, write>;
@group(0) @binding(3) var<uniform> u: Uniforms;
@group(0) @binding(4) var depthTexture: texture_2d<f32>;
@group(0) @binding(5) var nearestClampSampler: sampler;
@group(0) @binding(6) var depthWriteTexture: texture_storage_2d<r32float, write>;
@group(0) @binding(7) var dataTextureA: texture_storage_2d<rgba32float, write>;
@group(0) @binding(8) var dataTextureB: texture_storage_2d<rgba32float, write>;
@group(0) @binding(9) var dataTextureC: texture_storage_2d<rgba32float, write>;
@group(0) @binding(10) var<storage, read> extraBuffer: array<f32>;
@group(0) @binding(11) var videoTexture: texture_2d<f32>;
@group(0) @binding(12) var videoSampler: sampler;

struct Uniforms {
    config: vec4<f32>,
    zoom_config: vec4<f32>,
    zoom_params: vec4<f32>,
    ripples: array<vec4<f32>, 50>,
};

const PI: f32 = 3.14159265359;
const TAU: f32 = 6.28318530718;

// --- Noise / fBM helpers ---
fn hash22(p: vec2<f32>) -> vec2<f32> {
    var p3 = fract(vec3<f32>(p.xyx) * vec3<f32>(0.1031, 0.1030, 0.0973));
    p3 += dot(p3, p3.yzx + 33.33);
    return fract((p3.xx + p3.yz) * p3.zy);
}

fn vnoise2(p: vec2<f32>) -> f32 {
    let i = floor(p);
    let f = fract(p);
    let a = hash22(i).x;
    let b = hash22(i + vec2<f32>(1.0, 0.0)).x;
    let c = hash22(i + vec2<f32>(0.0, 1.0)).x;
    let d = hash22(i + vec2<f32>(1.0, 1.0)).x;
    let u = f * f * (3.0 - 2.0 * f);
    return mix(mix(a, b, u.x), mix(c, d, u.x), u.y);
}

fn fbm(p: vec2<f32>, octaves: i32) -> f32 {
    var value = 0.0;
    var amplitude = 0.5;
    var freq = 1.0;
    for (var i: i32 = 0; i < octaves; i = i + 1) {
        value += amplitude * vnoise2(p * freq);
        freq *= 2.0;
        amplitude *= 0.5;
    }
    return value;
}

// --- Color helpers ---
fn palette(t: f32) -> vec3<f32> {
    // Gold → Magenta → Cyan → back to warm
    let a = vec3<f32>(0.5, 0.5, 0.5);
    let b = vec3<f32>(0.5, 0.5, 0.5);
    let c = vec3<f32>(1.0, 1.0, 1.0);
    let d = vec3<f32>(0.263, 0.416, 0.557);
    return a + b * cos(TAU * (c * t + d));
}

// --- Domain warping ---
fn warpDomain(p: vec2<f32>, t: f32) -> vec2<f32> {
    let q = vec2<f32>(
        fbm(p + vec2<f32>(0.0, 0.0), 4),
        fbm(p + vec2<f32>(5.2, 1.3), 4)
    );
    let r = vec2<f32>(
        fbm(p + 4.0 * q + vec2<f32>(1.7, 9.2) + 0.15 * t, 4),
        fbm(p + 4.0 * q + vec2<f32>(8.3, 2.8) + 0.126 * t, 4)
    );
    return p + 2.0 * r;
}

@compute @workgroup_size(8, 8)
fn main(@builtin(global_invocation_id) id: vec3<u32>) {
    let dims = vec2<f32>(textureDimensions(writeTexture));
    let texel = vec2<f32>(id.xy);
    let uv = texel / dims;
    
    let t = u.config.x;
    let mouseDown = u.zoom_config.w;
    let mouse = u.zoom_config.yz;
    
    // Audio data (if available)
    let bass = extraBuffer[0];
    let mids = extraBuffer[1];
    let treble = extraBuffer[2];
    let overall = (bass + mids + treble) / 3.0;
    
    // Zoom params (modulated by audio if A-toggle is on in App.tsx)
    let density = u.zoom_params.x;
    let chaos = u.zoom_params.y;
    let warpAmt = u.zoom_params.z;
    let speed = u.zoom_params.w;
    
    // Centered coordinates
    let p = (uv - 0.5) * 2.0;
    let aspect = dims.x / dims.y;
    p.x *= aspect;
    
    // Mouse interaction (gravity well when claimed)
    let mousePos = (mouse - 0.5) * 2.0;
    mousePos.x *= aspect;
    let mDist = length(p - mousePos);
    let mousePull = exp(-mDist * 3.0) * mouseDown;
    
    // Warp domain based on mouse position when claimed
    var wp = p;
    if (mouseDown > 0.5) {
        wp = p + (mousePos - p) * mousePull * 0.5;
    }
    wp = warpDomain(wp * (1.0 + density * 2.0), t * speed);
    
    // Layered nebula clouds
    let f1 = fbm(wp + t * 0.1 * speed, 5);
    let f2 = fbm(wp * 2.0 - t * 0.15 * speed, 4);
    let f3 = fbm(wp * 0.5 + t * 0.05 * speed + 10.0, 3);
    
    // Combine layers with different contributions
    let nebula = f1 * 0.5 + f2 * 0.3 + f3 * 0.2;
    
    // Color cycling based on depth and time
    let colorT = nebula + t * 0.05 * speed + bass * 0.2;
    let col = palette(colorT);
    
    // Add chromatic variation based on treble
    col += vec3<f32>(treble * 0.3, treble * 0.1, treble * 0.5) * f2;
    
    // Shockwave rings from bass
    let ringDist = length(p) * (1.0 + bass * 0.5);
    let rings = sin(ringDist * 10.0 - t * 2.0 * speed) * exp(-ringDist * 2.0);
    col += rings * bass * vec3<f32>(0.8, 0.6, 0.3);
    
    // Fine particles from treble
    let particles = hash22(floor(p * 50.0 + t * 0.01)).x;
    let particleGlow = smoothstep(0.98, 1.0, particles) * treble * 2.0;
    col += vec3<f32>(particleGlow);
    
    // Mouse glow when active
    if (mouseDown > 0.5) {
        let mouseGlow = exp(-mDist * 4.0) * 0.5;
        col += vec3<f32>(0.3, 0.5, 1.0) * mouseGlow;
    }
    
    // Vignette
    let vig = 1.0 - smoothstep(0.5, 1.5, length(p));
    col *= vig;
    
    // Output
    let final = vec4<f32>(col * (0.8 + overall * 0.4), 1.0);
    textureStore(writeTexture, id.xy, final);
    
    // Write depth
    textureStore(depthWriteTexture, id.xy, vec4<f32>(nebula, 0.0, 0.0, 1.0));
}
```

## JSON Entry (shader_definitions/generative/nebula-core.json)
```json
{
  "id": "gen-showcase-nebula-core",
  "name": "Nebula Core",
  "category": "generative",
  "description": "Deep-space nebula with organic plasma. Mouse becomes gravity well. Audio-reactive: bass shockwaves, treble sparkles, mid rotation."
  "url": "shaders/gen-showcase-nebula-core.wgsl",
  "params": [
    { "name": "density", "default": 0.5, "min": 0, "max": 1, "label": "Plasma Density" },
    { "name": "chaos", "default": 0.3, "min": 0, "max": 1, "label": "Domain Chaos" },
    { "name": "warp", "default": 0.4, "min": 0, "max": 1, "label": "Warp Amount" },
    { "name": "speed", "default": 0.2, "min": 0, "max": 1, "label": "Time Speed" }
  ],
  "tags": ["showcase", "nebula", "space", "audio-reactive", "mouse-interactive"],
  "showcase": {
    "idleWeight": 1.0,
    "mouseClaimIntensity": 0.8,
    "audioBandMapping": {
      "bass": "zoomParam1",
      "mid": "zoomParam4",
      "treble": "zoomParam3",
      "overall": "zoomParam2"
    }
  }
}
```

## Showcase Behavior
- **Idle (0-11s):** Slow color cycling, gentle plasma drift, subtle shockwaves. The nebula feels alive but calm.
- **Mouse Claim (SPACE):** The cursor becomes a gravity source — plasma visibly pulls toward it, colors brighten, and the "breath" of the nebula intensifies near the mouse.
- **Audio Reactive:** Bass hits create expanding ring shockwaves. Treble adds star-like sparkles. Mids control rotation speed. The audio feels like it's "playing" the nebula.
