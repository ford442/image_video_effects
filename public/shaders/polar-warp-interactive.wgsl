// ═══════════════════════════════════════════════════════════════════
//  Polar Warp Interactive
//  Category: interactive-mouse
//  Features: mouse-driven, upgraded-rgba, audio-reactive, depth-aware, multi-ripple
//  Complexity: Medium
//  Upgraded: bass-driven warp, spiral component, ripple bursts, semantic alpha
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

@compute @workgroup_size(8, 8, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let res = u.config.zw;
    if (global_id.x >= u32(res.x) || global_id.y >= u32(res.y)) { return; }
    let gid = vec2<i32>(global_id.xy);
    let uv = vec2<f32>(global_id.xy) / res;
    let aspect = res.x / res.y;
    let time = u.config.x;

    let mouseRaw = u.zoom_config.yz;
    let mouse = select(mouseRaw, vec2<f32>(0.5), mouseRaw.x < 0.0);

    let bass = plasmaBuffer[0].x;
    let bassPulse = 1.0 + bass * 0.4;

    let warpStrength = u.zoom_params.x * bassPulse;
    let spiralAmount = u.zoom_params.y * 5.0;
    let rippleDecay = u.zoom_params.z;
    let pinchExpand = u.zoom_params.w;

    var diff = uv - mouse;
    diff.x *= aspect;

    let radius = length(diff);
    let angle = atan2(diff.y, diff.x);

    // Early exit: hide center singularity
    if (radius < EPS) {
        textureStore(writeTexture, gid, vec4<f32>(0.0));
        textureStore(writeDepthTexture, gid, vec4<f32>(0.0, 0.0, 0.0, 0.0));
        return;
    }

    // Polar distortion
    let zoom = 0.1 + warpStrength * 2.0;
    let r_new = pow(radius, 1.0 / zoom) - pinchExpand;
    var a_new = angle + radius * spiralAmount;

    // Click-triggered ripple bursts from u.ripples
    for (var i: i32 = 0; i < 50; i = i + 1) {
        let rp = u.ripples[i];
        if (rp.z > 0.0) {
            let age = time - rp.z;
            if (age > 0.0 && age < 3.0) {
                let rd = length((uv - rp.xy) * vec2<f32>(aspect, 1.0));
                let rippleWave = sin(rd * 30.0 - age * 10.0) * exp(-age * rippleDecay * 3.0);
                a_new = a_new + rippleWave * 0.1 * rp.w;
            }
        }
    }

    // Map polar back to UV space with time rotation
    let tunnel_u = (a_new / PI) * 2.0 + time * 0.1;
    let tunnel_v = 1.0 / (r_new + EPS);

    // Mirrored-repeat UV sampling for seamless edges
    let fuv = fract(vec2<f32>(tunnel_u, tunnel_v));
    let sampleUV = abs(fuv * 2.0 - 1.0);

    // Single texture sample
    let col = textureSampleLevel(readTexture, u_sampler, sampleUV, 0.0);

    // Radial fade at the singularity
    let fade = smoothstep(0.0, 0.1, radius);

    // Depth-aware fade
    let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
    let depthFade = mix(0.7, 1.0, depth);

    // Semantic alpha: reduce at extreme warp distortion
    let warpDistort = abs(r_new - radius) + abs(a_new - angle);
    let alpha = mix(col.a, 0.85, smoothstep(0.5, 1.5, warpDistort));
    let finalAlpha = alpha * fade * depthFade;

    textureStore(writeTexture, gid, vec4<f32>(col.rgb * fade * depthFade, finalAlpha));
    textureStore(writeDepthTexture, gid, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
