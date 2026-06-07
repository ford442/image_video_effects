// ═══════════════════════════════════════════════════════════════════
//  Magnetic Field Warp
//  Category: generative
//  Features: mouse-driven, audio-reactive, depth-aware, upgraded-rgba, aces-tone-map
//  Complexity: Medium
//  Created: 2026-05-10
//  Upgraded: 2026-06-06
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
  config: vec4<f32>,       // x=Time, y=ClickCount, z=ResX, w=ResY
  zoom_config: vec4<f32>,  // x=ZoomTime, y=MouseX, z=MouseY, w=Generic2
  zoom_params: vec4<f32>,  // x=Param1, y=Param2, z=Param3, w=Param4
  ripples: array<vec4<f32>, 50>,
};

const PHI = 1.618033988749895;

fn valueNoise(p: vec2<f32>) -> f32 {
    let ip = floor(p);
    let fp = fract(p);
    let u = fp * fp * (3.0 - 2.0 * fp);
    let h = vec4<f32>(dot(ip, vec2<f32>(127.1, 311.7)),
                      dot(ip + vec2<f32>(1.0, 0.0), vec2<f32>(127.1, 311.7)),
                      dot(ip + vec2<f32>(0.0, 1.0), vec2<f32>(127.1, 311.7)),
                      dot(ip + vec2<f32>(1.0, 1.0), vec2<f32>(127.1, 311.7)));
    let n = fract(sin(h) * 43758.5453123);
    return mix(mix(n.x, n.y, u.x), mix(n.z, n.w, u.x), u.y);
}

fn fbm(p: vec2<f32>) -> f32 {
    var a = 0.5;
    var s = 0.0;
    var q = p;
    for (var i = 0; i < 5; i = i + 1) {
        s = s + a * valueNoise(q);
        q = q * 2.02;
        a = a * 0.5;
    }
    return s;
}

fn warpedFBM(p: vec2<f32>, t: f32) -> f32 {
    let q = vec2<f32>(fbm(p + vec2<f32>(0.0, t)), fbm(p + vec2<f32>(5.2, 1.3)));
    let r = vec2<f32>(fbm(p + 4.0 * q + vec2<f32>(1.7, 9.2)), fbm(p + 4.0 * q + vec2<f32>(8.3, 2.8)));
    return fbm(p + 4.0 * r);
}

fn curl2D(p: vec2<f32>, t: f32) -> vec2<f32> {
    let eps = 0.005;
    let dx = warpedFBM(p + vec2<f32>(eps, 0.0), t) - warpedFBM(p - vec2<f32>(eps, 0.0), t);
    let dy = warpedFBM(p + vec2<f32>(0.0, eps), t) - warpedFBM(p - vec2<f32>(0.0, eps), t);
    return vec2<f32>(dy, -dx) / (2.0 * eps + 1e-6);
}

fn clifford(p: vec2<f32>, a: f32, b: f32, c: f32, d: f32) -> vec2<f32> {
    return vec2<f32>(sin(a * p.y) + c * cos(a * p.x), sin(b * p.x) + d * cos(b * p.y));
}

fn acesToneMap(x: vec3<f32>) -> vec3<f32> {
  let a = 2.51;
  let b = 0.03;
  let c = 2.43;
  let d = 0.59;
  let e = 0.14;
  return clamp((x * (a * x + b)) / (x * (c * x + d) + e), vec3<f32>(0.0), vec3<f32>(1.0));
}

@compute @workgroup_size(8, 8, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    if (global_id.x >= u32(u.config.z) || global_id.y >= u32(u.config.w)) { return; }

    let coords = vec2<i32>(global_id.xy);
    let res = vec2<i32>(i32(u.config.z), i32(u.config.w));
    let uv = vec2<f32>(coords) / vec2<f32>(res);
    let time = u.config.x;

    let bass   = plasmaBuffer[0].x;
    let mids   = plasmaBuffer[0].y;
    let treble = plasmaBuffer[0].z;

    // Domain-warped FBM turbulence on UV
    let warp = warpedFBM(uv * 3.0, time * 0.3);
    let turbUV = uv + (warp - 0.5) * 0.2 * u.zoom_params.z;

    // Mouse dipole field
    let mouse = u.zoom_config.yz;
    let delta = turbUV - mouse;
    let dist = length(delta);
    let safe_dist = max(dist, 0.001);
    let field_dir = select(vec2<f32>(0.0, 0.0), delta / safe_dist, dist > 0.001);
    let warp_strength = u.zoom_params.x * 2.5 * (1.0 + bass);
    let dipole = field_dir * (warp_strength / (safe_dist * safe_dist + 0.05));

    // Divergence-free curl-noise vorticity
    let curl = curl2D(uv * 4.0 + time * 0.2, time) * 0.3 * (1.0 + bass);

    // Clifford strange-attractor modulation
    let ca = 1.5 + bass * 0.5;
    let cd = -1.5 + sin(time * 0.1) * 0.3;
    let attractor = clifford(uv * 6.2831853, ca, -1.8, 1.2, cd);
    let a_weight = 0.12 * u.zoom_params.w;

    let field = dipole + curl + attractor * a_weight;
    let warped_uv = uv + field * 0.04;

    let safe_uv = clamp(warped_uv, vec2<f32>(0.0), vec2<f32>(1.0));
    let read_coords = vec2<i32>(safe_uv * vec2<f32>(res));
    let color = textureLoad(readTexture, read_coords, 0);

    // Depth
    let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;

    // Spectral remapping
    let luma = dot(color.rgb, vec3<f32>(0.299, 0.587, 0.114));
    let spectral_idx = u32(clamp(luma + bass * 0.5, 0.0, 1.0) * 255.0) % 256u;
    let plasma = plasmaBuffer[spectral_idx];

    let mix_factor = clamp(u.zoom_params.y, 0.0, 1.0);
    let mixed_color = mix(color, plasma, mix_factor);

    // Alpha encodes total field energy
    let energy = clamp(length(field) * 4.0 + length(attractor) * a_weight * 6.0, 0.0, 1.0);
    let target_alpha = clamp(0.5 + luma * 0.4 + bass * 0.25 + mids * 0.1 + treble * 0.05, 0.0, 1.0);
    let final_alpha = clamp(mix(color.a, target_alpha, energy * mix_factor), 0.0, 1.0);

    let finalColor = vec4<f32>(acesToneMap((mixed_color.rgb) * 1.1), final_alpha);

    textureStore(writeTexture, coords, finalColor);
    textureStore(dataTextureA, global_id.xy, finalColor);
    textureStore(writeDepthTexture, global_id.xy, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
