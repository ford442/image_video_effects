// gen-showcase-nebula-core.wgsl
// Showcase shader optimized for: idle animation + mouse claim + audio reactivity
// Deep-space nebula core with layered plasma clouds, gravity-well mouse interaction,
// and audio-reactive shockwaves / sparkles.
// Enriched with Wolfram Alpha Hydrogen Balmer Series astrophysics data.

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
    config: vec4<f32>,       // x: time, y: unused, z: unused, w: unused
    zoom_config: vec4<f32>,  // x: mouseX, y: mouseY, z: mouseDown, w: unused
    zoom_params: vec4<f32>,  // x: density, y: chaos, z: warpAmt, w: speed
    ripples: array<vec4<f32>, 50>,
};

const PI: f32 = 3.14159265359;
const TAU: f32 = 6.28318530718;

// --- ACES Filmic Tone Mapping ---
fn acesToneMap(x: vec3<f32>) -> vec3<f32> {
    let a = 2.51; let b = 0.03; let c = 2.43; let d = 0.59; let e = 0.14;
    return clamp((x * (a * x + b)) / (x * (c * x + d) + e), vec3<f32>(0.0), vec3<f32>(1.0));
}

// --- Hash / Noise helpers (canonical, naga-safe) ---
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

// --- Domain warping (canonical "Inigo" style) ---
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

// --- Hydrogen Balmer Series (Wolfram Alpha astrophysics data) ---
// H-alpha: 6562.71 Å → red  |  H-beta: 4861.28 Å → cyan
// H-gamma: 4340.47 Å → blue |  H-delta: 4101.71 Å → violet
fn balmerNebula(dist: f32, nebula: f32, ionization: f32) -> vec3<f32> {
    let hAlpha  = vec3<f32>(1.0, 0.1, 0.0);  // 6562.71 Å — red
    let hBeta   = vec3<f32>(0.0, 0.8, 1.0);  // 4861.28 Å — cyan
    let hGamma  = vec3<f32>(0.2, 0.3, 1.0);  // 4340.47 Å — blue
    let hDelta  = vec3<f32>(0.6, 0.0, 1.0);  // 4101.71 Å — violet

    let core  = smoothstep(0.4 + ionization * 0.3, 0.0, dist);
    let mid   = smoothstep(0.7 + ionization * 0.2, 0.3, dist) * smoothstep(0.0, 0.3, dist);
    let outer = smoothstep(1.2, 0.6, dist);

    return (hAlpha * core + hBeta * mid + hGamma * outer * 0.5 + hDelta * (1.0 - smoothstep(0.0, 1.5, dist)) * 0.25)
           * (0.3 + nebula * 1.4);
}

@compute @workgroup_size(8, 8)
fn main(@builtin(global_invocation_id) id: vec3<u32>) {
    let dims = vec2<f32>(textureDimensions(writeTexture));
    let texel = vec2<f32>(id.xy);
    let uv = texel / dims;
    let coords = vec2<i32>(id.xy);

    let t = u.config.x;
    let mouseDown = u.zoom_config.w;
    let mouse = u.zoom_config.yz;

    // Audio data from plasmaBuffer
    let bass = plasmaBuffer[0].x;
    let mids = plasmaBuffer[0].y;
    let treble = plasmaBuffer[0].z;
    let overall = (bass + mids + treble) / 3.0;

    // Zoom params
    let density = u.zoom_params.x;
    let chaos = u.zoom_params.y;
    let warpAmt = u.zoom_params.z;
    let speed = u.zoom_params.w;

    // Aspect-corrected centered coordinates
    var p = (uv - 0.5) * 2.0;
    let aspect = dims.x / dims.y;
    p.x *= aspect;

    // Mouse interaction: gravity well when claimed
    var mousePos = (mouse - 0.5) * 2.0;
    mousePos.x *= aspect;
    let mDist = length(p - mousePos);
    let mousePull = exp(-mDist * 3.0) * mouseDown;

    // Domain warp with mouse gravity + audio chaos
    var wp = p;
    if (mouseDown > 0.5) {
        wp = p + (mousePos - p) * mousePull * 0.5;
    }
    wp = warpDomain(wp * (1.0 + density * 2.0), t * speed * (1.0 + mids * 0.3));

    // Layered nebula clouds (3 octaves of fBM for performance)
    let f1 = fbm(wp + t * 0.1 * speed, 5);
    let f2 = fbm(wp * 2.0 - t * 0.15 * speed, 4);
    let f3 = fbm(wp * 0.5 + t * 0.05 * speed + 10.0, 3);

    let nebula = f1 * 0.5 + f2 * 0.3 + f3 * 0.2;

    // Ionization front driven by bass
    let ionization = smoothstep(0.3, 0.7, bass);

    // Balmer emission colors — H-alpha dominates core, H-beta in mid regions
    let dist = length(p);
    var col = balmerNebula(dist, nebula, ionization);

    // Treble adds chromatic sparkles / fine structure
    col += vec3<f32>(treble * 0.3, treble * 0.1, treble * 0.5) * f2;

    // Bass shockwave rings (tinted with H-beta cyan)
    let ringDist = length(p) * (1.0 + bass * 0.5);
    let rings = sin(ringDist * 10.0 - t * 2.0 * speed) * exp(-ringDist * 2.0);
    col += rings * bass * vec3<f32>(0.0, 0.8, 1.0);

    // Fine particles from treble (star-like)
    let particles = hash22(floor(p * 50.0 + t * 0.01)).x;
    let particleGlow = smoothstep(0.98, 1.0, particles) * treble * 2.0;
    col += vec3<f32>(particleGlow);

    // Mouse glow when active — seeds new star formation
    if (mouseDown > 0.5) {
        let mouseGlow = exp(-mDist * 4.0) * 0.5;
        col += vec3<f32>(0.9, 0.95, 1.0) * mouseGlow;
        // New star formation burst driven by bass
        let starBurst = exp(-mDist * 12.0) * bass * 3.0;
        col += vec3<f32>(1.0, 0.8, 0.6) * starBurst;
    }

    // Vignette
    let vig = 1.0 - smoothstep(0.5, 1.5, length(p));
    col *= vig;

    // Step 3: Temporal feedback
    let prev = textureLoad(dataTextureC, coords, 0);
    col = mix(prev.rgb * 0.96, col, 0.25);

    // Step 4: Chromatic aberration
    let caStr = 0.003 * (1.0 + bass);
    col = vec3<f32>(col.r + caStr, col.g, col.b - caStr * 0.5);

    // Step 5: ACES tone mapping + semantic alpha
    col = acesToneMap(col * 1.1);
    let alpha = clamp(length(col) * 1.2, 0.2, 0.95);

    let outColor = vec4<f32>(col * (0.8 + overall * 0.4), alpha);
    textureStore(writeTexture, coords, outColor);
    textureStore(dataTextureA, coords, outColor);

    // Write depth (nebula intensity as depth)
    textureStore(writeDepthTexture, coords, vec4<f32>(nebula, 0.0, 0.0, 1.0));
}
