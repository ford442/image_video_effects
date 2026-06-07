// gen-showcase-kinetic-bloom.wgsl
// Showcase shader optimized for: idle animation + mouse claim + audio reactivity
// Geometric flower/mandala that breathes and rotates. Mouse controls the center and 
// opens the petals. Audio-reactive: bass opens petals, mid spins faster, treble adds pollen sparkles.

// 13-binding universal layout (matches all 694+ shaders in this repo)
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
    config: vec4<f32>,       // x: time, y: unused, z: unused, w: unused
    zoom_config: vec4<f32>,  // x: mouseX, y: mouseY, z: mouseDown, w: unused
    zoom_params: vec4<f32>,  // x: petals, y: complexity, z: openness, w: spin
    ripples: array<vec4<f32>, 50>,
};

const PI: f32 = 3.14159265359;
const TAU: f32 = 6.28318530718;

// --- Hash / Noise helpers ---
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

// --- SDF helpers ---
fn sdCircle(p: vec2<f32>, r: f32) -> f32 {
    return length(p) - r;
}

fn sdSegment(p: vec2<f32>, a: vec2<f32>, b: vec2<f32>) -> f32 {
    let pa = p - a;
    let ba = b - a;
    let h = clamp(dot(pa, ba) / dot(ba, ba), 0.0, 1.0);
    return length(pa - ba * h);
}

// --- Polar helpers ---
fn toPolar(p: vec2<f32>) -> vec2<f32> {
    return vec2<f32>(length(p), atan2(p.y, p.x));
}

// --- Color palette ---
fn palette(t: f32) -> vec3<f32> {
    // Warm gold → coral → magenta → deep purple
    let a = vec3<f32>(0.5, 0.5, 0.5);
    let b = vec3<f32>(0.5, 0.5, 0.5);
    let c = vec3<f32>(1.0, 0.7, 0.9);
    let d = vec3<f32>(0.0, 0.33, 0.67);
    return a + b * cos(TAU * (c * t + d));
}

@compute @workgroup_size(8, 8)
fn main(@builtin(global_invocation_id) id: vec3<u32>) {
    let dims = vec2<f32>(textureDimensions(writeTexture));
    let texel = vec2<f32>(id.xy);
    let uv = texel / dims;

    let t = u.config.x;
    let mouseDown = u.zoom_config.w;
    let mouse = u.zoom_config.yz;

    // Audio data
    let bass = extraBuffer[0];
    let mids = extraBuffer[1];
    let treble = extraBuffer[2];
    let overall = (bass + mids + treble) / 3.0;

    // Zoom params
    let petalCount = u.zoom_params.x;
    let complexity = u.zoom_params.y;
    let openness = u.zoom_params.z;
    let spin = u.zoom_params.w;

    // Aspect-corrected centered coordinates
    let p = (uv - 0.5) * 2.0;
    let aspect = dims.x / dims.y;
    p.x *= aspect;

    // Mouse interaction
    let mousePos = (mouse - 0.5) * 2.0;
    mousePos.x *= aspect;
    let mDist = length(p - mousePos);

    // When mouse is claimed, center the bloom at mouse and increase openness
    var center = vec2<f32>(0.0);
    var openMod = openness;
    var spinMod = spin;
    if (mouseDown > 0.5) {
        center = mousePos;
        openMod = mix(openness, 1.0, 0.5); // petals open more when claimed
        spinMod = spin * (1.0 + mDist * 0.5); // spin faster near mouse
    }

    // Local coordinates relative to bloom center
    let lp = p - center;
    let polar = toPolar(lp);
    let r = polar.x;
    let theta = polar.y;

    // Petal count: 3 to 12 based on param
    let nPetals = 3.0 + petalCount * 9.0;

    // Spin over time + audio mid
    let rot = theta + t * spinMod * TAU * 0.1 + mids * 0.5;

    // Petal shape using sine modulation of radius
    let petalShape = 0.5 + 0.5 * cos(rot * nPetals);
    let petalR = 0.3 + openMod * 0.4 * petalShape;

    // Bloom intensity: petals + core
    let bloom = 1.0 - smoothstep(0.0, petalR, r);
    let core = 1.0 - smoothstep(0.0, 0.15, r);

    // Secondary ring structure (complexity)
    let rings = sin(r * 20.0 - t * 2.0 * spinMod) * complexity;
    let ringMask = smoothstep(0.0, 0.5, bloom) * (1.0 - smoothstep(0.5, 1.0, bloom));

    // Color based on angle and depth
    let colorT = theta / TAU + t * 0.03 + bass * 0.1 + r * 0.5;
    var col = palette(colorT);

    // Add warmth to core
    col += core * vec3<f32>(1.0, 0.8, 0.4) * 0.5;

    // Rings add chromatic detail
    col += rings * ringMask * vec3<f32>(0.3, 0.5, 0.7) * complexity;

    // Treble adds pollen sparkles
    let pollen = hash22(floor(lp * 80.0 + t * 0.02)).x;
    let pollenGlow = smoothstep(0.97, 1.0, pollen) * treble * 3.0;
    col += vec3<f32>(pollenGlow * 0.9, pollenGlow * 0.7, pollenGlow * 0.3);

    // Bass makes the bloom "pulse" brighter
    let pulse = 1.0 + bass * 0.5;
    col *= pulse;

    // Mouse glow when claimed
    if (mouseDown > 0.5) {
        let mouseGlow = exp(-mDist * 5.0) * 0.3;
        col += vec3<f32>(0.5, 0.8, 1.0) * mouseGlow;
    }

    // Vignette
    let vig = 1.0 - smoothstep(0.4, 1.2, length(p));
    col *= vig;

    // Output
    let final = vec4<f32>(col * bloom, 1.0);
    textureStore(writeTexture, id.xy, final);

    // Depth
    textureStore(depthWriteTexture, id.xy, vec4<f32>(bloom, 0.0, 0.0, 1.0));
}
