// ═══════════════════════════════════════════════════════════════════
//  Complex Exponent Warp
//  Category: distortion
//  Features: mouse-driven, audio-reactive, upgraded-rgba
//  Complexity: High
//  Upgraded: 2026-05-17
// ═══════════════════════════════════════════════════════════════════

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
  config: vec4<f32>,       // x=Time, y=MouseClickCount/FrameCount, z=ResX, w=ResY
  zoom_config: vec4<f32>,  // x=Time, y=MouseX, z=MouseY, w=MouseDown
  zoom_params: vec4<f32>,  // x=Param1, y=Param2, z=Param3, w=Param4
  ripples: array<vec4<f32>, 50>,
};

fn complex_mul(a: vec2<f32>, b: vec2<f32>) -> vec2<f32> {
    return vec2<f32>(a.x * b.x - a.y * b.y, a.x * b.y + a.y * b.x);
}

// z^w = exp(w * ln(z))
// Branchless: guard r=0 via max, never output garbage
fn complex_pow(z: vec2<f32>, w: vec2<f32>) -> vec2<f32> {
    let r     = max(length(z), 0.0001);
    let angle = atan2(z.y, z.x);

    // ln(z) = ln(r) + i*angle
    let ln_z     = vec2<f32>(log(r), angle);
    let exponent = complex_mul(w, ln_z);

    // exp(x + iy) = exp(x) * (cos(y) + i*sin(y))
    let mag = exp(exponent.x);
    return vec2<f32>(mag * cos(exponent.y), mag * sin(exponent.y));
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) gid: vec3<u32>) {
    let resolution = u.config.zw;
    if (gid.x >= u32(resolution.x) || gid.y >= u32(resolution.y)) {
        return;
    }

    let coord = vec2<i32>(gid.xy);
    let uv    = vec2<f32>(gid.xy) / resolution;
    let time  = u.config.x;

    // Audio reactivity
    let bass   = plasmaBuffer[0].x;
    let mids   = plasmaBuffer[0].y;
    let treble = plasmaBuffer[0].z;

    let aspect = resolution.x / max(resolution.y, 0.001);

    // Center UV on complex plane
    var z = (uv - 0.5) * 2.0;
    z.x *= aspect;

    let scale = mix(1.0, 5.0, u.zoom_params.x);
    z *= scale;

    let mouse = u.zoom_config.yz;

    let w_real = (mouse.x - 0.5) * mix(1.0, 10.0, u.zoom_params.z) + 1.0;
    // Mids add a time-varying imaginary exponent component
    let w_imag = (mouse.y - 0.5) * 6.0 + mids * sin(time) * 0.5;
    let w      = vec2<f32>(w_real, w_imag);

    var result_z = complex_pow(z, w);

    // Bass modulates spiral angle
    let spiral   = u.zoom_params.y * 3.14159265 + bass * 0.3;
    let rotation = vec2<f32>(cos(spiral), sin(spiral));
    result_z     = complex_mul(result_z, rotation);

    // Convert back to UV [0,1]
    result_z.x /= aspect;
    var final_uv = result_z * mix(0.1, 1.0, u.zoom_params.w) + 0.5;
    final_uv     = fract(final_uv);

    // Clamp before sampling (fract already keeps [0,1) but be explicit)
    let final_uv_clamped = clamp(final_uv, vec2<f32>(0.0), vec2<f32>(1.0));

    let sampled = textureSampleLevel(readTexture, u_sampler, final_uv_clamped, 0.0);

    // Alpha: encodes UV distance from center and bass (far-mapped = lower alpha)
    let uvDist    = length(result_z);
    let distAlpha = clamp(1.0 - uvDist * 0.15, 0.0, 1.0);
    let alpha     = clamp(distAlpha * (0.7 + bass * 0.3), 0.0, 1.0);

    let finalColor = vec4<f32>(sampled.rgb, alpha);

    textureStore(writeTexture, coord, finalColor);

    // Depth pass-through
    let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
    textureStore(writeDepthTexture, coord, vec4<f32>(depth, 0.0, 0.0, 0.0));
    textureStore(dataTextureA, coord, finalColor);
}
