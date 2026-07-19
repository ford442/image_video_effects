// ═══ RIPPLE TANK — PASS 1/3: WAVE STEP + SOURCE INJECTION ══════════════════
//  Category: simulation (multipass 1 of 3: step → optics gather → render)
//  Discrete 2D wave equation on a height field, 5×5 Laplacian.
//
//  State packing (dataTextureA = committed, dataTextureC = previous frame):
//    .r = height u(t)
//    .g = velocity ∂u/∂t
//    .b = previous height u(t-1)
//    .a = driver phase accumulator (mouse oscillator)
//
//  Data flow (Tier B — no graph runner):
//    read dataTextureC (t-1) → integrate + inject → write dataTextureA.
//    dataTextureA → dataTextureC copy happens automatically after the chain;
//    this pass is the ONLY writer of dataTextureA in the chain.
//    dataTextureB is never referenced so its feedback copy stays disabled.
//
//  zoom_params: .x wave speed, .y damping, .z source strength, .w boundary reflect

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
  config: vec4<f32>,       // .x = time, .y = delta_time, .zw = resolution
  zoom_config: vec4<f32>,  // .x = zoom, .yz = mouse_uv, .w = mouse_down
  zoom_params: vec4<f32>,  // .x wave speed, .y damping, .z source, .w boundary
  ripples: array<vec4<f32>, 50>,
};

const PI: f32 = 3.14159265359;
const TAU: f32 = 6.28318530718;

fn hashf(n: f32) -> f32 {
    return fract(sin(n * 127.1) * 43758.5453);
}
fn hash2f(n: f32) -> vec2<f32> {
    return vec2<f32>(hashf(n), hashf(n + 73.156));
}

fn loadHeight(pixel: vec2<i32>, res: vec2<i32>) -> f32 {
    let p = clamp(pixel, vec2<i32>(0), res - vec2<i32>(1));
    return textureLoad(dataTextureC, p, 0).r;
}

// 5×5 Laplacian — stable wide-stencil ∇²u.
// Neighbor weights sum to 28, so the center is -28: the kernel must sum to
// zero or a uniform field self-amplifies (the legacy wave-equation 5×5 kernel
// used -24 and was unstable, which is why its main() fell back to 3×3).
fn laplacian5x5(pixel: vec2<i32>, res: vec2<i32>) -> f32 {
    var sum = -28.0 * loadHeight(pixel, res);
    // ring 1 (cross, weight 4)
    sum += 4.0 * loadHeight(pixel + vec2<i32>( 1,  0), res);
    sum += 4.0 * loadHeight(pixel + vec2<i32>(-1,  0), res);
    sum += 4.0 * loadHeight(pixel + vec2<i32>( 0,  1), res);
    sum += 4.0 * loadHeight(pixel + vec2<i32>( 0, -1), res);
    // ring 1 diagonals (weight 2)
    sum += 2.0 * loadHeight(pixel + vec2<i32>( 1,  1), res);
    sum += 2.0 * loadHeight(pixel + vec2<i32>( 1, -1), res);
    sum += 2.0 * loadHeight(pixel + vec2<i32>(-1,  1), res);
    sum += 2.0 * loadHeight(pixel + vec2<i32>(-1, -1), res);
    // ring 2 cross (weight 1)
    sum += 1.0 * loadHeight(pixel + vec2<i32>( 2,  0), res);
    sum += 1.0 * loadHeight(pixel + vec2<i32>(-2,  0), res);
    sum += 1.0 * loadHeight(pixel + vec2<i32>( 0,  2), res);
    sum += 1.0 * loadHeight(pixel + vec2<i32>( 0, -2), res);
    return sum / 14.0;  // ≈ ∇²u with the wide stencil's effective spacing
}

// Smooth radial impulse profile for drops and drivers
fn splash(distSq: f32, radius: f32) -> f32 {
    let d = sqrt(distSq) / radius;
    return smoothstep(1.0, 0.0, d) * cos(d * PI * 0.5);
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let pixel = vec2<i32>(global_id.xy);
    let res   = vec2<f32>(u.config.zw);
    if (pixel.x >= i32(res.x) || pixel.y >= i32(res.y)) { return; }

    let resI  = vec2<i32>(res);
    let uv    = vec2<f32>(pixel) / res;
    let aspect = vec2<f32>(res.x / res.y, 1.0);
    let time  = u.config.x;

    let bass   = plasmaBuffer[0].x;
    let mids   = plasmaBuffer[0].y;
    let treble = plasmaBuffer[0].z;

    // ── Parameter mapping ──────────────────────────────────────────────────
    let waveSpeed      = mix(0.08, 0.45, u.zoom_params.x);
    let damping        = mix(0.975, 0.9995, u.zoom_params.y);
    let sourceStrength = mix(0.15, 1.5, u.zoom_params.z) * (1.0 + bass * 0.6);
    let driverFreq     = mix(4.0, 18.0, u.zoom_params.z) * (1.0 + treble * 0.5);
    let boundaryReflect = u.zoom_params.w;

    // ── Wave equation step (Verlet-style) ──────────────────────────────────
    let state = textureLoad(dataTextureC, pixel, 0);
    var height   = state.r;
    var velocity = state.g;
    var phase    = state.a;

    let lap = laplacian5x5(pixel, resI);
    velocity += waveSpeed * waveSpeed * lap;
    velocity *= damping;
    let prevHeight = height;
    height += velocity;

    // ── Injection: mouse driver (hold to oscillate) ────────────────────────
    let mouse = u.zoom_config.yz;
    let mouseDown = u.zoom_config.w > 0.5;
    let dm = (uv - mouse) * aspect;
    let mouseDistSq = dot(dm, dm);
    let mouseRadius = 0.018;
    if (mouseDown && mouseDistSq < mouseRadius * mouseRadius) {
        phase += driverFreq * 0.016;
        let drive = sin(phase * TAU) * sourceStrength * 0.4;
        height += drive * splash(mouseDistSq, mouseRadius);
    }
    phase = fract(phase);

    // ── Injection: click ripples (sharp expanding-ring impulses) ───────────
    for (var i = 0; i < 50; i++) {
        let ripple = u.ripples[i];
        if (ripple.z <= 0.0) { continue; }
        let age = time - ripple.z;
        // Brief press-down impulse — the wave equation turns it into a ring
        if (age < 0.0 || age > 0.1) { continue; }
        let dr = (uv - ripple.xy) * aspect;
        let distSq = dot(dr, dr);
        let radius = 0.02;
        if (distSq < radius * radius) {
            let punch = (1.0 - age / 0.1) * sourceStrength * ripple.w;
            height -= punch * 0.5 * splash(distSq, radius);
        }
    }

    // ── Injection: ambient audio-reactive rain (keeps idle tank alive) ─────
    let dripRate = 0.7 + treble * 0.9;
    for (var d = 0; d < 2; d++) {
        let t = time * dripRate + f32(d) * 0.5;
        let cell = floor(t);
        let age  = fract(t) / dripRate;
        let pos  = hash2f(cell * 7.31 + f32(d) * 91.7) * 0.8 + vec2<f32>(0.1);
        if (age < 0.08) {
            let dd = (uv - pos) * aspect;
            let distSq = dot(dd, dd);
            let radius = 0.014;
            if (distSq < radius * radius) {
                let amp = sourceStrength * 0.25 * (0.35 + mids * 0.8);
                height -= amp * splash(distSq, radius) * (1.0 - age / 0.08);
            }
        }
    }

    // ── Boundary: absorbing (fade at edges) ↔ reflecting (free waves) ──────
    let edgeDist = min(min(uv.x, 1.0 - uv.x), min(uv.y, 1.0 - uv.y));
    let edgeFade = smoothstep(0.0, 0.06, edgeDist);
    let absorb = mix(edgeFade, 1.0, boundaryReflect);
    height   *= absorb;
    velocity *= absorb;

    // Stability clamp
    height   = clamp(height, -1.5, 1.5);
    velocity = clamp(velocity, -0.8, 0.8);

    textureStore(dataTextureA, pixel, vec4<f32>(height, velocity, prevHeight, phase));
}
