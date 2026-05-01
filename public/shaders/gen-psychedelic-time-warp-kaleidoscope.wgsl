// ----------------------------------------------------------------
// Psychedelic Time-Warp Kaleidoscope
// Category: generative
// ----------------------------------------------------------------

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
    config: vec4<f32>,       // x=Time, y=Audio/ClickCount, z=ResX, w=ResY
    zoom_config: vec4<f32>,  // x=ZoomTime, y=MouseX, z=MouseY, w=Generic2
    zoom_params: vec4<f32>,  // x=Mirror Strength, y=Wobble, z=Noise Intensity, w=unused
    ripples: array<vec4<f32>, 50>,
};

// Hash function
fn hash31(p: vec3<f32>) -> f32 {
    let q = fract(p * 0.1031);
    let r = q + vec3<f32>(dot(q, q.yzx + vec3<f32>(33.33)));
    return fract((r.x + r.y) * r.z);
}

// 3D Noise for distortion
fn noise3D(p: vec3<f32>) -> f32 {
    let i = floor(p);
    let f = fract(p);
    let u = f * f * (vec3<f32>(3.0) - vec3<f32>(2.0) * f);
    return mix(
        mix(mix(hash31(i + vec3<f32>(0.0,0.0,0.0)), hash31(i + vec3<f32>(1.0,0.0,0.0)), u.x),
            mix(hash31(i + vec3<f32>(0.0,1.0,0.0)), hash31(i + vec3<f32>(1.0,1.0,0.0)), u.x), u.y),
        mix(mix(hash31(i + vec3<f32>(0.0,0.0,1.0)), hash31(i + vec3<f32>(1.0,0.0,1.0)), u.x),
            mix(hash31(i + vec3<f32>(0.0,1.0,1.0)), hash31(i + vec3<f32>(1.0,1.0,1.0)), u.x), u.y),
        u.z
    );
}

fn curlNoise3D(p: vec3<f32>) -> vec2<f32> {
    let e = 0.01;
    let nx = noise3D(p + vec3<f32>(e, 0.0, 0.0)) - noise3D(p - vec3<f32>(e, 0.0, 0.0));
    let ny = noise3D(p + vec3<f32>(0.0, e, 0.0)) - noise3D(p - vec3<f32>(0.0, e, 0.0));
    let nz = noise3D(p + vec3<f32>(0.0, 0.0, e)) - noise3D(p - vec3<f32>(0.0, 0.0, e));
    return vec2<f32>(ny - nz, nz - nx);
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let coords = vec2<i32>(global_id.xy);
    let res = vec2<f32>(u.config.z, u.config.w);
    if (coords.x >= i32(res.x) || coords.y >= i32(res.y)) { return; }

    let time = u.config.x;
    let audio = u.config.y; // Audio reactivity

    // Mouse center, default to middle if 0
    var center = u.zoom_config.yz * res;
    if (center.x == 0.0 && center.y == 0.0) {
        center = res * 0.5;
    }

    // Calculate 3D curl noise for distortion
    let norm_coords = vec2<f32>(coords) / res;
    let noise_val = curlNoise3D(vec3<f32>(norm_coords * 5.0, time * 0.2));

    // Store in dataTextureA as requested
    textureStore(dataTextureA, coords, vec4<f32>(noise_val, 0.0, 1.0));

    // Modulate based on u.zoom_params which might be 0.0 if sliders are missing.
    // If they are 0.0, default to interesting values.
    let mirror_strength = mix(1.0, 2.0, u.zoom_params.x);
    let wobble = mix(0.1, 0.5, u.zoom_params.y);
    let noise_intensity = mix(0.5, 2.0, u.zoom_params.z);

    // Retrieve sine wave from plasmaBuffer to modulate mirror count
    let plasmaIndex = u32(abs(time * 10.0 + audio * 100.0)) % 256u;
    var plasmaVal = plasmaBuffer[plasmaIndex].x;
    if (plasmaVal == 0.0) { plasmaVal = 0.5; }

    // Dynamic mirror count
    let min_mirrors = 3.0;
    let max_mirrors = 12.0;
    let mirror_count = mix(min_mirrors, max_mirrors, plasmaVal);
    let angle_step = 3.14159265 * 2.0 / mirror_count;

    var uv = vec2<f32>(coords) - center;
    let dist = length(uv);
    var angle = atan2(uv.y, uv.x);

    // Wobble effect
    angle += wobble * sin(dist * 0.02 - time * 2.0);

    // Kaleidoscope mirroring logic
    angle = ((angle - angle_step * floor(angle / angle_step)) + angle_step); angle = angle - angle_step * floor(angle / angle_step);
    angle = abs(angle - angle_step / 2.0) * mirror_strength;

    uv = vec2<f32>(cos(angle), sin(angle)) * dist;

    // Add curl noise distortion based on noise_intensity
    let dist_uv = vec2<i32>(uv + center + noise_val * 50.0 * noise_intensity);

    // Wrap or clamp texture coordinates.
    // We can just mirror repeat or clamp. Clamp for simplicity since readTexture might be a video feed.
    let clamped_uv = clamp(dist_uv, vec2<i32>(0), vec2<i32>(res) - vec2<i32>(1));
    var color = textureLoad(readTexture, clamped_uv, 0).rgb;

    // Audio glow to the edges of the kaleidescope
    let glow = max(0.0, 1.0 - (dist / (res.x * 0.5))) * audio;
    color += vec3<f32>(0.2, 0.5, 1.0) * glow * plasmaVal;

    textureStore(writeTexture, coords, vec4<f32>(color, 1.0));
}
