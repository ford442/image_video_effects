// ═══════════════════════════════════════════════════════════════════
//  Vortex Warp
//  Category: distortion
//  Features: mouse-driven, spatial-warp, spiral-distortion
//  Complexity: Medium
//  Created: 2026-05-31
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

const PI: f32 = 3.141592653589793;

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let resolution = u.config.zw;
    if (global_id.x >= u32(resolution.x) || global_id.y >= u32(resolution.y)) { return; }

    let uv = vec2<f32>(global_id.xy) / resolution;
    let aspect = resolution.x / resolution.y;
    let time = u.config.x;

    let strength = u.zoom_params.x * 2.0;
    let twist = u.zoom_params.y * 4.0;
    let radius = u.zoom_params.z * 0.5 + 0.05;
    let decay = u.zoom_params.w * 3.0 + 0.5;

    var mouse = u.zoom_config.yz;
    mouse.x = mouse.x * aspect;

    var p = uv;
    p.x = p.x * aspect;

    let delta = p - mouse;
    let dist = length(delta);

    var displacedUV = uv;

    if (dist < radius && dist > 0.001) {
        let angle = atan2(delta.y, delta.x);
        let normalizedDist = dist / radius;

        let falloff = pow(1.0 - normalizedDist, decay);
        let rotation = falloff * twist * PI;

        let spiralStrength = strength * falloff * (1.0 - normalizedDist);
        let newAngle = angle + rotation + time * 0.3 * strength;
        let newDist = dist - spiralStrength * radius * 0.5;

        var newP = mouse + vec2<f32>(cos(newAngle), sin(newAngle)) * newDist;
        newP.x = newP.x / aspect;
        displacedUV = newP;
    }

    displacedUV = clamp(displacedUV, vec2<f32>(0.0), vec2<f32>(1.0));
    let color = textureSampleLevel(readTexture, u_sampler, displacedUV, 0.0).rgb;

    let edgeDist = length(uv - vec2<f32>(0.5));
    let vignette = 1.0 - smoothstep(0.3, 0.8, edgeDist);
    let finalColor = color * (0.85 + vignette * 0.15);

    let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
    textureStore(writeTexture, vec2<i32>(global_id.xy), vec4<f32>(finalColor, 1.0));
    textureStore(writeDepthTexture, global_id.xy, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
