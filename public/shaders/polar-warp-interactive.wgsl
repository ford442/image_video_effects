// ═══════════════════════════════════════════════════════════════════
//  Polar Warp Interactive
//  Category: image
//  Features: mouse-driven
//  Complexity: Low
//  Chunks From: original polar-warp-interactive
//  Created: 2026-05-03
//  By: Optimizer
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
  config: vec4<f32>,
  zoom_config: vec4<f32>,
  zoom_params: vec4<f32>,
  ripples: array<vec4<f32>, 50>,
};

const PI: f32 = 3.14159265;
const TAU: f32 = 6.2831853;
const EPS: f32 = 1e-3;

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let res = u.config.zw;
    let gid = vec2<i32>(global_id.xy);
    if (f32(global_id.x) >= res.x || f32(global_id.y) >= res.y) { return; }

    let uv = vec2<f32>(global_id.xy) / res;
    let aspect = res.x / res.y;

    // Branchless mouse fallback to center when unavailable
    let mouseRaw = u.zoom_config.yz;
    let mouse = select(mouseRaw, vec2<f32>(0.5), mouseRaw.x < 0.0);

    // Aspect-corrected polar coordinates centered on mouse
    var diff = uv - mouse;
    diff.x *= aspect;

    let radius = length(diff);
    let angle = atan2(diff.y, diff.x);

    // Tunable params
    let zoom = 0.1 + u.zoom_params.x * 2.0;
    let spiral = u.zoom_params.y * 5.0;
    let repeats = max(1.0, u.zoom_params.z);
    let offset = u.zoom_params.w;

    // Early exit: hide center singularity
    if (radius < EPS) {
        textureStore(writeTexture, gid, vec4<f32>(0.0));
        return;
    }

    // Polar distortion
    let r_new = pow(radius, 1.0 / zoom) - offset;
    let a_new = angle + radius * spiral;

    // Map polar back to UV space with time rotation
    let tunnel_u = (a_new / PI) * repeats + u.config.x * 0.1;
    let tunnel_v = 1.0 / (r_new + EPS);

    // Mirrored-repeat UV sampling for seamless edges
    let fuv = fract(vec2<f32>(tunnel_u, tunnel_v));
    let sampleUV = abs(fuv * 2.0 - 1.0);

    // Single texture sample
    let col = textureSampleLevel(readTexture, u_sampler, sampleUV, 0.0);

    // Radial fade at the singularity
    let fade = smoothstep(0.0, 0.1, radius);

    // HDR-ready output: explicit alpha for clean slot chaining
    textureStore(writeTexture, gid, vec4<f32>(col.rgb * fade, 1.0));
}
