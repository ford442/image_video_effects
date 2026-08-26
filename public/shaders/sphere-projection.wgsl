// ═══════════════════════════════════════════════════════════════
//  Sphere Projection
//  Category: geometric
//  Features: mouse-driven, 3d, audio-reactive, upgraded-rgba,
//            meridians, held-drag, bounded-click-ripples
//  Complexity: High
//  Upgraded: 2026-08-23
// ═══════════════════════════════════════════════════════════════

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

const PI: f32 = 3.14159265359;

fn hsv2rgb(hsv: vec3<f32>) -> vec3<f32> {
    let k = vec4<f32>(1.0, 2.0 / 3.0, 1.0 / 3.0, 3.0);
    let p = abs(fract(hsv.xxx + k.xyz) * 6.0 - k.www);
    return hsv.z * mix(k.xxx, clamp(p - k.xxx, vec3<f32>(0.0), vec3<f32>(1.0)), hsv.y);
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let pixel = vec2<i32>(global_id.xy);
    let resolution = u.config.zw;
    if (global_id.x >= u32(resolution.x) || global_id.y >= u32(resolution.y)) { return; }

    let uv = vec2<f32>(global_id.xy) / resolution;
    let time = u.config.x;
    let held = f32(u.zoom_config.w > 0.5);
    let mouse = u.zoom_config.yz;
    let prev = textureLoad(dataTextureC, pixel, 0);
    let bass = plasmaBuffer[0].x;
    let mids = plasmaBuffer[0].y;
    let treble = plasmaBuffer[0].z;
    let zoom_param = max(u.zoom_params.x, 0.01);
    let rotation_param = u.zoom_params.y;
    let light_param = u.zoom_params.z;
    let ambient_param = u.zoom_params.w;

    let min_res = min(resolution.x, resolution.y);
    let ndc = (vec2<f32>(global_id.xy) * 2.0 - resolution) / min_res;
    let distCam = 3.0 / zoom_param * (1.0 - held * 0.12);
    let ro = vec3<f32>(0.0, 0.0, -distCam);
    let rd = normalize(vec3<f32>(ndc, 1.0));
    let b = dot(ro, rd);
    let c = dot(ro, ro) - 1.0;
    let h = b * b - c;
    let hit = f32(h >= 0.0);
    let t = select(0.0, -b - sqrt(max(h, 0.0)), hit > 0.5);
    let p = ro + rd * t;
    let n = normalize(p);

    let yaw = -(mouse.x - 0.5) * 2.0 * PI - time * rotation_param * (1.0 + bass * 0.4);
    let pitch = (mouse.y - 0.5) * PI;
    let cy = cos(yaw); let sy = sin(yaw);
    let cx = cos(pitch); let sx = sin(pitch);
    let rotY = mat3x3<f32>(cy, 0.0, sy, 0.0, 1.0, 0.0, -sy, 0.0, cy);
    let rotX = mat3x3<f32>(1.0, 0.0, 0.0, 0.0, cx, -sx, 0.0, sx, cx);
    let n_rot = rotX * (rotY * n);
    let tex_uv = vec2<f32>(fract(atan2(n_rot.z, n_rot.x) / (2.0 * PI) + 0.5), clamp(acos(clamp(n_rot.y, -1.0, 1.0)) / PI, 0.0, 1.0));
    let tex = textureSampleLevel(readTexture, u_sampler, tex_uv, 0.0);
    let bg = textureSampleLevel(readTexture, u_sampler, uv, 0.0);
    let lightDir = normalize(vec3<f32>(-0.5, 0.5, -1.0));
    let lighting = mix(1.0, mix(0.0, 0.6, ambient_param) + max(0.0, dot(n, lightDir)), light_param);
    var color = mix(bg.rgb, tex.rgb * lighting, hit);

    let lon = atan2(n_rot.z, n_rot.x);
    let lat = asin(clamp(n_rot.y, -1.0, 1.0));
    let meridians = smoothstep(0.06, 0.0, abs(fract(lon / PI * 6.0 + time * (0.35 + rotation_param)) - 0.5));
    let parallels = smoothstep(0.06, 0.0, abs(fract(lat / PI * 8.0 - time * 0.55) - 0.5));
    var click = 0.0;
    let rippleCount = min(u32(u.config.y), 50u);
    for (var i: u32 = 0u; i < rippleCount; i = i + 1u) {
        let rp = u.ripples[i];
        let age = time - rp.z;
        if (rp.z > 0.0 && age >= 0.0 && age < 1.5) {
            click = max(click, exp(-abs(distance(uv, rp.xy) - age * 0.5) * 58.0) * (1.0 - age / 1.5));
        }
    }
    let slick = hsv2rgb(vec3<f32>(fract(lon / (2.0 * PI) + time * 0.08 + mids * 0.2), 0.7, 1.0));
    color = mix(color, color * slick * 1.2, hit * (0.22 + treble * 0.2));
    color += slick * hit * (meridians * 0.28 + parallels * 0.22 + click * 0.5);

    let luma = dot(color, vec3<f32>(0.299, 0.587, 0.114));
    let alpha = clamp(mix(bg.a, 0.35 + luma * 0.65, hit), 0.0, 1.0);
    let outCol = vec4<f32>(mix(color, prev.rgb * 0.88, 0.2 * hit), mix(alpha, prev.a * 0.88, 0.2 * hit));
    let depthSrc = textureLoad(readDepthTexture, pixel, 0).r;
    let depthOut = mix(depthSrc, clamp(t / 10.0 + meridians * 0.05, 0.0, 1.0), hit);
    textureStore(writeTexture, pixel, outCol);
    textureStore(dataTextureA, pixel, outCol);
    textureStore(writeDepthTexture, pixel, vec4<f32>(depthOut, 0.0, 0.0, 0.0));
}
